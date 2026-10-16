# odma_registers: Specification

## 1. Overview

`odma_registers` is the register interface of OpenDMA (architecture section 7.1): the register bank of both channels
behind the AXI4-Lite port (RG-1), one interrupt controller per channel (RG-2), the reset controller with the soft
reset and the reset outputs (RG-3) and the extension window with identification, configuration readback, ECC
counters and error injection (RG-4). In Direct Register Mode it turns the programmed address and length of a channel
into a transfer command and updates the status registers from the transfer results of the channels.

This specification covers phase a (Direct Register Mode). The registers and fields of Scatter/Gather Mode, the
interrupt coalescing and the delay timer follow with phase b; their requirements will be added then. Where a field
has no function in DR mode, this specification states its DR behaviour and traces it to the access rules
(`MAP.ACCESS`, `MAP.DR`), so that the function itself stays planned in the compliance matrix until it is implemented.

## 2. Partner behaviour

| Interface | Partner | Behaviour the specification accounts for |
| --- | --- | --- |
| `S_AxiLite_*` | Processor software through an interconnect (the drivers written for PG021) | Single 32-bit accesses at word addresses; write address and write data may arrive in any order or together (PG021 asks for both together, OpenDMA accepts both); full-word writes with all strobes set, but OpenDMA ignores the strobes (`MAP.WSTRB`). Software reads DMACR and writes it back with changed bits (read-modify-write), polls `DMACR.Reset` until it reads 0 after a soft reset and `DMASR.Halted` after a start, writes the length register last, clears `IOC_Irq` and `Err_Irq` by writing ones to DMASR, and checks `DMASR.Idle` before a new transfer |
| Transfer command and result (internal) | `odma_mm2s`, `odma_s2mm` (architecture section 7, "Internal interfaces") | A command is accepted when the channel is ready; a result arrives once per command with the transferred bytes and an error code; a halt or drain request is acknowledged by an idle or drained level |

## 3. Requirements

Requirements trace to the items this module owns or shares (architecture section 10). Items owned by other blocks,
such as the programming sequences (`SEQ.*`, owner CO-1), are verified by the requirements of their owners.

### 3.1 Register port and address map (RG-1)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| RG-IF-01 | The register port shall be an AXI4-Lite slave with 32-bit data and a 10-bit byte address; address bits 1 and 0 shall be ignored. | `MAP.DR` |
| RG-IF-02 | Every access shall complete with the response OKAY; a read of an address without a register shall return 0, a write to it shall have no effect. | `MAP.DR` |
| RG-IF-03 | A write shall take all 32 bits of the write data, independent of the write strobes. | `MAP.WSTRB` |
| RG-IF-04 | Bit n of a register shall be bit n of the AXI4-Lite data word (little-endian registers). | `MAP.ENDIAN` |
| RG-MAP-01 | In DR mode the registers shall be at the offsets of PG021 Table 5: `MM2S_DMACR` 0x00, `MM2S_DMASR` 0x04, `MM2S_SA` 0x18, `MM2S_SA_MSB` 0x1C, `MM2S_LENGTH` 0x28, `S2MM_DMACR` 0x30, `S2MM_DMASR` 0x34, `S2MM_DA` 0x48, `S2MM_DA_MSB` 0x4C, `S2MM_LENGTH` 0x58; the offsets 0x08 to 0x14, 0x2C and 0x38 to 0x44 shall read 0. | `MAP.DR` |
| RG-MAP-02 | Read-only fields shall ignore writes; read/write fields shall read back the last written value unless a requirement below changes them; flags of the access type R/WC shall be cleared by writing 1 and keep their value when 0 is written. | `MAP.ACCESS` |
| RG-MAP-03 | When a channel is not included (`IncludeMm2s_g` or `IncludeS2mm_g` false), all its registers shall read 0 and ignore writes. | `MAP.DR` |
| RG-MAP-04 | The extension window 0x100 to 0x1FF shall hold the registers of section 3.7 when `ExtRegs_g` is true and read 0 otherwise; no other register shall lie at or above offset 0x100 or between the registers of Table 5. | `MAP.DR` |

