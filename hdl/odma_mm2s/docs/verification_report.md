# odma_mm2s: Verification Report

## 1. Test results

Run on 2026-10-17 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*odma_mm2s*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `odma_mm2s_tb` | 312 (19 test cases: 16 in all 18 configurations, TC-MM-16 to TC-MM-18 in the eight `j_` configurations) | 312 |

## 2. Summary

All test cases pass; every requirement of the specification is covered. VSG reports no errors and no warnings.
The sources analyse with `ghdl -a --std=08` without `-frelaxed` and without warnings, and synthesise with
`ghdl --synth` without warnings and without latches in the configurations
of section 4.

Measured throughput of TC-MM-05 (64 bursts or the longest length, memory and stream peer always ready):

| Configuration | Stream beats per burst | Beats | Clock cycles from the first to the last beat |
| --- | --- | --- | --- |
| `w32_s32` | 16 | 1024 | 1024 |
| `w64_s8` | 128 | 8192 | 8192 |
| `w128_s32` | 1024 | 65536 | 65536 |
| `w128_s64` | 64 | 4096 | 4096 |
| `w256_s16` | 128 | 8192 | 8192 |
| `w256_s128` | 8 | 512 | 512 |
| `w512_s256` | 16 | 1024 | 1024 |
| `w512_s512` | 2 | 128 | 252 |
| `w1024_s8` | 256 | 255 | 255 |
| `w1024_s1024` | 32 (bursts of 4 KB) | 32 | 32 |

Findings:

| Finding | Resolution |
| --- | --- |
| With fewer than 8 stream beats per burst the channel does not reach one beat per clock cycle: the read master requests a burst only when its internal FIFOs of two bursts can take it, which does not hide the read latency of the memory for short bursts | MM-RD-05 applies from 8 stream beats per burst; the architecture (section 8) states the measured throughput below |
| The result was specified after the handshake of the last beat at the input of the output register stage, before the stream peer had taken the beat | The result waits until the register stage is empty (MM-ST-03, architecture section 5); TC-MM-08 delays the last beat by 40 clock cycles |
| The transfer and response buffers are `olo_ft_fifo_sync` instances without an index in the ECC counters of the extension window | Indices 4 and 5 of the extension window; `Ecc_Sec`, `Ecc_Ded` and `EccInj_Valid` have one bit per buffer; TC-MM-13 injects into all three buffers |
| A command of length 0 had no defined behaviour; in Scatter/Gather Mode a buffer length of 0 is an internal error | No read, no beat, result with the internal error code (MM-RD-06, interpretation M3); TC-MM-10 |
| The AXI4-Stream BFM of UVVM takes at most 32 `TStrb` bits (256 data bits) | The stream checker of the harness checks every configuration (verification plan, section 1) |
| `olo_axi_master_simple` of Open Logic 4.7.0-ft.6 does not elaborate when `AxiMaxBeats_g` exceeds the beats of 4 KB (for example 256 beats of 1024 bits): a slice of its 4 KB beat count is out of range; `ghdl --synth` stops, a simulation stops when the branch is reached | The read master runs with at most the beats of 4 KB (architecture section 4); no AXI burst crosses 4 KB, so the bursts are the same. The configuration `w1024_s1024` simulates `BurstBeats_g` 256 with 1024 bits |
| The write path of `olo_axi_master_full` of Open Logic 4.7.0-ft.6 stalls after a command whose size lies in the last user data word below 2**`UserTransactionSizeBits_g` (found with `odma_s2mm`, gap G14) | The read master runs with `UserTransactionSizeBits_g` = `LengthWidth_g` + 1 like the write master; the regression of this module passes with it |
| A counter of the read commands outstanding at the read master entered `Stopped`; a fault that ignored it passed every test | The counter is removed: a transfer entry with a read is popped only after its response, so an empty transfer buffer already means that no read is outstanding (architecture section 6) |
| TC-MM-13 injected the error into the first word of a transfer, which left the read data buffer at once; a fault that did not qualify the ECC event with the handshake passed | TC-MM-13 injects into a transfer that waits at the output of the buffers behind another transfer |
| The memory was filled with a count pattern that repeats every 256 bytes, so a read from an address wrong by a multiple of 256 bytes (a later burst at the address of the first one, a wrong 4 KB page after a split) delivered the expected bytes | The memory model fills a pattern that depends on every address bit (`odmaMemByte`, requirement PKG-10 of `odma_pkg`); the checker compares with the memory contents at the address of each byte. Three address faults are in the table of section 5 |

