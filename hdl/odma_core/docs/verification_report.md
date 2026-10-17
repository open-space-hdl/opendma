# odma_core: Verification Report

## 1. Test results

Run on 2026-10-17 in the GHDL CI of the repository, GitHub Actions run 39076889615 on commit 5e49ffb (its
`results.xml`), with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.03.20:
`python run.py -p 4 --xunit-xml results.xml`, the tests of `odma_core_tb`, and
`python lint/synth_check.py -j 4` in the same run.

| Testbench or check | Tests | Passed |
| --- | --- | --- |
| `odma_core_tb` | 100 (19 test cases in the configurations of verification plan section 2: 9 in the DR, 9 in the SG configurations, TC-CO-19 in both) | 100 |
| `lint/synth_check.py` (TC-CO-09) | 31 (23 configurations synthesised, 7 of them in SG mode; 8 inconsistent ones rejected) | 31 |

Pause per S2MM buffer boundary and rate (TC-CO-20, two packets of 16 KB, a stream without gaps, write response
latency 0 / 50 clock cycles, buffers at multiples of 64 bytes unless stated):

| Configuration | Pause per buffer boundary | Beats per clock cycle, 1 KB buffers | Beats per clock cycle, 4 KB buffers | Beats per clock cycle, 4 KB buffers at unaligned addresses | Cycles per KB added by unaligned buffers |
| --- | --- | --- | --- | --- | --- |
| `sg`, `sg_s2mm_only` (32 / 32 bits, 16 beats) | 43 / 93 | 0.63 / 0.56 | 0.69 / 0.67 | 0.59 / 0.57 | 62 / 62 |
| `sg_aw64` (512 / 256 bits, 4 beats) | 25 / 75 | 0.36 / 0.23 | 0.46 / 0.39 | 0.38 / 0.34 | 14 / 14 |
| `sg_lw8` (64 / 8 bits, 2 beats; buffers of at most 255 bytes, so no boundary figure) | - | 0.60 / 0.53 | 0.60 / 0.53 | 0.52 / 0.47 | 240 / 240 |

A probe of the stages at a buffer boundary (user guide, section 7) shows the write master idle for 50 + L clock cycles
(36 + L with 512 / 256 bits) from the last write beat of a full buffer to the first one of the next, against 7 (11)
between two bursts inside a buffer: the write response, the result, the next command (the engine holds the next
descriptor; its status write and the next fetch are not on the path), the first chunk of the next buffer and the start
of the burst in the write master, which waits until all data of the burst is buffered.

## 2. Summary

All test cases pass; every requirement of the specification is covered. VSG reports no errors and no warnings.
The core synthesises with `ghdl --synth` without errors and without latches in the configurations of section 4, in DR
mode and in SG mode, and each inconsistent configuration
stops the elaboration with its message.

Findings of the verification:

