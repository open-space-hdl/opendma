# odma_core: Verification Plan

## 1. Overview

The core is verified as software and the system see it: through the register port, the two memory ports, the two
streams, the interrupt and the reset outputs. The register accesses, interrupt waits and stream packets of most
tests come from the model of the programming sequences (`tb/model/odma_model.py`, written from \[PG021\] chapter 4
independently of the RTL): the `pre_config` of each test writes the sequence, the memory image of the source buffers
and the expected memory of the destination buffers for the generics of its configuration into the output path of
the test, and the sequence player of `tb/odma_tb_seq_pkg.vhd` executes them. The data of the scenarios is random
without a period (`random_bytes` of the model), so that a byte at a wrong address or in a wrong lane differs from the
expected one. The expected memory contains, next to every S2MM packet, 16 bytes before and after it that must stay
unwritten, so that a write outside the packet fails the comparison. Tests observe only the ports of the core and its
registers; the expected values come from \[PG021\], the specifications and the model, never from the RTL.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `odma_core_tb` | `odma_core_th` | `odma_core`; the AXI4-Lite VVC on the register port; AXI memory model instance 0 (`MemRd_c`) on the MM2S read port, instance 1 (`MemWr_c`) on the S2MM write port, each with the maximum burst of its channel; the AXI4-Stream VVCs on the streams (instance 0 sends on the S2MM stream, instance 1 receives the MM2S stream); a second S2MM stream peer that sends one packet and abandons it when `S2mm_RstOut` rises, as a peer connected to the reset output does; monitors of the AXI4 bursts and responses, of read and write beats in the same clock cycle, of S2MM beats taken while `S2mm_RstOut` is high, and of the idle values of a channel that is not included (in every clock cycle after the reset) |

| VUnit configuration | Generics (others at their defaults) | Purpose |
| --- | --- | --- |
| `default` | none | The default configuration of the core: 32-bit addresses, length width 14, 32-bit memory and stream, bursts of 16 beats |
| `aw40` | `AddrWidth_g` 40, `LengthWidth_g` 26; MM2S 64/32 bits, bursts of 16; S2MM 128/64 bits, bursts of 32 | Addresses above 4 GB, the widest length, different widths per channel |
| `aw64` | `AddrWidth_g` 64, `LengthWidth_g` 20; MM2S 256/64 bits, bursts of 8; S2MM 512/256 bits, bursts of 4 | 64-bit addresses, wide memories, the widest stream of the VVC |
| `lw8` | `LengthWidth_g` 8; MM2S 128/8 bits, bursts of 4; S2MM 64/8 bits, bursts of 2 | The shortest length width, 8-bit streams, the shortest burst |
| `no_ext` | `ExtRegs_g` false | Core without the extension window |
| `mm2s_only` | `IncludeS2mm_g` false | Configuration without the S2MM channel |
| `s2mm_only` | `IncludeMm2s_g` false | Configuration without the MM2S channel |

The data buffers hold four bursts. Stream widths stay at or below 256 bits, the limit of the AXI4-Stream VVC; the unit
benches of the channels simulate the wider streams and every width pair. Each test runs in the configurations its
function needs:

| Test | Configurations |
| --- | --- |
| `test_dr_reference` | `aw40`, `aw64` (addresses above 32 bits) |
| `test_dr_random`, `test_concurrent`, `test_errors`, `test_soft_reset_load` | `default`, `aw40`, `aw64`, `lw8`, `no_ext` |
| `test_ecc_index`, `test_configuration` | all |
| `test_ecc_data` | `default`, `aw40`, `aw64`, `mm2s_only`, `s2mm_only` (extension window and streams of at least 16 bits, so that the length consequence keeps the number of beats) |
| `test_excluded_channel` | `mm2s_only`, `s2mm_only` |

