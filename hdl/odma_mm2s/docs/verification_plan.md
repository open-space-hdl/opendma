# odma_mm2s: Verification Plan

## 1. Overview

The channel is verified through its ports: transfer commands and the channel control from the bench, results
collected by a monitor of the harness, the memory port on the AXI memory model of `tb/` (with its protocol checks,
error ranges, backpressure and statistics), the stream port on the AXI4-Stream slave VVC and, for transfers longer
than the 16 KB of the VVC, on a stream checker of the harness that compares every byte with the count pattern of the
memory. Expected stream data is computed by the bench from the memory contents, never by the RTL.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `odma_mm2s_tb` | `odma_mm2s_th` | `odma_mm2s`; AXI memory model instance 0 on `M_Axi_*` with the maximum burst set to `BurstBeats_g`; AXI4-Stream slave VVC and the long-transfer checker on `M_Mm2s_*`; a monitor of the result port and of the R channel (beats with `RValid` and not `RReady`) |

| VUnit configuration | `MemWidth_g`, `StreamWidth_g`, `BurstBeats_g`, `AddrWidth_g`, `LengthWidth_g` | Purpose |
| --- | --- | --- |
| `w32_s32` | 32, 32, 16, 32, 26 | Default of PG021 |
| `w64_s8` | 64, 8, 16, 40, 26 | Narrow stream, wide memory |
| `w128_s32` | 128, 32, 256, 64, 26 | Longest burst, 64-bit addresses |
| `w512_s512` | 512, 512, 2, 32, 14 | Equal widths, shortest burst |
| `w1024_s8` | 1024, 8, 2, 32, 8 | Widest ratio, shortest length width |

Clock 100 MHz. Simulators: GHDL; QuestaSim with and without code coverage in the batch of phase a.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_aligned` (TC-MM-01) | Transfers at aligned addresses of 1 byte, one stream beat, one memory word, one burst and 3.5 bursts; stream bytes, `TKeep` and `TLast` compared byte for byte; one result per command with the length and the end of packet | MM-IF-02, MM-RD-01, MM-ST-01, MM-ST-02, MM-ST-03 |
| `test_unaligned` (TC-MM-02) | Every start offset within a memory word combined with lengths from 1 to three memory words; first byte in lane 0, last `TKeep`; the statistics of the memory model show reads only of the words that contain the buffer | MM-RD-01, MM-ST-01 |
| `test_bursts` (TC-MM-03) | Transfers that start shortly before a 4 KB boundary and span several boundaries; the memory model checks every burst against 4 KB and `BurstBeats_g` (no alert allowed) | MM-IF-01, MM-RD-02 |
| `test_backpressure` (TC-MM-04) | 20 transfers of random address and length with 50 % random backpressure of the stream peer and 50 % stall and a latency of 30 cycles in the memory model; data identical | MM-ST-01, MM-ST-02 |
| `test_throughput` (TC-MM-05) | A transfer of 256 bursts with a ready stream peer and memory: the number of clock cycles from the first to the last stream beat exceeds the number of beats by at most 2 | MM-RD-05 |
| `test_bus_not_held` (TC-MM-06) | The stream peer stops after 10 beats of a long transfer; during the next 5000 clock cycles the R channel never has `RValid` without `RReady` and the number of read bursts stays bounded by the buffer depth; the transfer completes when the peer resumes | MM-RD-03 |
| `test_queue` (TC-MM-07) | Three commands back to back: three packets in order and three results in order, the second one rejected (buffer beyond the top) between two good ones | MM-IF-03, MM-ST-03, MM-RD-04 |
| `test_result_timing` (TC-MM-08) | With the stream peer delayed, the result appears only after the handshake of the last beat | MM-ST-03 |
| `test_read_errors` (TC-MM-09) | SLVERR on a middle beat, DECERR on the last beat, SLVERR followed by DECERR within one transfer: the transfer is sent completely with `TLast`, the result carries the code of the first error | MM-ER-01, MM-ER-02 |
| `test_beyond_top` (TC-MM-10) | A buffer ending at the top of the address space is read; a buffer one byte longer causes no burst (statistics), no beat and the result decode error with 0 bytes | MM-RD-04 |
| `test_halt` (TC-MM-11) | `Run` falls during a transfer: the transfer is sent completely, its result returned, a further command is not accepted, `Stopped` rises after the result | MM-IF-03, MM-HA-01 |
| `test_drain` (TC-MM-12) | `Drain` rises during a transfer with a stalled stream peer: no further beat, all read bursts complete (statistics), no result, `Stopped` rises; with `Drain` before any command: no command accepted | MM-HA-02 |
| `test_ecc` (TC-MM-13) | Single error injected: the data is correct and `Ecc_Sec` pulses once; double error injected: `Ecc_Ded` pulses once | MM-FT-01 |
| `test_long_transfer` (TC-MM-14) | A transfer of 1 MB against the long-transfer checker, with backpressure | MM-RD-01, MM-ST-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| MM-IF-01 | TC-MM-03 |
| MM-IF-02 | TC-MM-01 |
| MM-IF-03 | TC-MM-07, TC-MM-11 |
| MM-RD-01 | TC-MM-01, TC-MM-02, TC-MM-14 |
| MM-RD-02 | TC-MM-03 |
| MM-RD-03 | TC-MM-06 |
| MM-RD-04 | TC-MM-07, TC-MM-10 |
| MM-RD-05 | TC-MM-05 |
| MM-ST-01 | TC-MM-01, TC-MM-02, TC-MM-04, TC-MM-14 |
| MM-ST-02 | TC-MM-01, TC-MM-04 |
| MM-ST-03 | TC-MM-01, TC-MM-07, TC-MM-08 |
| MM-ER-01, MM-ER-02 | TC-MM-09 |
| MM-HA-01 | TC-MM-11 |
| MM-HA-02 | TC-MM-12 |
| MM-FT-01 | TC-MM-13 |

The recovery of the state machines from an illegal state (`when others`, architecture D15) cannot be reached through
the ports; it is reviewed in the code and listed in the coverage report.

## 5. Negative tests

| Check or error path | Test |
| --- | --- |
| Read error responses SLVERR and DECERR | TC-MM-09 |
| Buffer beyond the top of the address space | TC-MM-10 |
| Commands while halted or draining | TC-MM-11, TC-MM-12 |
| ECC single and double errors | TC-MM-13 |
