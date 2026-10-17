# odma_s2mm: Verification Report

## 1. Test results

Run on 2026-10-17 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*odma_s2mm*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `odma_s2mm_tb` | 306 (20 test cases: 14 in all 18 configurations, TC-S2-07, TC-S2-08 and TC-S2-13 in the ten without the split, TC-S2-17 to TC-S2-19 in the eight `s_` configurations) | 306 |

## 2. Summary

All test cases pass; every requirement of the specification is covered. VSG reports no errors and no warnings.
The sources analyse with `ghdl -a --std=08` without `-frelaxed` and without warnings, and synthesise with
`ghdl --synth` without warnings and without latches in the configurations
of section 4.

Measured throughput of TC-S2-06 (64 chunks or the longest length, memory always ready, stream without gaps):

| Configuration | Beats per chunk | Memory width / stream width | Beats | Clock cycles from the first to the last beat |
| --- | --- | --- | --- | --- |
| `w32_s32` | 16 | 1 | 1024 | 1353 |
| `w64_s8` | 128 | 8 | 8192 | 8192 |
| `w128_s32` | 1024 | 4 | 65536 | 65536 |
| `w128_s64` | 64 | 2 | 4096 | 4299 |
| `w256_s16` | 128 | 16 | 8192 | 8192 |
| `w256_s128` | 8 | 2 | 512 | 995 |
| `w512_s256` | 16 | 2 | 1024 | 1467 |
| `w512_s512` | 2 | 1 | 128 | 527 |
| `w1024_s8` | 256 | 128 | 255 | 255 |
| `w1024_s1024` | 32 | 1 | 32 | 32 (the packet fits into the data buffer) |

Findings:

| Finding | Resolution |
| --- | --- |
| The write path of `olo_axi_master_full` of Open Logic 4.7.0-ft.6 counts the user data words of a write command at the width of the size field without its low bits; for the sizes in the last user data word below 2**`UserTransactionSizeBits_g` the count wraps to 0 and the master issues no further burst: with 1024-bit stream words and a length width of 12 a transfer of 4000 to 4095 bytes left the channel without its next result (reproduced with two transfers back to back, also with 512-bit words, independent of the address width) | Both masters run with `UserTransactionSizeBits_g` = `LengthWidth_g` + 1 (gap G14 of the architecture). TC-S2-16 transfers the longest length back to back and fails with a timeout of 2 ms, not a hang, when the master runs with `LengthWidth_g` size bits |
| The channel issues one write command per chunk, and the write master accepts the next command after the data of the previous one, about 7 clock cycles per command; with equal memory and stream widths and chunks of 16 beats the channel takes about 0.7 beats per clock cycle | S2-WR-05 requires at least 0.9 beats per clock cycle with chunks of at least 64 beats; the throughput is measured in every configuration (table above). With a memory four or more times wider than the stream the write side is faster than the stream and the channel takes one beat per clock cycle |
| A second beat counter in `olo_base_chunker` counted the same beats as the counter of the descriptor; in a delta cycle the two disagreed | The chunk end follows from the counter of the descriptor; `olo_base_chunker` is not instantiated (architecture section 2) |
| A result with a write error carried the end of packet when the packet ended in the failing chunk | A result with an error carries no end of packet (S2-RS-03) |
| A command of length 0 had no defined behaviour; in Scatter/Gather Mode a buffer length of 0 is an internal error | No write, no stream data taken, result with the internal error code (S2-WR-06, interpretation S4); TC-S2-10 |
| The AXI4-Stream BFM of UVVM takes at most 32 `TStrb` bits (256 data bits) | The stream generator of the harness drives every configuration (verification plan, section 1) |
| With the split, a halt inside a packet let the next packet pass without a command, and the segment of the next command was left over for a later packet: the split takes a new segment in the clock cycle in which its previous one ends, and S2-1 offered the discard segment for the whole discard, so the split took one more after the last beat of the discarded packet | The register `NeedSeg` offers a discard segment only when the split has none for the rest of the packet (architecture section 4.2); TC-S2-19 halts one and a half chunks into the second buffer and checks the next packet complete and alone |
| Four safeguards of the first implementation with the split were equivalent: a flag that limited the discard to one per flush, the drop of a segment that the split had not taken at the result, the clearing of `NeedSeg` at a halt and the gating of `StrmOpen` during the discard; a mutant that disabled each one passed every test | They are removed; the architecture states why each case cannot occur (sections 4.2 and 4.3) |
| A result without bytes and without the end of packet (buffer length 0, buffer beyond the top of the address space) carried the start of packet; found by the core scenario `sg_errors` (`RXSOF` in the status of a descriptor of length 0) | Such a result belongs to no packet and has `Res_Sof` '0' (S2-SG-02, interpretation SGI-14); TC-S2-10 checks it |
| TC-S2-10 expected the packet after the rejected commands in the data buffer; with `Split_g` it waits at the stream port, because the split takes no beat without a segment (S2-SG-03). The test had not run in the configurations with the split | TC-S2-10 checks that no beat is taken with `Split_g` and runs in every configuration |

## 3. Response codes

The write master reports the response code of a failed command (`Wr_ErrorResp`, gap G5 of the architecture). The
channel maps DECERR to the decode error and SLVERR and EXOKAY to the slave error (interpretation I14); the first
failing response of a transfer decides. TC-S2-15 checks every response type and both orders within one transfer. The
decode error of a buffer beyond the top of the address space (S2-WR-04) comes from the channel itself, without a
write.

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

The recovery branches of the state machines (`when others`) cannot be reached through the ports.
