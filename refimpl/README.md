# Lattice layout reference implementation

Clean-room Python 3 (no dependencies) model of the layout algorithm in
`../ADDENDUM-3.md`. It is the **source of truth for the golden numbers** in
ADDENDUM-3 §3 and §8. It is our own code; it reproduces no TrellisWM code, site
JS or internal names.

| File | Purpose |
|---|---|
| `lattice_layout.py` | Tree model, normalize, requirements, space sharing, solve pipeline, operations |
| `goldens.py` | Golden cases G01–G27 plus G13b (28 cases) (`python3 goldens.py` prints, `--json` dumps) |
| `goldens.json` | Frozen expected output; `test_refimpl.py` compares against it |
| `examples.py` / `examples.txt` | Worked examples E1–E19 for ADDENDUM-3 §3 |
| `test_refimpl.py` | Golden check plus property tests (sharing, gaps/shared edges, fit check on every node, close-undoes-add, seam isolation) |

Run: `python3 test_refimpl.py`. The Swift `LayoutModel`/`LayoutEngine` must
reproduce `goldens.json` exactly (port the cases as XCTest data). If the
spec and this code disagree, fix one of them in the same change and
regenerate: `python3 goldens.py --json > goldens.json && python3 examples.py > examples.txt`.
