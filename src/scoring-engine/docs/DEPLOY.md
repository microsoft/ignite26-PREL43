# Deploying the Scoring Engine to a tenant

The Scoring Engine runs inside the Microsoft 365 tenant whose lab accounts it scores. One settings file
says **which tenant and subscription** to deploy to; the deploy script does the rest. No Bicep, Helm or
code changes are needed per tenant.

## 1. Before you start

| You need | Why |
|---|---|
| **Global Administrator** in the target tenant (or Privileged Role Administrator + Application Administrator) | Grant the engine's read-only Microsoft Graph permissions and create the admin sign-in app registrations |
| **Owner** on one Azure subscription in that tenant | Create AKS, PostgreSQL, Key Vault, Container Registry and role assignments |
| Two DNS names you control, e.g. `scoring-admin.contoso.com` and `scorecard.contoso.com` | Admin portal + lab partner API, and the participant scorecard |
| Azure CLI 2.65+, Helm 3.14+, kubectl, Python 3 | Run the script. Docker is **not** required: images build in Azure Container Registry |

Find the two IDs in the Azure portal:
- **Tenant ID:** Microsoft Entra ID → Overview → *Tenant ID*
- **Subscription ID:** Subscriptions → your subscription → *Subscription ID*

## 2. Fill in the settings file

```bash
cp deploy/env/tenant.env.example deploy/env/mytenant.env
```

Edit `deploy/env/mytenant.env`. Only the first block normally changes:

| Setting | Example | Notes |
|---|---|---|
| `TENANT_ID` | `11111111-2222-3333-4444-555555555555` | The tenant the lab accounts live in |
| `SUBSCRIPTION_ID` | `66666666-7777-8888-9999-000000000000` | Must belong to `TENANT_ID`; the script checks this |
| `LOCATION` | `eastus2` | Any Azure region with AKS and PostgreSQL Flexible Server |
| `RESOURCE_GROUP` | `vsl-scoring-rg` | Created if missing |
| `ADMIN_HOST` | `scoring-admin.contoso.com` | Admin portal and the `/oauth` + `/v1` partner API |
| `SCORECARD_HOST` | `scorecard.contoso.com` | Participant scorecard |
| `SIZE` | `small` or `standard` | `small` for pilots (2 nodes, burstable DB); `standard` for events (3–8 nodes, zone-redundant DB) |
| `TLS_KEYVAULT_CERT_URI` | *(optional)* | A Key Vault certificate covering both host names |

`deploy/env/*.env` files are git-ignored, so tenant details never get committed.

## 3. Deploy

```bash
./deploy/scripts/deploy.sh deploy/env/mytenant.env check   # sign-in, tenant/subscription match, tools, Owner role
./deploy/scripts/deploy.sh deploy/env/mytenant.env all     # infra -> images -> graph -> app
```

| Step | What it does | Typical time |
|---|---|---|
| `check` | Signs in to `TENANT_ID`, selects `SUBSCRIPTION_ID`, confirms they match and prints the plan | 1 min |
| `infra` | Bicep: VNet, AKS (workload identity, Key Vault CSI, app routing), PostgreSQL (private), Key Vault, Container Registry, managed identity | 15–20 min |
| `images` | Builds the API/worker, admin portal and scorecard images in the new registry | 5–8 min |
| `graph` | Grants the managed identity read-only Microsoft Graph application permissions (admin consent) | 1 min |
| `app` | Creates the admin sign-in app registrations (first run only), then installs the Helm release | 5 min |

Every step can be re-run on its own and is safe to repeat; for example after a code change run `images` then `app`.

## 4. After the script finishes

1. **DNS:** point `ADMIN_HOST` and `SCORECARD_HOST` at the ingress IP printed at the end.
2. **Admins:** Entra ID → Enterprise applications → *VectorSense Scoring API* → Users and groups → assign **Scoring Admin** to the event organisers.
3. **Sign in** at `https://<ADMIN_HOST>` and check *System*: Microsoft Graph should show *Connected* with the tenant name.
4. **Event:** create the event, add use cases and steps, and paste each step's rubric (samples in `backend/samples/rubrics/`). Set the event to **Live**.
5. **Lab partner:** *Integrations* → New integration. Send the client ID and secret, together with `docs/API_CONTRACT.md`, over a secure channel.
6. **Roster (optional):** *Event → Settings → Lab account roster*: set the Entra group that contains the lab accounts, or import a CSV, so **Sync now** can score accounts directly from Microsoft 365.
7. **Participants:** share `https://<SCORECARD_HOST>/<event_id>`.

## 5. Microsoft Graph permissions granted

Application permissions, read-only, granted to the engine's managed identity only (no client secret exists):

`Files.Read.All` · `Mail.ReadBasic.All` · `Calendars.ReadBasic.All` · `ChannelMessage.Read.All` · `User.Read.All` ·
`GroupMember.Read.All` · `Organization.Read.All` · `AiEnterpriseInteraction.Read.All` · `AuditLogsQuery.Read.All`

## 6. Updating and removing

| Task | Command |
|---|---|
| New version | Set `IMAGE_TAG`, then run the `images` and `app` steps. Database migrations run automatically before the new pods start |
| Scale for a peak | `kubectl -n vectorsense scale deploy/vectorsense-scoring-worker --replicas=6` |
| Remove everything | `az group delete -n <RESOURCE_GROUP>`, then delete the two *VectorSense Scoring* app registrations in Entra ID |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Subscription ... is not in tenant ...` | `SUBSCRIPTION_ID` belongs to another tenant; check both IDs in the portal |
| `MissingSubscriptionRegistration` during `infra` | Wait a few minutes for the resource providers the script registers, then re-run `infra` |
| *System* shows Graph *Unavailable* | Re-run the `graph` step as a Global Administrator; role grants can take ~10 minutes to apply |
| Admin sign-in says *missing app role Scoring.Admin* | Assign the role (section 4, step 2) and sign in again |
| Pods stuck in `ContainerCreating` | `kubectl -n vectorsense describe pod <name>`: usually Key Vault access still propagating; wait and it retries |
