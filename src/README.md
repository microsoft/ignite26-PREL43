# src

| Path | What it is |
|---|---|
| `engine/` | The `vs-hydrate` Python package (`vs_hydrate/`), its `pyproject.toml` and tests |
| `tools/build_datapack.py` | Rebuilds `data/release/helix-datapack-<version>.zip` from `data/helix/`, with validation and the scoring-integrity lint |
| `scoring-engine/` | The Scoring Engine web application (admin portal, participant scorecard, API, worker) and its Azure deployment. See [scoring-engine/README.md](scoring-engine/README.md) |

The version for every component comes from `engine/vs_hydrate/__init__.py`.

```bash
pip install ./src/engine                                   # operators
pip install -e "./src/engine[test]" python-docx openpyxl reportlab pillow   # development
python src/tools/build_datapack.py
python -m pytest src/engine/tests -q
```

Engine reference: [docs/engine.md](../docs/engine.md).

## Scoring Engine

Deployed into the same tenant the Hydration Kit fills. Tenant and subscription are set in one file:

```bash
cd src/scoring-engine
cp deploy/env/tenant.env.example deploy/env/mytenant.env   # TENANT_ID, SUBSCRIPTION_ID, host names
./deploy/scripts/deploy.sh deploy/env/mytenant.env check
./deploy/scripts/deploy.sh deploy/env/mytenant.env all
```

Full guide: [scoring-engine/docs/DEPLOY.md](scoring-engine/docs/DEPLOY.md). Run it locally with Docker: `docker compose up -d --build` from `src/scoring-engine` (admin portal on port 8080, scorecard on 8081).
