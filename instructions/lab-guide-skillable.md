# Launch Command Center: Delegate, Verify and Automate with Microsoft 365 Copilot Cowork

**Advanced · 3 hrs - Individual**

Launch Command Center is a three-hour, advanced Hack in a Day for launch leads, program managers and anyone who runs cross-functional work in Microsoft 365. Here's the setup. Zava Corporation's Helix product ships in 10 days, its launch lead has moved on, and the job is now yours. What you inherit is untidy. A supplier problem is still open. An executive is waiting to hear whether the date holds. Two decisions are stuck in Microsoft Teams, the spec and the launch plan disagree, and your calendar has meetings stacked on top of each other.

Microsoft 365 Copilot Cowork does the legwork while you keep the final say. You start by getting a feel for the controls: a catch-up where every claim has a source, reply drafts that sit in Outlook until you send them, a long task you stop and restart, and a calendar permission you grant and then take back. After that, a single written brief gets you the whole readiness pack (PowerPoint deck, Excel risk register, one-page customer PDF and status card). Your job is to check it, trace it back to the files and get Cowork to correct anything that's wrong.

The second half is about not doing the same work twice. You turn your status report rules into a custom skill, open its SKILL.md in OneDrive and prove it loads in a new task. Then you set up a briefing that arrives every weekday morning but still waits for your OK before it sends. If you have time, an optional milestone adds a second skill with its own template and runs the two together.

You work in Microsoft Edge on the lab desktop, in a Microsoft 365 lab tenant already seeded with Helix mail, Teams posts, files and meetings.

## Lab outline

1. **Master the Delegation Controls** (40 min)
2. **Build the Readiness Pack from a Single Brief** (52 min)
3. **Capture Your Reporting Standard as a Skill** (35 min)
4. **Schedule the Daily Launch Briefing** (23 min)
5. **Combine Skills into a Toolkit (Optional)** (44 min)

===

# Briefing

### Where things stand

You've just taken over the Helix launch at Zava Corporation, and it ships in 10 days. Your predecessor left a supplier issue that isn't closed, an executive who hasn't had a reply, two questions in the Launch - Helix Teams channel that nobody has decided, a spec that disagrees with the launch plan, and a week of double-booked meetings. The executive's question is simple. Does the date hold?

### How you'll work

Microsoft 365 Copilot Cowork does the running around. You describe the result you want. Cowork plans the steps, works through your mail, Teams, files and calendar, and produces real drafts, documents and meetings. It acts with your permissions and nothing more, and it asks before it sends mail or touches your calendar.

A few habits make this go well.

- Stay in charge. Watch what Cowork is doing and stop it if it drifts. Approve each action that matters. Standing permission is something you choose to give, and you can take it back.
- Trust the source, not the summary. Every risk and every number should point to a named file, post or email. If it can't, it gets marked UNCONFIRMED.
- Write the rules down once. A report you produce every week belongs in a skill, so each run follows the same standard.

### The plan for today

1. Get comfortable with the controls: catch-up, drafts, stop and resume, approve and revoke.
2. Build the readiness pack (deck, risk register, customer PDF, status card) from one brief, then trace a risk and fix a defect by instruction.
3. Turn your status report standard into a custom skill and try it in a new task.
4. Schedule the weekday briefing and approve its first send.
5. Optional: add a second skill with a template and run both together.

### How scoring works

Scoring looks for evidence in your own mailbox, calendar and OneDrive. That means the drafts Cowork saved, the focus blocks you approved and the one you cancelled, the readiness files, your SKILL.md and the report it produced, and the first briefing email. Stick to the exact names in the steps, or the checks won't find your work.

### Good to know

- Stay on the lab desktop and the lab account the whole time.
- When an approval card is open, deal with it before you type anything else. A new message cancels the pending action.
- Cowork runs can take a few minutes. Keep an eye on the **Workspace** panel rather than sending the prompt again.

===

# Getting started

### 1. Open your lab desktop

*Start your lab machine. (2 min)*

1. On **Your lab desktop**, select **Launch Lab**.
2. If you're asked to sign in, take the **Desktop username** and **Desktop password** from **Lab Access** in the **Lab Guide**.
3. From here on, everything happens on this desktop rather than your own computer.

