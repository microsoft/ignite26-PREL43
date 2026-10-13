# Contributing

Changes come from VectorSense maintainers and licensed partners.

## Workflow

1. Branch from `main`.
2. Make the change and run the checks locally:
   ```bash
   pip install -e "src/engine[test]" python-docx openpyxl reportlab pillow
   python src/tools/build_datapack.py
   python -m pytest src/engine/tests -q
   ```
3. Open a pull request. CI must pass before merge.

## Changing lab data

- Edit `data/helix/*.yaml`. Do not edit generated files.
- The data pack build refuses changes that break the track: day-one counts, the overlapping meetings, the free focus-block slots, times after D-1 09:00, or any scoring phrase in seeded content (`data/scoring/scorecard.json` → `seed_rules.forbidden`).
- Rebuild the data pack (`python src/tools/build_datapack.py`, with LibreOffice installed so the pricing workbook has computed values) and commit `data/release/helix-datapack-<version>.zip`.
- Any change to data, readiness or scoring is a new release: bump `__version__` in `src/engine/vs_hydrate/__init__.py` and rename `data/readiness/check-set-<version>.json` to match.

## Releasing

Tag the release commit (`git tag v1.0.0 && git push --tags`) and add an entry to `docs/release-notes.md`. Skillable checks out the tag and reinstalls the engine.

## Changing the engine

- Keep every write idempotent and record created IDs in seat state, so interrupted runs resume without duplicates.
- Add a test against the in-memory tenant (`src/engine/vs_hydrate/api/fake.py`) for new behaviour; extend the fake when the engine uses a new Graph call.
- Never log or write credentials or Temporary Access Passes outside `out/`.

## Changing lab instructions

Keep `instructions/lab-guide.md` and `instructions/lab-guide-skillable.md` in step, and keep names that scoring looks for (for example "Helix launch briefing", "Skill-Inventory.docx") exactly as written.
