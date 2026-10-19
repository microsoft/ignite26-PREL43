#!/usr/bin/env bash
# Creates the two app registrations the admin portal signs in with:
#   - "VectorSense Scoring API": exposes api://<id>/access_as_admin and the app role Scoring.Admin
#   - "VectorSense Scoring Portal": SPA with redirect https://<admin-host>/
# Assign the Scoring.Admin role to admins under Enterprise applications > VectorSense Scoring API > Users and groups.
#   ./create-entra-apps.sh <admin-host>
set -euo pipefail
HOST="${1:?usage: $0 <admin-host>}"
ROLE_ID=$(uuidgen | tr 'A-Z' 'a-z')
SCOPE_ID=$(uuidgen | tr 'A-Z' 'a-z')

API_APP_ID=$(az ad app create --display-name "VectorSense Scoring API" --sign-in-audience AzureADMyOrg \
  --app-roles "[{\"allowedMemberTypes\":[\"User\"],\"description\":\"Administer the scoring engine\",\"displayName\":\"Scoring Admin\",\"id\":\"$ROLE_ID\",\"isEnabled\":true,\"value\":\"Scoring.Admin\"}]" \
  --query appId -o tsv)
API_OBJ=$(az ad app show --id "$API_APP_ID" --query id -o tsv)
az ad app update --id "$API_APP_ID" --identifier-uris "api://$API_APP_ID"
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$API_OBJ" --headers "Content-Type=application/json" --body \
  "{\"api\":{\"requestedAccessTokenVersion\":2,\"oauth2PermissionScopes\":[{\"id\":\"$SCOPE_ID\",\"adminConsentDescription\":\"Access the scoring admin API\",\"adminConsentDisplayName\":\"Access scoring admin API\",\"isEnabled\":true,\"type\":\"Admin\",\"value\":\"access_as_admin\"}]}}"
az ad sp create --id "$API_APP_ID" >/dev/null
az ad sp update --id "$API_APP_ID" --set appRoleAssignmentRequired=true

SPA_APP_ID=$(az ad app create --display-name "VectorSense Scoring Portal" --sign-in-audience AzureADMyOrg --query appId -o tsv)
SPA_OBJ=$(az ad app show --id "$SPA_APP_ID" --query id -o tsv)
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$SPA_OBJ" --headers "Content-Type=application/json" --body \
  "{\"spa\":{\"redirectUris\":[\"https://$HOST/\",\"http://localhost:5173/\"]},\"requiredResourceAccess\":[{\"resourceAppId\":\"$API_APP_ID\",\"resourceAccess\":[{\"id\":\"$SCOPE_ID\",\"type\":\"Scope\"}]}]}"
az ad sp create --id "$SPA_APP_ID" >/dev/null
# Pre-authorise the portal so admins are not prompted for consent.
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$API_OBJ" --headers "Content-Type=application/json" --body \
  "{\"api\":{\"preAuthorizedApplications\":[{\"appId\":\"$SPA_APP_ID\",\"delegatedPermissionIds\":[\"$SCOPE_ID\"]}]}}"

echo "ENTRA_API_CLIENT_ID=$API_APP_ID"
echo "ENTRA_SPA_CLIENT_ID=$SPA_APP_ID"
echo "Now assign the 'Scoring Admin' role to your admins in Enterprise applications > VectorSense Scoring API."