### 3.2 Control registers (RG-1, RG-2, RG-3)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| RG-CR-01 | `DMACR.RS` (bit 0) shall be read/write with reset value 0. Writing 1 while the channel is halted and no error flag of the channel is set shall start the channel; writing 1 while an error flag is set shall have no effect (interpretation I3). Writing 0 while the channel runs shall request a halt. | `*_DMACR.RS` |
| RG-CR-02 | When a transfer result of the channel carries an error, `DMACR.RS` shall be cleared. | `*_DMACR.RS` |
| RG-CR-03 | `DMACR` bit 1 shall read 1, bits 11 to 5 and bit 15 shall read 0. | `*_DMACR.Reserved` |
| RG-CR-04 | In DR mode, `DMACR.Keyhole` (bit 3), `DMACR.CyclicBD` (bit 4), `DMACR.Dly_IrqEn` (bit 13) and `DMACR.IRQDelay` (bits 31 to 24) shall be read/write with reset value 0 and have no function; `DMACR.IRQThreshold` (bits 23 to 16) shall be read/write with reset value 0x01 and no function, and a write of 0x00 to it shall leave it unchanged. | `MAP.ACCESS` |
| RG-CR-05 | `DMACR.IOC_IrqEn` (bit 12, interpretation I2) and `DMACR.Err_IrqEn` (bit 14) shall be read/write with reset value 0. | `*_DMACR.IOC_IrqEn`, `*_DMACR.Err_IrqEn` |
| RG-CR-06 | Writing 1 to `DMACR.Reset` (bit 2) of either channel shall start the soft reset of the whole core (section 3.5); `DMACR.Reset` of both channels shall read 1 while the soft reset is in progress and 0 otherwise. | `*_DMACR.Reset` |

### 3.3 Status registers (RG-1, RG-2)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| RG-SR-01 | `DMASR.Halted` (bit 0) shall be 1 after a reset, 0 from the start of the channel (RG-CR-01) and 1 again once the channel has stopped after a halt request or an error. | `*_DMASR.Halted` |
| RG-SR-02 | In DR mode, `DMASR.Idle` (bit 1) shall be 0 while the channel is halted, 0 after the start until the first transfer completes, 0 while a transfer is in progress, and 1 from the completion of a transfer until the next transfer starts. | `*_DMASR.Idle` |
| RG-SR-03 | `DMASR.SGIncld` (bit 3) shall read the value of `IncludeSg_g` (0 in DR mode). | `*_DMASR.SGIncld` |
| RG-SR-04 | `DMASR` bits 2, 7, 11 and 15 shall read 0. | `*_DMASR.Reserved` |
| RG-SR-05 | `MM2S_DMASR.DMASlvErr` (bit 5) and `MM2S_DMASR.DMADecErr` (bit 6) shall be set by an MM2S transfer result with the slave error or the decode error code; `S2MM_DMASR.DMASlvErr` and `S2MM_DMASR.DMADecErr` likewise by an S2MM result. They shall be read-only and cleared only by a reset. | `*_DMASR.DMASlvErr`, `*_DMASR.DMADecErr` |
| RG-SR-06 | `S2MM_DMASR.DMAIntErr` (bit 4) shall be set in DR mode by an S2MM transfer result with the internal error code (packet longer than the buffer, architecture D6) and together with `DMASlvErr` or `DMADecErr` by every S2MM result with the slave or the decode error code (interpretation I13; the decode error also covers a buffer beyond the top of the address space); read-only, cleared only by a reset. | `S2MM_DMASR.DMAIntErr` |
| RG-SR-07 | In DR mode, `MM2S_DMASR.DMAIntErr` (bit 4), `DMASR.SGIntErr` (bit 8), `DMASR.SGSlvErr` (bit 9), `DMASR.SGDecErr` (bit 10) and `DMASR.Dly_Irq` (bit 13) shall read 0; `DMASR.IRQThresholdSts` (bits 23 to 16) shall read the value of `DMACR.IRQThreshold` and `DMASR.IRQDelaySts` (bits 31 to 24) shall read 0. | `MAP.DR` |

