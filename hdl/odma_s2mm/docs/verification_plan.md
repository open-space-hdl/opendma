# odma_s2mm: Verification Plan

## 1. Overview

The channel is verified through its ports: transfer commands and the channel control from the bench, results
collected by a monitor of the harness, the stream port driven by a stream generator of the harness and the memory
port on the AXI memory model of `tb/`. The generator sends the packets the bench queues: byte n of a packet from the
source address a is `odmaMemByte(a + n, seed A)`, a byte that depends on every address bit; it can leave `TValid`
low in a given percentage of the clock cycles, hold the stream and send the `TKeep` cases of S2-ST-02. Before each
transfer the bench fills the buffer and 256 bytes on each side of it with `odmaMemByte(address, seed B)` and sets the
write window of the memory model to the buffer, so that every byte written outside the buffer raises an alert.
After the result the bench compares every byte of the buffer and of the bytes around it through the backdoor: the
written bytes carry the packet, all other bytes keep their pre-fill. A write to a wrong address, also one shifted by
a whole burst, by 256 bytes or by 4 KB, therefore fails. Expected memory contents are computed by the bench, never
by the RTL. The AXI4-Stream VVC of UVVM is not used: its BFM takes at most 32 `TStrb` bits (256 data bits).

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `odma_s2mm_tb` | `odma_s2mm_th` | `odma_s2mm`; AXI memory model instance 0 on `M_Axi_*` with the maximum burst set to `BurstBeats_g`; the stream generator on `S_S2mm_*`; monitors of the result port, of the AW channel (bursts, attributes), of the W channel (gaps between the data beats of a burst), of the B channel and of the ECC events |

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
| `s_w64_s8`, `s_w256_s16`, `s_w32_s32`, `s_w128_s64`, `s_w256_s128`, `s_w512_s256`, `s_w512_s512`, `s_w1024_s8` | as the configuration without `s_`, `Split_g` true | The stream split with every stream width (1 to 64 byte lanes) and the shortest length width (several discard segments per packet) |

Every configuration has a data buffer of four bursts (`BufferBeats_g` = 4 x `BurstBeats_g` x `MemWidth_g` /
`StreamWidth_g`); together the configurations simulate every memory width and every stream width, and every stream
width up to 512 bits with the split. The tests of phase a run in every configuration, except two that need a packet
in the data buffer before its command or a packet longer than its buffer: TC-S2-07 and TC-S2-08 run only without
`Split_g`. With `Split_g` neither can occur: the split takes no stream beat while no segment is active, and
a segment exists only for an accepted command, so no data enters the data buffer before its command; and a segment
is never longer than the buffer of its command, so a packet longer than the buffer continues in the next buffer
(S2-SG-01) instead of overflowing. The tests of Scatter/Gather Mode (TC-S2-17 to TC-S2-19)
run in the `s_` configurations; lengths are limited to 2**`LengthWidth_g` - 1.

