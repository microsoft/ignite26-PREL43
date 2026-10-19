# Architecture

## Shape

```
Lab platform backend (lab partner)
   │ 1. POST /oauth/token          (client_id + client_secret → JWT, 60 min)
   │ 2. POST /v1/steps/complete    (event, use case, step, participant, lab account UPN, lab start)
   ▼
┌────────────── AKS (Ignite-tenant subscription) ──────────────┐
│ Ingress (AKS app routing, NGINX)                             │
│   admin host:     /api /v1 /oauth ─► API (FastAPI, 3–12 pods)│
│                   /               ─► web-admin (React)       │
│   scorecard host: /               ─► web-scorecard (React);  │
│                   its nginx forwards only /api/public        │
│                                                              │
│ Worker (2–8 pods) ── Postgres queue (FOR UPDATE SKIP LOCKED) │
│   ├─ evaluates rubrics against Microsoft Graph               │
│   ├─ re-verifies deferred Copilot evidence                   │
│   └─ delivers signed result webhooks                         │
└──────────────────────────────────────────────────────────────┘
        │ workload identity (no secrets)        │ private VNet
        ▼                                       ▼
  Microsoft Graph (same tenant)        PostgreSQL Flexible Server
  OneDrive · Outlook · Teams ·          (state, queue, realtime NOTIFY)
  Copilot interaction export ·
  Purview audit                         Key Vault (DB URL, JWT key, pepper)
```

**Three tiers:** a React portal, a FastAPI API plus worker, and PostgreSQL. There is no Redis. Postgres does three jobs:
- **System of record.**
- **Job queue:** `SELECT … FOR UPDATE SKIP LOCKED`, so any number of workers can run and a crashed pod's lock simply expires.
- **Realtime bus:** `LISTEN/NOTIFY`. Each API pod listens once and fans out to its Server-Sent Events clients.

That means fewer moving parts to deploy into a tenant we don't own.

## Request lifecycle

1. The vendor gets a token from `/oauth/token`. Secrets are stored as HMAC-SHA256 with a server pepper and shown only once.
2. `POST /v1/steps/complete` checks the event, use case and step. It then upserts the participant (keyed by `external_id`) and inserts a `submission` with status `queued`. An `Idempotency-Key` makes retries and double-clicks safe.
3. A worker claims the submission and runs the step rubric. All checks run concurrently.
4. The worker decides:

   | Condition | Result |
   |---|---|
   | All blocking checks pass | **complete** |
   | A blocking check fails, still inside its `retry_window_seconds` | Stays `evaluating` and is retried every 8 s. This absorbs Graph propagation delay |
   | A blocking check fails, window over | **incomplete**, with the check's `fail_message` as the reason |
   | Graph is throttled or down | Retried with backoff up to 5 times, then `error` |
   | Any check crashes | `error` with a reason. A participant is never left unscored |

5. The worker updates `step_progress` (one row per participant per step; complete is sticky). It queues a webhook and sends a `NOTIFY`. Open leaderboards refetch within about a second.
6. Deferred checks run in the background every 5 minutes, for up to 3 hours. The result sets `verification_status` to `verified` or `unverified`; it never flips complete to incomplete. Organisers see a badge and can override.

## Two ways results come in

| Path | Trigger | When to use |
|---|---|---|
| **Partner call** | The lab platform calls `POST /v1/steps/complete` on each Complete click | Normal operation: instant feedback in the lab |
| **Microsoft 365 sync** | An organiser clicks **Sync now** on the event leaderboard | The lab platform cannot call the API, or to catch up on work that was never clicked |

How a sync works (`backend/app/sync.py`):
- **Roster:** pulls the event's lab accounts from its Entra group, if one is set, and adds them to accounts already known from partner calls or a CSV import.
- **Delta:** steps that are already complete are never re-scanned, and participants who have finished every step are skipped. Open steps are checked over the whole lab window, because one step can need evidence from both before and after the last sync.
- **Timing:** synced completions are timed by the evidence itself (when the work was done), so ranking stays fair.
- **Watermark:** each run records the instant it scanned up to, so the next run's window is "previous watermark → now".

Both paths write the same results. A partner call for an account that was first found by a sync adopts that participant instead of creating a duplicate.

## Who sees what

| Surface | Audience | Shows |
|---|---|---|
| Admin portal leaderboard | Administrators (Entra ID) | Everyone, every step, with export |
| Participant scorecard | The participant | Only their own steps, entered by lab account; there is no public leaderboard |

Scorecard lookups are rate-limited per client to slow down enumeration of lab accounts.

## Proving "genuine completion" for Copilot Cowork

### Evidence sources (per Microsoft documentation)

