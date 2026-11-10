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
| existing | "Enable TAP Prereqs + Generate TAP" (variables `TAP`, `TAP2`) | Post-Build | — | Leave as is: not used by the guide, and Studio does not allow editing them | | | |
| new | **Prepare Helix workspace**: Execute Script in Virtual Machine, PowerShell (Start from Scratch) | **First Displayable** (VM scripts cannot use Post-Build) | `lifecycle/Prepare-Helix-Workspace.ps1` | **Yes** (unticked by default) | 45 min | End lab (Log while testing) | 0 |

The script waits up to 2 minutes for the HELIXKIT DVD and up to 5 minutes for internet (at First
Displayable the VM can be up before its network), uses PowerShell 7 (installed, or the portable copy from the media extracted to
`C:\ProgramData\HelixKit\pwsh`), and runs Grant, Credits, Learner, Pre-flight, Hydrate, Readiness and CreditsCheck (about 7–10 minutes on a fresh tenant). Any failure stops it with
the last lines of output, and **End lab** keeps a broken tenant away from participants.

**Grant** adds any Graph permissions the credential's app lacks in this launch's tenant, signed in as the
tenant admin from the tokens on lines 21–23 (`@lab.CloudCredential(WWLM365E7).TenantName`, `.Username`,
`.Password`; if the username token is unfilled it uses `admin@<TenantName>`). Check once that `.Username`
and `.Password` match the credential's property names in Studio. It needs an admin without MFA, and does
nothing when the credential already has every permission.

Edit before each event, at the top of the script: `$EventDate` (yyyy-MM-dd; left as `YYYY-MM-DD` a
launch uses today) and `$EventTimeZone` (Windows name, default `India Standard Time`). The script also sets the lab
desktop's time zone to `$EventTimeZone`, so meetings and the 8:00 briefing show at the learner's local time.

Lab variables it sets: `PermissionStatus`, `PreflightStatus`, `HydrationStatus`, `HydratedAt`, `ReadinessStatus`, `CreditsStatus`
(each `ok`), `LearnerUpn`, `CreditsPolicyId`.

**Credits:** switches Cowork on, replacing the manual *Activate* in admin center → Copilot → Cost management. It signs in as
the admin, registers a helper app (*HelixKit Copilot Credits*) with admin consent for the delegated CopilotCostManagement
permissions, and creates a spending policy for **all users** with **Cowork** on (Work IQ too when accepted), billed to
**prepaid credits** (the tenant's Capacity Pack), 25,000 credits a month and 20,000 per user. An existing active all-users
policy with Cowork on is reused. **CreditsCheck** waits up to 10 minutes for the policy to become *enabled*. With
`$RequireCredits = $true` (line 17) a failure ends the lab; `$false` lets a test continue. The API is a Microsoft
**preview** (Graph beta): re-test before each event.

**Learner:** this launch's **Office 365 admin** (`AdministrativeUsername` token; `$LearnerUpn = 'admin'` on line 22). If the
admin has no licence that includes Copilot, the Learner step assigns one: a free seat, or else the seat of the last spare
licensed user by UPN, always keeping 6 users for the Helix meeting organisers. It sets `usageLocation` first.

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

Every script (Settings tab): target **Virtual Machine → Win11-Pro-Base**, language **PowerShell**, Script enabled
**on**, Show output to user **on**, Retries 0, score value and *Task list properties → Task Name* as below. The scripts
need no cloud subscription: each runs its check in the PowerShell 7 that the life cycle action installed in the VM.
The lab VM must be running when the learner selects Check my work. (`optional/activities-cloud/` has the same checks
as Cloud Subscription scripts, PS 7.x, for a profile that has a subscription.)

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
