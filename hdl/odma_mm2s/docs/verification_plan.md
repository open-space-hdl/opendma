# odma_mm2s: Verification Plan

## 1. Overview

The channel is verified through its ports: transfer commands and the channel control from the bench, results
collected by a monitor of the harness, the memory port on the AXI memory model of `tb/` (with its protocol checks,
error ranges, backpressure and statistics) and the stream port on a stream checker of the harness. The bench fills
the memory with the fill pattern of the memory model, which depends on every address bit (`odmaMemByte`), and queues
the packets it expects (one or more buffers of address and length each; for a keyhole buffer the backing range of
the FIFO window of the memory model, PKG-12); the checker compares every byte with the memory contents at its address,
checks `TKeep` and `TLast` and raises an alert on a difference or a beat without an expected packet. A read from a
wrong address, also one shifted by a whole burst, by 256 bytes or by 4 KB, therefore delivers other bytes. The
checker drives `TReady`: always high, high in a given percentage of the clock cycles, held low, or low for a number
of clock cycles before a given beat. Expected stream data is computed by the bench from the
memory contents, never by the RTL. The AXI4-Stream VVC of UVVM is not used: its BFM takes at most 32 `TStrb` bits
(256 data bits), and the checker has no packet size limit.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `odma_mm2s_tb` | `odma_mm2s_th` | `odma_mm2s`; AXI memory model instance 0 on `M_Axi_*` with the maximum burst set to `BurstBeats_g`; the stream checker on `M_Mm2s_*`; monitors of the result port (with the clock cycle of every result), of the AR channel (bursts, attributes, burst type, the addresses of FIXED bursts), of the R channel (cycles with `RValid` and not `RReady`, bursts completed) and of the ECC events |

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
| `j_w64_s8`, `j_w256_s16`, `j_w32_s32`, `j_w128_s64`, `j_w256_s128`, `j_w512_s256`, `j_w512_s512`, `j_w1024_s1024` | as the configuration without `j_`, `Join_g` true | The stream join with every stream width (1 to 128 byte lanes) |

Every configuration has a data buffer of four bursts (`BufferBeats_g` = 4 x `BurstBeats_g` x `MemWidth_g` /
`StreamWidth_g`); together the configurations simulate every memory width and every stream width, and every stream
width with the join. The tests of phase a run in every configuration (with `Join_g` they show that the join passes
packets of one command unchanged); the tests of Scatter/Gather Mode (TC-MM-16 to TC-MM-18 and TC-MM-20) run in
the `j_` configurations; lengths are limited to 2**`LengthWidth_g` - 1.

