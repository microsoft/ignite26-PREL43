# VectorSense Labs Scoring Engine: Lab Partner API Reference (v1)

Audience: lab platform partners who connect their **Complete** button to the Scoring Engine.

The scoring engine answers one question per click: **did this participant genuinely complete this step?** The answer is `complete` or `incomplete`. When it is `incomplete`, the response says why. The engine decides by reading real evidence (files, mail, meetings, Copilot activity) for the participant's lab account in the tenant where the engine is deployed.

The live OpenAPI reference is at `https://<host>/api/docs`.

---

## 1. Integration model

| Item | Value |
|---|---|
| Base URL | `https://<host>` (given to you at onboarding) |
| Authentication | OAuth 2.0 **client credentials**. The scoring admin issues a `client_id` and `client_secret` per vendor integration |
| Token lifetime | 3600 s. Cache it and refresh about 60 s before expiry |
| Transport | HTTPS only, JSON (UTF-8) |
| Who calls | **Your backend, server to server.** The secret must never reach a browser or a lab VM |
| Results | Poll `GET /v1/submissions/{id}`, hold the request open with `wait_seconds`, or receive a signed webhook |

### Vendor dependencies (must be in place before the event)

1. Your platform calls `POST /v1/steps/complete` from your backend whenever a participant clicks Complete (or Submit) on a step.
2. Every call carries the participant's **lab account UPN** in the tenant where the engine runs, and the **lab start time**. Without these, genuine work cannot be told apart from pre-built work.
3. You show the participant our `status` and `reasons[].message`. These messages are written for participants.
4. Lab accounts are licensed and enabled for Microsoft 365 Copilot, including Cowork, before the event.
5. Outbound HTTPS from your platform can reach our host. If we restrict the API by IP, you send us your egress IPs.

---

## 2. Handshake: get a token

```http
POST /oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&client_id=vsl_xxx&client_secret=vss_xxx
```

The engine also accepts HTTP Basic (`Authorization: Basic base64(client_id:client_secret)`) or a JSON body with the same fields.

```json
200 OK
{ "access_token": "eyJ...", "token_type": "Bearer", "expires_in": 3600 }
```

| Status | Body | Meaning |
|---|---|---|
| 400 | `{"detail":{"error":"invalid_request"}}` | Missing client_id or secret |
| 400 | `{"detail":{"error":"unsupported_grant_type"}}` | Only `client_credentials` is supported |
| 401 | `{"detail":{"error":"invalid_client"}}` | Wrong credentials, or the integration is revoked |

Rotating the secret in the admin portal invalidates the old secret **and every token issued with it**, immediately.

---

## 3. Participant clicked Complete

```http
POST /v1/steps/complete?wait_seconds=10
Authorization: Bearer <access_token>
Idempotency-Key: 6f1c2a1e-6b1f-4f4e-9d55-0d1f7f0c2a11
Content-Type: application/json
```

```json
{
  "event_id": "ignite-2026",
  "use_case_id": "cowork-sales-brief",
  "step_id": "step-3",
  "lab": {
    "lab_profile_id": "SKL-12345",
    "lab_instance_id": "inst-998877",
    "lab_started_at": "2026-11-18T10:42:00Z"
  },
  "participant": {
    "external_id": "skl-user-55621",
    "first_name": "Asha",
    "last_name": "Kumar",
    "email": "asha.kumar@contoso.com"
  },
  "lab_account": {
    "upn": "labuser0421@ignitetenant.onmicrosoft.com"
  },
  "submitted_at": "2026-11-18T11:15:09Z"
}
```

| Field | Required | Notes |
|---|---|---|
| `event_id` | yes | Event slug agreed at onboarding |
| `use_case_id` | yes | Use case code, as configured in the engine |
| `step_id` | yes | Step code within the use case |
| `lab.lab_started_at` | yes | ISO-8601 UTC. Evidence created before this time is rejected |
| `lab.lab_profile_id`, `lab.lab_instance_id` | recommended | For support and audit |
| `participant.external_id` | yes | Your stable participant ID. It is the key for the leaderboard and progress |
| `participant.first_name`, `last_name`, `email` | recommended | Used for the administrator leaderboard and exports, and to greet the participant on their own scorecard |
| `lab_account.upn` | yes | The lab account the participant works as, in the engine's tenant |
| `submitted_at` | optional | When the participant clicked. Defaults to the time the engine receives the call |

| Header / query | Notes |
|---|---|
| `Idempotency-Key` | **Strongly recommended.** One UUID per click. Retrying with the same key returns the original submission (`Idempotent-Replayed: true`) and never scores twice |
| `wait_seconds` (0–25) | Holds the request open until the result is final or the time runs out. Use about 10 for a simple button flow |