The memory model responds SLVERR to reads from 0x4_0000 to 0x4_0FFF and to writes from 0x5_0000 to 0x5_0FFF in
`test_errors` (the regions `ERR_READ_BASE` and `ERR_WRITE_BASE` of the model). Clock 100 MHz. Simulators: GHDL;
QuestaSim with and without code coverage in the batch of phase a.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_dr_reference` (TC-CO-01) | The reference scenario of the model (`dr_reference`, the scenario of the golden files of `odma_pkg`): soft reset, one MM2S and one S2MM transfer with interrupt at unaligned addresses above 4 GB, the S2MM buffer longer than the packet, one MM2S transfer by polling | CO-SQ-01, CO-SQ-02, CO-CF-01 |
| `test_dr_random` (TC-CO-02) | Scenario `dr_random`: 12 transfers of random channels, among them 1 byte and the longest length (2**`LengthWidth_g` - 1, at most 16384 bytes), random unaligned addresses, 40 % of them across a 4 KB boundary, above 32 address bits half of them in the region with the most significant address bit set, completion by interrupt or by polling, S2MM buffers as long as or longer than the packet; then a halt and a restart of each channel with one more transfer; both memory models with 30 % stall and a latency of 8 cycles | CO-IF-01, CO-IF-02, CO-CF-01, CO-SQ-01, CO-SQ-02, CO-SQ-04 |
| `test_concurrent` (TC-CO-03) | Scenario `dr_concurrent`: four pairs of MM2S and S2MM transfers of 8000 bytes (at most the longest length), both programmed before the first completion is awaited, three by interrupt and one by polling; a read beat and a write beat in the same clock cycle are observed | CO-SQ-03 |
| `test_errors` (TC-CO-04) | Scenario `dr_errors`: an MM2S read with SLVERR (the packet still sent, `DMASlvErr`), an S2MM write with SLVERR (`DMASlvErr` and `DMAIntErr`), an S2MM packet longer than its buffer (`DMAIntErr`, no byte beyond the buffer), MM2S and S2MM buffers beyond the top of the address space (`DMADecErr`, S2MM also `DMAIntErr`, no access, no stream data); each error with `Err_Irq`, the interrupt output, `DMASR.Halted` after the interrupt and the write-one-to-clear of `Err_Irq`; after each error a transfer of the other channel without a reset, then a soft reset that clears the flags; finally a transfer of each channel | CO-ER-01, CO-ER-02, CO-SQ-03 |
| `test_soft_reset_load` (TC-CO-05) | Both memory models with a latency of 100 cycles and 50 % stall; an MM2S transfer whose stream peer takes nothing and an S2MM packet of three data buffers from the resettable stream peer; with read and write bursts outstanding and the peer in the middle of its packet, a soft reset: both reset outputs high during the reset, every accepted burst completed or answered, no burst after the reset, no S2MM beat taken while `S2mm_RstOut` is high, the peer abandoned its packet, `DMACR` and `DMASR` of both channels at their reset values; then scenario `after_reset` (a reset and four random transfers) without stall: no beat of the interrupted transfers appears | CO-RS-01 |
| `test_ecc_index` (TC-CO-06) | For each buffer index 0 to 6: counters and flags cleared, `ECC_ENABLE` = SEC, a single error injected at the index, one transfer of 256 bytes (at most the longest length) through the channel of the index; the SEC counter of the index counts, the DED counter stays 0, every other counter stays 0, `ECC_STATUS` shows the SEC flag and `Ecc_Irq` rises; index 6 (no buffer in DR mode), indices of an excluded channel and the configuration without the extension window count nothing and keep `Ecc_Irq` low; the transfer data is correct. Then for each index 0 to 5 of an included channel: a single error injected, a soft reset, a transfer through the channel: no counter counts (the reset cancelled the pending injection) | CO-FT-01, CO-RS-01 |
| `test_ecc_data` (TC-CO-10) | Error injections in data mode (`ECC_INJECT.Data`), a single and then a double error into every buffer of the included channels, after a soft reset each. MM2S: the error is injected before a transfer of 254 bytes from an aligned buffer, so it goes into its first read data word (index 0), its entry (index 4) or its response (index 5). S2MM: packet A of 62 bytes waits in the data buffer before the error is injected and its transfer programmed, packet B of 62 bytes follows, both into buffers of 128 bytes; the error goes into the write data of A (index 3), the first data word of B (index 1) or the chunk entry of B (index 2). A single error leaves every packet, length and result unchanged and counts one SEC at its index. A double error counts one DED at its index and has the consequence of its buffer: index 0 byte 0 of the MM2S packet with bits 0 and 1 inverted; index 4 a packet of 253 bytes; index 5 a complete packet and the transfer halted with `DMADecErr`; index 3 byte 0 of packet A inverted in bits 0 and 1; index 1 byte 0 of packet B inverted; index 2 packet B of 61 bytes in memory and in `S2MM_LENGTH`. The other counters stay 0 | CO-FT-01, CO-FT-02 |
| `test_configuration` (TC-CO-07) | `DMACR` and `DMASR` reset values of both channels (0 for an excluded channel); `EXT_ID`, `EXT_CONFIG`, `EXT_MM2S_CONFIG`, `EXT_S2MM_CONFIG` and `ECC_INFO` against the generics (0 without the extension window); the address registers and the MSB registers hold `AddrWidth_g` bits, the length registers `LengthWidth_g` bits; a length written while the channel is halted starts no memory access | CO-CF-01, CO-FT-01 |
| `test_excluded_channel` (TC-CO-08) | The registers of the excluded channel read 0 after writes (start, address, length) and start nothing; the scenario `single_channel` (six random transfers, a halt and a restart) runs on the included channel; no access of the excluded channel; the idle monitor of the harness checks every port of the excluded channel in every clock cycle | CO-CF-03 |
| `lint/synth_check.py` (TC-CO-09) | GHDL synthesis of the core in its boundary configurations (address and length widths 32/8 and 64/26, every memory width with an 8-bit stream and the shortest burst, equal widths 32 and 1024 with the longest burst, different channel configurations, buffers of two bursts, each channel excluded, no extension window) without errors and inferred latches; each inconsistent configuration (no channel, `IncludeSg_g`, `StsCntrlStrm_g`, `UseRxLength_g`, `MicroDma_g`, a memory width that is not a power of two, a stream wider than the memory, a burst size that is not a power of two, a buffer of less than two bursts) stops the elaboration with the message of its check | CO-CF-01, CO-CF-02 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| CO-IF-01 | TC-CO-02 |
| CO-IF-02 | TC-CO-02 |
| CO-CF-01 | TC-CO-01, TC-CO-02, TC-CO-07, TC-CO-09 |
| CO-CF-02 | TC-CO-09 |
| CO-CF-03 | TC-CO-08 |
| CO-SQ-01, CO-SQ-02 | TC-CO-01, TC-CO-02 |
| CO-SQ-03 | TC-CO-03, TC-CO-04 |
| CO-SQ-04 | TC-CO-02 |
| CO-ER-01, CO-ER-02 | TC-CO-04 |
| CO-RS-01 | TC-CO-05, TC-CO-06 |
| CO-FT-01 | TC-CO-06, TC-CO-07, TC-CO-10 |
| CO-FT-02 | TC-CO-10 |

## 5. Negative tests

| Check or error path | Test |
| --- | --- |
| Read and write error responses, buffers beyond the top of the address space, S2MM packet longer than its buffer | TC-CO-04 |
| Soft reset with outstanding transactions and a stream peer in the middle of a packet | TC-CO-05 |
| Error injection into every FT buffer, injection at an index without a buffer, injection cancelled by a soft reset | TC-CO-06 |
| Single and double errors on data bits of every FT buffer: correction of a data bit, consequence of a double error | TC-CO-10 |
| Writes to the registers of an excluded channel; idle values of its ports | TC-CO-08 |
| Inconsistent configurations | TC-CO-09 |
| Writes outside an S2MM packet (unwritten bytes around every packet in the expected memory) | TC-CO-02 to TC-CO-06, TC-CO-08 |
