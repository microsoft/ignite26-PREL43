# Launch Command Center: Delegate, Verify and Automate with Microsoft 365 Copilot Cowork

**Advanced · 3 hours · Individual**

Zava Corporation launches its **Helix** product in 10 days. The launch lead has left, and now **you** run the launch.

There is a lot to sort out:

- A supplier problem is still open.
- An executive wants to know if the launch date is safe.
- Two decisions are stuck in Microsoft Teams.
- The product spec and the launch plan do not agree.
- Your calendar has meetings on top of each other.

In this lab, **Microsoft 365 Copilot Cowork** does the work for you. You stay in control and make the final decisions.

You will:

- Learn the Cowork controls: catch-up, drafts, stop and resume, approve and take back a permission.
- Build a full launch readiness pack from one prompt, then check it.
- Save your status report rules as a reusable **skill**.
- Schedule a daily briefing email.
- Optional: build a second skill with a template.

Your Microsoft 365 account already has Helix emails, Teams posts, files and meetings.

## Lab outline

1. **Master the Delegation Controls** (40 min)
1. **Build the Readiness Pack from a Single Brief** (52 min)
1. **Capture Your Reporting Standard as a Skill** (35 min)
1. **Schedule the Daily Launch Briefing** (23 min)
1. **Combine Skills into a Toolkit** (optional, 44 min)

===

# Briefing

### Your situation

- You lead the Helix launch at Zava Corporation.
- Helix ships in **10 days**.
- The executive's question: **Will the launch date hold?**

### How Cowork works

- You describe the result you want.
- Cowork plans the steps and works across your mail, Teams, files and calendar.
- It creates real drafts, documents and meetings.
- It asks you **before** it sends mail or changes your calendar.

### Three good habits

- **Stay in charge.** Watch what Cowork does. Stop it if it goes off track.
- **Check the source.** Every risk and number must point to a file, post or email. If it can't, it must say **UNCONFIRMED**.
- **Write rules once.** Save repeat work as a skill.

### How scoring works

- At the end of each milestone, select **Check my work**.
- Each item turns **green** when your work is found in your mailbox, calendar or OneDrive.
- A **red** item shows a hint. Fix it, then check again. You can check as many times as you like.
- Use the **exact names** in the steps, or the checks can't find your work.
- Total: **100 points**. You need **70** to pass.

| Milestone | Points |
| --- | --- |
| 1. Delegation controls | 32 |
| 2. Readiness pack | 17 |
| 3. Status report skill | 22 |
| 4. Daily briefing | 15 |
| 5. Toolkit (optional) | 14 |

### Good to know

- Do all work on the lab desktop, signed in with the lab account.
- If an **approval card** is open, answer it **before** you type anything. A new message cancels the action.
- Cowork can take a few minutes. Watch the **Workspace** panel. Don't send the same prompt again.

===

# Getting started

> [!NOTE] **Lab preparation status** (test build only: remove before the event)
> Pre-flight: **@lab.Variable(PreflightStatus)** · Hydration: **@lab.Variable(HydrationStatus)** · Readiness: **@lab.Variable(ReadinessStatus)**
> All three should say **ok**. If not, tell your proctor.

### 1. Sign in to the lab desktop

*(2 min)*

1. Select the lab desktop.
1. If Windows asks for a password, enter: ++@lab.VirtualMachine(Win11-Pro-Base).Password++

> [!HINT] Text with a **T** icon types itself into the lab desktop. Click in the right box first, then select the text.

- [] The Windows desktop is open.

### 2. Sign in to Microsoft 365

*(5 min)*

1. Open **Microsoft Edge** and go to: +++https://m365.cloud.microsoft+++
1. Sign in with the **Office 365 Tenant** account:
    - Username: ++@lab.CloudCredential(__CRED__).AdministrativeUsername++
    - Password: ++@lab.CloudCredential(__CRED__).AdministrativePassword++
1. If you see **More information required**, set up **Microsoft Authenticator** on your phone. Follow the steps on screen. You do this only once.
1. If you see a **404** page, open an **InPrivate** window in Edge and sign in again.

> [!ALERT] Use only this account. Do **not** use the Azure Portal account in **Lab Access**. All checks look at this account's mail, calendar and OneDrive.