### Response

`200 OK` when the result is final within `wait_seconds`; `202 Accepted` while it is still evaluating.

```json
{
  "submission_id": "0d734b37-c10b-46ea-bf80-c53d27ce21a2",
  "event_id": "ignite-2026",
  "use_case_id": "cowork-sales-brief",
  "step_id": "step-3",
  "participant_external_id": "skl-user-55621",
  "status": "incomplete",
  "completed": false,
  "reasons": [
    { "check": "brief_emailed",
      "message": "No sent email with \"Contoso\" in the subject and an attachment was found since your lab started." }
  ],
  "verification": { "status": "not_required" },
  "received_at": "2026-11-18T11:15:09.412Z",
  "evaluated_at": "2026-11-18T11:15:40.090Z",
  "links": {
    "self": "https://<host>/v1/submissions/0d734b37-...",
    "participant_scorecard": "https://<scorecard-host>/ignite-2026"
  },
  "poll_after_seconds": 3
}
```

| `status` | `completed` | Meaning | What to show the participant |
|---|---|---|---|
| `evaluating` | `null` | Evidence is still being checked. Some checks re-try for up to their retry window (typically 30–60 s) to absorb Microsoft 365 propagation delay | A spinner: "Checking your work…" |
| `complete` | `true` | Every blocking check passed | Step complete |
| `incomplete` | `false` | At least one blocking check failed | Each `reasons[].message`, plus "fix it and click Complete again" |
| `error` | `false` | Evidence could not be read after retries (for example, Microsoft Graph unavailable) | "We couldn't verify this step right now. Please try again." |

`verification.status` covers slower Copilot evidence, such as the Purview audit log. It never changes `status`.

| Value | Meaning |
|---|---|
| `not_required` | No slow evidence is configured for this step |
| `pending` | Slow evidence is still being confirmed |
| `verified` | Slow evidence confirmed |
| `unverified` | Slow evidence never appeared; flagged for organiser review |

Clicking Complete again on an already-complete step is harmless: complete is sticky on the leaderboard.

### Errors

| Status | `detail.error` | Meaning |
|---|---|---|
| 401 | n/a | Missing, expired or revoked token |
| 404 | `unknown_event` / `unknown_use_case` / `unknown_step` | The IDs don't match the engine's configuration |
| 409 | `event_closed` | The event is closed for submissions |
| 409 | `step_not_configured` | The step has no scoring rubric yet |
| 422 | `invalid_payload` | `detail.errors[]` lists `{field, message}` |
| 5xx | n/a | Retry with the **same** Idempotency-Key and exponential backoff |

---

## 4. Get a result

```http
GET /v1/submissions/{submission_id}
Authorization: Bearer <access_token>
```

The response has the same shape as section 3. Poll every `poll_after_seconds` (3 s) until `status` is not `evaluating`. Evaluation usually finishes within 2–60 s, depending on each step's retry window.

## 5. Participant progress

```http
GET /v1/events/{event_id}/participants/{external_id}/progress
Authorization: Bearer <access_token>
```

```json
{ "event_id": "ignite-2026", "participant_external_id": "skl-user-55621",
  "completed_steps": 3, "total_steps": 6,
  "steps": [ { "use_case_id": "cowork-sales-brief", "step_id": "step-1", "title": "Draft the Contoso account brief",
               "status": "complete", "attempts": 1, "completed_at": "2026-11-18T10:58:02Z" } ] }
```

## 6. Optional: result webhook

If the integration has a webhook URL, every final result is POSTed to it:

```http
POST <your webhook URL>
Content-Type: application/json
X-VectorSense-Delivery: <delivery id>
X-VectorSense-Signature: t=1763464540,v1=<hex HMAC-SHA256>

{ "type": "submission.evaluated", "data": { ...same shape as section 3... } }
```

To verify a delivery:
1. Compute `HMAC_SHA256(webhook_secret, "<t>." + raw_body)` and compare it to `v1` with a constant-time comparison.
2. Reject deliveries where `t` is more than 5 minutes old.

Failed deliveries are retried with backoff for up to 8 attempts. Respond with `2xx` quickly.

## 7. Limits and behaviour

- **No vendor code runs in the engine.** Vendors send identifiers only. What counts as "complete" is defined in the engine's rubric for each step.
- **Rate:** a token covers any number of calls. Double-clicks are made safe by `Idempotency-Key`.
- **Privacy:** there is no public leaderboard. A participant can open `participant_scorecard` and enter their lab account to see only their own results; the full leaderboard is visible to event administrators only.
- **Scoring without partner calls:** organisers can also run a Microsoft 365 sync from the admin portal, which scores every lab account directly from its evidence. Partner calls and syncs feed the same results, so an integration can go live in stages.
