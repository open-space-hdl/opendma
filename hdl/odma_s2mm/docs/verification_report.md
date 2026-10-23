# odma_s2mm: Verification Report

## 1. Test results

Run on 2026-10-20 in the GHDL CI of the repository, GitHub Actions run 39467613918 on commit fee4598 (its
`results.xml`), with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.03.20:
`python run.py -p 4 --xunit-xml results.xml`, the tests of `odma_s2mm_tb`.

QuestaSim (Questa Pro Microchip Edition 2024.3, time resolution 1 fs) ran the tests of release 0.2.0 on commit ad726b1
with Open Logic 4.7.0-ft.10 (sources and testbenches as in fee4598), with code coverage and in the optimised run without
it, and all of them passed; the code coverage of the core is in `docs/coverage.md`.

The test end changed after this run (`odmaTestEnd`, see the verification report of `odma_pkg`); the tests of this bench
expect no alerts, so their results are unchanged.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `odma_s2mm_tb` | 429 (28 test cases: 19 in all 19 configurations, TC-S2-07 and TC-S2-08 in the ten without the split, TC-S2-17 to TC-S2-19 and TC-S2-24 in the nine `s_` configurations, TC-S2-28 in seven, TC-S2-21 in four, TC-S2-25 in one) | 429 |

## 2. Summary

All test cases pass; every requirement of the specification is covered. VSG reports no errors and no warnings.
The sources analyse with `ghdl -a --std=08` without `-frelaxed` and without warnings, and synthesise with
`ghdl --synth` without warnings and without latches in the configurations
of section 4.

Every test checks at its end that no write burst had a clock cycle without write data (S2-WR-07).

Measured throughput of TC-S2-06 (64 chunks or the longest length, memory always ready, stream without gaps): the
clock cycles from the first to the last beat for a buffer at a burst boundary, one at the stream width above a burst
boundary and one 1 byte above (with 8-bit streams the two offsets are the same):

| Configuration | Beats per chunk | Memory width / stream width | Beats | Aligned | Stream width above | 1 byte above |
| --- | --- | --- | --- | --- | --- | --- |
| `w32_s32` | 16 | 1 | 1024 | 1040 | 1040 | 1043 |
| `w64_s8` | 128 | 8 | 8192 | 8192 | 8192 | 8192 |
| `w128_s32` | 1024 | 4 | 65536 | 65536 | 65536 | 65536 |
| `w128_s64` | 64 | 2 | 4096 | 4096 | 4096 | 4096 |
| `w256_s16` | 128 | 16 | 8192 | 8192 | 8303 | 8303 |
| `w256_s128` | 8 | 2 | 512 | 604 | 720 | 720 |
| `w512_s256` | 16 | 2 | 1024 | 1040 | 1040 | 1040 |
| `w512_s512` | 2 | 1 | 128 | 414 | 418 | 642 |
| `w1024_s8` | 256 | 128 | 255 | 255 | 255 | 255 |
| `w1024_s1024` | 32 | 1 | 32 | 32 | 32 | 32 (the packet fits into the data buffer) |
| `s_w32_s32` | 16 | 1 | 1024 | 1040 | 1040 | 1043 |
| `s_w64_s8` | 128 | 8 | 8192 | 8192 | 8192 | 8192 |
| `s_w128_s64` | 64 | 2 | 4096 | 4096 | 4096 | 4096 |
| `s_w256_s16` | 128 | 16 | 8192 | 8192 | 8192 | 8192 |
| `s_w256_s128` | 8 | 2 | 512 | 604 | 603 | 720 |
| `s_w512_s256` | 16 | 2 | 1024 | 1040 | 1039 | 1047 |
| `s_w512_s512` | 2 | 1 | 128 | 409 | 413 | 633 |
| `s_w1024_s8` | 256 | 128 | 255 | 255 | 255 | 255 |
| `s_w1024_s1024` | 32 | 1 | 32 | 32 | 32 | 32 (the packet fits into the data buffer) |