- [] You are signed in to Microsoft 365.

### 3. Check Cowork and the Helix data

*(5 min)*

1. Go to Microsoft 365 Copilot: +++https://copilot.cloud.microsoft/chat+++
1. Check each item below. Open Outlook and Teams from the **Start** menu.

| Where | What you should see |
| --- | --- |
| Copilot | **Cowork** in the left pane, next to **Chat**. If it's missing, wait 1 minute and refresh. |
| Outlook > Inbox | A thread of 6 emails about a supplier at risk |
| Teams > Launch - Helix | About 20 posts |
| Launch - Helix > Shared | Helix-Product-Spec.docx, Helix-Launch-Plan.docx, Helix-Pricing.xlsx and 3 Competitor PDFs |
| Launch - Helix > Shared > Recordings | Helix-Sync-Notes-1.docx and Helix-Sync-Notes-2.docx |
| Outlook > Calendar | 4 meetings in the next 5 days. At least 2 overlap. |

1. Something missing? Tell your proctor. Later steps need this data.

> [!NOTE] There are no real meeting recordings. The two **Helix-Sync-Notes** files are the notes from two earlier meetings.

- [] Cowork is there and all the Helix data is in place.

### 4. Read the briefing

*(2 min)*

1. Read the **Briefing** page.
1. Come back here when you're ready for Milestone 1.

- [] You know your role and the deadline.

> [!HINT] **Learn more:** [Get started with Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/get-started)

===

# Milestone 1: Master the Delegation Controls

*40 min · required*

In this milestone you will:

- Get a catch-up where every point has a source.
- Get reply drafts that wait in Outlook.
- Stop a task and start it again.
- Give a calendar permission, use it, then take it back.

### 1.1 Get a catch-up

*(5 min)*

1. Open Copilot in a new Edge tab: +++https://copilot.cloud.microsoft/chat+++
1. Select **Cowork**, then **New task**.
1. Paste this prompt and send it:

```
I've just inherited the Helix launch, and it ships in 10 days. Bring me up to speed.
List what is at risk, which decisions are still open, who is waiting on me, and anything I have missed over the last two weeks. Search my inbox, the Launch - Helix Teams channel and the files shared there, and cite every email, Teams post and file you rely on.
```

1. Watch the **Workspace** panel on the right:
    - **Steps** shows progress, for example **1 / 4**.
    - **Tools** shows what Cowork uses, for example Outlook and Teams.

> [!NOTE] **Expected:** A summary of risks, open decisions and who is waiting on you.

- [] The catch-up is done.

### 1.2 Check the sources

*(3 min)*

1. Read each risk in the answer.
1. Each risk should cite an email, a Teams post or a file.
1. Only files cited? Select **New task** and send the same prompt again.

- [] Every risk has a source.

### 1.3 Get three reply drafts

*(4 min)*

1. In the same task, send:

+++Draft replies to the two people who have been waiting on me the longest. Also draft a short holding reply on the supplier escalation thread saying I now own the launch and will confirm our position within 48 hours.+++

1. Wait for it to finish. Cowork saves the replies as drafts. Nothing is sent.

> [!NOTE] **Expected:** Cowork says it saved three drafts.

- [] Three drafts are saved.

### 1.4 Review the drafts in Outlook

*(4 min)*

1. Open Outlook **Drafts**: +++https://outlook.office.com/mail/drafts+++
1. Find the three **[Draft]** replies. Each ends with **Sent by Copilot Cowork**.
1. For each draft: edit it, delete it, or send it.
1. **Keep or send at least one.** The check looks for the line **Sent by Copilot Cowork**.

> [!NOTE] Nothing left your mailbox until **you** selected **Send**.

- [] You reviewed the drafts and kept or sent at least one.

### 1.5 Stop a task

*(4 min)*

1. In the same task, send:

```
Compare the Helix launch plan with the product spec in the shared launch files.
Find every point where they disagree and list each one with the section reference from both documents.
```

1. While it runs, select the **Stop** icon in the message box.
1. Look at **Steps** to see how far it got.

> [!NOTE] **Steps** can lag a few seconds behind.

