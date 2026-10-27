HelixKit v1.0.4

Removable media for the Copilot Cowork lab (COWORK-T1). Attached to the lab VM; the life cycle action
"Prepare Helix workspace" (Prepare-Helix-Workspace.ps1) finds this folder and runs, in PowerShell 7:

  Grant.ps1       grants the cloud credential's app any missing Graph permissions (as tenant admin)
  Learner.ps1     sets the learner (the tenant admin) and gives it a Copilot licence (lab variable LearnerUpn)
  Preflight.ps1   checks Microsoft Graph permissions, learner and licences (writes nothing)
  Hydrate.ps1     writes the Helix launch story into the learner's Microsoft 365 (data pack inside)
  Readiness.ps1   confirms the day-one items and that no scoring check already passes
  Score-All.ps1   prints the whole scorecard as JSON (for testing)

pwsh\ holds a portable PowerShell 7, used when PowerShell 7 is not installed on the VM.