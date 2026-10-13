# Hydration Kit — Operator Guide for Skillable

**Product:** VectorSense Hydration Kit for the Copilot Cowork hands-on lab
**Audience:** Skillable lab engineers and operations staff
**Kit version:** 1.0.0 (built in the `vectorsense-hydration-kit` repository; not yet run against a live tenant)

> Zava Corporation is Microsoft's fictional company, used here as it is in the track. Production releases may ship with a VectorSense fictional company; nothing in the procedures below changes.

---

## 1. What the kit does

The Hydration Kit fills a Microsoft 365 tenant with the Zava Helix launch, two weeks before it is due to ship:
- people and an org chart;
- a six-message supplier thread and other Helix mail;
- the Launch - Helix Teams channel with about twenty posts;
- six shared files and two sync notes;
- four meetings in the next five days.

It then prepares one ready-to-use seat per learner. It also checks each seat before release and scores the learner when they select Submit.

The kit serves the **Launch Command Center** track (COWORK-T1): four required milestones (M1–M4) and an optional fifth (M5), scored by 12 automatic checks worth 100 points with a pass mark of 70.

**Readiness check versus track.** The readiness check is an operator step, not a learner activity. Before a seat is released, the kit confirms the six day-one data items are present, checks that every seeded fact is anchored in the seat's mail, posts, files and calendar, checks that the content is searchable, and confirms that nothing in the seat already satisfies a scoring check. Copilot cannot be queried with app-only credentials, so a proctor also asks the seven fact questions on one seat per batch (see `lab/instructor-notes.md`). Learners never see the readiness check.

Skillable owns the tenant, the licences and the lab VMs, and runs the kit. VectorSense supplies the kit under licence. The kit runs with Skillable's credentials; VectorSense never has access to the tenant.

## 2. How the kit is delivered

VectorSense delivers the kit as **source code in a private GitHub repository in Skillable's GitHub organisation**. There is no container image and no separate file share: Skillable clones the repository, installs the engine with `pip`, and runs it. Each release is a git tag (`v1.0.0`) with notes in [release-notes.md](release-notes.md).

```
vectorsense-hydration-repository/
├─ data/
│  ├─ helix/                      The Helix story as data (source of the data pack)
│  ├─ release/
│  │  └─ helix-datapack-1.0.0.zip Built data pack: personas, mail, Teams channel, files, calendar
│  ├─ readiness/
│  │  └─ check-set-1.0.0.json     Readiness check items, seeded facts and expected answers
│  └─ scoring/
│     ├─ scorecard.json                                12 checks, points, skill areas, pass mark
│     └─ Launch_Command_Center_Scorecard_Template.xlsx Proctor scorecard, event results, seat readiness
├─ docs/                          This guide, engine and data pack references, release notes
├─ infra/
│  ├─ config/tenant.example.yaml  Configuration template
│  └─ entra/                      App registration permissions and setup script
├─ instructions/                  Learner lab guide (plain and Skillable markdown), instructor notes
└─ src/engine/                    The vs-hydrate engine (Python package) and its tests
```

The built data pack carries a SHA-256 checksum for every file it contains; `validate` verifies them before anything is written.

## 3. Prerequisites

### 3.1 Tenant

| Item | Requirement |
|---|---|
| Tenant | Dedicated to this lab and persistent between sessions |
| Persona accounts | 32 accounts, Microsoft 365 E3, created by the kit, never deleted |
| Seat licences | Microsoft 365 E5 (or E3) and Microsoft 365 Copilot, available in the tenant for the kit to assign |
| Cowork | Enabled for the seat security group only, with usage-based billing on |
| Copilot Credits | Billing policy linked to an Azure subscription, with a per-seat cap |
| Sign-in | Temporary Access Pass enabled for the seat group |
| Mail routing | Seats can mail themselves and internal personas; mail to external addresses (the supplier) goes to a sink mailbox rather than being rejected |
| OneDrive | Provisioned for every seat before hydration; left empty |
| Time zone | Seat mailbox time zone set to the event region, so “tomorrow at 10:00” lands correctly |
| Reviewer account | One named lab user for Milestone 5 skill sharing |

### 3.2 App registration

Create one app registration in the tenant for the kit. Use a **certificate credential** (no client secrets), and grant admin consent for these **application** permissions:

| Permission | Used for |
|---|---|
| `User.ReadWrite.All` | Personas, seats, profiles, managers, licences, photos |
| `Group.ReadWrite.All` | Seat group membership; removing seat teams at retire |
| `Organization.Read.All` | Reading licence SKUs |
| `UserAuthenticationMethod.ReadWrite.All` | Temporary Access Pass for each seat |
| `MailboxSettings.ReadWrite` | Seat time zone and regional settings |
| `Mail.ReadWrite` | Seeded mail; readiness and scoring reads |
| `Calendars.ReadWrite` | Meetings, acceptance, cancellation at retire |
| `Teamwork.Migrate.All` | Backdated Teams team, channel and messages |
| `TeamMember.ReadWrite.All` | Adding each seat to its team |
| `ChannelMessage.Read.All` | Readiness check of channel posts |
| `Files.ReadWrite.All` | Channel files; reading OneDrive for scoring |
| `Sites.ReadWrite.All` | Channel SharePoint folders |

Grant the app the **User Administrator** and **License Administrator** Entra roles, and nothing broader. `infra/entra/setup-app-registration.ps1` does all of this in one run. Store the certificate in Skillable's key vault and place the PEM (private key and certificate) on the runner host at the path set in `auth.certificate_path`.

### 3.3 Runtime

- **Runner host:** any Linux, Windows or macOS machine or VM with **Python 3.11 or later** and git, for example a Skillable automation host. The same host runs the Submit activity's `score` call, so it keeps the `out/` folder (seat state and inventory) between commands.
- **Network:** outbound HTTPS to `login.microsoftonline.com` and `graph.microsoft.com`. No inbound ports.
- **Size:** 2 vCPU and 4 GB memory are sufficient. Run time is driven by Microsoft Graph throttling, not compute.

## 4. Install and configure

On the runner host:

```bash
git clone <Skillable's private repository URL> vectorsense-hydration-repository
cd vectorsense-hydration-repository
git checkout v1.0.0
python -m venv .venv && source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install ./src/engine
vs-hydrate --version
```

Copy `infra/config/tenant.example.yaml` to `tenant.yaml` at the repository root (it is git-ignored) and fill it in. Relative paths resolve from the folder that holds `tenant.yaml`:

```yaml
tenant:
  id: 00000000-0000-0000-0000-000000000000     # Directory (tenant) ID
  domain: zava.example                          # Verified domain used for UPNs
auth:
  client_id: 00000000-0000-0000-0000-000000000000
  certificate_path: /etc/vs-hydrate/vs-hydration.pem  # PEM from Skillable's key vault
datapack:
  path: data/release/helix-datapack-1.0.0.zip
licences:
  seat_skus: [SPE_E5, Microsoft_365_Copilot]   # SKU part numbers in the tenant (SPE_E3 also supported)
  persona_sku: SPE_E3
seats:
  prefix: lab                                   # lab0001@zava.example, lab0002@...
  group: VS-Lab-Seats                           # Cowork is enabled for this group
  time_zone: "India Standard Time"              # Mailbox time zone for the event region
  reviewer: helix.reviewer@zava.example         # Named lab user for M5 sharing
lab_day: 2026-10-20                             # Event date; anchor for relative dates (auto = run date)
output:
  dir: out                                      # Reports and seat inventory are written here
```

## 5. Commands

Run every command from the repository root on the runner host:

```bash
vs-hydrate <command> --config tenant.yaml
```

| Command | What it does | When to run |
|---|---|---|
| `validate` | Checks permissions, licences, the seat group, the data pack and the hydration window. Lists Cowork enablement, the credits policy, the mail sink and the TAP policy as attestations to confirm, because app-only access cannot see them. Changes nothing. | Before every other command |
| `tenant` | Creates personas, directory profiles and the reviewer account | Once per tenant, and again after a new data-pack release |
| `seats --count N` | Creates and licenses N new seats, sets the time zone, issues a Temporary Access Pass, and writes each seat's Helix mail, Launch - Helix team and channel, shared files and calendar | From D−1 09:30 (seat time zone) for an event on D0, sized to expected launches plus a 15% buffer |
| `check` | Runs the readiness check on each new seat: six day-one items, seeded facts, scoring integrity. Marks seats `ready` or `failed` | After seats are indexed; re-run until all seats are settled |
| `score --seat <upn>` | Runs the 12 scoring checks for one seat; prints a JSON result | When the learner selects Submit |
| `retire --seat <upn>`, `retire --used` or `retire --failed` | Removes a seat (its team, its meetings and the account) and releases its licences | At lab teardown, in bulk after an event, or for seats that failed `check` |