- [] The task stopped before it finished.

### 1.6 Resume the task

*(3 min)*

1. In the same task, send: +++Resume+++
1. Let it finish.

> [!NOTE] **Expected:** A list of the differences, with section names from both documents.

- [] The task finished.

### 1.7 Plan the week (no changes)

*(4 min)*

1. Send:

+++My calendar for the next five days has conflicts. Plan my week around the Helix launch: tell me which meetings to keep, which to delegate and which to decline, and where I need focus blocks to finish the readiness review. Do not change anything yet; just propose the plan.+++

1. Read the plan. You asked for no changes, so no approval card appears.

- [] You have a plan, and your calendar did not change.

### 1.8 Approve a change with Always allow

*(5 min)*

1. Send:

+++Add a 30-minute focus block to my calendar tomorrow at 10:00 titled "Helix messaging review".+++

1. An approval card appears, for example **Create calendar event?**
1. Check the time and title.
1. Open the arrow next to the action button and select **Always allow**.
1. Select the action button to approve.

> [!ALERT] Don't type anything while the card is open. A new message cancels the action.

> [!NOTE] **Expected:** **Helix messaging review** is on tomorrow's calendar at 10:00.

- [] The first focus block is on your calendar.

### 1.9 Use the permission

*(3 min)*

1. In the same task, send:

+++Add another 30-minute focus block to my calendar tomorrow at 14:00 titled "Helix launch checklist".+++

1. No approval card appears this time, because you chose **Always allow**.
1. Check your calendar. Both focus blocks are there.

- [] The second focus block was added without a card.

### 1.10 Take the permission back

*(5 min)*

1. In the **Workspace** panel, open **Permissions**.
1. Revoke the calendar permission.
1. In the same task, send:

+++Add one more 30-minute focus block to my calendar tomorrow at 16:00 titled "Helix status review".+++

1. The approval card is back. Select **Cancel**.

> [!NOTE] **Always allow** works only in the current task. A new task always starts without it.

> [!NOTE] **Expected:** No **Helix status review** event on your calendar.

- [] You revoked the permission and cancelled the third request.

> [!HINT] **Learn more:** [Use Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork)

### Check your work

Select **Check my work**. Green means done. Red shows a hint: fix it, then check again. **(32 points)**

@lab.Activity(CheckM1)

===

# Milestone 2: Build the Readiness Pack from a Single Brief

*52 min · required*

In this milestone you will:

- Create four outputs from one prompt: a deck, a risk register, a customer PDF and a status card.
- Check that all four are correct and agree.
- Trace a risk and a number back to their source.
- Fix a mistake by asking Cowork, not by hand.

### 2.1 Send the readiness brief

*(5 min)*

1. In Cowork, select **New task**.
1. Paste this brief and send it:

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

> [!NOTE] This run takes several minutes. Cowork builds four outputs and checks them itself.

- [] The brief is sent.

### 2.2 Watch the Workspace panel

*(6 min)*

While Cowork works, look at the **Workspace** panel:

| Section | What it shows |
| --- | --- |
| Steps | The plan, with a tick next to each finished step |
| Output | Files as they are created |
| Skills & Plugins | The skills Cowork uses |
| Tools | The apps it uses, for example Outlook, Teams and Files |

Near the end, Cowork checks its own work and fixes problems.

- [] You followed the plan in the Workspace panel.

### 2.3 Answer questions and let it finish

*(6 min)*

1. If Cowork asks a question, answer it.
1. Wait for the final reply. Don't send the brief again.

> [!NOTE] **Expected:** The final reply lists the files created, the sources used, the checks done, the mistakes fixed, and what is still **UNCONFIRMED**.

- [] The run is finished.

### 2.4 Find the four outputs

*(5 min)*

1. Use the file cards in the reply to open the **deck**, the **risk register** and the **customer PDF**.
1. Scroll up in the task to find the **status card**.

- [] You found all four outputs.

### 2.5 Find the files in OneDrive

*(4 min)*

1. Open OneDrive: +++https://www.office.com/launch/onedrive+++
1. Go to the task's output folder.

> [!KNOWLEDGE] **Where:** My files > Documents > Cowork > Tasks > (this task) > output