With `Split_g` a buffer at the stream width above a burst boundary takes the beats at the rate of the aligned buffer:
its first chunk ends at the burst boundary (S2-ST-04), and TC-S2-06 checks the rate within 2 % when the packet has at
least 16 chunks. Without the split every chunk of such a buffer is written as two bursts. A buffer at a multiple of
the memory word (the stream-width offset with equal widths) costs nothing in either mode.

The chunk plan and the write command mode were measured by variants of the sources of commit b6d359e (GHDL 6.0.0,
TC-S2-06 and the core test TC-CO-20; each variant changes the sources by a text substitution, the rest of the design
stays). Beats per clock cycle, buffers of the configurations with the split at the stream width above a burst
boundary, without and with the first chunk up to the burst boundary:

| Configuration | Burst beats B | Without | With |
| --- | --- | --- | --- |
| `s_w64_s8` | 16 | 0.987 | 1.000 |
| `s_w128_s64` | 32 | 0.905 | 0.953 |
| `s_w256_s16` | 8 | 0.987 | 1.000 |
| `s_w256_s128` | 4 | 0.419 | 0.515 |
| `s_w512_s256` | 8 | 0.604 | 0.698 |
| Core `sg_lw8` (64 / 8 bits, 2 beats), 4 KB buffers 1 byte above a multiple of 64 bytes | 2 | 240 clock cycles more per KB | 0 clock cycles more per KB |

Buffers 1 byte above a burst boundary (inside a stream word), without and with chunks one memory word shorter; the
last column is the rule of S2-ST-04:

| Configuration | Memory width / stream width | Burst beats B | Without | With | Short chunks |
| --- | --- | --- | --- | --- | --- |
| `s_w32_s32` | 1 | 16 | 0.866 | 0.854 | no |
| `s_w128_s64` | 2 | 32 | 0.905 | 0.936 | yes |
| `s_w256_s16` | 16 | 8 | 0.987 | 0.994 | yes |
| `s_w256_s128` | 2 | 4 | 0.419 | 0.408 | no |
| `s_w512_s256` | 2 | 8 | 0.604 | 0.632 | yes |
| `s_w512_s512` | 1 | 2 | 0.203 | 0.156 | no |
| Core `sg` (32 / 32 bits), 4 KB buffers 1 byte above a multiple of 64 bytes | 1 | 16 | 15 clock cycles more per KB | 20 clock cycles more per KB | no |
| Core `sg_aw64` (512 / 256 bits), the same buffers | 2 | 4 | 14 clock cycles more per KB | 18 clock cycles more per KB | no |

A short chunk is written as one burst instead of two but carries one memory word less, so a buffer needs more chunks.
With bursts of 2 or 4 beats that word is a large part of a burst, and with equal widths the low-latency writes make
the second burst of a chunk cheaper than the shorter chunks (architecture section 4.2).

Equal memory and stream widths, aligned buffers, with high-latency and with low-latency write commands of the write
master (S2-WR-03):

| Configuration | Burst beats B | High latency | Low latency |
| --- | --- | --- | --- |
| `w32_s32`, `s_w32_s32` | 16 | 0.757 | 0.910 |
| `w32_s32`, `s_w32_s32`, 1 byte above a burst boundary | 16 | 0.648 | 0.866 |
| `w512_s512` | 2 | 0.243 | 0.311 |
| `s_w512_s512` | 2 | 0.246 | 0.314 |
| Core `sg` (32 / 32 bits), 1 KB buffers | 16 | 0.70 (8192 beats in 11657 clock cycles) | 0.85 (in 9667 clock cycles) |

With a wider memory the channel keeps the high-latency mode, and the variant with high-latency writes for every
width gives the same values there.

Findings:

| Finding | Resolution |
| --- | --- |
| The write path of `olo_axi_master_full` of Open Logic 4.7.0-ft.6 counts the user data words of a write command at the width of the size field without its low bits; for the sizes in the last user data word below 2**`UserTransactionSizeBits_g` the count wraps to 0 and the master issues no further burst: with 1024-bit stream words and a length width of 12 a transfer of 4000 to 4095 bytes left the channel without its next result (reproduced with two transfers back to back, also with 512-bit words, independent of the address width) | Both masters run with `UserTransactionSizeBits_g` = `LengthWidth_g` + 1 (gap G14 of the architecture). TC-S2-16 transfers the longest length back to back and fails with a timeout of 2 ms, not a hang, when the master runs with `LengthWidth_g` size bits |
| The channel issues one write command per chunk, and the write master accepted the next command after the data of the previous one, about 7 clock cycles per command; with equal memory and stream widths and chunks of 16 beats the channel took about 0.76 beats per clock cycle | With equal widths the write master runs with low-latency write commands (S2-WR-03): S2-2 issues a command only for a chunk complete in the data buffer, so the burst follows at once and its data at one beat per clock cycle; 0.91 beats per clock cycle with chunks of 16 beats (tables above). S2-WR-05 requires at least 0.9 beats per clock cycle with chunks of at least 64 beats; the throughput is measured in every configuration. With a memory four or more times wider than the stream the write side is faster than the stream and the channel takes one beat per clock cycle |
| With `Split_g` every chunk of a buffer at a multiple of the stream width that is not a multiple of the memory word covered parts of two bursts and was written as two: 0.60 instead of 0.70 beats per clock cycle with 512 / 256 bits, 240 clock cycles more per KB in the core with 64 / 8 bits | The chunk plan ends the first chunk of such a buffer at the burst boundary above its address, and the later chunks are aligned (S2-ST-04). TC-S2-24 checks the bursts of ten offsets against a model of the plan and of the burst split of the master, TC-S2-06 the rate within 2 % of the aligned buffer |
| The first chunk plan ended the first chunk at the burst boundary for every address that is not a multiple of the burst size, also at multiples of the memory word, where a full chunk is one burst anyway: it only added a chunk per buffer, and in the core with 512 / 256 bits and 4-beat bursts the pause per buffer boundary rose from 1 to 8 clock cycles (TC-CO-20) | At a multiple of the memory word the chunks keep their full size (S2-ST-04); TC-S2-24 includes such offsets |
| Chunks one memory word shorter for buffers that start inside a stream word (one burst per chunk instead of two) gain with a wider memory and bursts of 8 beats or more, but lose with equal widths and with bursts of 2 or 4 beats (tables above) | S2-ST-04 applies them when `MemWidth_g` is above `StreamWidth_g` and the burst has at least 8 beats (`shortBeats` of `odma_s2mm_pkg`); TC-S2-25 checks the rule for the 264 configurations of the generic ranges |
| Low-latency write commands with a memory wider than the stream leave clock cycles without write data inside a burst: the master issues the burst before it has assembled its memory words, which then follow at the stream rate (a variant with low-latency writes for every width, section 5) | The high-latency mode stays with a wider memory (S2-WR-03, S2-WR-07); every test checks the W gaps at its end |
| A second beat counter in `olo_base_chunker` counted the same beats as the counter of the descriptor; in a delta cycle the two disagreed | The chunk end follows from the counter of the descriptor; `olo_base_chunker` is not instantiated (architecture section 2) |
| A result with a write error carried the end of packet when the packet ended in the failing chunk | A result with an error carries no end of packet (S2-RS-03) |
| A command of length 0 had no defined behaviour; in Scatter/Gather Mode a buffer length of 0 is an internal error | No write, no stream data taken, result with the internal error code (S2-WR-06, interpretation S4); TC-S2-10 |
| The AXI4-Stream BFM of UVVM takes at most 32 `TStrb` bits (256 data bits) | The stream generator of the harness drives every configuration (verification plan, section 1) |
| With the split, a halt inside a packet let the next packet pass without a command, and the segment of the next command was left over for a later packet: the split takes a new segment in the clock cycle in which its previous one ends, and S2-1 offered the discard segment for the whole discard, so the split took one more after the last beat of the discarded packet | The register `NeedSeg` offers a discard segment only when the split has none for the rest of the packet (architecture section 4.2); TC-S2-19 halts one and a half chunks into the second buffer and checks the next packet complete and alone |
| Four safeguards of the first implementation with the split were equivalent: a flag that limited the discard to one per flush, the drop of a segment that the split had not taken at the result, the clearing of `NeedSeg` at a halt and the gating of `StrmOpen` during the discard; a mutant that disabled each one passed every test | They are removed; the architecture states why each case cannot occur (sections 4.2 and 4.3) |
| A result without bytes and without the end of packet (buffer length 0, buffer beyond the top of the address space) carried the start of packet; found by the core scenario `sg_errors` (`RXSOF` in the status of a descriptor of length 0) | Such a result belongs to no packet and has `Res_Sof` '0' (S2-SG-02, interpretation SGI-14); TC-S2-10 checks it |
| TC-S2-10 expected the packet after the rejected commands in the data buffer; with `Split_g` it waits at the stream port, because the split takes no beat without a segment (S2-SG-03). The test had not run in the configurations with the split | TC-S2-10 checks that no beat is taken with `Split_g` and runs in every configuration |
| With the split, a packet that the stream port had accepted completely was lost or cut when `Run` fell while its end was still in the split (up to two beats): S2-1 took no beat while halted; a packet of one or two beats did not count as open, so the split was reset and no result had its bytes, and a longer one was discarded with a result of 0 bytes (S2-HA-01) | The register `EndPend` records the end of a packet in the split. A packet whose end is in the split and belongs to the active segment is complete: S2-1 takes its rest also while halted, and it counts as open (architecture section 4.2). TC-S2-11 halts in the clock cycle after the end of a packet in every configuration; TC-S2-19 halts after the end of a packet that ends one byte beyond its buffer, whose rest waits for the next buffer, and is cut |
| TC-S2-11 also failed with the split for reasons of the testbench: it set the halt inside a packet by beats counted at the stream port, but the split holds up to two of them, so with chunks of two beats (`s_w512_s512`) only two chunks were in the data buffer at the halt; and it expected the data of later packets in the data buffer before their commands | With the split the halt comes two beats later, and the later packets wait at the stream port through the halt and fill the buffers of their commands after the restart |
| TC-S2-15 placed the two errors of a transfer on its first and its last byte. With a 1024-bit memory and a length width of 8 or 12 the buffer fits into one burst, whose single response carries the worse code, so the case "the first error decides" was not tested there (`w1024_s8`, `s_w1024_s8`, `w1024_s1024`) | The buffers of these cases start one memory word before a 4 KB boundary, which no burst crosses, so the errors are in two bursts in every configuration |
| TC-S2-13 ran only without the split, so the injection into the three buffers was not tested with it | TC-S2-13 runs in every configuration: the injection applies to the next word written, also when the packet waits at the stream port for its command |
| After an overflow in the chunk that ends the packet, the channel flushed once more: the flush after an error (S2-RS-03) looked at the end of packet of the transfer, which the overflow did not record, so the next packet was dropped as the rest of the overflowing one (TC-S2-08 in every configuration without the split), and without a next packet the channel did not stop (TC-CO-04 in `aw40` and `aw64`, whose chunks hold the whole packet) | The overflow records the end of packet of the overflowing chunk; the result still carries none with the error. The flush follows only when the packet goes on |
| `Stopped` rose as soon as S2-2 was idle, before it had flushed the data received before a halt: with the split, a halt in the clock cycle after the `TLast` of a packet that needs a further buffer left the discard descriptor of its rest in the chunk buffer after the result of the full buffer, and a restart at `Stopped` gave that descriptor to the next transfer (a result of 0 bytes, TC-S2-19); the next buffer also kept the continuation of the cut packet instead of a start of packet | `Stopped` waits, after a halt, until the chunk buffer is empty and S2-1 writes no further descriptor (S2-HA-03, architecture section 6); a flush that ends a packet sets the start of packet for the next buffer |
| A transfer accepted while S2-1 discarded the rest of an earlier packet did not end at the next halt: its halt exit waited until no packet was open, and the packet stays open in the discard until the stream peer sends the `TLast` of the rest, so `Stopped` (and `DMASR.Halted`) did not come while the peer stalled | The halt exit waits only for the descriptors of S2-1 still to come (`DescPend`), which the discard does not write, and withdraws the segment of the transfer that the split has not taken, so that it cannot be taken when the discard ends; `PacketOpen` is removed. TC-S2-11 halts such a transfer and restarts with the rest arriving while no command is pending |
| A halt right after a full buffer was queued, with its write responses late, let the halted block flush the rest of its packet; a write error of that buffer arriving after the flush asked for a second flush, which waited for an end of packet that no longer came, so `Stopped` did not rise. The new step of TC-S2-23 reproduced it in the eight configurations with the split | `QCont` records whether the rest of the packet of the queued transfer is still to come and is cleared when a descriptor with its end is taken, by the next transfer or by a flush; the error asks for the flush only while it is set. TC-S2-23 halts right after the queuing and expects `Stopped` within 1000 clock cycles after the error result, and not before it |
| After an error of a queued transfer that ended its packet, the next transfer went on with the next packet: when that packet ended before the halt, its result had the end of packet, and in Scatter/Gather Mode its interrupt followed the error interrupt, depending on the timing of the halt | Every error of the queued transfer stops the next transfer: no further write, its result after the halt without the end of packet, the start of packet as received (S2-RS-03, S2-RS-04, SGI-15). TC-S2-23 halts 600 clock cycles after the error result and expects the next result after the halt, without the end of packet |
| The step of TC-S2-23 that presents a command while a failed result waits checked that the result came first, not that the command was taken with `Cmd_Ready`: a channel that took the command without the handshake passed (a fault of section 5) | TC-S2-23 checks the handshake of that command |