> [!NOTE] **Expected:** The Windows desktop of your lab machine loads.

> [!HINT] Text shown with a **T** icon types itself into the lab desktop: click into the right box first (for example the Edge address bar), then select the text.

- [] The lab desktop is open and you're signed in.

### 2. Sign in to Microsoft 365

*Sign in to Microsoft 365 in Edge with the lab account. (3 min)*

1. Open **Microsoft Edge** on the lab desktop and go to:

+++https://m365.cloud.microsoft+++

2. Sign in with the **Entra username** and **Temporary Access Pass** (or **Temporary password**) from **Lab Access**.
3. Hit a **404**? Open an **InPrivate** window in Edge and try again.

> [!ALERT] Stick to the lab account. Over the next few hours you'll send mail, change a calendar and schedule an automation, and all of that belongs in the lab tenant, not yours.

> [!NOTE] **Expected:** The Microsoft 365 home page, signed in as your lab user.

- [] You're signed in to Microsoft 365 with the lab account.

### 3. Check Cowork and the Helix data

*Make sure Cowork is switched on and the six pieces of Helix data are in place. (5 min)*

1. Go to Microsoft 365 Copilot:

+++https://copilot.cloud.microsoft/chat+++

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

> [!NOTE] There are no real meeting recordings in this lab. The two Helix-Sync-Notes files play that role, so treat them as the record of two earlier Helix meetings.

- [] Cowork is available and all six items check out.

### 4. Read the briefing and scenario

*Get the scenario and the deadline in your head. (2 min)*

1. Open the **Briefing** tab in the **Lab Guide** and read it through.
2. The short version: you lead the Helix launch at Zava Corporation, it ships in 10 days, and an executive wants to know if that date is safe.
3. Come back to the **Instructions** tab when you're ready for Milestone 1.

- [] You've read the briefing and know your role and the deadline.

> [!HINT] **Learn more:** [Get started with Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/get-started)

===

# Milestone 1: Master the Delegation Controls

*40 min · required*

Learn how Cowork's controls behave: a catch-up with sources, reply drafts, stopping and resuming a task, and giving and taking back a permission.

**In this milestone you will:**

- Delegate a multi-step catch-up and follow it in the Workspace panel
- Interrupt a long task and resume it
- Grant, use and revoke an Always allow permission

### 1.1 Get caught up, with sources

*Start a Cowork task that pulls the launch picture together from mail, Teams and files. (5 min)*

1. Open Microsoft 365 Copilot in a new Edge tab:

+++https://copilot.cloud.microsoft/chat+++

2. Select **Cowork** in the left pane, then **New task**.
3. Paste the prompt below into the **What's left to wrap up?** box and send it.

```
I've just inherited the Helix launch, and it ships in 10 days. Bring me up to speed.
List what is at risk, which decisions are still open, who is waiting on me, and anything I have missed over the last two weeks. Search my inbox, the Launch - Helix Teams channel and the files shared there, and cite every email, Teams post and file you rely on.
```

4. Keep an eye on the **Workspace** panel on the right while it runs. **Steps** counts progress (for example **1 / 4**), and **Tools** shows which systems Cowork is pulling from, such as Outlook, Teams and Work IQ.

> [!NOTE] **Expected:** A catch-up covering what's at risk, which decisions are open and who's waiting on you.

- [] The catch-up run is complete.

### 1.2 Check the source behind each risk

*Make sure each risk in the catch-up points to a source. (3 min)*

1. Go through the finished answer risk by risk.
2. Each one should cite an email, a Teams post or a file.
3. Only files cited? Start a **New task** and send the same prompt again. It names the inbox, the channel and the files deliberately, to stop the search from narrowing.

- [] Every risk in the catch-up cites a source.

### 1.3 Get three replies drafted

*Get three reply drafts that wait in Outlook. (4 min)*

1. Stay in the same task and send:

+++Draft replies to the two people who have been waiting on me the longest. Also draft a short holding reply on the supplier escalation thread saying I now own the launch and will confirm our position within 48 hours.+++

2. Let the run finish. The replies are saved as Outlook drafts, and nothing is sent.