Common options:
- `--json`: prints machine-readable output.
- `--dry-run`: shows what would change, without writing anything.
- `--concurrency <n>`: parallel writes. The default respects Microsoft Graph throttling, so change it only on VectorSense's advice.

Exit codes: `0` success · `1` validation failed · `2` partial failure (see the report) · `3` configuration error.

Every write is idempotent, so a failed or interrupted run can be re-run safely and resumes where it stopped. Re-running `seats` after exit code 2 resumes the unfinished batch; it does not create extra seats.

**Hydration timing.** Microsoft Teams import cannot write posts dated in the future, and the latest seeded content is D−1 09:00. Run `seats` from D−1 09:30 in the seat time zone for an event on D0; earlier runs stop with exit code 3. Seats therefore cannot be pooled days ahead, and `check` marks a seat failed once its lab day has passed.

## 6. Running an event

### First time in a new tenant
1. `validate`
2. `tenant`
3. Wait for indexing, then continue with "Before each event".

### Before each event
1. Set `lab_day` to the event date, then run `validate`
2. On D−1 (from 09:30), `seats --count N`
3. Wait for indexing. Microsoft 365 needs time to index new content before Copilot can find it.
4. `check`. Re-run until no seats remain pending.
5. Load `out/seat-inventory.json` into the Skillable seat pool. Only seats with `"state": "ready"` are listed. The file holds Temporary Access Passes; keep it in the key vault, not in a shared folder.
6. A proctor runs the Copilot spot-check on one ready seat (`lab/instructor-notes.md`).

### During the event
- **Launch:** assign one ready seat per learner from the pool and show its Entra username and Temporary Access Pass under Lab Access (see section 7).
- **Milestones:** learners work through M1–M4 (and optionally M5) in Cowork. Their outputs land in their own mailbox, calendar and OneDrive.
- **Submit:** the Submit activity runs `score` for the seat (see section 8).
- **Lab reset:** when a learner asks for a reset because day-one data is missing, assign the next ready seat and mark the old one for `retire`.

### After the event
1. `retire --used`, then `retire --failed`
2. `seats --count N` to replenish the pool for the next event.

## 7. Lab launch integration

`seat-inventory.json` contains one entry per ready seat:

```json
{ "upn": "lab0042@zava.example", "tap": "<Temporary Access Pass>", "state": "ready", "datapack": "1.0.0" }
```

In the Skillable lab profile:

1. **On launch,** a life cycle action takes the next unused seat from the pool and stores its Entra username and Temporary Access Pass as lab variables.
2. **In Lab Access,** show both values for the learner to sign in to Microsoft 365 in Edge on the lab VM.
3. **Optionally,** set the seat's display name to the learner's name and event code. This makes proctoring easier.
4. **On teardown,** a life cycle action calls `retire --seat <upn>`, or marks the seat for the bulk retire after the event.

Seats are single-use. Never assign a seat to a second learner.

## 8. Scoring integration

The published scorecard has **12 automatic checks worth 100 points, with a pass mark of 70**. Every check reads the learner's own mailbox, calendar and OneDrive through Microsoft Graph for the item a step produces; nothing is handed in beyond Submit. Reading directly rather than through search means results do not wait for indexing.

| Milestone | Check | Points | Skill area | Passes when the learner's data has |
|---|---|---|---|---|
| M1 | `drafts-saved` | 8 | Functional correctness | Mail containing “Sent by Copilot Cowork” |
| M1 | `focus-block-approved` | 7 | Functional correctness | Event “Helix messaging review” |
| M1 | `focus-block-always-allow` | 7 | Functional correctness | Event “Helix launch checklist” |
| M1 | `third-block-cancelled` | 10 | Security and governance | No event “Helix status review” |
| M2 | `risk-register-columns` | 10 | Functional correctness | OneDrive file containing “Source evidence” |
| M2 | `unconfirmed-marked` | 7 | Security and governance | OneDrive file containing UNCONFIRMED |
| M3 | `skill-saved` | 12 | Architecture and best practices | OneDrive item matching launch-status-report |
| M3 | `status-report-produced` | 10 | Functional correctness | OneDrive file matching Helix-Status |
| M4 | `briefing-email-received` | 15 | Functional correctness | Mail “Helix launch briefing” |
| M5 | `meeting-prep-skill` | 5 | Architecture and best practices | OneDrive item matching helix-meeting-prep |
| M5 | `companion-template` | 4 | Architecture and best practices | OneDrive item matching brief-template |
| M5 | `skill-inventory` | 5 | Functional correctness | OneDrive file matching Skill-Inventory |

