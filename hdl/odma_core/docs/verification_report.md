# odma_core: Verification Report

## 1. Test results

Run on 2026-10-17 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*odma_core*"` and
`python lint/synth_check.py`.

| Testbench or check | Tests | Passed |
| --- | --- | --- |
| `odma_core_tb` | 83 (16 test cases in the configurations of verification plan section 2: 9 in the DR, 7 in the SG configurations) | 83 |
| `lint/synth_check.py` (TC-CO-09) | 29 (21 configurations synthesised, 5 of them in SG mode; 8 inconsistent ones rejected) | 29 |

The test cases of section 3.1 of the plan (TC-CO-18, TC-CO-19) wait for Open Logic and are not run.

## 2. Summary

All test cases pass; every requirement of the specification is covered except CO-SG-09 to CO-SG-11, which wait
for Open Logic. VSG reports no errors and no warnings. The core synthesises with `ghdl --synth` without errors and
without latches in the configurations of section 4, in DR mode and in SG mode, and each inconsistent configuration
stops the elaboration with its message.

Findings of the verification:

| Finding | Resolution |
| --- | --- |
| The sequence player passed the whole line of a command as the message of a VVC command; a packet line of more than about 250 characters exceeded the message field of 300 characters and stopped the simulation | The message carries the end of the file name, the line number and the start of the line (`odma_pkg` architecture, section 3.3) |
| Right after the error interrupt `S2MM_DMASR.Halted` can still read 0: the error flags and `Err_Irq` are set with the result, `Halted` follows when the channel has shut down. \[PG021\] describes the same order for an error (`RS` falls, `Halted` is set when the engine has shut down) | The model polls `Halted` after the error interrupt (`failed_transfer`); the user guide states the order (section 5.4) |
| The injection flipped parity bits only, so a double error never changed data and a single error never exercised the correction of a data bit: a channel that used the uncorrected word of a buffer would have passed every injection test, and the buffers of one channel could not be told apart | `ECC_INJECT.Data` selects data bits; TC-CO-10, TC-MM-13 and TC-S2-13 inject single errors on a data bit, TC-CO-10 double errors with the consequence of each buffer (`odma_registers` RG-EX-05) |
| A mutation check found the channel reset and the S2MM drain of the soft reset not observed: with the transfers drained the channels reached the same state without them | TC-CO-05 sends the S2MM packet from a stream peer that is still sending at the reset and counts the beats taken during the reset; TC-CO-06 shows that the soft reset cancels an injection pending in each buffer |
| The first S2MM error scenario failed the fetch of the second descriptor: the halt then came while the packet of the first descriptor was still arriving, which ended that packet early (interpretation I8 of `odma_registers`), so no `IOC_Irq` came. The behaviour is correct; the scenario did not match it | `sg_errors` lets the S2MM fetch error and the stale descriptor hit the first descriptor, before any packet; MM2S keeps them at the second descriptor, whose predecessor completes first (the model documents why) |
| A mutation check of the Scatter/Gather integration found three faults that passed: every stream beat taken as a packet start, `Stopped` of the S2MM channel without its engine (and without the channel), and the indices 6 to 9 rotated. The first is visible only when a packet starts before the completion of the one before; the second only when a soft reset meets an outstanding descriptor access or data burst of the channel alone; the third not at all while every index is injected at once | TC-CO-16 runs two packets back to back so that the delay timer must run during the second (interpretation R10), TC-CO-17 resets once with a descriptor access and once with only data bursts outstanding, TC-CO-15 injects one index at a time |

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
| `IncludeSg_g` | boolean | false, true (with both channels and with each channel alone) | false, true (default, 32/8, 64/26 address and length widths, each channel alone) |
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
