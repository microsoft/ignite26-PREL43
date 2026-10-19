#!/usr/bin/env bash
# One-shot deployment of the Scoring Engine into any tenant and subscription.
#
#   cp deploy/env/tenant.env.example deploy/env/<name>.env      # set TENANT_ID, SUBSCRIPTION_ID, hosts
#   ./deploy/scripts/deploy.sh deploy/env/<name>.env [check|infra|images|graph|app|all]
#
# Steps: check (sign-in and prerequisites) -> infra (Bicep) -> images (ACR cloud build)
#        -> graph (Microsoft Graph app roles) -> app (Helm on AKS)
# Everything tenant-specific comes from the env file; nothing in Bicep or Helm needs editing.
set -euo pipefail
# Resolve the settings file against the caller's directory before changing into deploy/.
[[ -f "${1:?usage: $0 <env-file> [step]}" ]] || { echo "Settings file not found: $1" >&2; exit 1; }
ENV_FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
STEP="${2:-all}"
cd "$(dirname "$0")/.."
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
OUT_FILE="${ENV_FILE%.env}.outputs.env"

: "${LOCATION:=eastus2}" "${RESOURCE_GROUP:=vsl-scoring-rg}" "${ENV_NAME:=prod}" "${NAME_PREFIX:=vsl}"
: "${SIZE:=standard}" "${NAMESPACE:=vectorsense}" "${RELEASE:=vectorsense-scoring}" "${IMAGE_TAG:=1.0.0}"
: "${AUTH_MODE:=entra}" "${ADMIN_PRINCIPAL_ID:=}" "${TLS_KEYVAULT_CERT_URI:=}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

for v in TENANT_ID SUBSCRIPTION_ID ADMIN_HOST SCORECARD_HOST; do
  [[ -n "${!v:-}" && "${!v}" != *"<"* ]] || die "Set $v in $ENV_FILE"
done
[[ "$NAMESPACE" == "vectorsense" && "$RELEASE" == "vectorsense-scoring" ]] || \
  die "NAMESPACE/RELEASE must match the workload identity federation in bicep/main.bicep (vectorsense / vectorsense-scoring)"

signin() {
  if [[ "$(az account show --query tenantId -o tsv 2>/dev/null || true)" != "$TENANT_ID" ]]; then
    az login --tenant "$TENANT_ID" -o none
  fi
  az account set --subscription "$SUBSCRIPTION_ID"
  [[ "$(az account show --query tenantId -o tsv)" == "$TENANT_ID" ]] || die "Subscription $SUBSCRIPTION_ID is not in tenant $TENANT_ID"
}

