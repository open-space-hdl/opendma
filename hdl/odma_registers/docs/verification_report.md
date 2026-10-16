# odma_registers: Verification Report

## 1. Test results

Run on 2026-10-16 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*odma_registers*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `odma_registers_tb` | 19 (15 test cases; TC-RG-02 in two configurations, TC-RG-12 in two, TC-RG-15 in three) | 19 |

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

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `IncludeSg_g` | false (true stops the elaboration, phase b) | false | false |
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

The recovery branches of the state machines (`when others`) cannot be reached through the ports.