> [!NOTE] **Expected:** Cowork confirms it saved three drafts.

- [] Three reply drafts are saved in Outlook.

### 1.4 Deal with the drafts in Outlook

*Decide what happens to each draft yourself. (4 min)*

1. Open **Outlook** from the **Start** menu and go to **Drafts**. Or copy this address into Edge:

+++https://outlook.office.com/mail/drafts+++

2. Look for the three **[Draft]** replies. Each one ends with **Sent by Copilot Cowork**.
3. Open them one at a time. Edit the text, or use the trash icon to throw one away.
4. Send the ones you're happy with. Keep or send at least one, since scoring looks for the **Sent by Copilot Cowork** line.
5. Notice that nothing left your mailbox until you pressed **Send** yourself.

> [!NOTE] **Expected:** Three **[Draft]** replies in the **Drafts** folder.

- [] You've reviewed all three drafts and kept or sent at least one.

### 1.5 Stop a task mid-run

*Stop a long comparison partway through. (4 min)*

1. Still in the same task, send this longer request:

```
Compare the Helix launch plan with the product spec in the shared launch files.
Find every point where they disagree and list each one with the section reference from both documents.
```

2. While it's running, select the stop icon in the message box. Stopping mid-step is fine.
3. Check **Steps** in the **Workspace** panel to see how far it got.

> [!NOTE] **Steps** sometimes trails by a few seconds. Give it a moment before you decide the run has stalled.

> [!NOTE] **Expected:** The run stops with some steps still unfinished.

- [] The comparison task stopped before it finished.

### 1.6 Resume the stopped task

*Restart the stopped comparison without leaving the task. (3 min)*

1. Send this in the same task:

+++Resume+++

2. Let it run to the end.

> [!NOTE] **Expected:** Each disagreement is listed, with the section headings from both documents.

- [] The comparison picked up again and finished in the same task.

### 1.7 Plan the week without changing it

*Get a proposal for the week without any calendar changes. (4 min)*

1. Next, send:

+++My calendar for the next five days has conflicts. Plan my week around the Helix launch: tell me which meetings to keep, which to delegate and which to decline, and where I need focus blocks to finish the readiness review. Do not change anything yet; just propose the plan.+++

2. Read through the plan. Because the prompt says not to change anything, there's no approval card this time.

> [!NOTE] **Expected:** A proposed week (meetings to keep, delegate and decline, plus focus blocks) and no changes on your calendar.

- [] You have a week plan and your calendar is unchanged.

### 1.8 Approve a calendar change with Always allow

*Put the first focus block on the calendar through an approval card. (5 min)*

1. Now ask for a real change:

+++Add a 30-minute focus block to my calendar tomorrow at 10:00 titled "Helix messaging review".+++

2. An approval card appears, for example **Create calendar event?** with a label such as **Medium risk**.
3. Check the time and title. You can edit both on the card.
4. Open the arrow next to the action button and choose **Always allow**.
5. Select the action button to approve.

> [!ALERT] Don't type a new message while the card is open. Doing so cancels the action and throws away any edits you made.

> [!NOTE] **Expected:** **Helix messaging review** is on tomorrow's calendar at 10:00.

- [] The first focus block was created through the card, and Always allow is granted.

### 1.9 Rely on the standing permission

*Add a second focus block. This time no card should appear. (3 min)*

1. Send this in the same task:

+++Add another 30-minute focus block to my calendar tomorrow at 14:00 titled "Helix launch checklist".+++

2. Watch **Steps** in the **Workspace** panel. Because of **Always allow**, there's no approval card.
3. Open your calendar and check that both focus blocks are there.

> [!NOTE] **Expected:** **Helix messaging review** and **Helix launch checklist** both sit on tomorrow's calendar.

- [] The second focus block was created with no approval card.

### 1.10 Take the permission back

*Take back Always allow and cancel the third request. (5 min)*

1. Open **Permissions** in the **Workspace** panel.
2. Revoke the calendar event permission.
3. Then, in the same task, send:

+++Add one more 30-minute focus block to my calendar tomorrow at 16:00 titled "Helix status review".+++

4. The approval card is back. Select **Cancel**.

