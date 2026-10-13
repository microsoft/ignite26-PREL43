# Instructor and proctor notes: Launch Command Center (COWORK-T1)

These notes are for proctors and instructors. Learners never see them.

## Before the event

1. Confirm the seat pool: `out/seat-inventory.json` lists only seats in `ready` state. Size it to expected launches plus 15%.
2. **Copilot spot-check (one seat per batch).** App-only credentials cannot query Microsoft 365 Copilot, so this step is done by a person. Sign in to one ready seat with its Entra username and Temporary Access Pass and ask each question below in Microsoft 365 Copilot Chat. Each answer should contain the listed terms. If two or more fail, the content is probably still indexing: wait 30 minutes and try again before the event starts.

| Fact | Ask Copilot | Answer should mention |
|---|---|---|
| F1 | What is the status of the Helix sensor module supplier? | 60%, 40%, eight days |
| F2 | Has the Helix launch price been decided? | 249, 279 (undecided) |
| F3 | Where do the Helix spec and launch plan disagree? | Germany, battery, firmware, CE |
| F4 | Do I have overlapping Helix meetings this week? | supplier call, price decision |
| F5 | Is there evidence that Helix is twice as accurate as SensorCloud? | 0.2 (comparable accuracy, so no evidence) |
| F6 | Who is asking whether the Helix date holds? | Elena |
| W1/W2 | Who is waiting on me about Helix? | Hannah, Marcus |

3. Tell learners the **reviewer account** for Milestone 5 sharing: `helix.reviewer@<tenant domain>` unless the tenant config names another.
4. Lab day matters. Seats are written for one event date (`lab_day`): Helix ships in 10 days, and the overlapping meetings are "tomorrow". On any later day the dates no longer match the lab guide, so `check` marks a seat failed once its lab day has passed.

## Ground truth (what a good learner finds)

| Fact | Ground truth | Where it lives |
|---|---|---|
| F1 | Corvane can ship 60% of modules on time, 40% eight days late. Decision due end of day D+2, unanswered. If no answer, Corvane holds the full order. | Supplier thread s-1 to s-6; Helix-Sync-Notes-2 |
| F2 | Launch price (249 or 279) and the Gen2 fallback are both undecided, with no owner named. | Channel posts p-06 and p-10; Helix-Pricing.xlsx; Sync notes 2 |
| F3 | Spec v3 and plan v4 disagree: markets (spec adds Germany), battery (18 vs 24 months), firmware (2.1 vs 2.0), certification (CE before ship vs CE on D+12, after ship). | Helix-Product-Spec.docx §2.1, §4.2, §5.3, §7; Helix-Launch-Plan.docx §3, §4, §5.1, §6; post p-16 |
| F4 | Helix supplier call (11:00-12:00) and Helix price decision (11:30-12:30) overlap tomorrow. | Calendar |
| F5 | "2x more accurate than SensorCloud" has no source. SensorCloud Pro's accuracy (±0.2 °C) equals Helix's. It must stay out of the customer one-pager. | Post p-14; Competitor-1-SensorCloud.pdf |
| F6 | Elena Marsh (CEO) wants to know whether the date holds before the readiness review on D+2. | Mail m-30; post p-18; Helix readiness review |
| W1/W2 | Hannah Schmidt (customer FAQ, D-6) and Marcus Hale (sales pricing, D-4) have waited longest. M1-3 drafts go to them. | Mail m-21, m-24 |

**Expected recommendation: CONDITIONAL GO.** Conditions: a supplier decision (split shipment or Gen2 fallback) before end of day D+2, an answer on CE timing (it currently falls two days after ship), and a launch price decision.

**Numbers learners trace (M2-9).** List price 249 or 279; unit cost 142; gross margin 43.0% or 49.1%; launch volume 12,000 units (all Helix-Pricing.xlsx); 60% of modules on time (supplier thread s-3); ship date D+10 (launch plan §2 and §4).

**Owners (M2-8, M2-10).** Only two risk owners are named in a source: Nadia Kowalski (supplier capacity) and Omar Haddad (firmware readiness), both in launch plan §8. Certification timing and the Gen2 fallback decision have no owner anywhere, so the risk register must show UNCONFIRMED for them. A register that names Ben Carter or Chloe Martin as owner has inferred it; that is the defect M2-10 asks learners to fix by instruction.

## During the event

- **Learner reports missing day-one data.** Do not troubleshoot the seat. Assign the next ready seat and mark the old one for `retire`.
- **No Cowork in the left pane.** Wait a minute and refresh. If it is still missing, the seat's licence or group membership is still provisioning; assign another ready seat.
- **M1 focus blocks at the wrong hour.** The seat's mailbox time zone is the event region set at hydration. If a learner is elsewhere, the blocks still score (scoring checks the title, not the hour).
- **Cowork stops mid-run in M2.** The seat probably hit its Copilot Credits cap. M2 builds four outputs and uses the most credits; raise the cap for the event.
- **Approval card disappeared.** The learner typed while the card was open, which cancels the action. They repeat the request.

## Scoring

The Submit activity runs `vs-hydrate score --seat <upn> --json`. Twelve checks, 100 points, pass mark 70. Each check reads the learner's own mailbox, calendar and OneDrive directly.

| Milestone | Check | Points | Passes when the learner's data has |
|---|---|---|---|
| M1 | drafts-saved | 8 | Mail containing "Sent by Copilot Cowork" (Drafts, Sent Items or Inbox) |
| M1 | focus-block-approved | 7 | Event "Helix messaging review" |
| M1 | focus-block-always-allow | 7 | Event "Helix launch checklist" |
| M1 | third-block-cancelled | 10 | No event "Helix status review" |
| M2 | risk-register-columns | 10 | OneDrive file containing "Source evidence" |
| M2 | unconfirmed-marked | 7 | OneDrive file containing UNCONFIRMED (skill files excluded) |
| M3 | skill-saved | 12 | OneDrive item matching launch-status-report |
| M3 | status-report-produced | 10 | OneDrive file matching Helix-Status |
| M4 | briefing-email-received | 15 | Mail whose subject starts "Helix launch briefing" |
| M5 | meeting-prep-skill | 5 | OneDrive item matching helix-meeting-prep |
| M5 | companion-template | 4 | OneDrive file matching brief-template |
| M5 | skill-inventory | 5 | OneDrive file matching Skill-Inventory |

Two deliberate interpretations of the published scorecard, both in `data/scoring/scorecard.json`:

- **unconfirmed-marked** ignores SKILL.md and the skill quality report. The M3 skill text contains the word UNCONFIRMED, so without this exclusion a learner could earn the M2 points from M3 alone.
- **third-block-cancelled** has a guard that is **off** by default, matching the published scorecard. Off, a learner who never reaches M1-10 still gets these 10 points because the event is absent. Turn `guards.third-block-cancelled.enabled` on to require at least one focus block first.

**Re-checks.** If a OneDrive check fails while the learner's OneDrive changed in the last 20 minutes, the result lists it under `recheck`. Run `score` again a few minutes later, or confirm it by hand in `Launch_Command_Center_Scorecard_Template.xlsx`.

## After the event

1. `vs-hydrate retire --used` removes every seat that was scored or shows learner activity.
2. `vs-hydrate retire --failed` removes seats that failed the readiness check.
3. `vs-hydrate seats --count N` replenishes the pool for the next event.
