# Data pack reference

The data pack is the Helix launch as files: `data/helix/*.yaml` plus the generated Word, Excel and PDF files and persona photos, zipped with a manifest of SHA-256 checksums.

## Built pack layout

```
helix-datapack-1.0.0.zip
├─ manifest.json        name, version, latest_content, counts, sha256 of every entry
├─ source/*.yaml        the six source files from data/helix/
├─ files/               Helix-Product-Spec.docx, Helix-Launch-Plan.docx, Helix-Pricing.xlsx,
│                       Competitor-1-SensorCloud.pdf, Competitor-2-EdgeSense.pdf, Competitor-3-Gen3.pdf,
│                       Helix-Sync-Notes-1.docx, Helix-Sync-Notes-2.docx
└─ photos/<key>.png     initials avatars for the 32 personas
```

## Source files

### people.yaml
`internal[]`: `key`, `given`, `surname`, `mail` (UPN local part), `title`, `department`, `manager` (key), `office`. `external[]`: `key`, `email` (reserved `.example` domains), `title`, `company`. `seat`: title, department and manager given to every learner seat. `reviewer`: the Milestone 5 sharing account.

### mail.yaml
`messages[]`: `id`, `from`, `to`, `cc` (person keys or `learner`), `subject`, `sent` (offset), `read`, optional `flag`, `importance`, `conversation`, `fact`, and `body` (blank line between paragraphs). Messages sharing a `conversation` are threaded.

### teams.yaml
`team`: display name, description, `created` offset and the channel with its `files_folder` layout (`shared` and `Recordings`). `posts[]`: `id`, `from`, `sent`, `body`, optional `mentions: [learner]` with `{{mention:learner}}` in the body, and `replies[]`.

### calendar.yaml
`events[]`: `id`, `subject`, `organiser` (internal key), `attendees` (must include `learner`), `start`, `end`, `body`.

### documents.yaml
`documents`: Word files as blocks (`h`, `h2`, `p`, `bullets`, `table`). `competitors`: one-page PDF profiles. `pricing`: unit cost, volume and price scenarios for the workbook.

## Rules the build enforces

| Rule | Why |
|---|---|
| 6 supplier-thread messages, 20 channel messages, 6 shared files plus 2 in Recordings | Learners check these exact counts on day one (Getting started step 3) |
| Exactly 4 meetings from D0 to D+5, at least two overlapping | Day-one check and fact F4 |
| D+1 10:00, 14:00 and 16:00 free for 30 minutes | M1 focus blocks |
| Nothing later than D-1 09:00 | Teams import rejects future-dated posts, so seats are hydrated from D-1 09:30 |
| Every person key and placeholder resolves | No broken names or dates in a seat |
| No seeded text, file name or file content contains a scoring phrase | A seeded match would hand out free points |

## Seeded facts

| Fact | Ground truth |
|---|---|
| F1 | Corvane can ship 60% of modules on time and 40% eight days late; decision due by end of D+2 |
| F2 | Launch price (249 or 279) and the Gen2 fallback are undecided, with no owner |
| F3 | Spec and plan disagree on markets, battery life, firmware and certification timing |
| F4 | The supplier call and the price decision overlap tomorrow |
| F5 | "2x more accurate than SensorCloud" has no supporting source |
| F6 | The CEO asks whether the date holds; expected recommendation CONDITIONAL GO |
| W1/W2 | Hannah Schmidt and Marcus Hale have waited longest for replies |
