# Release notes

## v1.0.0

First release of the VectorSense Hydration Kit for the Launch Command Center lab (COWORK-T1).

- Data pack `helix-datapack-1.0.0.zip`: 32 personas, 35 messages (including the 6-message supplier thread), the Launch - Helix channel (20 posts), 8 channel files, 8 meetings (exactly 4 in the next five days).
- Readiness check set 1.0.0: six day-one items, seeded facts F1-F6 and W1/W2 with anchors, indexing checks, scoring-integrity baseline.
- Scorecard: 12 checks, 100 points, pass mark 70.
- Engine `vs-hydrate` 1.0.0: `validate`, `tenant`, `seats`, `check`, `score`, `retire`.

**Required actions:** set up the app registration (`infra/entra/setup-app-registration.ps1`), install the engine (`pip install ./src/engine`), create `tenant.yaml`, then run `validate` and `tenant`.

**Known limits:** seats are hydrated from D-1 09:30 (seat time zone) for a lab on D0, because Teams import rejects future-dated posts. Not yet run against a live tenant.