> [!NOTE] **Always allow** lasts for the current task only. Every new task starts without it.

> [!NOTE] **Expected:** The approval card returns, and no **Helix status review** event appears on your calendar.

> [!KNOWLEDGE] **Milestone check:** Milestone 1 is complete when:
> - Every risk in the catch-up has a citation
> - You've reviewed the three drafts in Outlook
> - Tomorrow's calendar has **Helix messaging review** and **Helix launch checklist**
> - The permission is revoked and there's no **Helix status review** event

- [] The permission is revoked and the third request was cancelled.

> [!HINT] **Learn more:** [Get started with Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/get-started) · [Use Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork)

### Milestone 1 complete when

- [] Catch-up with every risk sourced, and three reply drafts reviewed in Outlook
- [] Helix messaging review and Helix launch checklist on tomorrow's calendar
- [] Permission revoked and the Helix status review request cancelled

===

# Milestone 2: Build the Readiness Pack from a Single Brief

*52 min · required*

One brief produces a readiness deck, risk register, customer PDF and status card. Then you check them, trace them to source and fix what's wrong.

**In this milestone you will:**

- Produce four linked outputs from one written brief
- Check the structure and consistency of all four
- Trace a risk and a number to source and fix a defect by instruction

### 2.1 Send the readiness brief

*Hand Cowork the whole readiness pack in one prompt. (5 min)*

1. Select **New task** in Cowork.
2. Paste in the brief below and send it.

