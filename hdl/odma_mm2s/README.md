# odma_mm2s

Memory to stream channel of OpenDMA: reads the buffer of each transfer command through an AXI4 read master with
unaligned addresses, burst and 4 KB splitting and an ECC-protected read data buffer, sends it on the MM2S stream with
`TKeep` and `TLast` and returns one result per command.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, interpretations of the published interface |
| [Architecture](docs/architecture.md) | Entities, ports, read command, stream output, halt and drain |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results, generic ranges, known deviation |

Tests: `python run.py "*odma_mm2s*"`

| File | Content |
| --- | --- |
| `tb/odma_mm2s_th.vhd` | Harness: clock, reset, DUT, AXI memory model on the read port, AXI4-Stream slave VVC and stream checker on the stream port, monitors of the results, the AXI4 port and the ECC events |
| `tb/odma_mm2s_tb.vhd` | VUnit testbench, one `run("test_...")` per test case of the verification plan |
| `tb/odma_mm2s_tb_pkg.vhd` | Configuration of the stream checker and the observations of the harness |
| `tb/odma_mm2s_tb_pktvar_pkg.vhd` | The queue of the packets that the stream checker expects (shared variable `Pkts_v`) |
| `tb/vunit_config.py` | VUnit configurations of the generics (verification plan, section 2) |