Clock 100 MHz. Simulators: GHDL; QuestaSim with and without code coverage in the batches of phases a and b.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_aligned` (TC-S2-01) | Packets of 1 byte, one beat, one chunk, one chunk plus one byte and 3.5 chunks into aligned buffers of the packet length and of a larger length; memory compared byte for byte, the bytes around the buffer unchanged; one result per command with the bytes and the end of packet | S2-IF-02, S2-ST-03, S2-WR-01, S2-WR-02, S2-RS-01 |
| `test_unaligned` (TC-S2-02) | Every start offset within a memory word combined with packet lengths from 1 to three memory words; write window = the buffer | S2-WR-01, S2-WR-02 |
| `test_keep` (TC-S2-03) | Last beats with every number of valid bytes, a last beat without valid bytes after a full chunk and after a partial chunk, `TKeep` of non-last beats with deasserted bits (ignored), a last beat with a gap in `TKeep` (bytes up to the gap) | S2-ST-02 |
| `test_bursts` (TC-S2-04) | Buffers that start shortly before a 4 KB boundary and span several boundaries; the memory model checks every burst against 4 KB and `BurstBeats_g` (no alert allowed); `AwSize`, `AwBurst`, `AwLock`, `AwCache` and `AwProt`; every burst has all its data in the master: no clock cycle with `WValid` low and `WReady` high between two data beats of a burst | S2-IF-01, S2-WR-03 |
| `test_backpressure` (TC-S2-05) | 20 packets of random length with random gaps of the stream and 50 % stall and a latency of 30 cycles in the memory model; data identical | S2-WR-01, S2-ST-03 |
| `test_throughput` (TC-S2-06) | A packet of 64 chunks (at most the longest length) with a ready memory and a stream without gaps: with chunks of at least 64 beats the channel takes at least 0.9 beats per clock cycle from the first to the last accepted stream beat; in the other configurations the number is logged and listed in the verification report | S2-WR-05 |
| `test_early_data` (TC-S2-07) | A packet arrives before the command: it waits in the data buffer and is written after the command; with the channel halted the input is not ready | S2-ST-01, S2-IF-03 |
| `test_overflow` (TC-S2-08) | A packet longer than the buffer by one byte and by several chunks: the bytes that fit are written, nothing beyond the buffer (window), the rest discarded up to `TLast`, the next packet is written correctly by the next command; the result carries the internal error before the `TLast` of a long rest arrives | S2-RS-02, S2-RS-04, S2-WR-02 |
| `test_write_errors` (TC-S2-09) | SLVERR on the first burst and DECERR on the burst of the fourth chunk of a packet of eight chunks: the result carries an error code and no end of packet, the last chunk of the packet keeps its pre-fill (no write after the error), the rest of the packet is discarded, the next packet is written correctly | S2-RS-03, S2-RS-04 |
| `test_beyond_top` (TC-S2-10) | A buffer ending at the top of the address space is written; a buffer one byte longer and a buffer length of 0 cause no write burst, take no stream data and give the decode error and the internal error with 0 bytes and without the start of a packet; the waiting packet (in the data buffer, with `Split_g` at the stream port) is written by the next transfer, with the start of the packet | S2-WR-04, S2-WR-06 |
| `test_halt` (TC-S2-11) | `Run` falls before the packet: result with 0 bytes; inside the packet: the complete chunks written, the rest discarded up to `TLast`, result without the end of packet, `Stopped` before the `TLast` of the rest; a halt in the clock cycle after the last beat of the packet, while its descriptor is stored but not yet at the output of the chunk buffer (with the split: while the end of the packet is still in the split): normal result; data of a later packet received before the halt is discarded and the next packet after the restart is written completely (with the split the later packets wait at the stream port through the halt, and each one fills the buffer of its command after the restart); with the split the halt comes two beats later, the beats that the split holds | S2-HA-01, S2-HA-03, S2-ST-01 |
| `test_drain` (TC-S2-12) | `Drain` rises while chunks are being written and the stream sends: the input stops, the writes given to the master complete (all bursts answered, no burst without data), no result, `Stopped` rises | S2-HA-02 |
| `test_ecc` (TC-S2-13) | Single and double errors injected into each of the three buffers; the packet waits 200 clock cycles before its command, without the split in the buffers with its first words at their outputs, with the split at the stream port, and the pending injection applies to the first word written: correct data and one `Ecc_Sec` pulse of the buffer for a single error, one `Ecc_Ded` pulse for a double error; correct data and one `Ecc_Sec` pulse for a single error on a data bit (data mode) | S2-FT-01 |
| `test_longest_back_to_back` (TC-S2-16) | Three transfers of the longest length (at most 16383 bytes) back to back into aligned buffers: each completes within 2 ms and is written completely; with 1024 bits and a length width of 12 the last write command of each transfer has the largest word count of the write master (gap G14) | S2-WR-01 |
| `test_long_packet` (TC-S2-14) | A packet of at least 64 KB and 16384 stream beats (at most the longest length) with gaps of the stream and backpressure of the memory | S2-WR-01, S2-ST-03 |
| `test_error_codes` (TC-S2-15) | SLVERR only, DECERR only, EXOKAY only, SLVERR before DECERR and DECERR before SLVERR within one packet, in two bursts on both sides of a 4 KB boundary (also where the buffer would fit into one burst): the result carries the slave error, the decode error, the slave error (interpretation I14), the slave error and the decode error | S2-RS-05 |
| `test_split` (TC-S2-17) | 40 packets of random lengths written over 1 to 5 buffers each, every buffer at a random address (every offset within a memory word) and of a random length, among them a packet that ends exactly at the end of a buffer, a packet whose last beat without valid bytes follows a buffer end, a packet without bytes and buffers of one byte; random gaps of the stream, 30 % stall and a latency of 20 cycles in the memory model: memory compared byte for byte with 16 unwritten bytes around every buffer; per buffer one result with its bytes, the start of packet on the first buffer of a packet (also of the packet without bytes, interpretation SGI-13) and the end of packet on its last | S2-SG-01, S2-SG-02, S2-ST-03, S2-RS-01 |
| `test_split_wait` (TC-S2-18) | A packet arrives without a command: `S_S2mm_Ready` stays '0' for 500 clock cycles, then the command takes it. A packet longer than the buffer of its command and no next command for 500 clock cycles: after the first buffer no stream beat is taken; the next command takes the rest | S2-SG-03, S2-ST-01 |
| `test_split_halt` (TC-S2-19) | `Run` falls one and a half chunks into the second buffer of a packet of three buffers, the next packet sent directly after it: the complete chunks are written, the result carries no end of packet, the rest of the packet, longer than 2**`LengthWidth_g` - 1 bytes where the length width allows, is discarded up to its `TLast`, the next packet waits at the input while halted and arrives complete after the restart with the start of packet. SLVERR on the first chunk of a buffer of four chunks of a packet of three buffers, the stream without gaps, the next packet directly after it: result with the error, the rest of the packet discarded through the discard segments of S2-1 (`FlushReq`), the next packet complete in the buffer of the next command. The same with a short rest and a write response latency of 200 cycles. A command accepted, `Run` falling in the next clock cycle, no packet: result with 0 bytes; after `Run` rises, a new packet longer than its buffer arrives complete and alone in the buffers of its two commands. `Run` falling while the split holds the first beat of a packet: the packet is discarded, the next one arrives complete. `Run` falling in the clock cycle after the `TLast` of a packet that ends one byte beyond its buffer: the buffer holds complete chunks or is full, without the end of packet, the last byte is discarded, and the next packet arrives complete and alone. `Drain` inside a multi-buffer packet: no further write, no result, `Stopped` rises | S2-SG-01, S2-SG-02, S2-HA-01, S2-HA-02, S2-RS-03 |
| `test_keyhole` (TC-S2-20) | Keyhole commands of packets of 1 byte, one memory word, 16 and 17 memory words and 3.5 bursts, at aligned and unaligned addresses, also next to a 4 KB boundary and at the top of the address space: every AW burst FIXED with at most 16 beats at the address with the bits below the memory width cleared; the address is the FIFO window of the memory model (PKG-12), so every beat lands in the next word of its backing range: the backing range holds the packet packed from lane 0, the strobes of the last beat only for the remaining bytes, and nothing else is written (write window); an incrementing transfer after a keyhole transfer and the reverse are both correct; in the `s_` configurations also a keyhole packet over two buffers | S2-SG-04, S2-IF-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| S2-IF-01 | TC-S2-04, TC-S2-20 |
| S2-IF-02 | TC-S2-01 |
| S2-IF-03 | TC-S2-07 |
| S2-ST-01 | TC-S2-07, TC-S2-11, TC-S2-18 |
| S2-ST-02 | TC-S2-03 |
| S2-ST-03 | TC-S2-01, TC-S2-05, TC-S2-14, TC-S2-17 |
| S2-WR-01 | TC-S2-01, TC-S2-02, TC-S2-05, TC-S2-14, TC-S2-16 |
| S2-WR-02 | TC-S2-01, TC-S2-02, TC-S2-08 |
| S2-WR-03 | TC-S2-04 |
| S2-WR-04 | TC-S2-10 |
| S2-WR-05 | TC-S2-06 |
| S2-WR-06 | TC-S2-10 |
| S2-RS-01 | TC-S2-01, TC-S2-17 |
| S2-RS-02 | TC-S2-08 |
| S2-RS-03 | TC-S2-09, TC-S2-19 |
| S2-RS-05 | TC-S2-15 |
| S2-RS-04 | TC-S2-08, TC-S2-09 |
| S2-HA-01, S2-HA-03 | TC-S2-11, TC-S2-19 |
| S2-HA-02 | TC-S2-12, TC-S2-19 |
| S2-FT-01 | TC-S2-13 |
| S2-SG-01, S2-SG-02 | TC-S2-17, TC-S2-19 |
| S2-SG-03 | TC-S2-18 |
| S2-SG-04 | TC-S2-20 |

## 5. Negative tests

| Check or error path | Test |
| --- | --- |
| Packet longer than the buffer | TC-S2-08 |
| Write error responses SLVERR and DECERR | TC-S2-09 |
| The error code of each response type, EXOKAY, the first error of a packet deciding | TC-S2-15 |
| Halt, write error and drain inside a packet of several buffers | TC-S2-19 |
| Buffer beyond the top of the address space, buffer length of 0 | TC-S2-10 |
| Halt and drain in the middle of a packet | TC-S2-11, TC-S2-12 |
| ECC single and double errors of every buffer | TC-S2-13 |
| Writes outside the buffer (write window of the memory model, in every test) | TC-S2-01, TC-S2-02, TC-S2-08, TC-S2-17, TC-S2-20 |

The recovery of the state machines from an illegal state (`when others`) cannot be reached through the ports; it is
reviewed in the code and listed in the coverage report.
