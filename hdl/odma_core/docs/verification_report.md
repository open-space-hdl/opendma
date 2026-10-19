# odma_core: Verification Report

## 1. Test results

Run on 2026-10-19 in the GHDL CI of the repository, GitHub Actions run 39209624300 on commit b3a592b (its
`results.xml`), with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.03.20:
`python run.py -p 4 --xunit-xml results.xml`, the tests of `odma_core_tb`, and
`python lint/synth_check.py -j 4` in the same run.

| Testbench or check | Tests | Passed |
| --- | --- | --- |
| `odma_core_tb` | 104 (20 test cases in the configurations of verification plan section 2: 9 in the DR, 10 in the SG configurations, TC-CO-19 in both) | 104 |
| `lint/synth_check.py` (TC-CO-09) | 31 (23 configurations synthesised, 7 of them in SG mode; 8 inconsistent ones rejected) | 31 |

Pause per S2MM buffer boundary and rate (TC-CO-20, two packets of 16 KB, a stream without gaps, write response
latency 0 / 50 clock cycles, buffers at multiples of 64 bytes unless stated):

| Configuration | Pause per buffer boundary | Beats per clock cycle, 1 KB buffers | Beats per clock cycle, 4 KB buffers | Beats per clock cycle, 4 KB buffers at unaligned addresses | Cycles per KB added by unaligned buffers |
| --- | --- | --- | --- | --- | --- |
| `sg`, `sg_s2mm_only` (32 / 32 bits, 16 beats) | 1 / 1 | 0.85 / 0.85 | 0.85 / 0.85 | 0.81 / 0.81 | 15 / 15 |
| `sg_aw64` (512 / 256 bits, 4 beats) | 1 / 19 | 0.48 / 0.40 | 0.49 / 0.49 | 0.40 / 0.40 | 14 / 14 |
| `sg_lw8` (64 / 8 bits, 2 beats; buffers of at most 255 bytes, so no boundary figure) | - | 0.64 / 0.64 | 0.64 / 0.64 | 0.64 / 0.64 | 0 / 0 |

The S2MM channel accepts the next buffer once the last write command of the full buffer is issued, while the
result of the full buffer waits for its write responses (`odma_s2mm` S2-RS-06), so a boundary costs one clock cycle
with the defaults at either latency. With 512 / 256 bits a buffer of 1 KB fills in about 66 clock cycles, and with a
response latency of 50 it waits at its end for the responses of the buffer before (one result waits at a time).

The unaligned buffers start 1 byte above a multiple of 64 bytes. With 64 / 8 bits that is a multiple of the stream
width: the first chunk ends at the burst boundary and the later chunks are aligned (`odma_s2mm` S2-ST-04), so the
buffers take no longer than aligned ones. With 32 / 32 and 512 / 256 bits the address is inside a stream word, where
the chunks keep their full size and each is written as two bursts. The defaults write with low-latency commands
(equal widths, `odma_s2mm` S2-WR-03): 8192 beats in 9667 clock cycles with 1 KB buffers, 11657 with high-latency
commands (a variant of the sources, `odma_s2mm` verification report).

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
| TC-CO-18 hung after the S2MM write error: `Halted` is set while the channel still discards the rest of the failed packet (documented behaviour), so the soft reset came while the stream VVC was still sending it. The VVC does not follow `S2mm_RstOut`, and the rest of the packet filled the first buffer of the new chain | The sequence command `T` waits until one stream packet is sent while the next one stays queued (`odma_pkg` architecture, section 3.3); the scenario waits for the failed packet before the soft reset, so the next packet still follows it directly. The step is now TC-CO-21, with the next buffer of the failed packet written before the error arrives |
| With the next S2MM buffer accepted while the write responses of the full buffer arrive (`odma_s2mm` S2-RS-06), the write-error step of TC-CO-18 failed in the four configurations with S2MM: its failing buffer was one chunk with responses without latency, and the next buffer of the packet now took a number of bytes before the error arrived that depends on the timing of the stream and the memory, while the scenario expected it unwritten | The step moves to TC-CO-21, whose write responses come 400 clock cycles late, so that the next buffer is written completely before the error: the scenario expects its bytes and its status (interpretation SGI-15), the third descriptor unchanged, and the next packet sent directly after the failed one complete after the soft reset |
| The first TC-CO-20 figures (69 clock cycles per boundary) mixed in a second effect: a chunk at an address that is not a multiple of the memory word covers one word more than a burst and is written as two bursts, and the runs with 1 KB and 4 KB buffers had different shares of such buffers. The buffers of the two runs also overlapped | TC-CO-20 places its buffers at multiples of 64 bytes in a region per buffer length and measures unaligned 4 KB buffers separately; the user guide (section 7) gives both effects. The chunk plan of `odma_s2mm` (S2-ST-04) removes the second effect for buffers at a multiple of the stream width (0 instead of 240 clock cycles more per KB with 64 / 8 bits) |
| A first chunk plan of `odma_s2mm` that also shortened the first chunk of buffers at a multiple of the memory word raised the pause per buffer boundary of `sg_aw64` from 1 to 8 clock cycles: the TC-CO-20 buffers lie at multiples of 64 bytes, one memory word at 512 bits, below the burst size of 256 bytes | At a multiple of the memory word the chunks keep their full size (`odma_s2mm` S2-ST-04) |
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
