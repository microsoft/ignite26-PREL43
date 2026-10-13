# data

Everything the lab's tenant contains, and the rules that check it.

| Path | What it is |
|---|---|
| `helix/company.yaml` | Zava profile, external organisations, competitors |
| `helix/people.yaml` | 32 personas, 4 external contacts, the seat persona and the reviewer account |
| `helix/mail.yaml` | 35 messages: the 6-message supplier thread, two people waiting, the CEO's question, routine mail |
| `helix/teams.yaml` | The Launch - Helix channel: 13 posts and 7 replies, and the channel file layout |
| `helix/calendar.yaml` | 4 past meetings and exactly 4 in the next five days |
| `helix/documents.yaml` | Product spec, launch plan, sync notes, pricing workbook, competitor one-pagers |
| `release/helix-datapack-1.0.0.zip` | The built data pack the engine reads, committed so a fresh clone runs without build tools |
| `readiness/check-set-1.0.0.json` | Readiness check: day-one items, facts F1-F6 with anchors, indexing, integrity |
| `scoring/scorecard.json` | 12 checks, 100 points, pass mark 70, and the phrases seeded data may never contain |
| `scoring/Launch_Command_Center_Scorecard_Template.xlsx` | Proctor scorecard, event results, seat readiness |

All times are offsets from the lab day, for example `D-9 09:12`, so the launch is always ten days out whenever the lab runs. `{{learner}}`, `{{learner_first}}`, `{{date:D+2}}` and `{{weekday:D+2}}` are filled in per seat.

After changing anything in `helix/`, rebuild with `python src/tools/build_datapack.py` and commit the new zip in `release/`. The build stops if a change breaks something the track depends on (exact counts, the overlapping meetings, the free focus-block slots, nothing dated after D-1 09:00, no scoring phrase in any seeded item). Field-by-field reference: [docs/data-pack.md](../docs/data-pack.md).