## 3. Response codes

The write master reports the response code of a failed command (`Wr_ErrorResp`, gap G5 of the architecture). The
channel maps DECERR to the decode error and SLVERR and EXOKAY to the slave error (interpretation I14); the first
failing response of a transfer decides. TC-S2-15 checks every response type and both orders within one transfer, in
two bursts. The decode error of a buffer beyond the top of the address space (S2-WR-04) comes from the channel
itself, without a write.

## 4. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `AddrWidth_g` | 32 to 64 | 32, 36, 40, 48, 64 | 32, 64 |
| `LengthWidth_g` | 8 to 26 | 8, 12, 14, 16, 18, 20, 22, 26 | 8, 26 |
| `MemWidth_g` | 32, 64, 128, 256, 512, 1024 | all | 32, 1024 |
| `StreamWidth_g` | 8 to 1024, powers of 2, at most `MemWidth_g` | all | 8, 1024 |
| `BurstBeats_g` | 2 to 256, powers of 2 | 2, 4, 8, 16, 32, 256 | 2, 256 |
| `BufferBeats_g` | at least 2 x `BurstBeats_g` x `MemWidth_g` / `StreamWidth_g` | four bursts | two bursts, four bursts |
| `Split_g` | boolean | false, true (the `s_` configurations, every memory width) | false, true (in the core, Scatter/Gather Mode) |

