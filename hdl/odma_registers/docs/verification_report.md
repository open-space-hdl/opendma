# odma_registers: Verification Report

## 1. Test results

Run on 2026-10-19 in the GHDL CI of the repository, GitHub Actions run 39290223755 on commit 8c32323 (its
`results.xml`), with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.03.20:
`python run.py -p 4 --xunit-xml results.xml`, the tests of `odma_registers_tb`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `odma_registers_tb` | 40 (24 test cases; Direct Register Mode: TC-RG-02 in two configurations, TC-RG-12 in two, TC-RG-15 in three; Scatter/Gather Mode: TC-RG-16 in five, TC-RG-17 and TC-RG-18 in three, TC-RG-19 in three, TC-RG-20 in two, TC-RG-23 in two) | 40 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan and the compliance
matrix). VSG reports no errors and no warnings. The sources analyse with `ghdl -a --std=08` without `-frelaxed` and
without warnings, and synthesise with `ghdl --synth` without warnings and without latches in the configurations of
section 3.

Findings:

| Finding | Resolution |
| --- | --- |
| A channel accepts a command only while `Run` is '1'. A halt request while the command waited for `Cmd_Ready` would have lowered `Run` and left a command that is never accepted and a result that never comes | `Run` stays '1' until the command is accepted; the command is never withdrawn (architecture section 4.2). TC-RG-07 requests the halt while the command waits |
| A reset of `olo_axi_lite_slave` and of the read strobe register by the core reset would lose an access in progress at the start of the reset phase; a read would end with the timeout of the slave and SLVERR | Both are reset by `Rst` only; a read during the reset phase returns the reset values (architecture section 6) |
| PG021 does not describe `RS` = 1 written while the channel stops after a halt request | No effect, the channel halts (interpretation R8, RG-CR-01); TC-RG-03 |
| The other bits of a `DMACR` write with `Reset` = 1 would have started or reconfigured a channel for the duration of the drain | The write only starts the soft reset (RG-CR-06); TC-RG-10 |
| The verification plan counted SEC and DED events on buffer index 15, which has no buffer | Indices without a buffer of the configuration count nothing and take no injection (RG-EX-03, RG-EX-05); TC-RG-12 and TC-RG-13 check both |
| A reload of the threshold counter in the clock cycle of the `DMACR` write would load the old `IRQThreshold` | The reload is a registered pulse one clock cycle after the write, with the new value (architecture section 5); TC-RG-21 |
| PG021 leaves open what a `TAILDESC` write does while the channel stops after a halt request | It only stores the pointer, as while halted (RG-SG-03); TC-RG-18 |
| An error report of the engine in the clock cycle of a start would have left the channel in `Started_s` with `Run` = '0' | The error moves the channel to `Stopping_s` whenever the next state is `Started_s` (architecture section 4.3) |
| `S2MM_DMACR.Keyhole` can change while a transfer of Direct Register Mode runs | The S2MM command carries the bit as stored at the write of `S2MM_LENGTH` (RG-SG-11); the MM2S command never carries it (interpretation I1); TC-RG-24 |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `IncludeSg_g` | boolean | false, true | false (core), true (`odma_registers` alone: `AddrWidth_g` 32 and 64, `LengthWidth_g` 8 and 26, without the S2MM channel) |
| `IncludeMm2s_g`, `IncludeS2mm_g` | boolean | true, false | true, false |
| `ExtRegs_g` | boolean | true, false | true, false |
| `AddrWidth_g` | 32 to 64 | 32, 40, 64 | 32, 64 |
| `LengthWidth_g` | 8 to 26 | 8, 26 | 8, 14, 26 |
| `StsCntrlStrm_g`, `UseRxLength_g`, `MicroDma_g` | boolean, configuration readback only | true, false, true | false |
| `Mm2s*_g`, `S2mm*_g` (widths, burst beats, buffer beats) | configuration readback only; the ranges are checked by the core | the values of the verification plan, section 2 | the defaults |

## 4. Checks of the testbench

Each of the following faults, inserted into a copy of the RTL, fails at least one test case; the RTL of the repository
passes all of them:

| Fault | Failing test case |
| --- | --- |
| A clear of `IOC_Irq` wins over a result of the same clock cycle | TC-RG-09 |
| A write of 0 to `DMACR.IRQThreshold` is taken | TC-RG-02 |
| The command address follows the address register instead of the value at the length write | TC-RG-04 |
| The reset phase of a soft reset lasts 15 clock cycles | TC-RG-10 |
| All 16 ECC indices count | TC-RG-13 |
| The soft reset does not wait for `Stopped` | TC-RG-10 |
| `RS` = 1 starts a channel with an error flag set | TC-RG-08 |
| An S2MM slave error does not set `DMAIntErr` | TC-RG-08 |
| `Run` falls with the halt request before the command is accepted | TC-RG-07 |
| Register writes are taken during a soft reset | TC-RG-10 |
| `ECC_INJECT.Data` is not taken with the strobe | TC-RG-13 |
| The injection mode is not reset | TC-RG-13 |
| A tail pointer write passed to the engine while the channel stops | TC-RG-18 |
| `TAILDESC` starts the engine above 32 address bits | TC-RG-18 |
| `CURDESC` never reads the pointer of the engine | TC-RG-17 |
| No reload of the threshold counter by a write of the field, or at the start | TC-RG-21 |
| The threshold counter sets `IOC_Irq` one packet late | TC-RG-21 |
| `Halted` without the engine stopped | TC-RG-19 |
| `DMASR.Idle` not gated by the run state | TC-RG-19 |
| An S2MM transfer error with the slave code without `DMAIntErr`; `SGDecErr` set by the slave code; an engine error that does not clear `RS` | TC-RG-20 |
| `Dly_Irq` not cleared by writing 1 | TC-RG-22 |
| No reload of the threshold counter at a timeout; the start of a packet does not stop the timer; the timer started by a packet that set `IOC_Irq`; a delay unit of 124 or 126 clock cycles | TC-RG-22 |
| ECC index 7 counts without the S2MM channel; index 9 does not count | TC-RG-16 |

One fault is equivalent: `CURDESC` written while the channel runs. In every clock cycle of a running channel `CurOwn`
is forced to '1', so the stored value is never read; only a write while halted, which replaces the stored value,
makes it visible again. The condition on the state documents the rule of RG-SG-02.

The recovery branches of the state machines (`when others`) cannot be reached through the ports.
