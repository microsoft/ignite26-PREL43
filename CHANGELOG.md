# Changelog

Cowork Lab (Launch Command Center, COWORK-T1): hydration and scoring for Skillable lab profile PREL 43.
The version is the HelixKit version: the ISO name, `kit.json` and the life cycle script all carry it, and the
script refuses an ISO of another version.

## 1.0.6 – 2 Nov 2026

### Update: reviewer wording – 3 Nov 2026

Lab guide only (re-paste `Lab-Instructions.md`; the ISO, life cycle and Check my work scripts are unchanged):

- Header: removed "(Milestones 1-4. Milestone 5 is optional.)"; "Lab Use case" is now "Know your use case:".
- Use Case Briefing: "How Cowork works" is now "How Cowork can help you fix this problem"; "General Tips" is
  now "Know before you start!", with a tip to keep the InPrivate window open.
- Getting started step 2 is now "Let's get your access verified!": the username and password first, then an Edge
  InPrivate window with Teams, Outlook, Calendar and Copilot links. The data check table stays; the 404 line is gone.
- Copilot and OneDrive steps open in the InPrivate window instead of "Edge".
- The VM image was cleaned of a saved sign-in from an older tenant (`tools/Clean-VmImage.ps1`).

**Final QA release.** It brings together the fixes from all four testers (Vidusha, Ishan, Gaurang and Christian
Coello's GitHub issues #11, #13–#18; see `docs/QA-Feedback-Fix-Plan.xlsx`) and the 1.0.5 updates below. Upload the
new ISO and re-paste everything (STEPS.txt).

- **New ISO, `HelixKit-1.0.6.iso`.** Its scoring code matches the Check my work scripts. The life cycle script
  refuses any other ISO version.
- **Lab guide (Christian's issues).**
  - #11: if sign-in asks for Authenticator, a passkey or a code, select **Use your password instead**. This also
    covers Outlook and Teams in Edge.
  - #13: 2.3 now says 15–20 minutes, with Stop / Resume if nothing changes for 10 minutes and a Q&A tip for
    proctors. Milestone 2 is 65 minutes.
  - #14: the full path to the channel: *Teams and channels → Zava Product Launches → See all channels →
    Launch - Helix*.
  - #15: the exact option is **Create a skill with Cowork**, not *Upload the skills file*.
  - #16: 3.2 and 5.1 are simpler. Type the skill name when asked, skip or describe-your-own for any other question,
    then type the rules. If unsure, just send the rules in the message box.
  - #17: 5.5 says it can take 5–10 minutes, with Stop / Resume guidance. The 5.4 OneDrive fallback was already in
    1.0.5. Milestone 5 is 48 minutes.
  - #18: 5.9 says how to create Skill-Inventory in OneDrive in Edge, and that any folder works.
- **Scoring.**
  - The skill, template and skill-inventory checks now ignore case, spaces, dashes, underscores and a plural
    "Skills", so *Skills Inventory.docx* and *Helix_Meeting_Prep* pass.
  - The status report check stays strict (`Helix-Status`), so a "Helix status card" doesn't count.
  - The skill-inventory hint now says "anywhere in your OneDrive".
  - The "Skil_inventory.docx" text Christian saw is not in our scripts: re-pasting the 1.0.6 scripts replaces it.
- **Security tidy-up.** Removed the dev tenant ID from `tools/Invoke-Local.ps1` and
  `docs/implementation-plan.html`.
- **Tests.** 2 new tests (loose names pass; the status report name stays strict). 92 in total.

## 1.0.5 – 28 Oct 2026

### Update: QA fixes – 30 Oct 2026

Changes from the QA runs by Vidusha, Ishan and Gaurang (fix plan: `docs/QA-Feedback-Fix-Plan.xlsx`).
The ISO and the 12 Check my work scripts are unchanged.

- **Lab guide: typing into the lab desktop.**
  - Every prompt is now one line. Typed multi-line prompts pressed Enter halfway and sent half a prompt.
  - The Windows and Microsoft 365 credentials are typed (T icon), not copied: the clipboard does not reach the VM.
  - New tip: copy and paste doesn't reach the lab desktop; type by hand if typing fails.
- **Lab guide: Cowork's current screens.**
  - New skill: *Customize → arrow next to Add → Create skill with Cowork*, then type the exact skill name
    (`launch-status-report`, `helix-meeting-prep`) when asked.
  - "Skills & Plugins" is now **Plugins** in the Workspace panel.
  - Sharing a skill: *Share → Publish → Only you → Publish* (no proctor needed; not scored).
  - Always allow: *arrow next to Save → Always allow*; revoke before the third request, and delete
    *Helix status review* if it was created anyway.
  - Step ticks may not update: judge by the final reply and the saved files.
- **Lab guide: content fixes.**
  - The 2.1 brief now says 10 days (it said 3).
  - Owners **and mitigations** not in a source are UNCONFIRMED.
  - The status report skill uses the last 7 days when there is no earlier report.
  - The meeting prep skill hands off to *launch-status-report* for status requests.
  - The template's five headings no longer run into the next sentence.
  - Duration says Milestone 5 is optional; step 3 points to the *Use Case Briefing* page.
- **Lab guide: places learners got stuck.**
  - Outlook, Calendar (week view), Teams and OneDrive open in Edge (the desktop apps ask for updates).
  - How to show a hidden *Launch - Helix* channel and find *Shared*.
  - Calendar row: 4 Helix meetings in the next 3 days, 2 of them tomorrow and overlapping.
  - SKILL.md and brief-template.docx: open from the file card or OneDrive in Edge, not File Explorer.
  - Keep the *Sent by Copilot Cowork* line in one draft until Check my work.
  - The 8:00 briefing uses the account's time zone, and each send asks first.
- **Life cycle script.** Sets the lab desktop's time zone to `$EventTimeZone`, so meetings, Cowork's "today"
  and the 8:00 briefing line up. A failure only logs a warning.
- **Tests.** The guide must have no multi-line prompt, no copied credentials, and every name the checks look for.
  90 in total.

### Update: Check my work runs in the lab VM

Skillable removed the Azure subscription from PREL 43, so every Check my work script failed with "Unable to
determine what subscription to run the script against".

- The 12 scripts in `activities/` now run **in the lab VM** (target *Virtual Machine → Win11-Pro-Base*). No cloud
  subscription needed. Each is a small Windows PowerShell script that runs the same check in the PowerShell 7 that
  *Prepare Helix workspace* installed, and reports Correct or Incorrect with the same messages.
- The secret goes to PowerShell 7 through the environment, not the command line, and is removed afterwards.
- The old cloud versions are kept in `optional/activities-cloud/` for a profile that has a subscription.
- No change to the ISO or the life cycle script: re-paste the 12 scripts and change each one's Target.
- 3 new tests: every VM check scores the same against the test tenant, the scripts run in Windows PowerShell 5.1,
  and the wrapper reports through `Set-ActivityResult` end to end. 90 in total.

### First release of 1.0.5

**Cowork works without the manual Activate click.**

- **Copilot credits, automated.** The life cycle action now creates the Copilot credits spending policy itself
  (new *Credits* step, after Grant). It signs in as the tenant admin and creates a policy for **all users** with
  **Cowork** on (Work IQ too when Microsoft accepts it), billed to the tenant's **prepaid credits** (the Capacity
  Pack), 25,000 credits a month and 20,000 per user. An existing active all-users policy with Cowork on is reused.
  This replaces *admin center → Copilot → Cost management → Activate*.
- **Credits check.** A new last step, *CreditsCheck*, waits up to 10 minutes for the policy to become active.
  `$RequireCredits = $true` (line 17 of the script) ends the lab if it doesn't; set `$false` only for tests.
- **Head start for Cowork.** The policy is created early and switches on while the Helix data loads.
- **Optional:** `lifecycle/Enable-Admin-TAP.ps1`, Skillable's admin TAP script with a 48-hour pass. Not needed: the
  guide no longer uses a TAP, and Studio does not let us edit the TAP actions.
- **Lab guide.**
  - Includes the team's changes: new title, *Use Case Briefing*, *Lab Tasks*, *General Tips*, *Bonus Challenge*.
  - The separate *Sign in to Microsoft 365* step is gone. *Getting started* step 2 opens Copilot and signs in with
    the admin **Username + Administrative Password** (no TAP), then checks Cowork and the Helix data.
  - Removed the "do not use Azure credentials" tip.
  - The status line adds **Copilot credits**.
  - The report name shows its date again (`Helix-Status-YYYY-MM-DD.docx`).
- **Life Cycle tab (Skillable).** Leave the TAP actions as they are.
- **Tests.** 9 new tests for the credits steps; 87 in total.
- **Note.** The Copilot Cost Management API is a Microsoft **preview** (Graph beta). It must be available in the
  tenant, and it can change: re-test before each event.

## 1.0.4 – 26 Oct 2026

**The learner is each launch's Office 365 admin.**

- Learners sign in with the **Administrative Username / Password** from Lab Access. No fixed user name (AlexW) is
  assumed.
- The *Learner* step gives the admin a licence that includes **Copilot** if it has none: a free seat, or else the
  seat of a spare user, always keeping 6 users for the Helix meetings.
- Our own TAP step was removed (not needed for the admin).
- **Lab guide rewritten in simple English:** short steps, bullets and Skillable's own blocks. Prompts, file names and
  event titles are unchanged, so scoring still finds them.
- **Check my work messages** are now "Done. Found …" or "Not yet. Go to step X.Y …".
- Fixed: a tenant with a single licence type could not be licensed (one-item list bug).
- Full live run on PREL 43 passed at **90/100**, with one deliberate mistake caught by the checks.

## 1.0.3 – 23 Oct 2026

- No fixed learner name: a licensed user of the launch's tenant is chosen and published as `LearnerUpn`.
- Our action issued the learner a 48-hour TAP (later replaced in 1.0.4).
- Fixed: the TAP lab variable was dropped before it reached Skillable.

## 1.0.2 – 23 Oct 2026

- New *Grant* step: when the cloud credential's app lacks Graph permissions, it signs in as the tenant admin and
  grants them, then waits until they are active.
- Admin tokens: `AdministrativeUsername` / `AdministrativePassword`.

## 1.0.1 – 23 Oct 2026

- Fixed: every Graph call failed on real tenants (`-StatusCodeVariable` is not an `Invoke-WebRequest` parameter).
  The simulated tenant had hidden it; new tests run the real Graph client.
- The ISO carries its version in its name, and the script refuses a different ISO version.

## 1.0.0 – 23 Oct 2026

**Hydration moves into the lab VM.**

- Hydration (with the Helix data pack) runs from removable media (`HelixKit.iso`) through one *Execute Script in
  Virtual Machine* action at **First Displayable**. Large cloud scripts failed with "argument list too long", and VM
  scripts cannot run at Post-Build.
- The script waits for the DVD and for the network, uses a portable PowerShell 7 from the ISO, and logs plain text.
- The 12 *Check my work* scripts were shrunk to 16–20 KB and made pure ASCII (Skillable's editor corrupts curly
  quotes).
