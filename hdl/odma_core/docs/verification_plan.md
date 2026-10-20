# odma_core: Verification Plan

## 1. Overview

The core is verified as software and the system see it: through the register port, the two memory ports, the two
streams, the interrupt and the reset outputs. The register accesses, interrupt waits and stream packets of most
tests come from the model of the programming sequences (`tb/model/odma_model.py`, written from \[PG021\] chapter 4
independently of the RTL): the `pre_config` of each test writes the sequence, the memory image of the source buffers
and the expected memory of the destination buffers for the generics of its configuration into the output path of
the test, and the sequence player of `tb/odma_tb_seq_pkg.vhd` executes them. In Scatter/Gather Mode the model also
writes the memory image of the descriptor chains and the expected descriptors with their status words; the bench
loads and checks them in the memory model of the descriptor port. The data of the scenarios is random
without a period (`random_bytes` of the model), so that a byte at a wrong address or in a wrong lane differs from the
expected one. The expected memory contains, next to every S2MM packet, 16 bytes before and after it that must stay
unwritten, so that a write outside the packet fails the comparison. Tests observe only the ports of the core and its
registers; the expected values come from \[PG021\], the specifications and the model, never from the RTL.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `odma_core_tb` | `odma_core_th` | `odma_core`; the AXI4-Lite VVC on the register port; AXI memory model instance 0 (`MemRd_c`) on the MM2S read port, instance 1 (`MemWr_c`) on the S2MM write port, each with the maximum burst of its channel; the AXI4-Stream VVCs on the streams (instance 0 sends on the S2MM stream, instance 1 receives the MM2S stream); a second S2MM stream peer that sends one packet and abandons it when `S2mm_RstOut` rises, as a peer connected to the reset output does; AXI memory model instance 2 (`MemSg_c`) on the descriptor port, bursts of at most 16 beats; monitors of the AXI4 bursts and responses of all three memory ports, of read and write beats in the same clock cycle, of S2MM beats taken while `S2mm_RstOut` is high, of the idle values of a channel that is not included and, in DR mode, of the idle descriptor port (in every clock cycle after the reset) |

| VUnit configuration | Generics (others at their defaults) | Purpose |
| --- | --- | --- |
| `default` | none | The default configuration of the core: 32-bit addresses, length width 14, 32-bit memory and stream, bursts of 16 beats |
| `aw40` | `AddrWidth_g` 40, `LengthWidth_g` 26; MM2S 64/32 bits, bursts of 16; S2MM 128/64 bits, bursts of 32 | Addresses above 4 GB, the widest length, different widths per channel |
| `aw64` | `AddrWidth_g` 64, `LengthWidth_g` 20; MM2S 256/64 bits, bursts of 8; S2MM 512/256 bits, bursts of 4 | 64-bit addresses, wide memories, the widest stream of the VVC |
| `lw8` | `LengthWidth_g` 8; MM2S 128/8 bits, bursts of 4; S2MM 64/8 bits, bursts of 2 | The shortest length width, 8-bit streams, the shortest burst |
| `no_ext` | `ExtRegs_g` false | Core without the extension window |
| `mm2s_only` | `IncludeS2mm_g` false | Configuration without the S2MM channel |
| `s2mm_only` | `IncludeMm2s_g` false | Configuration without the MM2S channel |
| `sg` | `IncludeSg_g` true | Scatter/Gather Mode in the default configuration |
| `sg_aw64` | `IncludeSg_g` true, the other generics of `aw64` | Descriptors and buffers above 32 address bits, wide memories and streams |
| `sg_lw8` | `IncludeSg_g` true, the other generics of `lw8` | The shortest length width and 8-bit streams in Scatter/Gather Mode |
| `sg_mm2s_only` | `IncludeSg_g` true, `IncludeS2mm_g` false | Engine with the MM2S channel only |
| `sg_s2mm_only` | `IncludeSg_g` true, `IncludeMm2s_g` false | Engine with the S2MM channel only |

The data buffers hold four bursts. Stream widths stay at or below 256 bits, the limit of the AXI4-Stream VVC; the unit
benches of the channels simulate the wider streams and every width pair. Each test runs in the configurations its
function needs:

| Test | Configurations |
| --- | --- |
| `test_dr_reference` | `aw40`, `aw64` (addresses above 32 bits) |
| `test_dr_random`, `test_concurrent`, `test_errors`, `test_soft_reset_load` | `default`, `aw40`, `aw64`, `lw8`, `no_ext` |
| `test_ecc_index` | the seven DR configurations |
| `test_configuration` | all |
| `test_ecc_data` | `default`, `aw40`, `aw64`, `mm2s_only`, `s2mm_only` (extension window and streams of at least 16 bits, so that the length consequence keeps the number of beats) |
| `test_excluded_channel` | `mm2s_only`, `s2mm_only` |
| `test_sg_reference`, `test_sg_tail_moves`, `test_sg_cyclic`, `test_sg_errors`, `test_sg_delay`, `test_sg_soft_reset`, `test_sg_ecc_index`, `test_sg_multi_buffer` | the five SG configurations |
| `test_sg_boundary_rate`, `test_sg_write_overlap` | the four SG configurations with the S2MM channel |
| `test_keyhole` | `default`, `aw64`, `s2mm_only` and the five SG configurations |

The memory model responds SLVERR to reads from 0x4_0000 to 0x4_0FFF and to writes from 0x5_0000 to 0x5_0FFF in
`test_errors` (the regions `ERR_READ_BASE` and `ERR_WRITE_BASE` of the model), DECERR to reads from 0x4_1000 to 0x4_1FFF
and to writes from 0x5_1000 to 0x5_1FFF, and the descriptor memory SLVERR to reads from 0x6_0000 to 0x6_0FFF and to
writes from 0x7_0000 to 0x7_0FFF in `test_sg_errors` (`ERR_DESC_READ_BASE` and `ERR_DESC_WRITE_BASE`), DECERR from
0x6_1000 and 0x7_1000 on. The descriptor chains of the model are rings at 64-byte aligned addresses 0x1C0 apart, so that
they cross 4 KB boundaries; their buffers are unaligned, some across a 4 KB boundary, and each holds one packet (MM2S
descriptors with `TXSOF` and `TXEOF`, S2MM packets of at most the buffer length), except in `test_sg_multi_buffer` and
`test_sg_boundary_rate`. Clock 100 MHz. Simulators: GHDL; QuestaSim with and without code coverage in the batches of
phases a and b.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_dr_reference` (TC-CO-01) | The reference scenario of the model (`dr_reference`, the scenario of the golden files of `odma_pkg`): soft reset, one MM2S and one S2MM transfer with interrupt at unaligned addresses above 4 GB, the S2MM buffer longer than the packet, one MM2S transfer by polling | CO-SQ-01, CO-SQ-02, CO-CF-01 |
| `test_dr_random` (TC-CO-02) | Scenario `dr_random`: 12 transfers of random channels, among them 1 byte and the longest length (2**`LengthWidth_g` - 1, at most 16384 bytes), random unaligned addresses, 40 % of them across a 4 KB boundary, above 32 address bits half of them in the region with the most significant address bit set, completion by interrupt or by polling, S2MM buffers as long as or longer than the packet; then a halt and a restart of each channel with one more transfer; both memory models with 30 % stall and a latency of 8 cycles | CO-IF-01, CO-IF-02, CO-CF-01, CO-SQ-01, CO-SQ-02, CO-SQ-04 |
| `test_concurrent` (TC-CO-03) | Scenario `dr_concurrent`: four pairs of MM2S and S2MM transfers of 8000 bytes (at most the longest length), both programmed before the first completion is awaited, three by interrupt and one by polling; the read memory model with a latency of 50 cycles, so that the read data arrive while S2MM writes also where the MM2S buffers hold a whole transfer (`lw8`); a read beat and a write beat in the same clock cycle are observed | CO-SQ-03 |
| `test_errors` (TC-CO-04) | Scenario `dr_errors`: an MM2S read with SLVERR (the packet still sent, `DMASlvErr`) and one with DECERR (`DMADecErr`), an S2MM write with SLVERR (`DMASlvErr` and `DMAIntErr`) and one with DECERR (`DMADecErr` and `DMAIntErr`), an S2MM packet longer than its buffer (`DMAIntErr`, no byte beyond the buffer), MM2S and S2MM buffers beyond the top of the address space (`DMADecErr`, S2MM also `DMAIntErr`, no access, no stream data); each error with `Err_Irq`, the interrupt output, `DMASR.Halted` after the interrupt and the write-one-to-clear of `Err_Irq`; after each error a transfer of the other channel without a reset, then a soft reset that clears the flags; finally a transfer of each channel | CO-ER-01, CO-ER-02, CO-SQ-03 |
| `test_soft_reset_load` (TC-CO-05) | Both memory models with a latency of 100 cycles and 50 % stall; an MM2S transfer whose stream peer takes nothing and an S2MM packet of three data buffers from the resettable stream peer; with read and write bursts outstanding and the peer in the middle of its packet, a soft reset: both reset outputs high during the reset, every accepted burst completed or answered, no burst after the reset, no S2MM beat taken while `S2mm_RstOut` is high, the peer abandoned its packet, `DMACR` and `DMASR` of both channels at their reset values; then scenario `after_reset` (a reset and four random transfers) without stall: no beat of the interrupted transfers appears | CO-RS-01 |
| `test_ecc_index` (TC-CO-06) | For each buffer index 0 to 6: counters and flags cleared, `ECC_ENABLE` = SEC, a single error injected at the index, one transfer of 256 bytes (at most the longest length) through the channel of the index; the SEC counter of the index counts, the DED counter stays 0, every other counter stays 0, `ECC_STATUS` shows the SEC flag and `Ecc_Irq` rises; index 6 (no buffer in DR mode), indices of an excluded channel and the configuration without the extension window count nothing and keep `Ecc_Irq` low; the transfer data is correct. Then for each index 0 to 5 of an included channel: a single error injected, a soft reset, a transfer through the channel: no counter counts (the reset cancelled the pending injection) | CO-FT-01, CO-RS-01 |
| `test_ecc_data` (TC-CO-10) | Error injections in data mode (`ECC_INJECT.Data`), a single and then a double error into every buffer of the included channels, after a soft reset each. MM2S: the error is injected before a transfer of 254 bytes from an aligned buffer, so it goes into its first read data word (index 0), its entry (index 4) or its response (index 5). S2MM: packet A of 62 bytes waits in the data buffer before the error is injected and its transfer programmed, packet B of 62 bytes follows, both into buffers of 128 bytes; the error goes into the write data of A (index 3), the first data word of B (index 1) or the chunk entry of B (index 2). A single error leaves every packet, length and result unchanged and counts one SEC at its index. A double error counts one DED at its index and has the consequence of its buffer: index 0 byte 0 of the MM2S packet with bits 0 and 1 inverted; index 4 a packet of 253 bytes; index 5 a complete packet and the transfer halted with `DMADecErr`; index 3 byte 0 of packet A inverted in bits 0 and 1; index 1 byte 0 of packet B inverted; index 2 packet B of 61 bytes in memory and in `S2MM_LENGTH`. The other counters stay 0 | CO-FT-01, CO-FT-02 |
| `test_configuration` (TC-CO-07) | `DMACR` and `DMASR` reset values of both channels (0 for an excluded channel, `SGIncld` with `IncludeSg_g`); `EXT_ID`, `EXT_CONFIG`, `EXT_MM2S_CONFIG`, `EXT_S2MM_CONFIG` and `ECC_INFO` against the generics (0 without the extension window). DR mode: the address registers and the MSB registers hold `AddrWidth_g` bits, the length registers `LengthWidth_g` bits; a length written while the channel is halted starts no memory access. SG mode: `CURDESC`, `TAILDESC` and their MSB registers hold `AddrWidth_g` bits without bits 5 to 0, the length registers read 0; the pointer writes of a halted channel start no access on any memory port. In DR mode the monitor of the harness checks the idle descriptor port in every test | CO-CF-01, CO-FT-01, CO-SG-01 |
| `test_excluded_channel` (TC-CO-08) | The registers of the excluded channel read 0 after writes (start, address, length) and start nothing; the scenario `single_channel` (six random transfers, a halt and a restart) runs on the included channel; no access of the excluded channel; the idle monitor of the harness checks every port of the excluded channel in every clock cycle | CO-CF-03 |
| `lint/synth_check.py` (TC-CO-09) | GHDL synthesis of the core in its boundary configurations (address and length widths 32/8 and 64/26, every memory width with an 8-bit stream and the shortest burst, equal widths 32 and 1024 with the longest burst, different channel configurations, buffers of two bursts, each channel excluded, no extension window; in SG mode the default configuration, address and length widths 32/8 and 64/26, each channel excluded, equal widths 1024 with the longest burst and a 32-bit memory with an 8-bit stream and the shortest burst, so that the stream join and split are synthesised at the widest and at the narrowest stream) without errors and inferred latches; each inconsistent configuration (no channel, `StsCntrlStrm_g`, `UseRxLength_g`, `MicroDma_g`, a memory width that is not a power of two, a stream wider than the memory, a burst size that is not a power of two, a buffer of less than two bursts) stops the elaboration with the message of its check | CO-CF-01, CO-CF-02, CO-SG-01 |
| `test_sg_reference` (TC-CO-11) | Scenario `sg_reference`: soft reset, then per channel the Scatter/Gather programming sequence (\[PG021\] chapter 4: `CURDESC`, `DMACR` with `RS`, `IOC_IrqEn`, `Err_IrqEn` and the threshold 1, `Halted` polled to 0, `TAILDESC`; above 32 address bits the MSB words, the upper word last) for a chain of four descriptors above 32 address bits when the address width allows; MM2S sends every buffer as one packet, S2MM writes every packet into its buffer with 16 unwritten bytes before and after it; afterwards `Idle`, `IOC_Irq` set and cleared by writing one, the interrupt output low, `CURDESC` at the tail; the status of every descriptor in the descriptor memory (transferred bytes, `RXSOF` and `RXEOF` of S2MM, `Cmplt`), no other descriptor word changed | CO-SG-02, CO-SG-03 |
| `test_sg_tail_moves` (TC-CO-12) | Scenario `sg_tail_moves`: chains of 12 descriptors per channel, both channels started with the threshold 2; the tail pointer of each channel moved by one to four descriptors at a time, while the engine still works or, after about half of the rounds, once both engines have reached the tail (`Idle` polled); MM2S and S2MM memory with 20 % stall, the descriptor memory with 30 % stall and a latency of 6 cycles; every packet in order and in memory, every status written, `CURDESC` at the last descriptor | CO-SG-04, CO-SG-02, CO-SG-03 |
| `test_sg_cyclic` (TC-CO-13) | Scenario `sg_cyclic`: rings of three descriptors per channel with `CyclicBD`, the tail pointer at the second descriptor; two laps per channel (the S2MM packets of the first lap with other bytes of the same lengths, so that the buffers hold those of the last lap), the status of every descriptor after the last lap; the S2MM channel halted after its last packet (`CURDESC` at the first descriptor, which was not started, `odma_sg` SGI-10), the MM2S channel, which is sending its third lap, stopped by a soft reset | CO-SG-05 |
| `test_sg_errors` (TC-CO-14) | Scenario `sg_errors`, per channel after a soft reset each: a descriptor fetch with SLVERR (`SGSlvErr`; MM2S the second descriptor, after the packet of the first, which sets `IOC_Irq`; S2MM the first descriptor) and one with DECERR (`SGDecErr`, the same positions), a stale descriptor (`SGIntErr`, the same positions), a buffer length of 0 (`DMAIntErr` in `DMASR` and bit 28 in the status, `Cmplt` 0), a status write with SLVERR (`SGSlvErr`, no `IOC_Irq`) and one with DECERR (`SGDecErr`); each with `Err_Irq`, the interrupt output, `Halted`, `CURDESC` at the descriptor of the error and the write-one-to-clear of `Err_Irq`; the descriptor memory unchanged except the statuses written; a soft reset at the end and the flags cleared | CO-SG-06 |
| `test_sg_delay` (TC-CO-16) | Scenarios `sg_delay` and `sg_delay_overlap`, threshold 2, `IRQDelay` 4 (500 clock cycles) with `Dly_IrqEn`, per channel. The stream VVCs pause every packet after its first beat. With a pause of 1500 clock cycles: one packet, then `Dly_Irq` and the interrupt output when the timer expires, no `IOC_Irq`; a second packet that completes, the threshold counter at 1 (`IRQThresholdSts`), then a third packet that starts after this completion and pauses longer than the delay: `IOC_Irq` at its completion and no `Dly_Irq`, also 1000 clock cycles later. With a pause of 400 clock cycles: two packets back to back, the first completes during the pause of the second, which then runs for at least 250 beats: `Dly_Irq` is set, `IOC_Irq` is not, the threshold counter reads 1 | CO-SG-07 |
| `test_sg_soft_reset` (TC-CO-17) | All three memories with a latency of 100 cycles and 50 % stall; chains of four descriptors per channel started, the MM2S stream peer takes nothing, the resettable peer of the harness sends one S2MM packet; a soft reset when a descriptor access is outstanding, then, after a restart, a soft reset when data bursts are outstanding (S2MM writes; MM2S reads without S2MM) and no descriptor access: after each, every accepted burst of the three ports completed or answered, no burst after the reset, no S2MM beat taken while `S2mm_RstOut` is high, the peer has ended its packet, `DMACR` and `DMASR` at their reset values; then scenario `sg_reference` without stall | CO-SG-08 |
| `test_sg_ecc_index` (TC-CO-15) | For each index 6 to 9: soft reset, counters and flags cleared, `ECC_ENABLE` = SEC, a single error injected at the index, scenario `sg_reference` without its soft reset (which would cancel the injection); the SEC counter of the index counts one when its buffer exists (6 with MM2S, 7 with S2MM, 8 and 9 always), every other counter stays 0; the chains are transferred correctly | CO-FT-01 |
| `test_sg_multi_buffer` (TC-CO-18) | Scenario `sg_multi_buffer`: per channel a chain of 12 descriptors forming packets of one to five descriptors, each buffer at a random unaligned address and of a random length (among them 1 byte), the threshold 1. MM2S: every packet one stream packet, `TLast` only at its end, the status of every descriptor written, one `IOC_Irq` per packet. S2MM: packets of random lengths over one to four buffers, one packet that ends exactly at a buffer end and one packet without bytes; the statuses with the bytes of each buffer, `RXSOF` in the first, `RXEOF` in the last (both in the buffer of the packet without bytes), 16 unwritten bytes around every buffer. Then an MM2S packet of three descriptors with the tail at the first one and a halt after its transfer: the packet ends with `TLast` on its last byte before `DMASR.Halted` is set. The S2MM write error inside a packet of several buffers is TC-CO-21 | CO-SG-09, CO-SG-10, CO-SG-12 |
| `test_keyhole` (TC-CO-19) | Scenario `keyhole`: S2MM transfers with `S2MM_DMACR.Keyhole` in DR mode, and in SG mode both channels with `DMACR.Keyhole`, of 1 byte, 16 and 17 memory words and three bursts at aligned and unaligned buffer addresses: every burst of the data ports FIXED with at most 16 beats at the address with the bits below the memory width cleared (monitor of the harness); the buffer address is the FIFO window of the memory model (PKG-12), which maps the k-th beat to the k-th word of a backing range: MM2S sends the backing data in order, S2MM writes the packet packed from lane 0 into the backing range and nothing else: the window word and 16 bytes on each side of it, 16 bytes before and after the backing range and the rest of the last word of each transfer stay unwritten; `MM2S_DMACR.Keyhole` in DR mode changes nothing (interpretation I1) | CO-SG-11 |
| `test_sg_boundary_rate` (TC-CO-20) | Two S2MM packets of 16 KB over buffers of 1 KB and of 4 KB at multiples of 64 bytes and over buffers of 4 KB 1 byte above a multiple of 64 bytes (at most the longest buffer length), with a write response latency of 0, 50 and 100 clock cycles, the stream without gaps: every packet complete; the clock cycles per buffer boundary (the difference of the 1 KB and 4 KB runs over the difference of their numbers of boundaries), the clock cycles per KB that unaligned buffers add and the average stream beats per clock cycle are logged and listed in the verification report | CO-SG-10 |
| `test_sg_write_overlap` (TC-CO-21) | Scenario `sg_write_overlap`, the write responses of the data memory 400 clock cycles late. First a packet of one chunk that ends in its buffer in the SLVERR range, no further packet before the halt: the next descriptor received no byte and is not written, `CURDESC` at the failed one, `DMASlvErr` with `DMAIntErr`, `Err_Irq`, `Halted`, the third descriptor unchanged, both buffers unwritten. Then an S2MM packet over three buffers whose first buffer, one chunk, lies in the SLVERR range; the second buffer, two chunks, is written before the error arrives: `DMASlvErr` with `DMAIntErr`, `Err_Irq`, `Halted`, `CURDESC` at the first descriptor, its status with the error flags and `Cmplt` 0, the status of the second with its bytes, `RXSOF` and `RXEOF` 0 and `Cmplt` 1, the third descriptor unchanged and its buffer not written; the bytes of the second buffer in memory beyond the failing one, 16 unwritten bytes around it; after the end of the discarded packet, a soft reset and a new start the next packet is complete in a new chain | CO-SG-13 |

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
| CO-FT-01 | TC-CO-06, TC-CO-07, TC-CO-10, TC-CO-15 |
| CO-FT-02 | TC-CO-10 |
| CO-SG-01 | TC-CO-07, TC-CO-09 |
| CO-SG-02, CO-SG-03 | TC-CO-11, TC-CO-12 |
| CO-SG-04 | TC-CO-12 |
| CO-SG-05 | TC-CO-13 |
| CO-SG-06 | TC-CO-14 |
| CO-SG-07 | TC-CO-16 |
| CO-SG-08 | TC-CO-17 |
| CO-SG-09 | TC-CO-18 |
| CO-SG-10 | TC-CO-18, TC-CO-20 |
| CO-SG-11 | TC-CO-19 |
| CO-SG-12 | TC-CO-18 |
| CO-SG-13 | TC-CO-21 |

## 5. Negative tests

| Check or error path | Test |
| --- | --- |
| Read and write error responses, buffers beyond the top of the address space, S2MM packet longer than its buffer | TC-CO-04 |
| S2MM write error of a buffer while the next buffer of its packet is written | TC-CO-21 |
| Soft reset with outstanding transactions and a stream peer in the middle of a packet | TC-CO-05 |
| Error injection into every FT buffer, injection at an index without a buffer, injection cancelled by a soft reset | TC-CO-06 |
| Single and double errors on data bits of every FT buffer: correction of a data bit, consequence of a double error | TC-CO-10 |
| Writes to the registers of an excluded channel; idle values of its ports | TC-CO-08 |
| Inconsistent configurations | TC-CO-09 |
| Writes outside an S2MM packet (unwritten bytes around every packet in the expected memory) | TC-CO-02 to TC-CO-06, TC-CO-08, TC-CO-11, TC-CO-12, TC-CO-16 |
| Failed descriptor fetch and status write (SLVERR and DECERR), stale descriptor, buffer length 0 | TC-CO-14 |
| A halt inside an MM2S packet of several descriptors | TC-CO-18 |
| Writes outside the memory word of a keyhole transfer | TC-CO-19 |
| Soft reset with descriptor accesses and with data bursts outstanding in Scatter/Gather Mode | TC-CO-17 |
| Error injection into each buffer of the engine | TC-CO-15 |
| Accesses of the descriptor port in DR mode (idle monitor), writes of descriptor words other than the status | TC-CO-07 and every DR test; TC-CO-11 to TC-CO-14 |
