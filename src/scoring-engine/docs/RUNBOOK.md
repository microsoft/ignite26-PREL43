# Runbook

## A. Run locally (mock Microsoft Graph)

Requires Docker Desktop.

```bash
docker compose up -d --build                 # db, migrate+seed, api, worker, web
docker compose --profile demo up -d simulator              # optional: 40 participants; the lab partner calls the API
docker compose --profile demo-sync up -d simulator-no-api  # optional: 20 more who only work in Microsoft 365
```

| What | Where |
|---|---|
| Admin portal | http://localhost:8080. Username `admin`; the password is `VS_ADMIN_PASSWORD` in `docker-compose.yml` |
| Participant scorecard | http://localhost:8081. Enter a lab account, e.g. `labuser001@ignite.demo` or `labuser105@ignite.demo` |
| Frontend dev servers (hot reload) | `cd frontend && npm run dev:admin` (5173) and `npm run dev:scorecard` (5174), proxying to the API on 8000 |
| API reference | http://localhost:8080/api/docs |
| Demo vendor credentials | Inside the `evidence` volume: `docker compose exec api cat /app/samples/local/demo_credentials.json` |

In mock mode, the worker reads "Microsoft 365 evidence" from `/app/samples/local/mock_graph.json`. The simulator writes to that file before each click. To reset everything:

```bash
docker compose --profile demo down -v
```

Backend tests:

```bash
cd backend && uv venv -p 3.12 .venv && uv pip install -p .venv -e ".[dev]" && .venv/bin/pytest
```

## B. Pilot deployment (test tenant)

Goal: prove the lab partner handshake against a deployed engine, and prove scoring from real Microsoft 365 evidence with a few test lab accounts.

1. Deploy with `SIZE=small` following [DEPLOY.md](DEPLOY.md):
   ```bash
   cp deploy/env/tenant.env.example deploy/env/pilot.env     # TENANT_ID, SUBSCRIPTION_ID, hosts, SIZE=small
   ./deploy/scripts/deploy.sh deploy/env/pilot.env all
   ```
2. Point DNS for `ADMIN_HOST` and `SCORECARD_HOST` at the ingress IP the script prints, and assign **Scoring Admin** to the organisers.
3. Provision a few test lab accounts with Microsoft 365 Copilot licences and Cowork enabled.
4. **Calibration run:** do one real Cowork task per step with a lab account, then check the evidence under Admin → Events → Submissions → Evidence. Tighten the rubrics as described in `ARCHITECTURE.md` → Calibration.
5. **Partner handshake:**
   - Admin → Integrations → New integration. Copy the client ID and secret.
   - The lab platform calls `/oauth/token` and then `/v1/steps/complete`, following `docs/API_CONTRACT.md`.
   - Before the platform is wired up, `backend/scripts/vendor_simulator.py --api https://<admin-host> --credentials creds.json --mock-file /dev/null` exercises the same handshake.
6. **Pass criteria:**
   - A token is issued to the partner's client credentials.
   - A participant who did the work gets `complete`; one who didn't gets `incomplete` with a readable reason.
   - **Sync now** scores the same accounts with no partner call.
   - The admin leaderboard updates live, both exports open, and the scorecard shows only the looked-up participant.

## C. Event deployment

Same as B, in the event tenant, with `SIZE=standard`:

```bash
cp deploy/env/tenant.env.example deploy/env/event.env     # the event tenant's TENANT_ID and SUBSCRIPTION_ID
./deploy/scripts/deploy.sh deploy/env/event.env all
```

Then:
1. Create the event in the portal, or `POST /api/admin/events`. Its slug is the `event_id` the lab platform sends.
2. Add the use cases and steps, and paste the rubrics. Samples are in `backend/samples/rubrics/`.
3. Set the event to **live**.
4. Admin → Integrations → New integration. Send the lab partner the client ID and secret over a secure channel, along with `docs/API_CONTRACT.md`.
5. Share the participant scorecard URL `https://<scorecard-host>/<event_id>` with participants. Each participant enters their lab account and sees only their own results.
6. Optional: set the event's Entra group (Settings → Lab account roster) so **Sync now** can score accounts the lab platform has not reported.

### Lab partner checklist

- [ ] The lab platform's backend calls `POST /v1/steps/complete` on every Complete click, server to server, with an `Idempotency-Key`.
- [ ] The payload carries `lab_account.upn` (the event-tenant lab account) and `lab.lab_started_at`.
- [ ] The lab UI shows `status` and `reasons[].message`, and polls or uses `wait_seconds` while the status is `evaluating`.
- [ ] Lab accounts have Copilot licences and Cowork enabled, and **no** Azure role on the scoring subscription.
- [ ] Global Administrator and subscription Owner were granted to the deployment team, and the Graph admin consent step was completed.
- [ ] A load test at expected peak (for example 2,000 clicks in 10 minutes) was run against the pilot deployment.

## D. Operations

| Task | How |
|---|---|
| Scale for a peak | `kubectl -n vectorsense scale deploy/vectorsense-scoring-worker --replicas=6`, or raise `worker.autoscaling.maxReplicas` |
| Graph throttling | Worker logs show `graph throttled`. Lower `config.graphMaxConcurrency`; evaluations retry automatically |
| A participant disputes a result | Admin → Event → Submissions → open the submission → Evidence. Then Re-evaluate, or Mark complete with a note (audited) |
| Rotate vendor secret | Admin → Integrations → Rotate secret. Old tokens stop working immediately |
| Lab partner is not calling the API | Event → Leaderboard → **Sync now**. Every lab account on the roster is scored straight from Microsoft 365. Each run records the time it scanned up to; the next run only re-checks steps that are still open. Add accounts via Event → Settings → Lab account roster (Entra group or CSV) |
| Close the event | Event → Settings → Status: Closed. New Complete calls get `409 event_closed`. The public board stays up |
| Export results | Event → Leaderboard → CSV or Excel |
| Upgrade | `IMAGE_TAG=1.0.1 ./deploy/scripts/deploy.sh deploy/env/event.env images` then `... app`. Migrations run as a Helm pre-upgrade hook |
| Logs | Container Insights in the `vsl-<env>-law` Log Analytics workspace |