### 3.4 Address and length registers, transfers (RG-1)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| RG-AR-01 | `MM2S_SA` and `MM2S_SA_MSB` shall be read/write with reset value 0 and hold the bits 31 to 0 and 63 to 32 of the MM2S buffer address; bits at or above `AddrWidth_g` shall read 0 and be ignored on writes. | `MM2S_SA`, `MM2S_SA_MSB` |
| RG-AR-02 | `S2MM_DA` and `S2MM_DA_MSB` shall be read/write with reset value 0 and hold the S2MM buffer address in the same way. | `S2MM_DA`, `S2MM_DA_MSB` |
| RG-AR-03 | `MM2S_LENGTH` and `S2MM_LENGTH` shall be read/write with reset value 0 in bits `LengthWidth_g` - 1 to 0; the bits above shall read 0 and be ignored on writes. | `MM2S_LENGTH`, `S2MM_LENGTH` |
| RG-AR-04 | A write of a non-zero value to `MM2S_LENGTH` while the MM2S channel runs and no MM2S transfer is in progress shall issue one MM2S transfer command with the address of `MM2S_SA` and `MM2S_SA_MSB`, the written length and start and end of packet set. | `MM2S_LENGTH` |
| RG-AR-05 | A write of a non-zero value to `S2MM_LENGTH` while the S2MM channel runs and no S2MM transfer is in progress shall issue one S2MM transfer command with the address of `S2MM_DA` and `S2MM_DA_MSB` and the written value as the buffer length. | `S2MM_LENGTH` |
| RG-AR-06 | When an S2MM transfer completes (a result without error and with the end of packet), `S2MM_LENGTH` shall read the number of bytes written to the buffer; after any other result it shall keep its value. | `S2MM_LENGTH` |
| RG-AR-07 | A write of 0 to a length register shall have no effect; a write while a transfer of the channel is in progress shall have no effect (interpretation I6); a write while the channel is halted shall be stored and read back but issue no transfer, also not when the channel is started later (interpretation I7). | `MM2S_LENGTH`, `S2MM_LENGTH` |
| RG-AR-08 | Writes to the address registers while a transfer is in progress shall not change the transfer in progress. | `MM2S_SA`, `S2MM_DA` |

### 3.5 Reset (RG-3)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| RG-RS-01 | The reset input `Rst` shall bring all registers to their reset values and assert both reset outputs while it is active. | `RST.HARD` |
| RG-RS-02 | A soft reset shall request both channels to stop issuing commands and to drain their accepted transfers, wait until both report drained, then reset the whole core to the state after `Rst` (all registers at their reset values). | `*_DMACR.Reset` |
| RG-RS-03 | The reset outputs `Mm2s_RstOut` and `S2mm_RstOut` shall be high during `Rst` and from the start of a soft reset until its end, at least 16 clock cycles (interpretation I12). | `RST.OUT` |
| RG-RS-04 | Register writes during a soft reset shall have no effect; reads shall be answered. | `*_DMACR.Reset` |

### 3.6 Interrupts (RG-2)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| RG-IR-01 | In DR mode, `DMASR.IOC_Irq` (bit 12) shall be set when a transfer of the channel completes: a result without error and with the end of packet. | `*_DMASR.IOC_Irq` |
| RG-IR-02 | `DMASR.Err_Irq` (bit 14) shall be set when an error flag of the channel is set. | `*_DMASR.Err_Irq` |
| RG-IR-03 | `IOC_Irq` and `Err_Irq` shall be cleared by writing 1 to them; when a set and a clear coincide, the flag shall stay set. | `MAP.ACCESS` |
| RG-IR-04 | `Mm2s_Irq` shall be high while (`IOC_Irq` and `IOC_IrqEn`) or (`Err_Irq` and `Err_IrqEn`) of the MM2S channel is set, with one clock cycle of latency; `S2mm_Irq` likewise for the S2MM channel. | `IRQ.OUT`, `*_DMACR.IOC_IrqEn`, `*_DMACR.Err_IrqEn` |

