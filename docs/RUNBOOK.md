# Runbook

How to prepare, run and close an event with the Cowork lab. Lab profile settings are in
[lab-profile.md](lab-profile.md); first-time set-up and testing is [STEPS.txt](../STEPS.txt).

## 1. Sign-off on a test launch (before the first event)

| Check | Pass when |
|---|---|
| Life cycle | *Prepare Helix workspace* green; log shows `Network ready`, the three steps and ends with `Helix workspace ready.`; note how long it took |
| Status line | Pre-flight, Hydration, Readiness all `ok` (or blank, see STEPS F1, with a green action) |
| Sign-in | The Office 365 admin (Lab Access) signs in at m365.cloud.microsoft; Authenticator set-up on first sign-in; **Cowork** shows in Copilot |
| Data | Outlook: Helix mail and this week's meetings. Teams: *Launch - Helix* channel with posts and 8 files |
| Copilot | Cowork answers a question about Helix with sources (indexing can take a while after hydration) |
| Baseline | Milestone 1 *Check my work*: only *Third focus block not created* is green (10 points) |
| Pass path | After step 1.3, *Three drafts saved by Cowork* turns green |
| Timing | Each *Check my work* answers in under a minute |

## 2. Before an event

1. Set `$EventDate` in the *Prepare Helix workspace* script to the event day (D). Check `$EventTimeZone`.
2. Remove the *Lab preparation status* NOTE from Getting started.
3. Schedule pre-instances: participants + 15 %, starting **no earlier than D−1 09:30** event time.
4. Spot-check one pre-built instance with section 1, including **Copilot credits: ok** and a Cowork task that runs.
   The Copilot credits API is a preview: re-test it in the week before the event.
5. **Open with Skillable before the first event:** does First Displayable run while a pre-instance is built, or
   only when the learner opens the lab? If only on open, every learner waits 10–20 minutes for hydration.
   VM scripts cannot run at Post-Build.

Re-runs are safe: hydration skips what already exists and rebuilds a half-imported team.

## 3. During the event

| Symptom | Do |
|---|---|
| A learner's *Check my work* says *We couldn't check this right now* | Wait a minute and check again; Graph throttling clears by itself |
| Everything red, including *Third focus block* | Learner is signed in as the admin, not the learner account in the instructions |
| An instance never became ready | Skillable ended it (End lab); the pool provides another |

## 4. After the event

Results are in Skillable's reports (Activity scores, pass at 70). Tenants are destroyed by Skillable; nothing
else to clean up. For the next event, change `$EventDate` and pre-build again.

## 5. Releasing a change

Rebuild (`./build/Build.ps1 -CloudCredential WWLM365E7 -Iso`), run the tests, then:
content or hydration change → upload the new `HelixKit-<version>.iso`, point the Removable Media image path at it, and re-paste the life cycle script (it checks the ISO version);
check change → re-paste the affected activity scripts; guide change → re-paste `Lab-Instructions.md`. Changes apply only to labs launched afterwards.