```
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

> [!NOTE] Cowork builds and self-checks four outputs in this run, so expect it to take several minutes.

> [!NOTE] **Expected:** Cowork lays out a plan in the **Workspace** panel.

- [] The readiness brief is sent in a new task.

### 2.2 Watch the plan as it runs

*Keep an eye on the Workspace panel while Cowork works. (6 min)*

1. While it runs, look at each part of the **Workspace** panel.

| Section | What it shows |
| --- | --- |
| Steps | The plan Cowork drafted, with a live count such as **4/5** and a tick next to each step it finishes |
| Output | Files appearing as they're created, before the run is over |
| Skills & Plugins | Which capabilities Cowork pulled in |
| Tools | Which systems it touched, such as Calendar, Files, Outlook, Teams and Work IQ |

2. Near the end, look for steps where Cowork reviews its own work and rebuilds anything that fails a check.

> [!NOTE] **Expected:** Review steps show up in **Steps** toward the end of the plan.

- [] You've followed the plan, outputs and tools in the Workspace panel.

### 2.3 Answer questions, then let it finish

*Answer any clarifying questions, then wait for the final reply. (6 min)*

1. If Cowork comes back with a question, answer it. A question usually means the brief left a gap.
2. Wait for the final reply, and don't send the brief a second time.

> [!NOTE] **Expected:** The final reply lists files created, sources used, checks completed, defects corrected and anything still UNCONFIRMED.

- [] The run is finished and the final summary is showing.

### 2.4 Find all four outputs

*Open the deck, register and PDF, and locate the status card. (5 min)*

1. Use the file cards at the end of the reply to open the PowerPoint deck, the Excel risk register and the customer PDF.
2. Scroll the conversation to find the executive status card.

> [!NOTE] **Expected:** Three files open, plus a status card in the task.

- [] You've found all four outputs.

### 2.5 Locate the files in OneDrive

*Check that Cowork saved the outputs in OneDrive. (4 min)*

1. Open **OneDrive** from the **Start** menu. Or copy this address into Edge:

+++https://www.office.com/launch/onedrive+++

2. Open the output folder for this task:

> [!KNOWLEDGE] **Where:** My files > Documents > Cowork > Tasks > (this task's folder) > output

3. The deck, register and PDF should all be there, with names that tie them to the Helix readiness task.

> [!NOTE] **Expected:** All three files are in the output folder.

- [] The three output files are in OneDrive.

### 2.6 Check the deck and risk register

*Check the deck and register are built the way the brief asked. (5 min)*

1. Look at structure only for now. Content comes in the next steps.
2. Go through the table.

| Output | What to confirm |
| --- | --- |
| Deck | No more than 8 slides, a clear GO, CONDITIONAL GO or NO-GO, and speaker notes on the recommendation, risk and commercial slides |
| Risk register | All 10 columns, with **Source file** and **Source evidence** filled in on every row, and UNCONFIRMED wherever the owner isn't known |

- [] The deck and risk register meet the structure the brief asked for.

### 2.7 Check the PDF and status card

*Check the PDF and the card, and make sure all four agree. (5 min)*

1. Go through the table.

| Output | What to confirm |
| --- | --- |
| Customer PDF | One page exactly, written for customers, with no internal risks in it |
| Status card | Its recommendation, open risk count and critical blocker count match the other files |
| All four | No conflicts in recommendation, owners, dates or numbers |

- [] The PDF and status card pass, and the four outputs agree with each other.

### 2.8 Trace one risk to its source

*Pick one high-impact risk and check it against the cited file. (6 min)*

1. Choose a high-impact risk in the risk register.
2. Find its **Source file** in the channel:

> [!KNOWLEDGE] **Where:** Microsoft Teams > Launch - Helix > Shared

3. Read the file and make sure it really supports the risk.
4. The owner, likelihood and mitigation should come from the source. If they don't, they should say UNCONFIRMED.
5. The same risk should read the same way in the deck and on the status card.
6. Write down any mismatch. You'll fix it at the end of this milestone.

- [] One risk is traced back to its source file.

### 2.9 Trace one number to its source

*Check one figure against the file it names. (4 min)*

1. Choose a number from the deck, such as a price or a date.
2. Open the source file it cites and compare.
3. If they don't match, note it as a defect.

- [] One number is traced back to its source file.

### 2.10 Fix a defect by instruction

*Repair by prompt rather than by hand. (6 min)*

1. Found a defect? Leave the file alone and send Cowork a precise fix in the same task, along these lines:

+++Check the risk register again against its cited source files. Replace any inferred owner with UNCONFIRMED, bring the deck and status card into line, regenerate the affected artifacts, and tell me exactly what changed.+++

2. Cowork should rebuild the affected files and tell you what changed.
3. No defect found? Read the **Defects found and corrected** section of the final reply instead.

> [!NOTE] **Expected:** Cowork lists every change it made.

> [!KNOWLEDGE] **Milestone check:** Milestone 2 is complete when:
> - One brief produced all four outputs
> - The deck, the 10-column risk register and the one-page PDF meet their structure rules
> - All four carry the same recommendation
> - One risk and one number are traced to source, and unsupported items read UNCONFIRMED
> - Any defect was fixed by instruction, not by hand

- [] The defect is fixed by instruction, or you've reviewed the final summary.

> [!HINT] **Learn more:** [Use Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork)

### Milestone 2 complete when

- [] Deck (8 slides or fewer), 10-column risk register, one-page PDF and status card from one brief
- [] One risk and one number traced to source, with unsupported items marked UNCONFIRMED
- [] Same recommendation in all four outputs, with any defect fixed by instruction

===

# Milestone 3: Capture Your Reporting Standard as a Skill

*35 min · required*

Turn the Helix status report rules into a custom skill, inspect its SKILL.md in OneDrive and test it in a brand-new task.

**In this milestone you will:**

- Create a custom skill from the Customize page
- Check SKILL.md and its frontmatter in OneDrive
- Confirm the skill loads in a new task

### 3.1 Start a new skill

*Begin a custom skill from the Customize page. (4 min)*

> [!KNOWLEDGE] **Where:** Cowork > Customize > Skills > Add > New skill

1. Select **Customize** in the Cowork left pane.
2. Go to the **Skills** tab. Anything you've made sits under **Your skills**, with **Built-in skills** such as PDF, Word and Excel further down.
3. Select **Add** > **New skill**.

> [!NOTE] **Expected:** A new task opens, asking **What should your new skill do?**

- [] The new skill flow is open.

### 3.2 Describe your status report rules

*Tell Cowork the rules for the weekly Helix report. (5 min)*

1. At **What should your new skill do?**, select **Skip**.
2. At **Which category fits it best?**, select **Describe another option**.
3. Paste the text below and select **Submit**.

```
Create a skill called Launch Status Report. Whenever I ask for this week's Helix launch status, collect the launch plan and product spec, every post in the Launch - Helix Teams channel since the last report, and Helix-related mail from the same period.
Output a Word document named Helix-Status-<YYYY-MM-DD>.docx with these sections: headline status, changes since last report, risks with owners and movement, decisions needed from the sponsor, next 7 days.
Each risk must name the file, channel post or email it came from. A risk with no source is marked UNCONFIRMED and listed last. Maximum 400 words. If the risk section would take it over the limit, shorten the next 7 days section to bullets first. Headline status is exactly one of ON TRACK, AT RISK or OFF TRACK. If any risk has high impact and open status, it cannot be ON TRACK.
```

> [!NOTE] No category question? Paste the same text into the message box and send it. You end up with the same skill.

- [] The skill description is submitted.

### 3.3 Save the skill and read its quality report

*Save SKILL.md and look at its quality score. (5 min)*

1. A **Copy file** approval card appears with the destination **skills/launch-status-report**. Select **Approve**.
2. Open the **skill-quality-report.html** file card.
3. Note the score and any weaknesses it calls out.

> [!NOTE] **Expected:** The skill is saved to /Documents/Cowork/skills/ in OneDrive, and the quality report sits alongside it.

- [] The skill is saved and you've read the quality report.

### 3.4 Look for the six elements

*Make sure SKILL.md captured every rule you gave it. (6 min)*

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

- [] SKILL.md contains all six elements.

### 3.5 Inspect SKILL.md in OneDrive

*Confirm the file location and the frontmatter. (5 min)*

1. Open the file in OneDrive:

> [!KNOWLEDGE] **Where:** My files > Documents > Cowork > skills > launch-status-report > SKILL.md

2. The frontmatter should be valid YAML with a **name** and a **description**.
3. Read the description. It should say what job the skill does, because that's what Cowork uses to decide when to load it.

> [!HINT] When a skill refuses to load, look at its location and frontmatter before anything else. A missing description is usually the culprit.

- [] SKILL.md sits in the right folder with a valid name and description.

### 3.6 Try the skill in a new task

*Show that the skill loads in a new session. (5 min)*

1. Select **New task**. Skills are picked up when a task starts, so an existing task won't see the new one.
2. Send:

+++Produce this week's Helix launch status report.+++

3. Watch **Skills & Plugins** in the **Workspace** panel.

> [!NOTE] **Expected:** A **launch-status-report** chip appears.

- [] The skill chip shows in the new task.

### 3.7 Check the report against your rules

*Check the output against your sections and rules. (5 min)*

1. Open the Word report. It's named in the **Helix-Status-<YYYY-MM-DD>.docx** pattern.
2. It should use your five sections rather than a generic layout.
3. Check the details too. The headline is exactly ON TRACK, AT RISK or OFF TRACK, every risk names its source, and the whole report is 400 words or fewer.

> [!KNOWLEDGE] **Milestone check:** Milestone 3 is complete when:
> - SKILL.md is in /Documents/Cowork/skills/launch-status-report/ with a valid name and description
> - All six elements are in it
> - The **launch-status-report** chip showed up in a new task
> - The report follows your sections

- [] The skill produced a status report and you've checked it.

> [!HINT] **Learn more:** [Use Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork) · [Customize Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/cowork-customize)

### Milestone 3 complete when

- [] SKILL.md at /Documents/Cowork/skills/launch-status-report/ with a valid name and description
- [] All six required elements present
- [] launch-status-report chip in a new task and a Helix-Status-<YYYY-MM-DD>.docx report produced

===

# Milestone 4: Schedule the Daily Launch Briefing

*23 min · required*

Set up a weekday 8am Helix launch briefing, check the schedule card, approve the first send and confirm the schedule is live.

**In this milestone you will:**

- Create a recurring launch briefing
- Check the schedule fields against the request
- Approve the first run and confirm the schedule is active

### 4.1 Ask for the daily briefing

*Ask Cowork for a weekday briefing on a schedule. (4 min)*

1. Select **New task** in Cowork and send:

+++Every weekday at 8am, email me a Helix launch briefing: what changed overnight in the Launch - Helix channel and in Helix mail, which risks moved, and what I need to decide today. Keep it under 200 words.+++

> [!NOTE] **Expected:** Cowork comes back with a schedule card for you to confirm.

- [] The schedule card is showing.

### 4.2 Review the schedule card

*Go over every field before you accept. (5 min)*

1. Compare the card with what you asked for.

| Field | What to check |
| --- | --- |
| Name | **Helix launch briefing**. If it says something else, change it. |
| Repeat | Weekdays at 8:00, set through two separate controls (recurrence and time) |
| Run in | Whether each run opens a **New conversation** or carries on in this one |
| Description | Your instruction exactly as the task will run it. Nothing extra, and in particular no delivery method you didn't ask for |

- [] All four fields match what you asked for.

### 4.3 Run it once and approve the send

*See the first run today rather than tomorrow morning. (6 min)*

1. Tick **Run once now** and select **Schedule**.
2. A **Send email?** approval card appears.
3. Look over the draft, then select **Send**.
4. Leave **Always allow** alone. That way every future run still checks with you before it sends.

> [!ALERT] Deal with the card before you type anything. A new message cancels the send, and you'd have to set up the schedule again.

> [!NOTE] **Expected:** The first run completes once you select **Send**.

- [] The first run was approved with Send, not Always allow.

### 4.4 Find it under Automations

*Make sure the schedule is live. (3 min)*

1. Select **Automations** in the Cowork left pane.
2. **Helix launch briefing** should be in the list.
3. Don't look for it on your calendar. A schedule only shows under **Automations**.

- [] Helix launch briefing appears under Automations.

### 4.5 Check the first briefing email

*Check that the first email matches what you asked for. (5 min)*

1. Open **Outlook** from the **Start** menu. Or copy this address into Edge:

+++https://outlook.office.com/mail+++

2. In **Inbox**, open **Helix launch briefing - [today's date]**.
3. It should be under 200 words and cover what changed, which risks moved and what you need to decide today.

> [!KNOWLEDGE] **Milestone check:** Milestone 4 is complete when:
> - You checked the fields on the schedule card
> - **Helix launch briefing** appears under **Automations**
> - The first briefing is in your Inbox and matches the request

- [] The first briefing email arrived and you've checked it.

> [!HINT] **Learn more:** [Use Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork) · [Manage tasks and schedule prompts in Microsoft Copilot Cowork](https://support.microsoft.com/en-us/microsoft-365-copilot/cowork-manage-tasks-schedule-prompts)

### Milestone 4 complete when

- [] Helix launch briefing schedule created with its Description checked
- [] Schedule listed under Automations
- [] First briefing email received, under 200 words and matching the request

===

# Milestone 5: Combine Skills into a Toolkit (Optional)

*44 min · optional*

Optional. Add a Helix Meeting Prep skill with its own template, run both skills in one task, share them and keep an inventory.

**In this milestone you will:**

- Create a second skill with a companion file
- Run two skills in one delegation
- Share both skills and record an inventory

### 5.1 Describe the meeting prep skill

*Start a second skill for readiness review prep. (5 min)*

> [!NOTE] This one is optional. Finishing Milestone 4 completes the lab.

1. Go to **Customize** > **Skills** > **Add** > **New skill**.
2. Select **Skip** at **What should your new skill do?**
3. At the category question, choose **Describe another option**.
4. Paste the text below and select **Submit**.

```
Create a skill called Helix Meeting Prep. Whenever I ask to be prepared for the Helix readiness review, find that meeting on my calendar, then collect the launch plan and product spec and the latest posts in the Launch - Helix Teams channel.
Output a Word document with these sections: meeting time and attendees, open decisions with owners, risks since the last review, and one recommended focus for the meeting. If a decision has no named owner, mark it UNCONFIRMED instead of guessing.
```

- [] The meeting prep skill description is submitted.

### 5.2 Save it and look for a hand-off

*Save the skill and see how it sits alongside the first one. (5 min)*

1. Approve the **Copy file** card with destination **skills/helix-meeting-prep**.
2. Open the **skill-quality-report.html** card and note the score and any weakness.
3. See whether Cowork added a hand-off clause so this skill doesn't compete with **launch-status-report**. If it did, find that clause in SKILL.md.

> [!NOTE] **Expected:** File cards for the skill, its SKILL.md and the quality report.

- [] The helix-meeting-prep skill is saved and you've read its quality report.

### 5.3 Add the brief template

*Give the skill a companion file to follow. (5 min)*

1. In the same task, send the following as a single message:

```
Add a companion file to the helix-meeting-prep skill: brief-template.docx, stored in the same skill folder. It is a one-page brief template with these headings, in this order:
1. Meeting Snapshot
2. Decisions Awaiting an Owner
3. Risks Since Last Review
4. Helix Go/No-Go Signal
5. One Thing to Push For Under Helix Go/No-Go Signal, the brief must always give exactly one of GO, CONDITIONAL GO or NO-GO.
Then update the skill instructions to say: Use brief-template.docx as the exact section structure, keep every heading in the given order, and do not add sections.
```

2. Approve the **Copy file** card with destination **skills/helix-meeting-prep**.

- [] The template is saved in the skill folder.

### 5.4 Check the template

*Check the headings and the skill update. (4 min)*

1. Select the **brief-template** file card.
2. The five headings should be in the order you gave, and **Helix Go/No-Go Signal** should offer GO, CONDITIONAL GO or NO-GO.
3. Cowork's reply should also say the skill instructions now point to brief-template.docx.

> [!HINT] You might find a stray copy of brief-template.docx at the top level of your OneDrive. The skill only reads the one in its own folder, so you can delete the extra.

- [] The template headings and the skill reference are confirmed.

### 5.5 Prove the skill uses the template

*Run the skill in a new task and look at the headings. (6 min)*

1. Select **New task** and send:

+++Prep me for the Helix readiness review.+++

2. Open the Word document it creates.
3. The five template headings should appear in order.

> [!NOTE] **Expected:** **Helix Go/No-Go Signal** shows exactly one of GO, CONDITIONAL GO or NO-GO. None of the source files use that heading, so it can only have come from your template.

- [] The brief follows the template.

### 5.6 Run both skills in one task

*Run both skills from a single request. (5 min)*

1. Select **New task** and send:

```
Do two things using my custom skills.
First, produce this week's Helix launch status report as its own Word document.
Then prep me for the Helix readiness review. In the brief's Risks Since Last Review section, cite the status report you just produced as the evidence.
```

2. Check **Skills & Plugins** for both the **launch-status-report** and **helix-meeting-prep** chips.
3. If Cowork asks which review you mean, pick the most recent one.

> [!HINT] Each sentence carries one skill's trigger phrase. Merge them into one sentence and usually only one skill loads.

> [!NOTE] **Expected:** Both skill chips in the **Workspace** panel.

- [] Both skills loaded in the same task.

### 5.7 Check both outputs

*Confirm you got two linked Word documents. (5 min)*

1. **Output** should hold two separate Word documents, the status report and the readiness brief.
2. Open the brief and check the five headings are intact.
3. **Risks Since Last Review** should cite the status report.

- [] Two linked documents were produced and you've checked them.

### 5.8 Share both skills

*Share each skill with a named lab user. (4 min)*

> [!KNOWLEDGE] **Where:** Cowork > Customize > Skills > (skill) > Share

1. On **Customize**, open each skill's page in turn.
2. Select **Share** and share it with the lab user your organiser named.

- [] Both skills are shared.

### 5.9 Write up the skill inventory

*Write up both skills in one Word table. (5 min)*

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

> [!KNOWLEDGE] **Milestone check:** Milestone 5 is complete when:
> - helix-meeting-prep is saved with brief-template.docx in its folder
> - Its output uses the template headings
> - Both skills loaded in one task and produced two documents
> - Both skills are shared and Skill-Inventory.docx is filled in

- [] Skill-Inventory.docx is filled in for both skills.

> [!HINT] **Learn more:** [Use Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork) · [Customize Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/cowork-customize)

### Milestone 5 complete when

- [] Helix Meeting Prep skill saved with brief-template.docx and proven used
- [] Both skill chips in one task, producing two Word documents
- [] Both skills shared and Skill-Inventory.docx completed

===

# Finish

You've completed the lab. Select **Submit** when you're done. Your work is checked automatically.