**Submit activity pattern** (Skillable activity, Python):

```python
import json, subprocess
seat = "@lab.Variable(SeatUpn)"          # Lab variable set at launch
result = subprocess.run(
    ["vs-hydrate", "score", "--seat", seat, "--config", "/opt/vectorsense-hydration-repository/tenant.yaml", "--json"],
    capture_output=True, text=True)
score = json.loads(result.stdout)
print(score["feedback"])                 # Shown to the learner
exit(0 if score["passed"] else 1)        # Pass mark 70
```

**Result format:**

```json
{
  "seat": "lab0042@zava.example",
  "score": 79,
  "max": 100,
  "pass_mark": 70,
  "passed": true,
  "checks": { "drafts-saved": 8, "focus-block-approved": 7, "focus-block-always-allow": 7,
              "third-block-cancelled": 10, "risk-register-columns": 10, "unconfirmed-marked": 0,
              "skill-saved": 12, "status-report-produced": 10, "briefing-email-received": 15,
              "meeting-prep-skill": 0, "companion-template": 0, "skill-inventory": 0 },
  "recheck": ["unconfirmed-marked"],
  "feedback": "M1–M4 complete except the UNCONFIRMED check, which will be re-checked after indexing."
}
```

**Re-checks.** A OneDrive check that fails while the learner's OneDrive changed in the last 20 minutes (a file may still be syncing) is listed in `recheck`; run `score` again later, or have a proctor confirm it in `Launch_Command_Center_Scorecard_Template.xlsx`.

**Two interpretations of the published scorecard** (both in `data/scoring/scorecard.json`): `unconfirmed-marked` ignores SKILL.md and the skill quality report, so the M3 skill text cannot earn the M2 points; and `third-block-cancelled` has an optional guard, off by default, that requires at least one focus block before awarding its 10 points.

**Why the readiness check matters for scoring.** Because every check looks for an item in the learner's data, any seeded item that matches a check would award free points, or for `third-block-cancelled`, take them away. The readiness check confirms that no seeded mail, event or file matches any check before the seat is released.

## 9. Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| `validate` reports missing permission | Consent not granted, or wrong app | Grant admin consent to the permissions in 3.2 |
| `seats` exits with code 2 | Throttling or a transient Graph error | Re-run the same command; it resumes |
| `seats` exits with code 3, "too early" | Run before D−1 09:30 for the configured `lab_day` | Wait until the stated time, or correct `lab_day` |
| `check` keeps seats pending | Content not yet indexed | Wait and re-run `check` |
| `check` marks a seat failed | Content missing or not findable | Run `retire --seat <upn>`, then `seats --count 1` |
| Learner sees no Cowork option | Seat not in the Cowork group, or licence still provisioning | Check group membership and licence state; assign another ready seat |
| Learner reports missing day-one data | Seat released before indexing finished | Lab reset: assign the next ready seat and retire this one |
| Focus blocks land at the wrong hour | Seat mailbox time zone differs from the learner's expectation | Set `seats.time_zone` to the event region before hydrating |
| Cowork task stops mid-run | Seat reached its credit cap | Raise the cap for the event; M2 builds four outputs and uses the most credits |
| A file-based check fails right after the step | Search indexing lag | Re-run `score` later or have a proctor re-check |

Every command writes a report to `out/` (`report-<command>-<timestamp>.json`). Attach it to any support request.

## 10. Security and licence notes

- The kit only reads from and writes to the configured tenant. It sends no data anywhere else.
- Credentials stay with Skillable. VectorSense never receives tenant access or certificates.
- Every person, company and product in the data pack is fictional.
- Skillable receives the kit's source code. Use of the kit, including the data pack, engine and scoring pack, is governed by the licence agreement between Skillable and VectorSense. Copying, modifying or using the kit outside licensed engagements is not permitted.

## 11. Releases and support

- **Versioning:** each release is a git tag carrying one version number for all components, for example `v1.0.0`. Check out the tag, then `pip install ./src/engine` again. A data-pack change needs `tenant` to be re-run; an engine-only change does not.
- **Release notes:** [docs/release-notes.md](release-notes.md) lists changes and any required actions for each tag.
- **Support:** raise issues with VectorSense. Include the release tag, the command run and the report file from `out/`.