Clock 100 MHz. Simulators: GHDL; QuestaSim with and without code coverage in the batches of phases a and b.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_aligned` (TC-MM-01) | Transfers at aligned addresses of 1 byte, one stream beat, one memory word, one burst and 3.5 bursts; stream bytes, `TKeep` and `TLast` compared byte for byte; one result per command with the length and the end of packet | MM-IF-02, MM-RD-01, MM-ST-01, MM-ST-02, MM-ST-03 |
| `test_unaligned` (TC-MM-02) | Every start offset within a memory word combined with lengths from 1 to three memory words; first byte in lane 0, last `TKeep`; the statistics of the memory model show reads only of the words that contain the buffer | MM-RD-01, MM-ST-01 |
| `test_bursts` (TC-MM-03) | Transfers that start shortly before a 4 KB boundary and span several boundaries; the memory model checks every burst against 4 KB and `BurstBeats_g` (no alert allowed) | MM-IF-01, MM-RD-02 |
| `test_backpressure` (TC-MM-04) | 20 transfers of random address and length with 50 % random backpressure of the stream peer and 50 % stall and a latency of 30 cycles in the memory model; data identical | MM-ST-01, MM-ST-02 |
| `test_throughput` (TC-MM-05) | A transfer of 64 bursts with a ready stream peer and memory: with at least 8 stream beats per burst, the number of clock cycles from the first to the last stream beat exceeds the number of beats by at most 2; in the other configurations the number is logged and listed in the verification report. The same transfer with a read latency of 20, 50 and 100 clock cycles in the memory model: the numbers are logged and listed in the verification report | MM-RD-05 |
| `test_bus_not_held` (TC-MM-06) | The stream peer stops after 10 beats of a long transfer; until no further read burst comes for 1000 clock cycles and for 2000 clock cycles after that, the R channel never has `RValid` without `RReady`; the number of read bursts stays bounded by the data buffer and the internal FIFOs of the read master; the transfer completes when the peer resumes | MM-RD-03 |
| `test_queue` (TC-MM-07) | Three commands back to back: three packets in order and three results in order, the second one rejected (buffer beyond the top) between two good ones | MM-IF-03, MM-ST-03, MM-RD-04 |
| `test_result_timing` (TC-MM-08) | The stream peer takes the last beat 40 clock cycles late: the result appears only after the handshake of the last beat | MM-ST-03 |
| `test_read_errors` (TC-MM-09) | SLVERR on a middle beat, DECERR on the last beat, SLVERR followed by DECERR within one transfer: the transfer is sent completely with `TLast`, the result carries an error code; a transfer after a failed one has no error | MM-ER-01, MM-ER-02 |
| `test_beyond_top` (TC-MM-10) | A buffer ending at the top of the address space is read; a buffer one byte longer causes no burst (statistics), no beat and the result decode error with 0 bytes; a command of length 0 causes no burst, no beat and the result internal error with 0 bytes. `Drain` while the entries of both commands, which have no read, wait with their result held at the head of the transfer buffer and a transfer behind them waits for its read data, and while they reach the head behind a transfer whose packet was sent and whose result is held: no read burst for them, no result of any drained entry, no beat of the drained transfer, `Stopped` rises; after `Rst` the next transfer is correct | MM-RD-04, MM-RD-06, MM-HA-02 |
| `test_halt` (TC-MM-11) | `Run` falls during a transfer: the transfer is sent completely, its result returned, a further command is not accepted, `Stopped` rises after the result | MM-IF-03, MM-HA-01 |
| `test_drain` (TC-MM-12) | `Drain` rises during a transfer with a stalled stream peer: no further beat, all read bursts complete (statistics), no result, `Stopped` rises; with `Drain` before any command: no command accepted; then `Rst` during a packet (the memory model is reset with the DUT, as the reset of the core resets its interconnect): no further beat, no result, the next transfer correct | MM-HA-02, MM-HA-03 |
| `test_ecc` (TC-MM-13) | For each of the three buffers: an error is injected into the data, the entry or the response of a transfer that waits at the output of the buffer while the transfer before it completes at a stalled stream peer; a single error gives correct data and results and one pulse on the bit of the buffer in `Ecc_Sec`, a double error one pulse in `Ecc_Ded`; a single error on a data bit (data mode) gives correct data and results and one pulse in `Ecc_Sec` | MM-FT-01 |
| `test_long_transfer` (TC-MM-14) | A transfer of at least 64 KB and 16384 stream beats (at most the longest length), with backpressure of the stream peer and of the memory | MM-RD-01, MM-ST-01 |
| `test_error_codes` (TC-MM-15) | SLVERR only, DECERR only, EXOKAY only, SLVERR before DECERR and DECERR before SLVERR within one transfer: the result carries the slave error, the decode error, the slave error (interpretation I14), the slave error and the decode error | MM-ER-03 |
| `test_join` (TC-MM-16) | 40 packets of 1 to 5 commands each, every buffer at a random address (every offset within a memory word) and of a random length (among them 1 byte, one stream beat, lengths that end on every lane), the start of packet on the first and the end of packet on the last command; 50 % random backpressure of the stream peer, 30 % stall and a latency of 20 cycles in the memory model: every packet is the concatenation of its buffers, every beat full except the last of the packet, `TLast` only there; one result per command with its length and end of packet | MM-SG-01, MM-IF-03 |
| `test_join_results` (TC-MM-17) | A packet of two commands, the first of at most one stream beat: the stream peer holds `TReady` low after the first beat; the result of the first command comes while the peer holds it (its bytes are in the join), the result of the second only after the peer has taken the beat with `TLast` | MM-SG-02, MM-ST-03 |
| `test_join_halt` (TC-MM-18) | Packets of three commands; `Run` falls after the first command was accepted, with lengths that leave 1, B - 1 and B bytes (B the bytes of a stream beat) in the join: no further command accepted, the packet ends with `TLast` on its last byte, `Stopped` rises only after the stream peer (40 clock cycles late) has taken that beat; then `Run` rises and the next packet is complete. A read error on the first command of a packet, followed by the fall of `Run`: the packet ends the same way. `Drain` with a packet open: no further beat, `Stopped` rises, and after the core reset the next packet is complete. `Drain` while the closing beat of a packet left open by a halt waits for the stream peer, and `Run` and `Drain` falling and rising in the same clock cycle while a packet is open between two of its commands: no closing beat, `Stopped` rises, the next packet after the core reset complete | MM-SG-04, MM-HA-01, MM-HA-02 |
| `test_keyhole` (TC-MM-19) | Keyhole commands of 1 byte, one memory word, 16 and 17 memory words and 3.5 bursts at aligned and unaligned addresses, also next to a 4 KB boundary: every AR burst FIXED with at most 16 beats at the address with the bits below the memory width cleared; the address is the FIFO window of the memory model, which returns a different word per beat (the consecutive words of its backing range, PKG-12), so the stream carries those words in order, packed from lane 0, the last beat with the remaining bytes, and an incrementing read would give other bytes; an incrementing command after a keyhole command and the reverse are both correct; a keyhole command at the top of the address space is read | MM-SG-03, MM-IF-01 |
| `test_join_halt_sweep` (TC-MM-20) | A packet of two commands, the second with and without the end of packet: the first has passed the stream (its result returned, the join holds its last byte), the second is accepted and `Run` falls 0 to 8 clock cycles after its handshake, before and after its entry reaches the stream. Both commands complete, the packet ends with `TLast` on the last byte of the second (its end of packet or the closing beat after the halt), one result each, no further result or packet, `Stopped` rises; the next packet after `Run` rises is complete | MM-HA-01, MM-SG-04 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| MM-IF-01 | TC-MM-03, TC-MM-19 |
| MM-IF-02 | TC-MM-01 |
| MM-IF-03 | TC-MM-07, TC-MM-11, TC-MM-16 |
| MM-RD-01 | TC-MM-01, TC-MM-02, TC-MM-14 |
| MM-RD-02 | TC-MM-03 |
| MM-RD-03 | TC-MM-06 |
| MM-RD-04 | TC-MM-07, TC-MM-10 |
| MM-RD-05 | TC-MM-05 |
| MM-RD-06 | TC-MM-10 |
| MM-ST-01 | TC-MM-01, TC-MM-02, TC-MM-04, TC-MM-14 |
| MM-ST-02 | TC-MM-01, TC-MM-04 |
| MM-ST-03 | TC-MM-01, TC-MM-07, TC-MM-08, TC-MM-17 |
| MM-ER-01, MM-ER-02 | TC-MM-09 |
| MM-ER-03 | TC-MM-15 |
| MM-HA-01 | TC-MM-11, TC-MM-18, TC-MM-20 |
| MM-HA-02 | TC-MM-10, TC-MM-12, TC-MM-18 |
| MM-HA-03 | TC-MM-12 |
| MM-FT-01 | TC-MM-13 |
| MM-SG-01 | TC-MM-16 |
| MM-SG-02 | TC-MM-17 |
| MM-SG-03 | TC-MM-19 |
| MM-SG-04 | TC-MM-18, TC-MM-20 |

The recovery of the state machines from an illegal state (`when others`, architecture D15) cannot be reached through
the ports; it is reviewed in the code and listed in the coverage report.

## 5. Negative tests

| Check or error path | Test |
| --- | --- |
| Read error responses SLVERR and DECERR | TC-MM-09 |
| The error code of each response type, EXOKAY, the first error of a transfer deciding | TC-MM-15 |
| A packet left open by a halt, an error or a drain | TC-MM-18 |
| A halt between the acceptance of a command of an open packet and its entry at the stream | TC-MM-20 |
| Buffer beyond the top of the address space, command of length 0 | TC-MM-10 |
| `Drain` while entries without a read wait at the head of the transfer buffer or reach it | TC-MM-10 |
| Commands while halted or draining | TC-MM-11, TC-MM-12 |
| `Rst` during a packet | TC-MM-12 |
| ECC single and double errors | TC-MM-13 |
