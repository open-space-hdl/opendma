# odma_core: Verification Report

## 1. Test results

Run on 2026-10-16 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*odma_core*"` and
`python lint/synth_check.py`.

| Testbench or check | Tests | Passed |
| --- | --- | --- |
| `odma_core_tb` | 43 (9 test cases in the configurations of verification plan section 2) | 43 |
| `lint/synth_check.py` (TC-CO-09) | 25 (16 configurations synthesised, 9 inconsistent ones rejected) | 25 |

## 2. Summary

All test cases pass; every requirement of the specification is covered. VSG reports no errors and no warnings. The
core synthesises with `ghdl --synth` without errors and without latches in the configurations of section 4, and each
inconsistent configuration stops the elaboration with its message.

Findings of the verification:

| Finding | Resolution |
| --- | --- |
| The sequence player passed the whole line of a command as the message of a VVC command; a packet line of more than about 250 characters exceeded the message field of 300 characters and stopped the simulation | The message carries the end of the file name, the line number and the start of the line (`odma_pkg` architecture, section 3.3) |
| Right after the error interrupt `S2MM_DMASR.Halted` can still read 0: the error flags and `Err_Irq` are set with the result, `Halted` follows when the channel has shut down. \[PG021\] describes the same order for an error (`RS` falls, `Halted` is set when the engine has shut down) | The model polls `Halted` after the error interrupt (`failed_transfer`); the user guide states the order (section 5.4) |
| The injection flipped parity bits only, so a double error never changed data and a single error never exercised the correction of a data bit: a channel that used the uncorrected word of a buffer would have passed every injection test, and the buffers of one channel could not be told apart | `ECC_INJECT.Data` selects data bits; TC-CO-10, TC-MM-13 and TC-S2-13 inject single errors on a data bit, TC-CO-10 double errors with the consequence of each buffer (`odma_registers` RG-EX-05) |
| A mutation check found the channel reset and the S2MM drain of the soft reset not observed: with the transfers drained the channels reached the same state without them | TC-CO-05 sends the S2MM packet from a stream peer that is still sending at the reset and counts the beats taken during the reset; TC-CO-06 shows that the soft reset cancels an injection pending in each buffer |

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
| `IncludeSg_g`, `StsCntrlStrm_g`, `UseRxLength_g`, `MicroDma_g` | false in phase a | false | false; true rejected |
| `LengthWidth_g` | 8 to 26 | 8, 14, 20, 26 | 8, 14, 26 |
| `AddrWidth_g` | 32 to 64 | 32, 40, 64 | 32, 64 |
| `Mm2sMemWidth_g`, `S2mmMemWidth_g` | 32, 64, 128, 256, 512, 1024 | MM2S 32, 64, 128, 256; S2MM 32, 64, 128, 512 | all; 48 rejected |
| `Mm2sStreamWidth_g`, `S2mmStreamWidth_g` | 8 to 1024, powers of 2, at most the memory width | MM2S 8, 32, 64; S2MM 8, 32, 64, 256 | 8, 32, 1024; a stream wider than the memory rejected |
| `Mm2sBurstBeats_g`, `S2mmBurstBeats_g` | 2 to 256, powers of 2 | MM2S 4, 8, 16; S2MM 2, 4, 16, 32 | 2, 16, 256; 3 rejected |
| `Mm2sBufferBeats_g`, `S2mmBufferBeats_g` | at least two bursts | four bursts | two bursts, four bursts; 31 (less than two bursts) rejected |
| `ExtRegs_g` | boolean | true, false | true, false |

The unit benches of `odma_mm2s` and `odma_s2mm` simulate every memory width with every stream width class, the
longest bursts and the stream widths above 256 bits (their verification reports, section 4); the core benches keep
the streams at or below 256 bits, the limit of the AXI4-Stream VVC.

## 5. Coverage

Code coverage is collected with QuestaSim in the batch of phase a (`docs/coverage.md`).