## 5. Checks of the testbench

Each of the following faults, inserted into a copy of the RTL of the channel or of the Open Logic write master, fails
at least one test case; the RTL of the repository passes all of them:

| Fault | Failing test case |
| --- | --- |
| No overflow check: chunks beyond the buffer are written | TC-S2-08 |
| Every chunk is written at the buffer address | TC-S2-01 |
| The write address is 256 bytes too high | TC-S2-01 |
| Every later burst of a command writes to the address of the first burst (`olo_axi_master_simple`) | TC-S2-04 |
| The address after a 4 KB boundary is 4096 bytes too high (`olo_axi_master_simple`) | TC-S2-04 |
| `TKeep` of the last beat ignored | TC-S2-03 |
| No discard descriptor at a halt inside a packet | TC-S2-11 |
| No flush of the rest of the packet after a write error | TC-S2-09 |
| A write error is ignored | TC-S2-09 |
| The result does not wait for the write responses | TC-S2-05 |
| Stream beats are taken during a drain | TC-S2-12 |
| The ECC event of the data buffer is not qualified by the handshake | TC-S2-13 |
| The halt decision does not see the stored descriptors | TC-S2-11 |
| The write master runs with `LengthWidth_g` size bits (gap G14) | TC-S2-16 |
| A single error in data mode flips two data bits (the word is corrupted instead of corrected) | TC-S2-13 |
| The start of packet set for every buffer | TC-S2-17 |
| The end of packet of a result from the buffer end instead of the packet end | TC-S2-17 |
| The discard segment offered for the whole discard, without `NeedSeg` | TC-S2-19 |
| `NeedSeg` not set when a segment ends inside a packet | TC-S2-19 |
| The split not reset while halted between packets (a stale segment) | TC-S2-19 |
| The open packet seen only by the chunk logic, without `StrmOpen` | TC-S2-19 |
| No flush after an error of a full buffer | TC-S2-19 |
| The flush ends at the buffer end instead of the packet end | TC-S2-19 |
| The keyhole bit not passed to the write master | TC-S2-20 |
| Keyhole chunks at incrementing addresses | TC-S2-20 |
| A keyhole buffer checked against the top of the address space | TC-S2-20 |
| The slave error code for every failed write | TC-S2-15 |
| The start of packet of a result without bytes and without the end of packet from `SofNext` | TC-S2-10 |
| The end of packet of an overflowing chunk not recorded (a second flush) | TC-S2-08 |
| `Stopped` without the data left in the channel (chunk buffer and `DescPend` ignored) | TC-S2-19 |
| A flush that ends a packet does not set the start of packet for the next buffer | TC-S2-19 |
| The end of a packet in the split never recorded (`EndPend` never set) | TC-S2-11 |
| A packet complete without the `NeedSeg` term (the rest of a packet that needs a further buffer kept) | TC-S2-19 |
| The end of a packet in the split not counted as open (`Open_i` without `EndPend`) | TC-S2-19, TC-S2-21 |
| A halt cuts a complete packet (`Cut` without `Complete`) | TC-S2-19 |
| `DescPend` also during the discard of a rest, so the halt exit of a transfer waits for its `TLast` | TC-S2-11 |
| The segment of a transfer ended by the halt not withdrawn | TC-S2-11 (configurations with the split) |
| Write responses counted against the current transfer before the queued one | TC-S2-23 |
| The current result while a result is queued | TC-S2-17 |
| The queued result before its write responses | TC-S2-17, TC-S2-19, TC-S2-22, TC-S2-23 |
| A second result queued over the first | TC-S2-17, TC-S2-19, TC-S2-22, TC-S2-23 |
| No stop of the next transfer at an error of the queued one | TC-S2-23 |
| The next transfer stopped only when it continues the packet of the queued one | TC-S2-23 |
| No flush of the rest of the packet at an error of the queued transfer | TC-S2-19 |
| The end of the packet of the queued transfer not recorded (`QCont` kept) | TC-S2-23 (configurations with the split) |
| `Stopped` while a result is queued | TC-S2-23 (configurations with the split) |
| `Stopped` while writes of the queued result are outstanding | TC-S2-22 |
| A command taken without `Cmd_Ready` while the queued result has an error | TC-S2-23 (the 14 configurations with two chunks within the longest length; verification plan, TC-S2-23) |
| A command accepted, with `Cmd_Ready`, while the queued result has an error | TC-S2-23 (the 14 configurations with two chunks within the longest length) |
| The stopped transfer returns its result before the halt | TC-S2-23 |
| The end of packet of a stopped transfer reported | TC-S2-23 |
| The next buffer of a continued packet starts a packet | TC-S2-17, TC-S2-22, TC-S2-23 (configurations with the split) |
| The chunk plan ignores the address: full chunks for every buffer | TC-S2-06, TC-S2-24 |
| A keyhole buffer gets the chunk plan of its address | TC-S2-20 |
| The first chunk ends at the burst boundary also at a multiple of the memory word | TC-S2-24 |
| Short chunks for every buffer that is neither a keyhole nor at a multiple of the memory word | TC-S2-06, TC-S2-24 |
| Short chunks in no configuration | TC-S2-24 |
| Short chunks in every configuration | TC-S2-24 |
| The size of the first chunk for every chunk of the buffer | TC-S2-06, TC-S2-24 |
| The plan of the buffer before (loaded at its last beat) | TC-S2-06, TC-S2-24 |
| Low-latency write commands with every width | TC-S2-01, TC-S2-05, TC-S2-06, by the W-gap check, in the 13 configurations with a memory wider than the stream |
| A descriptor taken while the stage of the feed jobs is full (its job is lost) | TC-S2-28 |

The recovery branches of the state machines (`when others`) cannot be reached through the ports.