check() {
  log "Checking prerequisites"
  for tool in az helm kubectl python3; do command -v "$tool" >/dev/null || die "Missing tool: $tool"; done
  signin
  printf 'Tenant        %s\nSubscription  %s (%s)\nSigned in as  %s\nTarget        %s in %s, size %s\nHosts         %s, %s\n' \
    "$TENANT_ID" "$SUBSCRIPTION_ID" "$(az account show --query name -o tsv)" "$(az account show --query user.name -o tsv)" \
    "$RESOURCE_GROUP" "$LOCATION" "$SIZE" "$ADMIN_HOST" "$SCORECARD_HOST"
  role=$(az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" --scope "/subscriptions/$SUBSCRIPTION_ID" \
         --include-inherited --query "[].roleDefinitionName" -o tsv 2>/dev/null | tr '\n' ' ')
  [[ "$role" == *Owner* ]] || echo "Warning: Owner not found on the subscription for the signed-in user (found: ${role:-none})"
}

infra() {
  signin
  [[ -n "$ADMIN_PRINCIPAL_ID" ]] || ADMIN_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
  log "Infrastructure: $RESOURCE_GROUP ($LOCATION), size $SIZE"
  for ns in Microsoft.ContainerService Microsoft.DBforPostgreSQL Microsoft.KeyVault Microsoft.ContainerRegistry \
            Microsoft.OperationalInsights Microsoft.ManagedIdentity Microsoft.Network; do
    az provider register --namespace "$ns" >/dev/null
  done
  az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none
  PARAMS=$(mktemp)
  python3 - "$PARAMS" <<'PY'
import json, os, sys
sizes = {
    "small":    {"aksNodeCount": 2, "aksMaxNodeCount": 4, "aksVmSize": "Standard_D2ds_v5",
                 "pgSku": "Standard_B2ms", "pgTier": "Burstable", "pgStorageGb": 32, "pgHighAvailability": False},
    "standard": {"aksNodeCount": 3, "aksMaxNodeCount": 8, "aksVmSize": "Standard_D4ds_v5",
                 "pgSku": "Standard_D2ds_v5", "pgTier": "GeneralPurpose", "pgStorageGb": 128, "pgHighAvailability": True},
}
size = os.environ["SIZE"]
if size not in sizes:
    sys.exit(f"SIZE must be one of {', '.join(sizes)}")
params = {"env": os.environ["ENV_NAME"], "prefix": os.environ["NAME_PREFIX"], "location": os.environ["LOCATION"],
          "adminPrincipalId": os.environ["ADMIN_PRINCIPAL_ID"], **sizes[size]}
json.dump({"$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
           "contentVersion": "1.0.0.0", "parameters": {k: {"value": v} for k, v in params.items()}},
          open(sys.argv[1], "w"), indent=2)
PY
  az deployment group create -g "$RESOURCE_GROUP" -n vectorsense-scoring -f bicep/main.bicep -p "@$PARAMS" \
    --query properties.outputs -o json > "$PARAMS.out"
  python3 - "$PARAMS.out" "$OUT_FILE" <<'PY'
import json, sys
out = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w") as fh:
    for k, v in out.items():
        fh.write(f"{k.upper()}={v['value']}\n")
print(open(sys.argv[2]).read())
PY
  rm -f "$PARAMS" "$PARAMS.out"
}

load_outputs() {
  [[ -f "$OUT_FILE" ]] || die "Run the infra step first ($OUT_FILE not found)"
  set -a; source "$OUT_FILE"; set +a
}

images() {
  signin; load_outputs
  log "Building images in $ACRNAME (cloud build, no local Docker needed)"
  az acr build -r "$ACRNAME" -t "vectorsense/scoring-backend:$IMAGE_TAG" ../backend
  az acr build -r "$ACRNAME" -t "vectorsense/scoring-admin:$IMAGE_TAG" --build-arg APP=web-admin ../frontend
  az acr build -r "$ACRNAME" -t "vectorsense/scoring-scorecard:$IMAGE_TAG" --build-arg APP=web-scorecard ../frontend
}

graph() {
  signin; load_outputs
  log "Granting Microsoft Graph application permissions to the workload identity"
  ./scripts/grant-graph-permissions.sh "$WORKLOADIDENTITYPRINCIPALID"
}

app() {
  signin; load_outputs
  if [[ "$AUTH_MODE" == "entra" && ( -z "${ENTRA_API_CLIENT_ID:-}" || -z "${ENTRA_SPA_CLIENT_ID:-}" ) ]]; then
    log "Creating Entra app registrations for the admin portal"
    eval "$(./scripts/create-entra-apps.sh "$ADMIN_HOST" | grep '^ENTRA_')"
    printf 'ENTRA_API_CLIENT_ID=%s\nENTRA_SPA_CLIENT_ID=%s\n' "$ENTRA_API_CLIENT_ID" "$ENTRA_SPA_CLIENT_ID" >> "$ENV_FILE"
  fi
  log "Deploying Helm release $RELEASE to $AKSNAME/$NAMESPACE"
  az aks get-credentials -g "$RESOURCE_GROUP" -n "$AKSNAME" --overwrite-existing --admin
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install "$RELEASE" helm/vectorsense-scoring -n "$NAMESPACE" --wait --timeout 15m \
    --set image.registry="$ACRLOGINSERVER" \
    --set image.tag="$IMAGE_TAG" \
    --set adminHost="$ADMIN_HOST" \
    --set scorecardHost="$SCORECARD_HOST" \
    --set ingress.tls.keyVaultCertificateUri="$TLS_KEYVAULT_CERT_URI" \
    --set ingress.tls.enabled="$([[ -n "$TLS_KEYVAULT_CERT_URI" ]] && echo true || echo false)" \
    --set workloadIdentity.clientId="$WORKLOADIDENTITYCLIENTID" \
    --set workloadIdentity.tenantId="$TENANT_ID" \
    --set keyVault.name="$KEYVAULTNAME" \
    --set config.environment="$ENV_NAME" \
    --set config.authMode="$AUTH_MODE" \
    --set config.entraTenantId="$TENANT_ID" \
    --set config.entraApiClientId="${ENTRA_API_CLIENT_ID:-}" \
    --set config.entraSpaClientId="${ENTRA_SPA_CLIENT_ID:-}"
  log "Ingress address (point $ADMIN_HOST and $SCORECARD_HOST here):"
  kubectl get ingress -n "$NAMESPACE"
}

case "$STEP" in
  check) check ;;
  infra) infra ;;
  images) images ;;
  graph) graph ;;
  app) app ;;
  all) check; infra; images; graph; app ;;
  *) die "unknown step $STEP (check|infra|images|graph|app|all)" ;;
esac
