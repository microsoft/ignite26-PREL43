#!/usr/bin/env bash
# Grants the scoring workload identity read-only Microsoft Graph APPLICATION permissions in this tenant.
# Requires a Global Administrator or Privileged Role Administrator signed in with `az login`.
#   ./grant-graph-permissions.sh <workload-identity-principal-object-id>
set -euo pipefail
PRINCIPAL_ID="${1:?usage: $0 <managed-identity-principal-id>}"
PERMISSIONS=(
  Files.Read.All               # OneDrive/SharePoint outputs (Cowork saves to OneDrive Cowork folder)
  Mail.ReadBasic.All           # sent mail metadata; switch to Mail.Read only if body checks are used
  Calendars.ReadBasic.All      # meetings created by the participant
  ChannelMessage.Read.All      # Teams channel posts
  User.Read.All                # resolve lab UPNs
  GroupMember.Read.All         # event roster from an Entra group (Microsoft 365 sync)
  Organization.Read.All        # connection status in the portal
  AiEnterpriseInteraction.Read.All   # Copilot interaction export
  AuditLogsQuery.Read.All      # Purview CopilotInteraction audit (deferred checks)
)
GRAPH_APP_ID=00000003-0000-0000-c000-000000000000
GRAPH_SP=$(az ad sp show --id "$GRAPH_APP_ID" --query id -o tsv)
ROLES=$(az ad sp show --id "$GRAPH_APP_ID" --query "appRoles[].{v:value,id:id}" -o tsv)
EXISTING=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$PRINCIPAL_ID/appRoleAssignments" \
  --query "value[].appRoleId" -o tsv || true)

for perm in "${PERMISSIONS[@]}"; do
  role_id=$(awk -v p="$perm" '$1==p {print $2}' <<<"$ROLES")
  if [[ -z "$role_id" ]]; then echo "!! $perm not found in Graph app roles (check tenant/licensing)"; continue; fi
  if grep -q "$role_id" <<<"$EXISTING"; then echo "== $perm already granted"; continue; fi
  az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$PRINCIPAL_ID/appRoleAssignments" \
    --headers "Content-Type=application/json" \
    --body "{\"principalId\":\"$PRINCIPAL_ID\",\"resourceId\":\"$GRAPH_SP\",\"appRoleId\":\"$role_id\"}" >/dev/null
  echo "++ granted $perm"
done
echo "Done. Graph tokens pick up new roles within ~10 minutes."
