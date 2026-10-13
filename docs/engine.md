# Engine: vs-hydrate

The command-line engine of the VectorSense Hydration Kit. It writes the Zava Helix launch into a Microsoft 365 tenant, prepares one seat per learner, checks each seat before release and scores the learner at Submit.

```
vs-hydrate validate                 read-only checks; changes nothing
vs-hydrate tenant                   personas, profiles, managers, photos, reviewer account
vs-hydrate seats --count N          create, license and hydrate N seats (re-run resumes)
vs-hydrate check [--seat UPN]       readiness check; writes out/seat-inventory.json
vs-hydrate score --seat UPN --json  12 scoring checks for one seat
vs-hydrate retire --seat UPN | --used | --failed
```

Common options: `--config tenant.yaml`, `--json`, `--dry-run`, `--concurrency N`, `--offline`, `-v`.
Exit codes: `0` success, `1` validation failed, `2` partial failure (see the report), `3` configuration error.

## Layout

```
src/engine/vs_hydrate/
  cli.py            argument parsing, exit codes, reports
  config.py         tenant.yaml loading and validation
  kit.py            run context; --dry-run wrapper
  datapack.py       data pack loading and checksum verification
  timeline.py       lab-day offsets ("D-9 09:12") -> real times in the seat time zone
  render.py         {{learner}} / {{date:D+2}} placeholders in text and Office files
  integrity.py      forbidden-phrase lint (no seeded item may satisfy a scoring check)
  scoring.py        scorecard evaluation against a seat's mail, calendar and OneDrive
  textextract.py    text from docx/xlsx/pptx/pdf/md for scoring and lint
  state.py          out/state.json, seat inventory, reports
  api/base.py       the tenant operations the kit uses
  api/graph.py      Microsoft Graph implementation (certificate auth, throttling-aware retries)
  api/fake.py       in-memory tenant for tests and --offline rehearsals
  ops/              one module per command
src/engine/tests/   offline end-to-end tests and Graph transport tests
```

## How each workload is written

| Workload | Method | Notes |
|---|---|---|
| Personas | `POST /users`, licence, manager, photo | Created once per tenant by `tenant`; updated in place on re-run, never deleted. Sign-in disabled by default. |
| Seat | `POST /users`, seat licences, seat group, mailbox settings, manager | `lab0001@domain` upward. Numbers are never reused. |
| Teams | Migration-mode team and channel, `POST .../messages` with `createdDateTime` and `from`, then `completeMigration` on every channel and the team, then the seat is added as owner | One "Zava Product Launches" team per seat. Personas are not members unless `team_add_personas: true` (each user can belong to at most 1,000 teams). |
| Channel files | `GET .../filesFolder`, upload to the channel folder and a Recordings subfolder | Placeholders inside .docx are rendered per seat before upload. |
| Mail | `POST /users/{seat}/mailFolders/inbox/messages` with MAPI extended properties | `PR_MESSAGE_FLAGS` makes it a received message rather than a draft; sent and received times, Message-ID, In-Reply-To, References and the conversation index keep the supplier thread as one conversation. Unread state is applied afterwards. |
| Calendar | Event created in the organiser persona's calendar with the seat as attendee; the seat's copy is found by iCalUId and accepted without a response; the invitation messages are removed from the seat's Inbox | `transactionId` makes creation idempotent. |
| TAP | `POST .../temporaryAccessPassMethods` | Starts two hours before the lab day; lifetime from config. |

Write order per seat: user, licence, group, mailbox, profile, team, posts, complete, members, files, mail, calendar, invites, TAP. Every phase is recorded in `out/state.json`, and every created item's ID is recorded as it is written, so an interrupted run resumes without duplicates.

## Microsoft Graph application permissions

| Permission | Used for |
|---|---|
| `User.ReadWrite.All` | Personas, seats, profiles, managers, licences, photos |
| `Group.ReadWrite.All` | Seat group membership; deleting seat teams at retire |
| `Organization.Read.All` | Reading licence SKUs |
| `UserAuthenticationMethod.ReadWrite.All` | Temporary Access Pass per seat |
| `MailboxSettings.ReadWrite` | Seat time zone and locale |
| `Mail.ReadWrite` | Seeded mail; reads for readiness and scoring |
| `Calendars.ReadWrite` | Meetings, acceptance, cancellation at retire |
| `Teamwork.Migrate.All` | Migration-mode teams, channels and backdated posts |
| `TeamMember.ReadWrite.All` | Adding the seat to its team |
| `ChannelMessage.Read.All` | Readiness check of channel posts |
| `Files.ReadWrite.All` | Channel files; reading OneDrive for scoring |
| `Sites.ReadWrite.All` | Channel SharePoint folders |

Entra roles for the app: **User Administrator** and **License Administrator**. Certificate credential only.

## Platform limits the design works around

- **Teams import refuses future timestamps.** All seeded content ends at D-1 09:00, so `seats` runs from D-1 09:30 (seat time zone) for a lab on D0, and refuses earlier with exit code 3. Seats cannot be pooled days ahead of the event.
- **Copilot cannot be queried app-only.** The readiness check verifies content, anchors, search indexing and scoring integrity through Graph. The Copilot question-and-answer check is a manual spot-check on one seat per batch (see `instructions/instructor-notes.md`).
- **Some tenant settings are invisible to app-only Graph** (Cowork enablement, the Copilot Credits policy, mail-flow rules, the TAP policy). `validate` lists them as attestations the operator confirms in `tenant.yaml`.
- **Profile fields `aboutMe` and `skills` cannot be written app-only.** Personas get name, title, department, office, manager and photo.
- **Scoring reads data directly, not through search.** Results do not wait on the search index. A OneDrive check that fails while the learner's OneDrive changed in the last 20 minutes is listed under `recheck`.
- **Persona calendars collect one copy of each meeting per seat.** `retire` cancels them.

## Development

```bash
pip install -e "./src/engine[test]" python-docx openpyxl reportlab pillow
python src/tools/build_datapack.py
python -m pytest src/engine/tests -q
```

`--offline` runs any command against an in-memory tenant saved in `out/offline-tenant.json`, so the whole flow can be rehearsed without a tenant:

```bash
vs-hydrate validate --offline && vs-hydrate tenant --offline && vs-hydrate seats --count 3 --offline
vs-hydrate check --offline && vs-hydrate score --seat lab0001@zava.example --offline
```

## Install

```bash
pip install ./src/engine
vs-hydrate --version
```

Set `VS_POLL_SECONDS` to change how often the engine polls for provisioning (default 10).