### 3.7 Extension window (RG-4)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| RG-EX-01 | The window shall hold a read-only identification word 0x4F444D41 ("ODMA" in ASCII) and a read-only version word (major, minor and patch level of the core). | none (extension) |
| RG-EX-02 | The window shall hold read-only configuration words with the values of all generics of the core. | none (extension) |
| RG-EX-03 | The window shall hold, for every FT buffer of the configuration, a single error (SEC) and a double error (DED) event counter that saturates; a write to the counter word of a buffer shall clear its counters, and a write of 1 to a clear bit shall clear all counters; an event in the same cycle as a clear shall be counted. | none (extension, architecture P5) |
| RG-EX-04 | The window shall hold a SEC and a DED event flag (R/WC) with enables; `Ecc_Irq` shall be high while an enabled flag is set. | none (extension) |
| RG-EX-05 | The window shall hold an error injection control that flips one bit (single error) or two bits (double error) of the next codeword written to a selected FT buffer, through the error injection inputs of the buffer. | none (extension) |

## 4. Interpretations of the published interface

| ID | PG021 | OpenDMA |
| --- | --- | --- |
| I2 | Table 6 lists `IOC_IrqEn` at bit 1 | Bit 12 in both channels (RG-CR-05) |
| I3 | Restart after an error not described | `RS` = 1 has no effect while an error flag is set; recovery by a reset (RG-CR-01) |
| I6, I7 | Length writes while busy or halted | RG-AR-07 |
| I12 | Active-low reset outputs | High-active (RG-RS-03) |
| I13 | `DMAIntErr` for any memory write error in DR mode | Set together with the slave or decode error (RG-SR-06) |
| R1 | Coalescing fields "ignored" in DR mode (Tables 6 and 16); the status fields "applicable only" with Scatter/Gather | Stored and read back without function (RG-CR-04); `IRQThresholdSts` reads the programmed threshold, `IRQDelaySts` 0 (RG-SR-07) |
| R2 | Error flags: no clearing described other than the reset | Read-only, cleared by a hard or soft reset (RG-SR-05, RG-SR-06) |
| R3 | `S2MM_LENGTH` "updated at the completion" | After an error or a halt during the transfer it keeps the programmed value (RG-AR-06) |
| R4 | Registers of a channel that is not included | Read 0, writes ignored (RG-MAP-03) |
| R5 | Accesses during a soft reset | Writes ignored, reads answered (RG-RS-04) |
| R6 | Both `DMACR.Reset` bits during a soft reset | Both read 1 (RG-CR-06) |
| R7 | Writes not affected by the strobes (Register Space note) | All 32 bits taken; also for partial strobes (RG-IF-03) |

## 5. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Transfer result with the slave or decode error code | Error code of the result | Error flag, `RS` cleared, `Err_Irq` set, channel halts (RG-CR-02, RG-SR-05) |
| S2MM packet longer than the buffer (DR mode) | Internal error code of the S2MM result | `S2MM_DMASR.DMAIntErr`, as above (RG-SR-06) |
| `RS` = 1 written with an error flag set | Register bank | No effect (RG-CR-01) |
| Length written while busy or halted | Register bank | No transfer (RG-AR-07) |
| Access to an address without a register | Register bank | Read 0, write ignored, OKAY (RG-IF-02) |
| Single or double error in an FT buffer | SEC and DED outputs of the buffers | Counted, flag and `Ecc_Irq` when enabled (RG-EX-03, RG-EX-04) |

## 6. Configuration parameters

The module takes the generics of the core that change its registers (architecture section 6, "Generics"):
`IncludeSg_g` (false only in phase a), `IncludeMm2s_g`, `IncludeS2mm_g`, `LengthWidth_g`, `AddrWidth_g`,
`ExtRegs_g`, and for the configuration readback of RG-EX-02 all other generics of the core. The number of FT buffers
follows from the configuration.
