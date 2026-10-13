# src

| Path | What it is |
|---|---|
| `engine/` | The `vs-hydrate` Python package (`vs_hydrate/`), its `pyproject.toml` and tests |
| `tools/build_datapack.py` | Rebuilds `data/release/helix-datapack-<version>.zip` from `data/helix/`, with validation and the scoring-integrity lint |

The version for every component comes from `engine/vs_hydrate/__init__.py`.

```bash
pip install ./src/engine                                   # operators
pip install -e "./src/engine[test]" python-docx openpyxl reportlab pillow   # development
python src/tools/build_datapack.py
python -m pytest src/engine/tests -q
```

Engine reference: [docs/engine.md](../docs/engine.md).