- [] The three files are in OneDrive.

### 2.6 Check the deck and risk register

*(5 min)*

| Output | Check |
| --- | --- |
| Deck | 8 slides or fewer. A clear GO, CONDITIONAL GO or NO-GO. Speaker notes on the recommendation, risk and commercial slides. |
| Risk register | All 10 columns. **Source file** and **Source evidence** filled in on every row. **UNCONFIRMED** where the owner is unknown. |

- [] The deck and risk register are correct.

### 2.7 Check the PDF and status card

*(5 min)*

| Output | Check |
| --- | --- |
| Customer PDF | Exactly one page. Written for customers. No internal risks. |
| Status card | Same recommendation, risk count and blocker count as the files |
| All four | Same recommendation, owners, dates and numbers |

- [] The PDF and status card are correct, and all four agree.

### 2.8 Trace a risk to its source

*(6 min)*

1. Pick a high-impact risk in the risk register.
1. Open its **Source file** in Teams.

> [!KNOWLEDGE] **Where:** Microsoft Teams > Launch - Helix > Shared

1. Check that the file really supports the risk.
1. The owner and mitigation must come from the file. If not, they must say **UNCONFIRMED**.
1. Write down any mistake. You fix it in step 2.10.

- [] One risk is traced to its source.

### 2.9 Trace a number to its source

*(4 min)*

1. Pick a number in the deck, for example a price or a date.
1. Open the source file and compare.
1. If they don't match, write it down.

- [] One number is traced to its source.

### 2.10 Fix a mistake by asking Cowork

*(6 min)*

1. Don't edit the files yourself. In the same task, send:

+++Check the risk register again against its cited source files. Replace any inferred owner with UNCONFIRMED, bring the deck and status card into line, regenerate the affected artifacts, and tell me exactly what changed.+++

1. Cowork fixes the files and lists what changed.
1. No mistakes found? Read **Defects found and corrected** in the final reply instead.

- [] The fix is done, or you read the summary.

> [!HINT] **Learn more:** [Use Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/use-cowork)

### Check your work

Select **Check my work**. Green means done. Red shows a hint: fix it, then check again. **(17 points)**

@lab.Activity(CheckM2)

===

# Milestone 3: Capture Your Reporting Standard as a Skill

*35 min · required*

In this milestone you will:

- Save your status report rules as a **skill**.
- Check the skill file (**SKILL.md**) in OneDrive.
- Use the skill in a new task.

### 3.1 Start a new skill

*(4 min)*

1. In Cowork, select **Customize**.
1. Open the **Skills** tab.
1. Select **Add** > **New skill**.

> [!NOTE] **Expected:** A new task asks **What should your new skill do?**

- [] The new skill task is open.

### 3.2 Describe your report rules

*(5 min)*

1. At **What should your new skill do?**, select **Skip**.
1. At **Which category fits it best?**, select **Describe another option**.
1. Paste this text and select **Submit**:

```
Create a skill called Launch Status Report. Whenever I ask for this week's Helix launch status, collect the launch plan and product spec, every post in the Launch - Helix Teams channel since the last report, and Helix-related mail from the same period.
Output a Word document named Helix-Status-<YYYY-MM-DD>.docx with these sections: headline status, changes since last report, risks with owners and movement, decisions needed from the sponsor, next 7 days.
Each risk must name the file, channel post or email it came from. A risk with no source is marked UNCONFIRMED and listed last. Maximum 400 words. If the risk section would take it over the limit, shorten the next 7 days section to bullets first. Headline status is exactly one of ON TRACK, AT RISK or OFF TRACK. If any risk has high impact and open status, it cannot be ON TRACK.
```

> [!NOTE] No category question? Paste the same text in the message box and send it.

- [] The skill description is sent.

### 3.3 Save the skill

*(5 min)*

1. A **Copy file** card appears for **skills/launch-status-report**. Select **Approve**.
1. Open the **skill-quality-report.html** card.
1. Note the score and any weak points.

- [] The skill is saved.

### 3.4 Check what the skill contains

*(6 min)*

Open the saved **SKILL.md**. Check that it has all six:

| Element | What to look for |
| --- | --- |
| Sources | Channel files, channel posts and Helix mail |
| Sections | The five report sections |
| Evidence rule | Each risk has a source, or says UNCONFIRMED |
| Length | 400 words maximum, and what to shorten first |
| Status rule | The headline agrees with the risks |
| Output | A Word file with the date in its name |

- [] SKILL.md has all six.

### 3.5 Find SKILL.md in OneDrive

*(5 min)*

> [!KNOWLEDGE] **Where:** My files > Documents > Cowork > skills > launch-status-report > SKILL.md

1. Open the file.
1. At the top, check there is a **name** and a **description**.
1. The description says what the skill does. Cowork uses it to decide when to use the skill.

> [!HINT] If a skill doesn't load, check its folder and description first.

- [] SKILL.md is in the right folder, with a name and description.

### 3.6 Use the skill in a new task

*(5 min)*

1. Select **New task**. A skill only loads when a task starts.
1. Send: +++Produce this week's Helix launch status report.+++
1. Look at **Skills & Plugins** in the **Workspace** panel.

> [!NOTE] **Expected:** A **launch-status-report** chip appears.

- [] The skill chip appears.

### 3.7 Check the report

*(5 min)*

1. Open the Word report. Its name looks like **Helix-Status-<YYYY-MM-DD>.docx**.
1. Check:
    - It has your five sections.
    - The headline is exactly ON TRACK, AT RISK or OFF TRACK.
    - Every risk has a source.
    - It is 400 words or fewer.

- [] The report follows your rules.

