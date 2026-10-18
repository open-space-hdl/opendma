# odma_s2mm

Stream to memory channel of OpenDMA: receives the S2MM stream into an ECC-protected data buffer, cuts each packet
into chunks of one memory burst and writes the complete chunks into the buffer of the transfer command through an
AXI4 write master, never beyond the buffer, and returns one result per command.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, interpretations of the published interface |
| [Architecture](docs/architecture.md) | Entities, ports, chunk former, write command, halt, flush and drain |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results, generic ranges, known deviation |

Tests: `python run.py "*odma_s2mm*"`

| File | Content |
| --- | --- |
| `tb/odma_s2mm_th.vhd` | Harness: clock, reset, DUT, AXI memory model on the write port, stream generator on the stream port, monitors of the results, the AXI4 port and the ECC events |
| `tb/odma_s2mm_tb.vhd` | VUnit testbench, one `run("test_...")` per test case of the verification plan |
| `tb/odma_s2mm_tb_pkg.vhd` | Queue of the packets of the generator, its configuration and the observations of the harness |
| `tb/odma_s2mm_tb_pktvar_pkg.vhd` | The queue of the packets that the generator sends (shared variable `Pkts_v`) |
| `tb/vunit_config.py` | VUnit configurations of the generics (verification plan, section 2) |
