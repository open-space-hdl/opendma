# odma_registers: Verification Plan

## 1. Overview

The register interface is verified through its ports: register accesses through the AXI4-Lite VVC, the transfer
commands and results through a channel model per channel in the harness, the interrupt, reset and ECC ports by the
bench. The channel model accepts commands with a configurable delay, records them for the checks, returns results
with configurable bytes, error code and end of packet and reports `Stopped` after a configurable drain time. Expected
register values are written in the bench from the specification, independently of the generated register package.

Objectives:

- every field of PG021 Table 5 and of the extension window: offset, reset value, access type, width limits;
- the DR state machine of both channels: start, transfer, completion, halt, errors, the rules for length writes;
- interrupt flags, their write-one-to-clear including the coincidence with an event, the interrupt outputs;
- soft and hard reset with the drain handshake, the reset outputs and their minimum length;
- ECC counters, flags, `Ecc_Irq` and the error injection strobes;
- the configurations of the generics that change the module.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `odma_registers_tb` | `odma_registers_th` | `odma_registers`; AXI4-Lite VVC on `S_AxiLite_*`; one channel model per channel on the command, result and control ports; `Ecc_Sec`, `Ecc_Ded` driven by the bench; `EccInj_*`, interrupt and reset outputs observed |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `default` | `AddrWidth_g` 40, `LengthWidth_g` 26, both channels, `ExtRegs_g` true | All tests |
| `narrow` | `AddrWidth_g` 32, `LengthWidth_g` 8 | Width limits (TC-RG-02, TC-RG-14, TC-RG-15) |
| `wide` | `AddrWidth_g` 64 | Address registers (TC-RG-14) |
| `no_mm2s`, `no_s2mm` | `IncludeMm2s_g` or `IncludeS2mm_g` false | TC-RG-11 |
| `no_ext` | `ExtRegs_g` false | TC-RG-13 |