> [!HINT] **Learn more:** [Customize Copilot Cowork](https://learn.microsoft.com/en-us/microsoft-365/copilot/cowork/cowork-customize)

### Check your work

Select **Check my work**. Green means done. Red shows a hint: fix it, then check again. **(22 points)**

@lab.Activity(CheckM3)

===

# Milestone 4: Schedule the Daily Launch Briefing

*23 min · required*

In this milestone you will:

- Schedule a briefing email for every weekday morning.
- Check the schedule before you accept it.
- Approve the first email.

### 4.1 Ask for the daily briefing

*(4 min)*

1. Select **New task** and send:

+++Every weekday at 8am, email me a Helix launch briefing: what changed overnight in the Launch - Helix channel and in Helix mail, which risks moved, and what I need to decide today. Keep it under 200 words.+++

> [!NOTE] **Expected:** Cowork shows a schedule card.

- [] The schedule card is showing.

### 4.2 Check the schedule card

*(5 min)*

| Field | Check |
| --- | --- |
| Name | **Helix launch briefing**. If it's different, change it. |
| Repeat | Weekdays at 8:00 |
| Run in | New conversation, or this one |
| Description | Your request, with nothing extra added |

- [] The schedule card matches your request.

### 4.3 Run it once and approve

*(6 min)*

1. Tick **Run once now**, then select **Schedule**.
1. A **Send email?** card appears.
1. Read the draft, then select **Send**.
1. Do **not** select **Always allow**. Future emails should still ask you first.

> [!ALERT] Answer the card before you type anything. A new message cancels the send.

- [] You approved the first email with **Send**.

### 4.4 Find it in Automations

*(3 min)*

1. In Cowork, select **Automations**.
1. **Helix launch briefing** is in the list.

> [!NOTE] Schedules show only in **Automations**, not on your calendar.

- [] The briefing is in Automations.

### 4.5 Check the first email

*(5 min)*

1. Open your Inbox: +++https://outlook.office.com/mail+++
1. Open **Helix launch briefing - [today's date]**.
1. Check: under 200 words, what changed, which risks moved, what to decide today.

- [] The first briefing email arrived.

> [!HINT] **Learn more:** [Schedule prompts in Copilot Cowork](https://support.microsoft.com/en-us/microsoft-365-copilot/cowork-manage-tasks-schedule-prompts)

### Check your work

Select **Check my work**. Green means done. Red shows a hint: fix it, then check again. **(15 points)**

@lab.Activity(CheckM4)

===

# Milestone 5: Combine Skills into a Toolkit (Optional)

*44 min · optional*

> [!NOTE] This milestone is optional. You can pass the lab after Milestone 4.

In this milestone you will:

- Create a second skill with a template.
- Use both skills in one task.
- Share both skills and list them in a table.

### 5.1 Describe the meeting prep skill

*(5 min)*

1. Go to **Customize** > **Skills** > **Add** > **New skill**.
1. Select **Skip**, then **Describe another option**.
1. Paste this text and select **Submit**:

```
Create a skill called Helix Meeting Prep. Whenever I ask to be prepared for the Helix readiness review, find that meeting on my calendar, then collect the launch plan and product spec and the latest posts in the Launch - Helix Teams channel.
Output a Word document with these sections: meeting time and attendees, open decisions with owners, risks since the last review, and one recommended focus for the meeting. If a decision has no named owner, mark it UNCONFIRMED instead of guessing.
```

- [] The description is sent.

### 5.2 Save the skill

*(5 min)*

1. Approve the **Copy file** card for **skills/helix-meeting-prep**.
1. Open **skill-quality-report.html** and note the score.
1. Check whether SKILL.md says when to hand off to **launch-status-report**.

- [] The helix-meeting-prep skill is saved.

### 5.3 Add a template

*(5 min)*

1. In the same task, send this as one message:

```
Add a companion file to the helix-meeting-prep skill: brief-template.docx, stored in the same skill folder. It is a one-page brief template with these headings, in this order:
1. Meeting Snapshot
2. Decisions Awaiting an Owner
3. Risks Since Last Review
4. Helix Go/No-Go Signal
5. One Thing to Push For Under Helix Go/No-Go Signal, the brief must always give exactly one of GO, CONDITIONAL GO or NO-GO.
Then update the skill instructions to say: Use brief-template.docx as the exact section structure, keep every heading in the given order, and do not add sections.
```

1. Approve the **Copy file** card for **skills/helix-meeting-prep**.

- [] The template is saved in the skill folder.

### 5.4 Check the template

*(4 min)*

1. Open the **brief-template** file card.
1. Check: five headings in order, and **Helix Go/No-Go Signal** gives GO, CONDITIONAL GO or NO-GO.

> [!HINT] A second copy of brief-template.docx may appear at the top of OneDrive. You can delete it. The skill uses the one in its own folder.

- [] The template is correct.

### 5.5 Test the template

*(6 min)*

1. Select **New task** and send: +++Prep me for the Helix readiness review.+++
1. Open the Word document. The five headings appear in order.

- [] The brief uses the template.

### 5.6 Use both skills in one task

*(5 min)*

1. Select **New task** and send:

```
Do two things using my custom skills.
First, produce this week's Helix launch status report as its own Word document.
Then prep me for the Helix readiness review. In the brief's Risks Since Last Review section, cite the status report you just produced as the evidence.
```

1. In **Skills & Plugins**, check for both chips: **launch-status-report** and **helix-meeting-prep**.
1. If Cowork asks which review, choose the latest one.

- [] Both skills loaded.

### 5.7 Check both documents

*(5 min)*

1. **Output** has two Word documents: the status report and the brief.
1. The brief has the five headings.
1. **Risks Since Last Review** cites the status report.

- [] Both documents are correct.

### 5.8 Share both skills

*(4 min)*

> [!KNOWLEDGE] **Where:** Cowork > Customize > Skills > (skill) > Share

1. Open each skill and select **Share**.
1. Share it with the user your proctor names.

- [] Both skills are shared.

### 5.9 Make a skill inventory

*(5 min)*

1. In OneDrive, create a Word document named **Skill-Inventory.docx**.
1. Add a table with one row per skill and these columns:

| Column | What to enter |
| --- | --- |
| Skill | The skill name |
| What it does | One line |
| When it runs | The phrase that starts it |
| Sources it reads | Files, posts, mail or calendar |
| Owner | You |
| Last tested | Today's date |
| Known gap | One weak point |

- [] Skill-Inventory.docx is done.

### Check your work

Select **Check my work**. Green means done. Red shows a hint: fix it, then check again. **(14 points, optional)**

@lab.Activity(CheckM5)

===

# Finish

You've finished the lab. Well done!

1. Go back to each milestone you did and select **Check my work** one more time.
1. Select **Submit**.

Your score is the total of your green items. You need **70 of 100** to pass.
