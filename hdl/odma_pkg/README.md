# odma_pkg

Definitions shared by all OpenDMA modules: error codes of a transfer result, the byte lane functions of the stream
conventions, the address range check and the consistency check of the core generics. The module also verifies the
shared verification components in `tb/` (AXI memory model, sequence player) and the model of the programming
sequences in `tb/model/`.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements |
| [Architecture](docs/architecture.md) | Package contents, memory model, sequence player and files, model of the programming sequences |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results |

Tests: `python run.py "*odma_pkg*"`

| File | Content |
| --- | --- |
| `tb/odma_pkg_th.vhd` | Harness: clock, AXI4 VVC and raw driver on the AXI memory model, AXI4-Lite VVC on a register stub, AXI4-Stream VVCs back to back |
| `tb/odma_pkg_tb.vhd` | VUnit testbench, one `run("test_...")` per test case of the verification plan |
| `tb/vunit_config.py` | VUnit configuration: the model writes the files of the reference scenario before `test_model_dr` |
| `tb/sequences/` | Sequence files of the player tests |
| `tb/golden/` | Golden files of the reference scenario of the model, written by hand from PG021 chapter 4 |
