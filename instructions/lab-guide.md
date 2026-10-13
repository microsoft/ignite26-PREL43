# Launch Command Center: Delegate, Verify and Automate with Microsoft 365 Copilot Cowork

Exported from the prod catalog on 12 Oct 2026 (track `01a11641-9c28-7948-8e61-a9dfc14f6f22`, revision `9d237608-9325-4fca-8783-98027d0a11c1`). Advanced · 3 hrs - Individual.

## Contents

- [Getting started](#getting-started)
- Milestone 1: Master the Delegation Controls
- Milestone 2: Build the Readiness Pack from a Single Brief
- Milestone 3: Capture Your Reporting Standard as a Skill
- Milestone 4: Schedule the Daily Launch Briefing
- Milestone 5: Combine Skills into a Toolkit (Optional)

## Getting started

### GS-1. Open your lab desktop (2 min)

*Start your lab machine.*

1. On **Your lab desktop**, select **Launch Lab**.
2. If you're asked to sign in, take the **Desktop username** and **Desktop password** from **Lab Access** in the **Lab Guide**.
3. From here on, everything happens on this desktop rather than your own computer.

**Expected:** The Windows desktop of your lab machine loads.

> **Important:** Addresses in these instructions are for copying, not clicking. Select **Copy**, then paste into the **Microsoft Edge** address bar on the lab desktop. A click opens the page on your own computer instead of inside the lab.

**Done when:** The lab desktop is open and you're signed in.

### GS-2. Sign in to Microsoft 365 (3 min)

*Sign in to Microsoft 365 in Edge with the lab account.*

1. Open **Microsoft Edge** on the lab desktop and go to:

*Address · Microsoft 365*

```text
https://m365.cloud.microsoft
```

2. Sign in with the **Entra username** and **Temporary Access Pass** (or **Temporary password**) from **Lab Access**.
3. Hit a **404**? Open an **InPrivate** window in Edge and try again.

> **Important:** Stick to the lab account. Over the next few hours you'll send mail, change a calendar and schedule an automation, and all of that belongs in the lab tenant, not yours.

**Expected:** The Microsoft 365 home page, signed in as your lab user.

**Done when:** You're signed in to Microsoft 365 with the lab account.

### GS-3. Check Cowork and the Helix data (5 min)

*Make sure Cowork is switched on and the six pieces of Helix data are in place.*

1. Go to Microsoft 365 Copilot:

*Address · Microsoft 365 Copilot*

```text
https://copilot.cloud.microsoft/chat
```

2. Open the other apps from the **Start** menu on the lab desktop.
3. Work through the table and tick off each item.

| Where to look | What to confirm |
| --- | --- |
| Microsoft 365 Copilot | **Cowork** appears in the left pane beside **Chat**. If it's missing, give it a minute and refresh. |
| Outlook > Inbox | A thread of 6 messages about a supplier that's at risk. |
| Microsoft Teams > Launch - Helix | Roughly 20 posts in the channel. |
| Launch - Helix > Shared | Helix-Product-Spec.docx, Helix-Launch-Plan.docx, Helix-Pricing.xlsx, Competitor-1-SensorCloud.pdf, Competitor-2-EdgeSense.pdf and Competitor-3-Gen3.pdf. |
| Launch - Helix > Shared > Recordings | Helix-Sync-Notes-1.docx and Helix-Sync-Notes-2.docx. |
| Outlook > Calendar | 4 meetings over the next 5 days, with at least 2 overlapping. |

4. Anything missing? Select **Help** in the left bar and ask for a lab reset. Later steps depend on this data, so don't work around a gap.

> **Note:** There are no real meeting recordings in this lab. The two Helix-Sync-Notes files play that role, so treat them as the record of two earlier Helix meetings.

**Done when:** Cowork is available and all six items check out.

### GS-4. Read the briefing and scenario (2 min)

*Get the scenario and the deadline in your head.*

1. Open the **Briefing** tab in the **Lab Guide** and read it through.
2. The short version: you lead the Helix launch at Zava Corporation, it ships in 10 days, and an executive wants to know if that date is safe.
3. Come back to the **Instructions** tab when you're ready for Milestone 1.

**Done when:** You've read the briefing and know your role and the deadline.

**Learn more:**

- Get started with Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/get-started

## Milestone 1: Master the Delegation Controls

*40 min · required · 10 steps*

Learn how Cowork's controls behave: a catch-up with sources, reply drafts, stopping and resuming a task, and giving and taking back a permission.

**Objectives:**

- Delegate a multi-step catch-up and follow it in the Workspace panel
- Interrupt a long task and resume it
- Grant, use and revoke an Always allow permission

**Criteria:**

- Catch-up with every risk sourced, and three reply drafts reviewed in Outlook
- Helix messaging review and Helix launch checklist on tomorrow's calendar
- Permission revoked and the Helix status review request cancelled

### M1-1. Get caught up, with sources (5 min)

*Start a Cowork task that pulls the launch picture together from mail, Teams and files.*

1. Open Microsoft 365 Copilot in a new Edge tab:

*Address · Microsoft 365 Copilot*

```text
https://copilot.cloud.microsoft/chat
```

2. Select **Cowork** in the left pane, then **New task**.
3. Paste the prompt below into the **What's left to wrap up?** box and send it.

```text
I've just inherited the Helix launch, and it ships in 10 days. Bring me up to speed.
List what is at risk, which decisions are still open, who is waiting on me, and anything I have missed over the last two weeks. Search my inbox, the Launch - Helix Teams channel and the files shared there, and cite every email, Teams post and file you rely on.
```

4. Keep an eye on the **Workspace** panel on the right while it runs. **Steps** counts progress (for example **1 / 4**), and **Tools** shows which systems Cowork is pulling from, such as Outlook, Teams and Work IQ.

**Expected:** A catch-up covering what's at risk, which decisions are open and who's waiting on you.

**Done when:** The catch-up run is complete.

### M1-2. Check the source behind each risk (3 min)

*Make sure each risk in the catch-up points to a source.*

1. Go through the finished answer risk by risk.
2. Each one should cite an email, a Teams post or a file.
3. Only files cited? Start a **New task** and send the same prompt again. It names the inbox, the channel and the files deliberately, to stop the search from narrowing.

**Done when:** Every risk in the catch-up cites a source.

### M1-3. Get three replies drafted (4 min)

*Get three reply drafts that wait in Outlook.*

1. Stay in the same task and send:

```text
Draft replies to the two people who have been waiting on me the longest. Also draft a short holding reply on the supplier escalation thread saying I now own the launch and will confirm our position within 48 hours.
```

2. Let the run finish. The replies are saved as Outlook drafts, and nothing is sent.

**Expected:** Cowork confirms it saved three drafts.

**Done when:** Three reply drafts are saved in Outlook.

### M1-4. Deal with the drafts in Outlook (4 min)

*Decide what happens to each draft yourself.*

1. Open **Outlook** from the **Start** menu and go to **Drafts**. Or copy this address into Edge:

*Address · Outlook Drafts*

```text
https://outlook.office.com/mail/drafts
```

2. Look for the three **[Draft]** replies. Each one ends with **Sent by Copilot Cowork**.
3. Open them one at a time. Edit the text, or use the trash icon to throw one away.
4. Send the ones you're happy with. Keep or send at least one, since scoring looks for the **Sent by Copilot Cowork** line.
5. Notice that nothing left your mailbox until you pressed **Send** yourself.

**Expected:** Three **[Draft]** replies in the **Drafts** folder.

**Done when:** You've reviewed all three drafts and kept or sent at least one.

### M1-5. Stop a task mid-run (4 min)

*Stop a long comparison partway through.*

1. Still in the same task, send this longer request:

```text
Compare the Helix launch plan with the product spec in the shared launch files.
Find every point where they disagree and list each one with the section reference from both documents.
```

2. While it's running, select the stop icon in the message box. Stopping mid-step is fine.
3. Check **Steps** in the **Workspace** panel to see how far it got.

> **Note:** **Steps** sometimes trails by a few seconds. Give it a moment before you decide the run has stalled.

**Expected:** The run stops with some steps still unfinished.

**Done when:** The comparison task stopped before it finished.

### M1-6. Resume the stopped task (3 min)

*Restart the stopped comparison without leaving the task.*

1. Send this in the same task:

```text
Resume
```

2. Let it run to the end.

**Expected:** Each disagreement is listed, with the section headings from both documents.

**Done when:** The comparison picked up again and finished in the same task.

### M1-7. Plan the week without changing it (4 min)

*Get a proposal for the week without any calendar changes.*

1. Next, send:

```text
My calendar for the next five days has conflicts. Plan my week around the Helix launch: tell me which meetings to keep, which to delegate and which to decline, and where I need focus blocks to finish the readiness review. Do not change anything yet; just propose the plan.
```

2. Read through the plan. Because the prompt says not to change anything, there's no approval card this time.

**Expected:** A proposed week (meetings to keep, delegate and decline, plus focus blocks) and no changes on your calendar.

**Done when:** You have a week plan and your calendar is unchanged.

### M1-8. Approve a calendar change with Always allow (5 min)

*Put the first focus block on the calendar through an approval card.*

1. Now ask for a real change:

```text
Add a 30-minute focus block to my calendar tomorrow at 10:00 titled "Helix messaging review".
```

2. An approval card appears, for example **Create calendar event?** with a label such as **Medium risk**.
3. Check the time and title. You can edit both on the card.
4. Open the arrow next to the action button and choose **Always allow**.
5. Select the action button to approve.

> **Warning:** Don't type a new message while the card is open. Doing so cancels the action and throws away any edits you made.

**Expected:** **Helix messaging review** is on tomorrow's calendar at 10:00.

**Done when:** The first focus block was created through the card, and Always allow is granted.

### M1-9. Rely on the standing permission (3 min)

*Add a second focus block. This time no card should appear.*

1. Send this in the same task:

```text
Add another 30-minute focus block to my calendar tomorrow at 14:00 titled "Helix launch checklist".
```

2. Watch **Steps** in the **Workspace** panel. Because of **Always allow**, there's no approval card.
3. Open your calendar and check that both focus blocks are there.

**Expected:** **Helix messaging review** and **Helix launch checklist** both sit on tomorrow's calendar.

**Done when:** The second focus block was created with no approval card.

### M1-10. Take the permission back (5 min)

*Take back Always allow and cancel the third request.*

1. Open **Permissions** in the **Workspace** panel.
2. Revoke the calendar event permission.
3. Then, in the same task, send:

```text
Add one more 30-minute focus block to my calendar tomorrow at 16:00 titled "Helix status review".
```

4. The approval card is back. Select **Cancel**.

> **Note:** **Always allow** lasts for the current task only. Every new task starts without it.

**Expected:** The approval card returns, and no **Helix status review** event appears on your calendar.

**Check:** Milestone 1 is complete when:
- Every risk in the catch-up has a citation
- You've reviewed the three drafts in Outlook
- Tomorrow's calendar has **Helix messaging review** and **Helix launch checklist**
- The permission is revoked and there's no **Helix status review** event

**Done when:** The permission is revoked and the third request was cancelled.

**Learn more:**

- Get started with Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/get-started
- Use Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork

## Milestone 2: Build the Readiness Pack from a Single Brief

*52 min · required · 10 steps*

One brief produces a readiness deck, risk register, customer PDF and status card. Then you check them, trace them to source and fix what's wrong.

**Objectives:**

- Produce four linked outputs from one written brief
- Check the structure and consistency of all four
- Trace a risk and a number to source and fix a defect by instruction

**Criteria:**

- Deck (8 slides or fewer), 10-column risk register, one-page PDF and status card from one brief
- One risk and one number traced to source, with unsupported items marked UNCONFIRMED
- Same recommendation in all four outputs, with any defect fixed by instruction

### M2-1. Send the readiness brief (5 min)

*Hand Cowork the whole readiness pack in one prompt.*

1. Select **New task** in Cowork.
2. Paste in the brief below and send it.

```text
You are the launch program manager for Helix.
Review every file in the Launch - Helix Teams channel. Decide whether Helix is ready to launch in 3 days, and build one coordinated launch-readiness package.
DELIVERABLE 1 - EXECUTIVE READINESS DECK
Build a PowerPoint deck of at most 8 slides covering:
- A clear GO, CONDITIONAL GO or NO-GO recommendation
- The evidence behind that recommendation
- The 10-day launch timeline
- The top three risks, with their owners and mitigations
- Competitive position
- Commercial position
- Missing information or approvals that could change the recommendation
- Speaker notes on the recommendation, risk and commercial slides
DELIVERABLE 2 - RISK REGISTER
Build an Excel workbook with one row per risk you can evidence, using these columns:
- Risk
- Category
- Likelihood
- Impact
- Owner
- Mitigation
- Status
- Source file
- Source evidence
- Confidence
Never invent an owner. If no owner is explicitly named, enter UNCONFIRMED.
DELIVERABLE 3 - CUSTOMER ONE-PAGER
Write a one-page, customer-facing document and export it as a PDF. Use only product claims backed by the source files. Leave out internal risks, unsupported comparisons and speculative benefits.
DELIVERABLE 4 - EXECUTIVE STATUS CARD
Post a short status card in this Cowork session with:
- Launch recommendation
- Three headline reasons
- Number of evidenced open risks
- Number of critical blockers
- Missing approvals
- Links to the generated artifacts
EVIDENCE AND QUALITY RULES
- Use only information from the source files.
- Every number must trace back to a named source file.
- Cite the source for every risk and every major conclusion.
- Separate direct evidence from interpretation.
- Mark anything unsupported or missing as UNCONFIRMED.
- Do not estimate missing figures or infer owners.
- Keep the recommendation identical across all four artifacts.
VALIDATION AND REPAIR
Before you finish, review all four outputs and confirm that:
- The deck has 8 slides or fewer, with the recommendation and speaker notes.
- The risk register has every required column and a source on every row.
- The customer PDF is exactly one page and contains only supported claims.
- The status card matches the recommendation and the risk totals in the files.
- Every number and major claim traces back to a source file.
If any output breaks a requirement, fix it and regenerate that artifact. In your final response, list:
- The files created
- The sources used
- Validation checks completed
- Defects found and corrected
- Remaining UNCONFIRMED items
```

> **Note:** Cowork builds and self-checks four outputs in this run, so expect it to take several minutes.

**Expected:** Cowork lays out a plan in the **Workspace** panel.

**Done when:** The readiness brief is sent in a new task.

### M2-2. Watch the plan as it runs (6 min)

*Keep an eye on the Workspace panel while Cowork works.*

1. While it runs, look at each part of the **Workspace** panel.

| Section | What it shows |
| --- | --- |
| Steps | The plan Cowork drafted, with a live count such as **4/5** and a tick next to each step it finishes |
| Output | Files appearing as they're created, before the run is over |
| Skills & Plugins | Which capabilities Cowork pulled in |
| Tools | Which systems it touched, such as Calendar, Files, Outlook, Teams and Work IQ |

2. Near the end, look for steps where Cowork reviews its own work and rebuilds anything that fails a check.

**Expected:** Review steps show up in **Steps** toward the end of the plan.

**Done when:** You've followed the plan, outputs and tools in the Workspace panel.

### M2-3. Answer questions, then let it finish (6 min)

*Answer any clarifying questions, then wait for the final reply.*

1. If Cowork comes back with a question, answer it. A question usually means the brief left a gap.
2. Wait for the final reply, and don't send the brief a second time.

**Expected:** The final reply lists files created, sources used, checks completed, defects corrected and anything still UNCONFIRMED.

**Done when:** The run is finished and the final summary is showing.

### M2-4. Find all four outputs (5 min)

*Open the deck, register and PDF, and locate the status card.*

1. Use the file cards at the end of the reply to open the PowerPoint deck, the Excel risk register and the customer PDF.
2. Scroll the conversation to find the executive status card.

**Expected:** Three files open, plus a status card in the task.

**Done when:** You've found all four outputs.

### M2-5. Locate the files in OneDrive (4 min)

*Check that Cowork saved the outputs in OneDrive.*

1. Open **OneDrive** from the **Start** menu. Or copy this address into Edge:

*Address · OneDrive*

```text
https://www.office.com/launch/onedrive
```

2. Open the output folder for this task:

**Where:** My files > Documents > Cowork > Tasks > (this task's folder) > output

3. The deck, register and PDF should all be there, with names that tie them to the Helix readiness task.

**Expected:** All three files are in the output folder.

**Done when:** The three output files are in OneDrive.

### M2-6. Check the deck and risk register (5 min)

*Check the deck and register are built the way the brief asked.*

1. Look at structure only for now. Content comes in the next steps.
2. Go through the table.

| Output | What to confirm |
| --- | --- |
| Deck | No more than 8 slides, a clear GO, CONDITIONAL GO or NO-GO, and speaker notes on the recommendation, risk and commercial slides |
| Risk register | All 10 columns, with **Source file** and **Source evidence** filled in on every row, and UNCONFIRMED wherever the owner isn't known |

**Done when:** The deck and risk register meet the structure the brief asked for.

### M2-7. Check the PDF and status card (5 min)

*Check the PDF and the card, and make sure all four agree.*

1. Go through the table.

| Output | What to confirm |
| --- | --- |
| Customer PDF | One page exactly, written for customers, with no internal risks in it |
| Status card | Its recommendation, open risk count and critical blocker count match the other files |
| All four | No conflicts in recommendation, owners, dates or numbers |

**Done when:** The PDF and status card pass, and the four outputs agree with each other.

### M2-8. Trace one risk to its source (6 min)

*Pick one high-impact risk and check it against the cited file.*

1. Choose a high-impact risk in the risk register.
2. Find its **Source file** in the channel:

**Where:** Microsoft Teams > Launch - Helix > Shared

3. Read the file and make sure it really supports the risk.
4. The owner, likelihood and mitigation should come from the source. If they don't, they should say UNCONFIRMED.
5. The same risk should read the same way in the deck and on the status card.
6. Write down any mismatch. You'll fix it at the end of this milestone.

**Done when:** One risk is traced back to its source file.

### M2-9. Trace one number to its source (4 min)

*Check one figure against the file it names.*

1. Choose a number from the deck, such as a price or a date.
2. Open the source file it cites and compare.
3. If they don't match, note it as a defect.

**Done when:** One number is traced back to its source file.

### M2-10. Fix a defect by instruction (6 min)

*Repair by prompt rather than by hand.*

1. Found a defect? Leave the file alone and send Cowork a precise fix in the same task, along these lines:

```text
Check the risk register again against its cited source files. Replace any inferred owner with UNCONFIRMED, bring the deck and status card into line, regenerate the affected artifacts, and tell me exactly what changed.
```

2. Cowork should rebuild the affected files and tell you what changed.
3. No defect found? Read the **Defects found and corrected** section of the final reply instead.

**Expected:** Cowork lists every change it made.

**Check:** Milestone 2 is complete when:
- One brief produced all four outputs
- The deck, the 10-column risk register and the one-page PDF meet their structure rules
- All four carry the same recommendation
- One risk and one number are traced to source, and unsupported items read UNCONFIRMED
- Any defect was fixed by instruction, not by hand

**Done when:** The defect is fixed by instruction, or you've reviewed the final summary.

**Learn more:**

- Use Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork

## Milestone 3: Capture Your Reporting Standard as a Skill

*35 min · required · 7 steps*

Turn the Helix status report rules into a custom skill, inspect its SKILL.md in OneDrive and test it in a brand-new task.

**Objectives:**

- Create a custom skill from the Customize page
- Check SKILL.md and its frontmatter in OneDrive
- Confirm the skill loads in a new task

**Criteria:**

- SKILL.md at /Documents/Cowork/skills/launch-status-report/ with a valid name and description
- All six required elements present
- launch-status-report chip in a new task and a Helix-Status-<YYYY-MM-DD>.docx report produced

### M3-1. Start a new skill (4 min)

*Begin a custom skill from the Customize page.*

**Where:** Cowork > Customize > Skills > Add > New skill

1. Select **Customize** in the Cowork left pane.
2. Go to the **Skills** tab. Anything you've made sits under **Your skills**, with **Built-in skills** such as PDF, Word and Excel further down.
3. Select **Add** > **New skill**.

**Expected:** A new task opens, asking **What should your new skill do?**

**Done when:** The new skill flow is open.

### M3-2. Describe your status report rules (5 min)

*Tell Cowork the rules for the weekly Helix report.*

1. At **What should your new skill do?**, select **Skip**.
2. At **Which category fits it best?**, select **Describe another option**.
3. Paste the text below and select **Submit**.

```text
Create a skill called Launch Status Report. Whenever I ask for this week's Helix launch status, collect the launch plan and product spec, every post in the Launch - Helix Teams channel since the last report, and Helix-related mail from the same period.
Output a Word document named Helix-Status-<YYYY-MM-DD>.docx with these sections: headline status, changes since last report, risks with owners and movement, decisions needed from the sponsor, next 7 days.
Each risk must name the file, channel post or email it came from. A risk with no source is marked UNCONFIRMED and listed last. Maximum 400 words. If the risk section would take it over the limit, shorten the next 7 days section to bullets first. Headline status is exactly one of ON TRACK, AT RISK or OFF TRACK. If any risk has high impact and open status, it cannot be ON TRACK.
```

> **Note:** No category question? Paste the same text into the message box and send it. You end up with the same skill.

**Done when:** The skill description is submitted.

### M3-3. Save the skill and read its quality report (5 min)

*Save SKILL.md and look at its quality score.*

1. A **Copy file** approval card appears with the destination **skills/launch-status-report**. Select **Approve**.
2. Open the **skill-quality-report.html** file card.
3. Note the score and any weaknesses it calls out.

**Expected:** The skill is saved to /Documents/Cowork/skills/ in OneDrive, and the quality report sits alongside it.

**Done when:** The skill is saved and you've read the quality report.

### M3-4. Look for the six elements (6 min)

*Make sure SKILL.md captured every rule you gave it.*

1. Open the saved **SKILL.md**.
2. Look for each of these elements.

| Element | Requirement |
| --- | --- |
| Sources | The files in the Launch - Helix channel, the channel posts, and Helix mail from the reporting period |
| Sections | Headline status, changes since last report, risks with owners and movement, decisions needed from the sponsor, next 7 days |
| Evidence rule | Each risk cites where it came from, and anything without a source is UNCONFIRMED |
| Length | A hard word limit, and what to trim first when it's exceeded |
| Consistency rule | The headline status agrees with the risk section |
| Output | A Word document with the date in its file name |

3. Each rule should be firm enough to test. "Maximum 400 words, cut the next 7 days section first" is a rule you can check. "Keep it concise" isn't.

**Done when:** SKILL.md contains all six elements.

### M3-5. Inspect SKILL.md in OneDrive (5 min)

*Confirm the file location and the frontmatter.*

1. Open the file in OneDrive:

**Where:** My files > Documents > Cowork > skills > launch-status-report > SKILL.md

2. The frontmatter should be valid YAML with a **name** and a **description**.
3. Read the description. It should say what job the skill does, because that's what Cowork uses to decide when to load it.

> **Tip:** When a skill refuses to load, look at its location and frontmatter before anything else. A missing description is usually the culprit.

**Done when:** SKILL.md sits in the right folder with a valid name and description.

### M3-6. Try the skill in a new task (5 min)

*Show that the skill loads in a new session.*

1. Select **New task**. Skills are picked up when a task starts, so an existing task won't see the new one.
2. Send:

```text
Produce this week's Helix launch status report.
```

3. Watch **Skills & Plugins** in the **Workspace** panel.

**Expected:** A **launch-status-report** chip appears.

**Done when:** The skill chip shows in the new task.

### M3-7. Check the report against your rules (5 min)

*Check the output against your sections and rules.*

1. Open the Word report. It's named in the **Helix-Status-<YYYY-MM-DD>.docx** pattern.
2. It should use your five sections rather than a generic layout.
3. Check the details too. The headline is exactly ON TRACK, AT RISK or OFF TRACK, every risk names its source, and the whole report is 400 words or fewer.

**Check:** Milestone 3 is complete when:
- SKILL.md is in /Documents/Cowork/skills/launch-status-report/ with a valid name and description
- All six elements are in it
- The **launch-status-report** chip showed up in a new task
- The report follows your sections

**Done when:** The skill produced a status report and you've checked it.

**Learn more:**

- Use Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork
- Customize Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/cowork-customize

## Milestone 4: Schedule the Daily Launch Briefing

*23 min · required · 5 steps*

Set up a weekday 8am Helix launch briefing, check the schedule card, approve the first send and confirm the schedule is live.

**Objectives:**

- Create a recurring launch briefing
- Check the schedule fields against the request
- Approve the first run and confirm the schedule is active

**Criteria:**

- Helix launch briefing schedule created with its Description checked
- Schedule listed under Automations
- First briefing email received, under 200 words and matching the request

### M4-1. Ask for the daily briefing (4 min)

*Ask Cowork for a weekday briefing on a schedule.*

1. Select **New task** in Cowork and send:

```text
Every weekday at 8am, email me a Helix launch briefing: what changed overnight in the Launch - Helix channel and in Helix mail, which risks moved, and what I need to decide today. Keep it under 200 words.
```

**Expected:** Cowork comes back with a schedule card for you to confirm.

**Done when:** The schedule card is showing.

### M4-2. Review the schedule card (5 min)

*Go over every field before you accept.*

1. Compare the card with what you asked for.

| Field | What to check |
| --- | --- |
| Name | **Helix launch briefing**. If it says something else, change it. |
| Repeat | Weekdays at 8:00, set through two separate controls (recurrence and time) |
| Run in | Whether each run opens a **New conversation** or carries on in this one |
| Description | Your instruction exactly as the task will run it. Nothing extra, and in particular no delivery method you didn't ask for |

**Done when:** All four fields match what you asked for.

### M4-3. Run it once and approve the send (6 min)

*See the first run today rather than tomorrow morning.*

1. Tick **Run once now** and select **Schedule**.
2. A **Send email?** approval card appears.
3. Look over the draft, then select **Send**.
4. Leave **Always allow** alone. That way every future run still checks with you before it sends.

> **Warning:** Deal with the card before you type anything. A new message cancels the send, and you'd have to set up the schedule again.

**Expected:** The first run completes once you select **Send**.

**Done when:** The first run was approved with Send, not Always allow.

### M4-4. Find it under Automations (3 min)

*Make sure the schedule is live.*

1. Select **Automations** in the Cowork left pane.
2. **Helix launch briefing** should be in the list.
3. Don't look for it on your calendar. A schedule only shows under **Automations**.

**Done when:** Helix launch briefing appears under Automations.

### M4-5. Check the first briefing email (5 min)

*Check that the first email matches what you asked for.*

1. Open **Outlook** from the **Start** menu. Or copy this address into Edge:

*Address · Outlook*

```text
https://outlook.office.com/mail
```

2. In **Inbox**, open **Helix launch briefing - [today's date]**.
3. It should be under 200 words and cover what changed, which risks moved and what you need to decide today.

**Check:** Milestone 4 is complete when:
- You checked the fields on the schedule card
- **Helix launch briefing** appears under **Automations**
- The first briefing is in your Inbox and matches the request

**Done when:** The first briefing email arrived and you've checked it.

**Learn more:**

- Use Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork
- Manage tasks and schedule prompts in Microsoft Copilot Cowork: https://support.microsoft.com/en-us/microsoft-365-copilot/cowork-manage-tasks-schedule-prompts

## Milestone 5: Combine Skills into a Toolkit (Optional)

*44 min · optional · 9 steps*

Optional. Add a Helix Meeting Prep skill with its own template, run both skills in one task, share them and keep an inventory.

**Objectives:**

- Create a second skill with a companion file
- Run two skills in one delegation
- Share both skills and record an inventory

**Criteria:**

- Helix Meeting Prep skill saved with brief-template.docx and proven used
- Both skill chips in one task, producing two Word documents
- Both skills shared and Skill-Inventory.docx completed

### M5-1. Describe the meeting prep skill (5 min)

*Start a second skill for readiness review prep.*

> **Note:** This one is optional. Finishing Milestone 4 completes the lab.

1. Go to **Customize** > **Skills** > **Add** > **New skill**.
2. Select **Skip** at **What should your new skill do?**
3. At the category question, choose **Describe another option**.
4. Paste the text below and select **Submit**.

```text
Create a skill called Helix Meeting Prep. Whenever I ask to be prepared for the Helix readiness review, find that meeting on my calendar, then collect the launch plan and product spec and the latest posts in the Launch - Helix Teams channel.
Output a Word document with these sections: meeting time and attendees, open decisions with owners, risks since the last review, and one recommended focus for the meeting. If a decision has no named owner, mark it UNCONFIRMED instead of guessing.
```

**Done when:** The meeting prep skill description is submitted.

### M5-2. Save it and look for a hand-off (5 min)

*Save the skill and see how it sits alongside the first one.*

1. Approve the **Copy file** card with destination **skills/helix-meeting-prep**.
2. Open the **skill-quality-report.html** card and note the score and any weakness.
3. See whether Cowork added a hand-off clause so this skill doesn't compete with **launch-status-report**. If it did, find that clause in SKILL.md.

**Expected:** File cards for the skill, its SKILL.md and the quality report.

**Done when:** The helix-meeting-prep skill is saved and you've read its quality report.

### M5-3. Add the brief template (5 min)

*Give the skill a companion file to follow.*

1. In the same task, send the following as a single message:

```text
Add a companion file to the helix-meeting-prep skill: brief-template.docx, stored in the same skill folder. It is a one-page brief template with these headings, in this order:
1. Meeting Snapshot
2. Decisions Awaiting an Owner
3. Risks Since Last Review
4. Helix Go/No-Go Signal
5. One Thing to Push For Under Helix Go/No-Go Signal, the brief must always give exactly one of GO, CONDITIONAL GO or NO-GO.
Then update the skill instructions to say: Use brief-template.docx as the exact section structure, keep every heading in the given order, and do not add sections.
```

2. Approve the **Copy file** card with destination **skills/helix-meeting-prep**.

**Done when:** The template is saved in the skill folder.

### M5-4. Check the template (4 min)

*Check the headings and the skill update.*

1. Select the **brief-template** file card.
2. The five headings should be in the order you gave, and **Helix Go/No-Go Signal** should offer GO, CONDITIONAL GO or NO-GO.
3. Cowork's reply should also say the skill instructions now point to brief-template.docx.

> **Tip:** You might find a stray copy of brief-template.docx at the top level of your OneDrive. The skill only reads the one in its own folder, so you can delete the extra.

**Done when:** The template headings and the skill reference are confirmed.

### M5-5. Prove the skill uses the template (6 min)

*Run the skill in a new task and look at the headings.*

1. Select **New task** and send:

```text
Prep me for the Helix readiness review.
```

2. Open the Word document it creates.
3. The five template headings should appear in order.

**Expected:** **Helix Go/No-Go Signal** shows exactly one of GO, CONDITIONAL GO or NO-GO. None of the source files use that heading, so it can only have come from your template.

**Done when:** The brief follows the template.

### M5-6. Run both skills in one task (5 min)

*Run both skills from a single request.*

1. Select **New task** and send:

```text
Do two things using my custom skills.
First, produce this week's Helix launch status report as its own Word document.
Then prep me for the Helix readiness review. In the brief's Risks Since Last Review section, cite the status report you just produced as the evidence.
```

2. Check **Skills & Plugins** for both the **launch-status-report** and **helix-meeting-prep** chips.
3. If Cowork asks which review you mean, pick the most recent one.

> **Tip:** Each sentence carries one skill's trigger phrase. Merge them into one sentence and usually only one skill loads.

**Expected:** Both skill chips in the **Workspace** panel.

**Done when:** Both skills loaded in the same task.

### M5-7. Check both outputs (5 min)

*Confirm you got two linked Word documents.*

1. **Output** should hold two separate Word documents, the status report and the readiness brief.
2. Open the brief and check the five headings are intact.
3. **Risks Since Last Review** should cite the status report.

**Done when:** Two linked documents were produced and you've checked them.

### M5-8. Share both skills (4 min)

*Share each skill with a named lab user.*

**Where:** Cowork > Customize > Skills > (skill) > Share

1. On **Customize**, open each skill's page in turn.
2. Select **Share** and share it with the lab user your organiser named.

**Done when:** Both skills are shared.

### M5-9. Write up the skill inventory (5 min)

*Write up both skills in one Word table.*

1. Create a Word document in OneDrive called **Skill-Inventory.docx**.
2. Add a table with these seven columns and a row for each skill.

| Column | What to enter |
| --- | --- |
| Skill | Name of the skill |
| What it does | One line describing what it produces |
| When it fires | The phrase that sets it off |
| Sources it reads | Files, channel posts, mail or calendar |
| Owner | Your lab user |
| Last tested | Today's date |
| Known gap | One weakness, perhaps from the quality report |

3. Select **Complete** for Milestone 5.
4. Select **Submit** when you're done. Your work is checked automatically.

**Check:** Milestone 5 is complete when:
- helix-meeting-prep is saved with brief-template.docx in its folder
- Its output uses the template headings
- Both skills loaded in one task and produced two documents
- Both skills are shared and Skill-Inventory.docx is filled in

**Done when:** Skill-Inventory.docx is filled in for both skills.

**Learn more:**

- Use Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork
- Customize Copilot Cowork: https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/cowork-customize