Clock 100 MHz. Simulators: GHDL; QuestaSim with and without code coverage in the batch of phase a.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_reset_values` (TC-RG-01) | Every register of Table 5 and of the extension window after the reset, the reserved offsets 0x08 to 0x14, 0x2C, 0x38 to 0x44 and a sample of unmapped offsets read 0 with OKAY; the bit order of a register (a pattern written to `MM2S_SA` reads back bit for bit) | RG-IF-01, RG-IF-02, RG-IF-04, RG-MAP-01, RG-MAP-04, RG-CR-03, RG-SR-03, RG-SR-04, RG-SR-07, RG-EX-01, RG-EX-02 |
| `test_access` (TC-RG-02) | Read/write fields read back, read-only fields and reserved bits ignore writes, writes to unmapped offsets have no effect, a write with partial strobes takes all 32 bits, `IRQThreshold` ignores 0, the stored DR-mode fields (`Keyhole`, `CyclicBD`, `Dly_IrqEn`, `IRQDelay`) have no effect on the commands and interrupts, the interrupt enables read back | RG-IF-02, RG-IF-03, RG-MAP-02, RG-CR-04, RG-CR-05 |
| `test_start_halt` (TC-RG-03) | `RS` = 1: `Halted` falls, `Idle` stays 0, `Run` rises; `RS` = 0: `Run` falls, `Halted` rises only after `Stopped`, with a drain time of 0 and of 50 cycles; both channels independently | RG-CR-01, RG-SR-01, RG-SR-02 |
| `test_mm2s_transfer` (TC-RG-04) | Address, address MSB and length produce one command with the address, the length, start and end of packet and keyhole '0'; `Idle` 0 while busy and 1 after the result; `IOC_Irq` set, `Mm2s_Irq` with and without `IOC_IrqEn`, cleared by writing one; an address write during the transfer leaves the command unchanged; three transfers in a row | RG-AR-04, RG-AR-08, RG-SR-02, RG-IR-01, RG-IR-03, RG-IR-04 |
| `test_s2mm_transfer` (TC-RG-05) | Destination and buffer length produce one command; a result with 29 bytes and end of packet sets `S2MM_LENGTH` to 29, `Idle` and `IOC_Irq`; `S2mm_Irq` | RG-AR-05, RG-AR-06, RG-IR-01, RG-IR-04 |
| `test_length_rules` (TC-RG-06) | A length of 0 has no effect; a length write while busy has no effect (one command only, the register unchanged); a length write while halted is stored and read back and produces no command, also not after the start | RG-AR-07 |
| `test_halt_during_transfer` (TC-RG-07) | `RS` = 0 while busy: no new command; an MM2S result with end of packet raises `IOC_Irq`; an S2MM result without end of packet raises no `IOC_Irq` and keeps `S2MM_LENGTH`; `Halted` after `Stopped` | RG-CR-01, RG-SR-01, RG-IR-01, RG-AR-06 |
| `test_errors` (TC-RG-08) | MM2S results with SLVERR and DECERR set `DMASlvErr` and `DMADecErr`, clear `RS`, set `Err_Irq` and `Mm2s_Irq` with `Err_IrqEn`, `Halted` after `Stopped`; an S2MM internal error sets `DMAIntErr`, an S2MM slave error sets `DMASlvErr` and `DMAIntErr`; `RS` = 1 has no effect while a flag is set; writing ones to the flags does not clear them; a soft reset clears them | RG-CR-01, RG-CR-02, RG-SR-05, RG-SR-06, RG-IR-02, RG-IR-04 |
| `test_irq_clear_race` (TC-RG-09) | A result is returned 0 to 8 clock cycles after the write handshake of a write-one-to-clear of `IOC_Irq`; from the documented write latency (architecture section 9) on, the flag stays set; before it, the flag is clear after the write | RG-IR-03 |
| `test_soft_reset` (TC-RG-10) | `DMACR.Reset` of each channel in turn: both `Reset` bits read 1, `Drain` rises on both channels, the reset outputs rise; `CoreRst` follows only after both channels report `Stopped` (drain times 0 and 100 cycles); the reset outputs stay high for at least 16 cycles; register writes during the reset have no effect; afterwards every register has its reset value | RG-CR-06, RG-RS-02, RG-RS-03, RG-RS-04 |
| `test_hard_reset` (TC-RG-11) | `Rst` in the middle of a transfer: reset outputs high during `Rst`, all registers at their reset values afterwards | RG-RS-01 |
| `test_excluded_channel` (TC-RG-12) | Configurations `no_mm2s` and `no_s2mm`: the registers of the excluded channel read 0 and ignore writes, its control outputs stay idle; the other channel works | RG-MAP-03 |
| `test_ecc` (TC-RG-13) | SEC and DED pulses on buffer indices 0, 3 and 15 increment their counters; a write to a counter word clears it; `ECC_CTRL` clears all; `ECC_STATUS` flags and `Ecc_Irq` with and without the enables; an event in the clock cycle of a clear is counted; `ECC_INJECT` raises exactly one `EccInj_Valid` strobe on the selected index with `EccInj_Double` as requested | RG-EX-03, RG-EX-04, RG-EX-05 |
| `test_no_extension` (TC-RG-14) | Configuration `no_ext`: the extension window reads 0, writes to it have no effect, `Ecc_Irq` stays low and no injection strobe appears | RG-MAP-04 |
| `test_widths` (TC-RG-15) | Configurations `narrow`, `default`, `wide`: the bits of the address MSB registers above `AddrWidth_g` and of the length registers above `LengthWidth_g` read 0; commands carry the full address and the written length | RG-AR-01, RG-AR-02, RG-AR-03 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| RG-IF-01, RG-IF-04 | TC-RG-01 |
| RG-IF-02 | TC-RG-01, TC-RG-02 |
| RG-IF-03 | TC-RG-02 |
| RG-MAP-01 | TC-RG-01 |
| RG-MAP-02 | TC-RG-02 |
| RG-MAP-03 | TC-RG-12 |
| RG-MAP-04 | TC-RG-01, TC-RG-14 |
| RG-CR-01 | TC-RG-03, TC-RG-07, TC-RG-08 |
| RG-CR-02 | TC-RG-08 |
| RG-CR-03 | TC-RG-01 |
| RG-CR-04, RG-CR-05 | TC-RG-02 |
| RG-CR-06 | TC-RG-10 |
| RG-SR-01 | TC-RG-03, TC-RG-07 |
| RG-SR-02 | TC-RG-03, TC-RG-04 |
| RG-SR-03, RG-SR-04, RG-SR-07 | TC-RG-01 |
| RG-SR-05, RG-SR-06 | TC-RG-08 |
| RG-AR-01, RG-AR-02, RG-AR-03 | TC-RG-15 |
| RG-AR-04, RG-AR-08 | TC-RG-04 |
| RG-AR-05 | TC-RG-05 |
| RG-AR-06 | TC-RG-05, TC-RG-07 |
| RG-AR-07 | TC-RG-06 |
| RG-RS-01 | TC-RG-11 |
| RG-RS-02, RG-RS-03, RG-RS-04 | TC-RG-10 |
| RG-IR-01 | TC-RG-04, TC-RG-05, TC-RG-07 |
| RG-IR-02 | TC-RG-08 |
| RG-IR-03 | TC-RG-04, TC-RG-09 |
| RG-IR-04 | TC-RG-04, TC-RG-05, TC-RG-08 |
| RG-EX-01, RG-EX-02 | TC-RG-01 |
| RG-EX-03, RG-EX-04, RG-EX-05 | TC-RG-13 |

## 5. Negative tests

| Check or error path | Test |
| --- | --- |
| Error codes of the results: SLVERR, DECERR, internal error, slave error with internal error | TC-RG-08 |
| Start refused while an error flag is set | TC-RG-08 |
| Length writes that must not start a transfer (zero, busy, halted) | TC-RG-06 |
| Writes during a soft reset | TC-RG-10 |
| Accesses to unmapped and reserved offsets | TC-RG-01, TC-RG-02 |

The recovery of the state machines from an illegal state (`when others`) cannot be reached through the ports; it is
reviewed in the code and listed in the coverage report.
