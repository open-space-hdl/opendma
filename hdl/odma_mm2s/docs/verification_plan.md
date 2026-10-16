# odma_mm2s: Verification Plan

## 1. Overview

The channel is verified through its ports: transfer commands and the channel control from the bench, results
collected by a monitor of the harness, the memory port on the AXI memory model of `tb/` (with its protocol checks,
error ranges, backpressure and statistics) and the stream port on a stream checker of the harness. The bench fills
the memory with the count pattern of the memory model and queues the packets it expects (first byte, length); the
checker compares every byte, `TKeep` and `TLast` with them and raises an alert on a difference or a beat without an
expected packet. The checker drives `TReady`: always high, high in a given percentage of the clock cycles, held low,
or low for a number of clock cycles before a given beat. Expected stream data is computed by the bench from the
memory contents, never by the RTL. The AXI4-Stream VVC of UVVM is not used: its BFM takes at most 32 `TStrb` bits
(256 data bits), and the checker has no packet size limit.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `odma_mm2s_tb` | `odma_mm2s_th` | `odma_mm2s`; AXI memory model instance 0 on `M_Axi_*` with the maximum burst set to `BurstBeats_g`; the stream checker on `M_Mm2s_*`; monitors of the result port, of the AR channel (bursts, attributes), of the R channel (cycles with `RValid` and not `RReady`, bursts completed) and of the ECC events |

| VUnit configuration | `MemWidth_g`, `StreamWidth_g`, `BurstBeats_g`, `AddrWidth_g`, `LengthWidth_g` | Purpose |
| --- | --- | --- |
| `w32_s32` | 32, 32, 16, 32, 26 | Default of PG021 |
| `w64_s8` | 64, 8, 16, 40, 26 | Narrow stream, wide memory |
| `w128_s32` | 128, 32, 256, 64, 26 | Longest burst, 64-bit addresses |
| `w128_s64` | 128, 64, 32, 32, 16 | Stream width 64 |
| `w256_s16` | 256, 16, 8, 48, 20 | Memory width 256, stream width 16 |
| `w256_s128` | 256, 128, 4, 32, 18 | Stream width 128 |
| `w512_s256` | 512, 256, 8, 36, 22 | Stream width 256 |
| `w512_s512` | 512, 512, 2, 32, 14 | Equal widths, shortest burst |
| `w1024_s8` | 1024, 8, 2, 32, 8 | Widest ratio, shortest length width |
| `w1024_s1024` | 1024, 1024, 256, 64, 12 | Widest stream and memory, bursts limited by 4 KB (32 beats) |

Every configuration has a data buffer of four bursts (`BufferBeats_g` = 4 x `BurstBeats_g` x `MemWidth_g` /
`StreamWidth_g`); together the configurations simulate every memory width and every stream width. Every test runs in
every configuration; lengths are limited to 2**`LengthWidth_g` - 1.

Clock 100 MHz. Simulators: GHDL; QuestaSim with and without code coverage in the batch of phase a.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_aligned` (TC-MM-01) | Transfers at aligned addresses of 1 byte, one stream beat, one memory word, one burst and 3.5 bursts; stream bytes, `TKeep` and `TLast` compared byte for byte; one result per command with the length and the end of packet | MM-IF-02, MM-RD-01, MM-ST-01, MM-ST-02, MM-ST-03 |
| `test_unaligned` (TC-MM-02) | Every start offset within a memory word combined with lengths from 1 to three memory words; first byte in lane 0, last `TKeep`; the statistics of the memory model show reads only of the words that contain the buffer | MM-RD-01, MM-ST-01 |
| `test_bursts` (TC-MM-03) | Transfers that start shortly before a 4 KB boundary and span several boundaries; the memory model checks every burst against 4 KB and `BurstBeats_g` (no alert allowed) | MM-IF-01, MM-RD-02 |
| `test_backpressure` (TC-MM-04) | 20 transfers of random address and length with 50 % random backpressure of the stream peer and 50 % stall and a latency of 30 cycles in the memory model; data identical | MM-ST-01, MM-ST-02 |
| `test_throughput` (TC-MM-05) | A transfer of 64 bursts with a ready stream peer and memory: with at least 8 stream beats per burst, the number of clock cycles from the first to the last stream beat exceeds the number of beats by at most 2; in the other configurations the number is logged and listed in the verification report | MM-RD-05 |
| `test_bus_not_held` (TC-MM-06) | The stream peer stops after 10 beats of a long transfer; until no further read burst comes for 1000 clock cycles and for 2000 clock cycles after that, the R channel never has `RValid` without `RReady`; the number of read bursts stays bounded by the data buffer and the internal FIFOs of the read master; the transfer completes when the peer resumes | MM-RD-03 |
| `test_queue` (TC-MM-07) | Three commands back to back: three packets in order and three results in order, the second one rejected (buffer beyond the top) between two good ones | MM-IF-03, MM-ST-03, MM-RD-04 |
| `test_result_timing` (TC-MM-08) | The stream peer takes the last beat 40 clock cycles late: the result appears only after the handshake of the last beat | MM-ST-03 |
| `test_read_errors` (TC-MM-09) | SLVERR on a middle beat, DECERR on the last beat, SLVERR followed by DECERR within one transfer: the transfer is sent completely with `TLast`, the result carries an error code; a transfer after a failed one has no error | MM-ER-01, MM-ER-02 |
| `test_beyond_top` (TC-MM-10) | A buffer ending at the top of the address space is read; a buffer one byte longer causes no burst (statistics), no beat and the result decode error with 0 bytes; a command of length 0 causes no burst, no beat and the result internal error with 0 bytes | MM-RD-04, MM-RD-06 |
| `test_halt` (TC-MM-11) | `Run` falls during a transfer: the transfer is sent completely, its result returned, a further command is not accepted, `Stopped` rises after the result | MM-IF-03, MM-HA-01 |
| `test_drain` (TC-MM-12) | `Drain` rises during a transfer with a stalled stream peer: no further beat, all read bursts complete (statistics), no result, `Stopped` rises; with `Drain` before any command: no command accepted | MM-HA-02 |
| `test_ecc` (TC-MM-13) | For each of the three buffers: an error is injected into the data, the entry or the response of a transfer that waits at the output of the buffer while the transfer before it completes at a stalled stream peer; a single error gives correct data and results and one pulse on the bit of the buffer in `Ecc_Sec`, a double error one pulse in `Ecc_Ded` | MM-FT-01 |
| `test_long_transfer` (TC-MM-14) | A transfer of at least 64 KB and 16384 stream beats (at most the longest length), with backpressure of the stream peer and of the memory | MM-RD-01, MM-ST-01 |

### 3.1 Test cases waiting for Open Logic

The test case below takes effect with the release of Open Logic that reports the response code of a failed read
command (specification section 3.7).

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_error_codes` (TC-MM-15) | SLVERR only, DECERR only, SLVERR before DECERR and DECERR before SLVERR within one transfer: the result carries the slave error, the decode error, the slave error and the decode error | MM-ER-03 |

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
| MM-RD-06 | TC-MM-10 |
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
| Buffer beyond the top of the address space, command of length 0 | TC-MM-10 |
| Commands while halted or draining | TC-MM-11, TC-MM-12 |
| ECC single and double errors | TC-MM-13 |
