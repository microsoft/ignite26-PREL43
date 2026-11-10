# Cowork Lab: hydration and scoring for Skillable

Hydration and scoring for the Copilot Cowork lab **Launch Command Center (COWORK-T1)**. Everything runs
inside Skillable; nothing is deployed in Azure. Every participant gets a fresh Microsoft 365 tenant.

| Part | Where it runs | What it does |
|---|---|---|
| **Hydration** | One life cycle action, *Execute Script in Virtual Machine*, at First Displayable. It runs the HelixKit scripts from an ISO attached to the lab VM | Pre-flight (Graph permissions, learner, licences), then writes the Helix launch story into the learner's Microsoft 365 (people, Teams channel, files, mail, calendar), then a readiness check |
| **Scoring** | Five scored Activities, *Check my work* at the end of each milestone (12 small cloud scripts) | Reads the learner's mail, calendar and OneDrive; each item turns green, or red with a hint. 100 points, pass mark 70 |

## Start here

**Setting up or testing a lab profile? Open [STEPS.txt](STEPS.txt)** and follow it top to bottom. Everything it
asks you to paste or upload is in [skillable/](skillable):

```
skillable/
  HelixKit-1.0.6.iso                          upload as removable media, attach to the lab VM
  lifecycle/Prepare-Helix-Workspace.ps1       the hydration life cycle action (VM script, First Displayable)
  lifecycle/Enable-Admin-TAP.ps1              the admin's 48-hour sign-in pass (cloud script, Post-Build)
  activities/M1 ... M5/*.ps1                  the 12 Check my work scripts (run in the lab VM; no subscription needed)
  Lab-Instructions.md                         full lab guide: sign-in, status line, Check my work blocks
  optional/activities-cloud/                  the same 12 checks as cloud scripts (only if the profile has a subscription)
  optional/TapPolicy.ps1, TapIssue.ps1        only if the lab's own TAP action is ever replaced
  media/HelixKit/                             what is inside the ISO (for reference)
```

The package is built for the cloud credential **WWLM365E7**. Learners sign in with each launch's **Office 365 admin** (Administrative Username/Password in Lab Access). The life cycle action makes sure that admin has a Copilot licence and puts the Helix data in its mailbox, calendar and the Launch - Helix team.

## Documents

| Document | Use it to |
|---|---|
| [STEPS.txt](STEPS.txt) | Configure the lab profile, launch, test, troubleshoot (plain text, open in Notepad) |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Run an event: before, during and after; sign-off checklist |
| [docs/lab-profile.md](docs/lab-profile.md) | Every Skillable setting in one place |
| [docs/tenant-requirements.md](docs/tenant-requirements.md) | What each participant tenant must have (checked by pre-flight) |
| [docs/implementation-plan.html](docs/implementation-plan.html) | The plan, for sharing |
| [CHANGELOG.md](CHANGELOG.md) | What changed in each version |

## For developers

```
src/common/        Graph client, timeline, text/Office/PDF handling, data pack loader
src/lifecycle/     Grant, Credits, Learner, Preflight, Hydrate, Readiness, Launcher (the VM life cycle action),
                   AdminTap (the admin's TAP action); Tap (optional scripts only)
src/scoring/       Checks (scorecard check types), Activity (one check per script)
content/           Lab-Instructions.md (source of the lab guide)
config/            scorecard.json, readiness.json
datapack/          helix-datapack-1.0.0.json.gz (240 KB; built into Hydrate.ps1 on the ISO)
build/Build.ps1    builds skillable/
tools/             Get-PortablePwsh.ps1, Convert-DataPack.ps1, Invoke-Local.ps1
tests/             Pester: unit, end-to-end against an in-memory tenant, and the built skillable/ package
```

Build (PowerShell 7; `-Iso` needs macOS `hdiutil` or Windows `oscdimg`):

```powershell
./tools/Get-PortablePwsh.ps1                       # once: portable PowerShell 7 for the ISO (vendor/)
./build/Build.ps1 -CloudCredential WWLM365E7 -Iso
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser   # once
Invoke-Pester ./tests                              # 87 passed
```

Optional build parameters: `-EventDate yyyy-MM-dd` (otherwise set it in the life cycle script; without one a
launch uses today), `-EventTimeZone` (default `India Standard Time`), `-LearnerUpn`.

| Change | Do |
|---|---|
| New data pack release | `./tools/Convert-DataPack.ps1 -Zip <path>/helix-datapack-<v>.zip` (needs `powershell-yaml`), rebuild, upload the new ISO |
| Scorecard change | Update `config/scorecard.json`, rebuild, re-paste the affected activity scripts |
| Lab guide change | Edit `content/Lab-Instructions.md`, rebuild, re-paste |
