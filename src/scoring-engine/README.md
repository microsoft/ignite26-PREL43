# VectorSense Labs: Scoring Engine

The scoring service for hands-on labs. A lab platform calls one API when a participant clicks **Complete**, or an organiser runs a Microsoft 365 sync. Either way, the engine checks real evidence in the tenant it is deployed in and answers **complete** or **incomplete**, with the reason why. Administrators see a realtime leaderboard; each participant sees only their own scorecard.

- **Frontend:** two React + TypeScript (Vite) apps sharing one design system:
  - `frontend/web-admin`: the admin portal, with events, rubrics, integrations, the full leaderboard and Microsoft 365 sync.
  - `frontend/web-scorecard`: the participant scorecard. A participant enters their lab account and sees only their own results.
- **Backend:** Python 3.12 + FastAPI API, plus a background worker. Microsoft Graph access is app-only, through workload identity.
- **Database:** PostgreSQL 16. It is the system of record, the job queue and the realtime bus.
- **Deploy:** Docker images, a Helm chart for AKS, Bicep for the Azure resources, and a one-shot deploy script.

## Repository layout

```
backend/                FastAPI app, worker, check types, migrations, tests
  app/checks/           evidence checks (OneDrive, SharePoint, mail, calendar, Teams, Copilot, Purview)
  app/graph/            Microsoft Graph client (live) and file-backed mock
  db/migrations/        SQL schema (source of truth)
  samples/rubrics/      Copilot Cowork sample rubrics
  scripts/vendor_simulator.py   end-to-end vendor simulator (handshake + Complete clicks)
frontend/
  shared/               design system (styles, UI components, theme, types)
  web-admin/            admin portal (port 8080 locally)
  web-scorecard/        participant scorecard (port 8081 locally)
deploy/
  bicep/                AKS, Postgres, Key Vault, ACR, identity, networking
  helm/vectorsense-scoring/   Kubernetes chart (api, worker, web, ingress, migrations hook)
  scripts/              deploy.sh, grant-graph-permissions.sh, create-entra-apps.sh
  env/                  per-tenant environment templates
docs/
  API_CONTRACT.md       the contract to hand to lab vendors
  ARCHITECTURE.md       design, Cowork evidence model, throttling, security
  DEPLOY.md             deploying to any tenant/subscription (settings file + one script)
  RUNBOOK.md            local run, test and event deployments, operations
docker-compose.yml      local stack with mock Graph
```

## Quick start (local)

```bash
docker compose up -d --build
docker compose --profile demo up -d simulator              # lab partner calling the API
docker compose --profile demo-sync up -d simulator-no-api  # work only in Microsoft 365; use "Sync now"
open http://localhost:8080        # admin portal (admin / VS_ADMIN_PASSWORD from docker-compose.yml)
open http://localhost:8081        # participant scorecard (enter e.g. labuser001@ignite.demo)
```

## Deploy to a tenant

```bash
cp deploy/env/tenant.env.example deploy/env/mytenant.env   # set TENANT_ID, SUBSCRIPTION_ID and the two host names
./deploy/scripts/deploy.sh deploy/env/mytenant.env check
./deploy/scripts/deploy.sh deploy/env/mytenant.env all
```

Step-by-step guide: [docs/DEPLOY.md](docs/DEPLOY.md). Operations and event-day tasks: [docs/RUNBOOK.md](docs/RUNBOOK.md).