| Finding | Resolution |
| --- | --- |
| The sequence player passed the whole line of a command as the message of a VVC command; a packet line of more than about 250 characters exceeded the message field of 300 characters and stopped the simulation | The message carries the end of the file name, the line number and the start of the line (`odma_pkg` architecture, section 3.3) |
| Right after the error interrupt `S2MM_DMASR.Halted` can still read 0: the error flags and `Err_Irq` are set with the result, `Halted` follows when the channel has shut down. \[PG021\] describes the same order for an error (`RS` falls, `Halted` is set when the engine has shut down) | The model polls `Halted` after the error interrupt (`failed_transfer`); the user guide states the order (section 5.4) |
| The injection flipped parity bits only, so a double error never changed data and a single error never exercised the correction of a data bit: a channel that used the uncorrected word of a buffer would have passed every injection test, and the buffers of one channel could not be told apart | `ECC_INJECT.Data` selects data bits; TC-CO-10, TC-MM-13 and TC-S2-13 inject single errors on a data bit, TC-CO-10 double errors with the consequence of each buffer (`odma_registers` RG-EX-05) |
| A mutation check found the channel reset and the S2MM drain of the soft reset not observed: with the transfers drained the channels reached the same state without them | TC-CO-05 sends the S2MM packet from a stream peer that is still sending at the reset and counts the beats taken during the reset; TC-CO-06 shows that the soft reset cancels an injection pending in each buffer |
| The first S2MM error scenario failed the fetch of the second descriptor: the halt then came while the packet of the first descriptor was still arriving, which ended that packet early (interpretation I8 of `odma_registers`), so no `IOC_Irq` came. The behaviour is correct; the scenario did not match it | `sg_errors` lets the S2MM fetch error and the stale descriptor hit the first descriptor, before any packet; MM2S keeps them at the second descriptor, whose predecessor completes first (the model documents why) |
| The S2MM channel gave a descriptor of length 0 the start of packet (`RXSOF` in its status, scenario `sg_errors`) | A result without bytes and without the end of packet belongs to no packet (`odma_s2mm` S2-SG-02, interpretation SGI-14) |
| TC-CO-18 hung after the S2MM write error: `Halted` is set while the channel still discards the rest of the failed packet (documented behaviour), so the soft reset came while the stream VVC was still sending it. The VVC does not follow `S2mm_RstOut`, and the rest of the packet filled the first buffer of the new chain | The sequence command `T` waits until one stream packet is sent while the next one stays queued (`odma_pkg` architecture, section 3.3); the scenario waits for the failed packet before the soft reset, so the next packet still follows it directly |
| The first TC-CO-20 figures (69 clock cycles per boundary) mixed in a second effect: a chunk at an address that is not a multiple of the memory word covers one word more than a burst and is written as two bursts, and the runs with 1 KB and 4 KB buffers had different shares of such buffers. The buffers of the two runs also overlapped | TC-CO-20 places its buffers at multiples of 64 bytes in a region per buffer length and measures unaligned 4 KB buffers separately; the user guide (section 7) gives both effects. Shorter boundary pauses and burst-aligned chunks are planned (roadmap) |
| A mutation check of the Scatter/Gather integration found three faults that passed: every stream beat taken as a packet start, `Stopped` of the S2MM channel without its engine (and without the channel), and the indices 6 to 9 rotated. The first is visible only when a packet starts before the completion of the one before; the second only when a soft reset meets an outstanding descriptor access or data burst of the channel alone; the third not at all while every index is injected at once | TC-CO-16 runs two packets back to back so that the delay timer must run during the second (interpretation R10), TC-CO-17 resets once with a descriptor access and once with only data bursts outstanding, TC-CO-15 injects one index at a time |
| TC-CO-19 did not check that the S2MM keyhole writes nothing outside the backing range of the FIFO window | The scenario `keyhole` expects the window word and 16 bytes on each side of it, 16 bytes before and after the backing range and the rest of the last word of each transfer unwritten |

## 3. Checks of the testbench

Each of the following faults, inserted into a copy of `odma_core`, fails the test case in the table; the RTL of the
repository passes all of them:

| Fault | Failing test case |
| --- | --- |
| The injection of the S2MM chunk buffer goes to the data buffer and vice versa | TC-CO-06 |
| The MM2S channel is reset by `Rst` only, not by the soft reset | TC-CO-06 |
| The S2MM channel is reset by `Rst` only | TC-CO-06 |
| The S2MM channel does not receive `Drain` | TC-CO-05 |
| The MM2S transfer and response buffers at exchanged indices (4 and 5) | TC-CO-10 |
| The MM2S read data buffer at the index of the transfer buffer | TC-CO-10 |
| The S2MM data and write data buffers at exchanged indices (1 and 3) | TC-CO-10 |
| The S2MM data and chunk buffers at exchanged indices (1 and 2) | TC-CO-10 |
| The MM2S channel does not receive the injection mode | TC-CO-10 |
| The MM2S channel does not receive `Drain` | TC-CO-05 |
| The idle burst type of an excluded MM2S channel is FIXED | TC-CO-07 (idle monitor) |
| The error code of the S2MM result does not reach the register interface | TC-CO-04 |
| The MM2S packet start pulse at '0' (no packet start reaches the delay timer) | TC-CO-16 |
| The S2MM packet start pulse at '0' | TC-CO-16 |
| Every MM2S stream beat taken as a packet start (`InPkt` held '0') | TC-CO-16 |
| Every S2MM stream beat taken as a packet start | TC-CO-16 |
| `Res_Sof` of the S2MM results at '0' | TC-CO-11 |
| `Stopped` of the MM2S channel without its engine | TC-CO-17 |
| `Stopped` of the MM2S channel from its engine only | TC-CO-17 |
| `Stopped` of the S2MM channel without its engine | TC-CO-17 |
| `Stopped` of the S2MM channel from its engine only | TC-CO-17 |
| The ECC events of the engine rotated by one index | TC-CO-15 |
| The injection strobes of the engine rotated by one index | TC-CO-15 |
| `ArValid` of the descriptor port at '1' in DR mode | TC-CO-07 (idle monitor) |
| `BReady` of the descriptor port at '1' in DR mode | TC-CO-07 (idle monitor) |
| The MM2S join off in Scatter/Gather Mode | TC-CO-18 |
| The S2MM split off in Scatter/Gather Mode | TC-CO-18 |
| `Res_Sof` at the S2MM input of the engine at '1' | TC-CO-18 |
| The MM2S keyhole of the engine at '0' | TC-CO-19 |
| The S2MM keyhole of the engine at '0' | TC-CO-19 |
| The S2MM keyhole of DR mode at '0' | TC-CO-19 |
| The MM2S keyhole of DR mode at '1' | TC-CO-19 |

One fault passes and is equivalent by design: `Stopped` of an excluded channel at '0'. `odma_registers` treats a
channel that is not included as stopped, so the idle value has no effect.

A permutation of the indices of the buffers of one channel, applied in the same way to the events and to the
injection, is not visible through the counters of single errors: an injection still reaches a buffer of the
channel and its event comes back at the same index. TC-CO-10 tells every buffer apart by the consequence of a
double error in data mode, so such a permutation fails it.

## 4. Generic ranges

| Generic | Declared range | Simulated (core) | Synthesised |
| --- | --- | --- | --- |
| `IncludeMm2s_g`, `IncludeS2mm_g` | boolean, at least one true | true/true, true/false, false/true | all three; false/false rejected |
| `IncludeSg_g` | boolean | false, true (with both channels and with each channel alone) | false, true (default, 32/8, 64/26 address and length widths, each channel alone, 1024 / 1024 bits with 256 beats, 32 / 8 bits with 2 beats) |
| `StsCntrlStrm_g`, `UseRxLength_g`, `MicroDma_g` | false until phase c | false | false; true rejected |
| `LengthWidth_g` | 8 to 26 | 8, 14, 20, 26 (SG mode 8, 14, 20) | 8, 14, 26 (SG mode 8, 14, 26) |
| `AddrWidth_g` | 32 to 64 | 32, 40, 64 (SG mode 32, 64) | 32, 64 (both modes) |
| `Mm2sMemWidth_g`, `S2mmMemWidth_g` | 32, 64, 128, 256, 512, 1024 | MM2S 32, 64, 128, 256; S2MM 32, 64, 128, 512 | all; 48 rejected |
| `Mm2sStreamWidth_g`, `S2mmStreamWidth_g` | 8 to 1024, powers of 2, at most the memory width | MM2S 8, 32, 64; S2MM 8, 32, 64, 256 | 8, 32, 1024; a stream wider than the memory rejected |
| `Mm2sBurstBeats_g`, `S2mmBurstBeats_g` | 2 to 256, powers of 2 | MM2S 4, 8, 16; S2MM 2, 4, 16, 32 | 2, 16, 256; 3 rejected |
| `Mm2sBufferBeats_g`, `S2mmBufferBeats_g` | at least two bursts | four bursts | two bursts, four bursts; 31 (less than two bursts) rejected |
| `ExtRegs_g` | boolean | true, false | true, false |

The unit benches of `odma_mm2s` and `odma_s2mm` simulate every memory width with every stream width class, the
longest bursts and the stream widths above 256 bits (their verification reports, section 4); the core benches keep
the streams at or below 256 bits, the limit of the AXI4-Stream VVC.

## 5. Coverage

Code coverage is collected with QuestaSim in the batches of phases a and b (`docs/coverage.md`).