## 3. Response codes

The read master reports the response code of a failed command (`Rd_ErrorResp`, gap G5 of the architecture). The
channel maps DECERR to the decode error and SLVERR and EXOKAY to the slave error (interpretation I14); the first
failing response of a transfer decides. TC-MM-15 checks every response type and both orders within one transfer. The
decode error of a buffer beyond the top of the address space (MM-RD-04) comes from the channel itself, without a
read.

## 4. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `AddrWidth_g` | 32 to 64 | 32, 36, 40, 48, 64 | 32, 64 |
| `LengthWidth_g` | 8 to 26 | 8, 12, 14, 16, 18, 20, 22, 26 | 8, 26 |
| `MemWidth_g` | 32, 64, 128, 256, 512, 1024 | all | 32, 1024 |
| `StreamWidth_g` | 8 to 1024, powers of 2, at most `MemWidth_g` | all | 8, 1024 |
| `BurstBeats_g` | 2 to 256, powers of 2 | 2, 4, 8, 16, 32, 256 | 2, 256 |
| `BufferBeats_g` | at least 2 x `BurstBeats_g` x `MemWidth_g` / `StreamWidth_g` | four bursts | two bursts, four bursts |
| `Join_g` | boolean | false, true (the `j_` configurations) | false, true (in the core, Scatter/Gather Mode) |

## 5. Checks of the testbench

Each of the following faults, inserted into a copy of the RTL of the channel or of the Open Logic read master, fails
at least one test case; the RTL of the repository passes all of them:

| Fault | Failing test case |
| --- | --- |
| A command of length 0 is read | TC-MM-10 |
| A buffer beyond the top of the address space is read | TC-MM-07 |
| The result does not wait for the empty register stage | TC-MM-08 |
| `TLast` on the last beat of a transfer without the end of packet | TC-MM-01 |
| Low-latency reads (`CmdRd_LowLat` = '1') | TC-MM-06 |
| A command is accepted while `Run` is '0' | TC-MM-11 |
| The register stage is not cleared by a drain | TC-MM-12 |
| `TKeep` of the last beat all ones | TC-MM-02 |
| The ECC event of the read data buffer is not qualified by the handshake | TC-MM-13 |
| The response code of the read master is ignored | TC-MM-09 |
| Every later burst of a command reads the address of the first burst (`olo_axi_master_simple`) | TC-MM-03 |
| The read address is 256 bytes too high | TC-MM-01 |
| The address after a 4 KB boundary is 4096 bytes too high (`olo_axi_master_simple`) | TC-MM-03 |
| A single error in data mode flips two data bits (the word is corrupted instead of corrected) | TC-MM-13 |
| The result of a transfer with the end of packet does not wait for its `TLast` beat | TC-MM-17 |
| No closing beat when `Run` falls inside a packet of several commands | TC-MM-18 |
| `Closed` always '1' (the channel reports stopped with a packet open) | TC-MM-18 |
| `TLast` on the last beat of every command, also inside a packet | TC-MM-16 |
| The open packet not tracked | TC-MM-18 |
| The keyhole bit not passed to the read master | TC-MM-19 |
| A keyhole buffer checked against the top of the address space | TC-MM-19 |
| The slave error code for every failed read | TC-MM-15 |

The recovery branches of the state machines (`when others`) cannot be reached through the ports.
