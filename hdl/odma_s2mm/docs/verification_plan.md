# odma_s2mm: Verification Plan

## 1. Overview

The channel is verified through its ports: transfer commands and the channel control from the bench, results
collected by a monitor of the harness, the stream port driven by the AXI4-Stream master VVC (packets up to 16 KB)
and by a stream generator of the harness for longer packets (count pattern), the memory port on the AXI memory model
of `tb/` with its write window set to the buffer of each transfer, so that every byte written outside the buffer
raises an alert. Expected memory contents are computed by the bench from the sent packets, never by the RTL, and
compared byte for byte through the backdoor; the bytes around each buffer are checked to be unchanged.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `odma_s2mm_tb` | `odma_s2mm_th` | `odma_s2mm`; AXI memory model instance 0 on `M_Axi_*` with the maximum burst set to `BurstBeats_g`; AXI4-Stream master VVC and the long-packet generator on `S_S2mm_*`; a monitor of the result port |

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
| `test_aligned` (TC-S2-01) | Packets of 1 byte, one beat, one chunk, one chunk plus one byte and 3.5 chunks into aligned buffers of the packet length and of a larger length; memory compared byte for byte, the bytes around the buffer unchanged; one result per command with the bytes and the end of packet | S2-IF-02, S2-ST-03, S2-WR-01, S2-WR-02, S2-RS-01 |
| `test_unaligned` (TC-S2-02) | Every start offset within a memory word combined with packet lengths from 1 to three memory words; write window = the buffer | S2-WR-01, S2-WR-02 |
| `test_keep` (TC-S2-03) | Last beats with every number of valid bytes, a last beat without valid bytes after a full chunk and after a partial chunk, `TKeep` of non-last beats with deasserted bits (ignored), a last beat with a gap in `TKeep` (bytes up to the gap) | S2-ST-02 |
| `test_bursts` (TC-S2-04) | Buffers that start shortly before a 4 KB boundary and span several boundaries; the memory model checks every burst against 4 KB and `BurstBeats_g` (no alert allowed); every burst has all its data when its address is accepted (no `WValid` low inside a burst while the memory is ready) | S2-IF-01, S2-WR-03 |
| `test_backpressure` (TC-S2-05) | 20 packets of random length with random gaps of the stream and 50 % stall and a latency of 30 cycles in the memory model; data identical | S2-WR-01, S2-ST-03 |
| `test_throughput` (TC-S2-06) | A packet of 256 chunks of at least 8 beats with a ready memory: the number of clock cycles from the first to the last accepted stream beat exceeds the number of beats by at most 2 | S2-WR-05 |
| `test_early_data` (TC-S2-07) | A packet arrives before the command: it waits in the data buffer and is written after the command; with the channel halted the input is not ready | S2-ST-01, S2-IF-03 |
| `test_overflow` (TC-S2-08) | A packet longer than the buffer by one byte and by several chunks: the bytes that fit are written, nothing beyond the buffer (window), the rest discarded up to `TLast`, the next packet is written correctly by the next command; the result carries the internal error before the `TLast` of a long rest arrives | S2-RS-02, S2-RS-04, S2-WR-02 |
| `test_write_errors` (TC-S2-09) | SLVERR on the first and DECERR on a later burst of a packet: the result carries the code of the first error, no write after it, the rest of the packet discarded, the next packet unaffected | S2-RS-03, S2-RS-04 |
| `test_beyond_top` (TC-S2-10) | A buffer ending at the top of the address space is written; a buffer one byte longer causes no write burst, consumes no stream data and gives the decode error with 0 bytes | S2-WR-04 |
| `test_halt` (TC-S2-11) | `Run` falls before the packet: result with 0 bytes; inside the packet: the complete chunks written, the rest discarded up to `TLast`, result without the end of packet, `Stopped` before the `TLast` of the rest; after the packet ended: normal result; data of a later packet received before the halt is discarded and the next packet after the restart is written completely | S2-HA-01, S2-HA-03, S2-ST-01 |
| `test_drain` (TC-S2-12) | `Drain` rises while chunks are being written and the stream sends: the input stops, the writes given to the master complete (all bursts answered, no burst without data), no result, `Stopped` rises | S2-HA-02 |
| `test_ecc` (TC-S2-13) | Single and double errors injected into each of the three buffers: correct data and one `Ecc_Sec` pulse of the buffer for a single error, one `Ecc_Ded` pulse for a double error | S2-FT-01 |
| `test_long_packet` (TC-S2-14) | A packet of 1 MB from the long-packet generator with backpressure | S2-WR-01, S2-ST-03 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| S2-IF-01 | TC-S2-04 |
| S2-IF-02 | TC-S2-01 |
| S2-IF-03 | TC-S2-07 |
| S2-ST-01 | TC-S2-07, TC-S2-11 |
| S2-ST-02 | TC-S2-03 |
| S2-ST-03 | TC-S2-01, TC-S2-05, TC-S2-14 |
| S2-WR-01 | TC-S2-01, TC-S2-02, TC-S2-05, TC-S2-14 |
| S2-WR-02 | TC-S2-01, TC-S2-02, TC-S2-08 |
| S2-WR-03 | TC-S2-04 |
| S2-WR-04 | TC-S2-10 |
| S2-WR-05 | TC-S2-06 |
| S2-RS-01 | TC-S2-01 |
| S2-RS-02 | TC-S2-08 |
| S2-RS-03 | TC-S2-09 |
| S2-RS-04 | TC-S2-08, TC-S2-09 |
| S2-HA-01, S2-HA-03 | TC-S2-11 |
| S2-HA-02 | TC-S2-12 |
| S2-FT-01 | TC-S2-13 |

## 5. Negative tests

| Check or error path | Test |
| --- | --- |
| Packet longer than the buffer | TC-S2-08 |
| Write error responses SLVERR and DECERR | TC-S2-09 |
| Buffer beyond the top of the address space | TC-S2-10 |
| Halt and drain in the middle of a packet | TC-S2-11, TC-S2-12 |
| ECC single and double errors of every buffer | TC-S2-13 |
| Writes outside the buffer (write window of the memory model, in every test) | TC-S2-01, TC-S2-02, TC-S2-08 |

The recovery of the state machines from an illegal state (`when others`) cannot be reached through the ports; it is
reviewed in the code and listed in the coverage report.