| Signal | Freshness | What it proves | Status |
|---|---|---|---|
| OneDrive file in the user's **Cowork** output folder (`driveItem` listing) | Seconds | The output exists, it was created after lab start, and its content matches | Confirmed: Cowork saves outputs to the user's OneDrive Cowork folder |
| Sent mail / calendar events (`/sentitems`, `/events`) | Near real time | Cowork's follow-up actions (send, schedule) happened | Freshness inferred from long-standing Graph behaviour |
| Copilot interaction export (`getAllEnterpriseInteractions`, `AiEnterpriseInteraction.Read.All`) | Varies by tenant | The user prompted Copilot about this task | API is v1.0. The Cowork `appClass` value and latency are confirmed per tenant during calibration |
| Purview audit `CopilotInteraction` (`/security/auditLog/queries`) | **60–90+ minutes** | Cowork activity, including "Cowork creates an artifact in OneDrive" | Confirmed that Cowork emits these records; latency confirmed as slow |
| `createdBy.application` on files | Seconds | Possibly that Copilot authored the file | Cowork "runs with the user's permissions", so authorship usually shows as the user; confirmed during calibration |

### The workaround for audit lag (what this build does)

- **Blocking checks use fast evidence only:** the output files in the Cowork folder plus content, mail and meetings. These answer the Complete button within seconds, using `retry_window_seconds` to cover propagation.
- **Copilot proof is deferred:**
  - The `copilot_interaction` and `copilot_audit` checks run with `mode: deferred`.
  - They are re-verified in the background and shown as a verification badge.
  - Purview audit queries are **batched into one tenant-wide query per 30-minute window**, because the tenant limit is a few hundred queries per day; there is never one query per participant.
- **Once latency is measured,** if the interaction export proves to be near-real-time, switch `copilot_interaction` to `mode: blocking` with a `retry_window_seconds` in the rubric. No code change is needed.

### Calibration to do on the first real Cowork run in the tenant

Record each of these once, then tighten the sample rubrics:
1. The `appClass` value on Cowork prompts in the interaction export, and the delay before they appear. Then set `app_class_contains`.
2. `AppIdentity`, `AgentName` and `AccessedResources` on the Cowork audit record. Then set `copilot_audit` params.
3. The exact OneDrive output folder path, and `createdBy.application` on a Cowork-created file. Then adjust `folder`, and set `created_by_application_contains` if it identifies Copilot.
4. Any header or extended property that marks mail sent by Cowork.

## Check types

| Type | Graph endpoint | Permission |
|---|---|---|
| `onedrive_file` | `/users/{upn}/drive/root:{folder}:/children` (+ `/content` for text checks) | Files.Read.All |
| `sharepoint_file` | `/sites/{site}` → `/drives` → `/children` | Files.Read.All |
| `mail_sent` | `/users/{upn}/mailFolders/sentitems/messages` | Mail.ReadBasic.All |
| `calendar_event` | `/users/{upn}/events` | Calendars.ReadBasic.All |
| `teams_channel_message` | `/teams/{id}/channels/{id}/messages` | ChannelMessage.Read.All |
| `copilot_interaction` | `/copilot/users/{id}/interactionHistory/getAllEnterpriseInteractions` | AiEnterpriseInteraction.Read.All |
| `copilot_audit` | `/security/auditLog/queries` (batched) | AuditLogsQuery.Read.All |

Content checks read `.docx`, `.pptx` and `.xlsx` (Office Open XML) plus text formats without extra libraries. Files over 15 MB are not downloaded.

## Throttling at event scale

Planning target: about 2,000 participants in an hour.
- **SharePoint/OneDrive:** the per-app tenant budget is 1,250 resource units (RU) per minute up to 1,000 licences, and 2,500 RU/min up to 5,000. A folder listing costs 2 RU. That is enough for about 18 listings per user per hour.
- **Outlook:** 10,000 requests per 10 minutes per mailbox. Not a concern.
- **Interaction export:** 30 requests per second per tenant.
- **Worker controls:** a semaphore (`VS_GRAPH_MAX_CONCURRENCY`) caps in-flight Graph calls per worker. `Retry-After` is honoured on 429 and 503.
- **Scale levers:** worker replicas (HPA on CPU), plus that concurrency setting.

## Data model

See `backend/db/migrations/001_initial.sql`.

| Table | Holds |
|---|---|
| `integrations` | Vendor credentials (hashed) and webhook config |
| `events` → `use_cases` → `steps` | Steps carry the YAML rubric plus a validated JSON copy and a version |
| `participants` | Per event, keyed by vendor `external_id`; `public_id` is used for public URLs |
| `submissions` | One per Complete click: the queue state, check results and reasons |
| `step_progress` | The leaderboard projection |
| `webhook_deliveries` | Outbound result callbacks |
| `audit_log` | Every admin action |

## Security

- **Vendor auth:** client credentials, a 60-minute HS256 JWT, revocable and rotatable. Rotation invalidates outstanding tokens.
- **Admin auth:** Entra ID (MSAL SPA → API scope `access_as_admin`), plus the app role `Scoring.Admin` with assignment required. Local password mode exists for test environments only.
- **Graph access:** a user-assigned managed identity through AKS workload identity. It holds read-only application permissions and no client secret.
- **Secrets:** stored in Key Vault and mounted through the Secrets Store CSI driver.
- **Network:** Postgres has a private endpoint only.
- **Shared tenant risk:** participants are users in the same tenant. Lab accounts must get **no Azure RBAC** on the scoring subscription. This is a lab partner prerequisite.
- **Public pages:** these show names in the configured format (default "Asha K."). Email, UPN and vendor IDs are never exposed. The realtime stream carries only "event changed" signals, no data.
