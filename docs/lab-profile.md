# Lab profile settings (Skillable Studio)

Every setting in one place. The step-by-step version is [STEPS.txt](../STEPS.txt). Files are in `skillable/`.

## Removable media

| Setting | Value |
|---|---|
| Media tab | Removable Media *HelixKit Media*, type **Optical**, image path to `HelixKit-<version>.iso` (about 107 MB) in the lab's media storage |
| Virtual Machines tab | Win11-Pro-Base → **DVD Drive: HelixKit Media** (this inserts it at start; the Media tab alone does not) |
| New release | Upload under the new versioned name and change the image path (the life cycle script checks the version and stops on a mismatch) |
| Contents | `HelixKit\` with `kit.json`, `Preflight.ps1`, `Hydrate.ps1` (Helix data pack inside), `Readiness.ps1`, `Score-All.ps1`, `pwsh\PowerShell-7.4.6-win-x64.zip` |

The VM needs outbound HTTPS to `login.microsoftonline.com` and `graph.microsoft.com`.

## Life cycle

| # | Action | Event | Script | Blocking | Timeout | Error action | Retries |
|---|---|---|---|---|---|---|---|
| existing | The lab's TAP action (for the Azure Portal account) | as today | as today | Leave it; our lab doesn't use a TAP | | | |
| new | **Prepare Helix workspace**: Execute Script in Virtual Machine, PowerShell (Start from Scratch) | **First Displayable** (VM scripts cannot use Post-Build) | `lifecycle/Prepare-Helix-Workspace.ps1` | **Yes** (unticked by default) | 45 min | End lab (Log while testing) | 0 |

The script waits up to 2 minutes for the HELIXKIT DVD and up to 5 minutes for internet (at First
Displayable the VM can be up before its network), uses PowerShell 7 (installed, or the portable copy from the media extracted to
`C:\ProgramData\HelixKit\pwsh`), and runs Grant, Learner, Pre-flight, Hydrate and Readiness (about 6–7 minutes on a fresh tenant; longer if the admin needed a licence). Any failure stops it with
the last lines of output, and **End lab** keeps a broken tenant away from participants.

**Grant** adds any Graph permissions the credential's app lacks in this launch's tenant, signed in as the
tenant admin from the tokens on lines 21–23 (`@lab.CloudCredential(WWLM365E7).TenantName`, `.Username`,
`.Password`; if the username token is unfilled it uses `admin@<TenantName>`). Check once that `.Username`
and `.Password` match the credential's property names in Studio. It needs an admin without MFA, and does
nothing when the credential already has every permission.

Edit before each event, at the top of the script: `$EventDate` (yyyy-MM-dd; left as `YYYY-MM-DD` a
launch uses today) and `$EventTimeZone` (Windows name, default `India Standard Time`).

Lab variables it sets: `PermissionStatus`, `PreflightStatus`, `HydrationStatus`, `HydratedAt`, `ReadinessStatus` (each `ok`),
`LearnerUpn`.

**Learner:** this launch's **Office 365 admin** (`AdministrativeUsername` token; `$LearnerUpn = 'admin'` on line 18). If the
admin has no licence that includes Copilot, the Learner step assigns one: a free seat, or else the seat of the last spare
licensed user by UPN, always keeping 6 users for the Helix meeting organisers. It sets `usageLocation` first. Cowork
itself (enabled for the tenant, Copilot credits) must come with Skillable's tenant; no Graph API turns it on.

## Pre-instancing (events)

Pre-build participants + 15 %, **starting no earlier than D−1 09:30** in the event time zone. Earlier builds
stop at Hydrate with "Outside the hydration window" and nothing written (Teams refuses future-dated posts).

## Instructions

Replace with `Lab-Instructions.md`. It signs learners in with `@lab.CloudCredential(WWLM365E7).AdministrativeUsername` /
`.AdministrativePassword` (Authenticator set-up on first sign-in), shows the lab preparation status line (remove before the event), and ends each
milestone with `@lab.Activity(CheckM1)` … `@lab.Activity(CheckM5)`.

## Scored Activities

Activities tab: Scoring Mode **Activity Scoring**, Passing Score **70**. Five Automated (Script)
Activities; Name and Replacement Token Alias both **CheckM1** … **CheckM5**.

Every activity: Show results in reports **on**, Scored **on**, Display scripts as task list **on**,
On-demand evaluation **on**, Custom evaluation button text **on** (*Check My Work*), Allow retries **on**,
Maximum attempts off, Required for submission off, Blocks page navigation off. Evaluation button placement
*Above task list*. With the task list on, On-demand evaluation shows greyed but ticked, and the activity's
feedback boxes move to each script's **Outcomes** tab (optional: Correct *Done.*, Incorrect *Not found yet -
read the hint, fix it, and check again.*); the scripts print their own result and hint anyway.

Activities, life cycle actions and the ISO apply only to labs launched after a change. A lab that was
running when an activity was added shows "The specified script was not found".

Every script (Settings tab): target **Cloud Subscription**, language **PowerShell**, version **PS 7.x** (for
example *PS 7.1.3 | Az 6.0.0*, never 5.1), Script enabled **on**, Show output to user **on**, Retries 0, score value
and *Task list properties → Task Name* as below.

| Activity | Script (`activities/`) | Score | Task name |
|---|---|---|---|
| CheckM1 | `M1/1-drafts-saved.ps1` | 8 | Three drafts saved by Cowork |
| | `M1/2-focus-block-approved.ps1` | 7 | Focus block approved |
| | `M1/3-focus-block-always-allow.ps1` | 7 | Focus block added with Always allow |
| | `M1/4-third-block-cancelled.ps1` | 10 | Third focus block not created |
| CheckM2 | `M2/1-risk-register-columns.ps1` | 10 | Risk register has the right columns |
| | `M2/2-unconfirmed-marked.ps1` | 7 | Unconfirmed figures marked |
| CheckM3 | `M3/1-skill-saved.ps1` | 12 | Status report skill saved |
| | `M3/2-status-report-produced.ps1` | 10 | Status report produced with the skill |
| CheckM4 | `M4/1-briefing-email-received.ps1` | 15 | Daily briefing email received |
| CheckM5 (optional) | `M5/1-meeting-prep-skill.ps1` | 5 | Meeting prep skill saved |
| | `M5/2-companion-template.ps1` | 4 | Companion template created |
| | `M5/3-skill-inventory.ps1` | 5 | Skill inventory produced |

Each script reports Correct with what it found, or Incorrect with the check's hint. If Microsoft Graph is
unavailable it reports Incorrect with "We couldn't check this right now" and the details, and the learner
simply checks again. The check scripts need no edits between events.
