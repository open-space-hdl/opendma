# odma_sg: Specification

## 1. Overview

`odma_sg` is the Scatter/Gather engine of OpenDMA (architecture section 7.4), used when `IncludeSg_g` is true. Per
channel it fetches the descriptors of the chain from memory (SG-1), turns each descriptor into a transfer command of
its channel, writes the status of every processed descriptor back to memory (SG-2) and reports the completed packets
and the errors to the register interface. Both channels share one AXI4 master for the descriptor accesses (SG-3,
port `M_AxiSg_*`).

This specification covers phase b: descriptors of eight words without user application fields, tail pointer mode,
cyclic mode, packets of several descriptors, keyhole, interrupt coalescing (with `odma_registers`). The user
application fields (APP0 to APP4, `StsCntrlStrm_g`) follow in phase c. The multichannel mode is out of scope.

The engine works between `odma_registers` (pointer registers, run and halt, interrupt events) and the channels
`odma_mm2s` and `odma_s2mm` (the transfer command and result interfaces of the architecture, section 7, "Internal
interfaces"). The register map of Scatter/Gather Mode, the coalescing of the interrupts and the delay timer are
requirements of `odma_registers` (its specification, section "Requirements of phase b").

## 2. Partner behaviour

| Interface | Partner | Behaviour the specification accounts for |
| --- | --- | --- |
| Descriptor chain in memory | Software (the drivers written for PG021) | Builds a chain of 16-word aligned descriptors linked by `NXTDESC`, the last one pointing back to the first (a ring); clears `Cmplt` of every descriptor it hands to the engine; writes `CURDESC` while the channel is halted, starts the channel, then writes `TAILDESC` (with more than 32 address bits both words, the upper word last); later processes the descriptors with `Cmplt` = 1, clears their status and moves the tail pointer to the last descriptor it prepared. MM2S: one packet is described by the descriptors from `TXSOF` to `TXEOF`; S2MM: the buffers of the chain together hold at least the largest packet. Software reads the status words after the interrupt of a packet |
| `M_AxiSg_*` | Memory through an AXI4 interconnect | Accepts bursts in any order of ready, answers in order (no IDs), OKAY, SLVERR or DECERR, any latency |
| Transfer commands and results | `odma_mm2s`, `odma_s2mm` | Accept a command only while running; return one result per command with the transferred bytes, the end of packet (S2MM: the packet ended in this buffer) and the error code; with the stream join and split of gap G10, consecutive commands of one packet form one contiguous packet on the stream |
| Pointer registers, run, interrupt events | `odma_registers` | Provides `CURDESC` written while halted, the tail pointer writes, `RS`, `CyclicBD`, `Keyhole`, the drain of a soft reset; takes the current descriptor pointer, the error flags, the idle level and the packet completion events |

## 3. Requirements

### 3.1 Interfaces

| ID | Requirement | PG021 items |
| --- | --- | --- |
| SG-IF-01 | The descriptor port shall be an AXI4 master with `AddrWidth_g` address bits and 32 data bits, INCR bursts, no ID signals, `AxCache` 0011 and `AxProt` 000, shared by both channels with round-robin arbitration between their fetches and updates. | `MAP.SG` |
| SG-IF-02 | Per channel the engine shall issue the transfer commands of the descriptors on the command interface of the channel and take every result of the channel; in Scatter/Gather Mode the register interface issues no transfer command. | `SEQ.SG.MM2S`, `SEQ.SG.S2MM` |
| SG-IF-03 | Descriptor fields at or above `AddrWidth_g` address bits and buffer length bits at or above `LengthWidth_g` shall be ignored; `NXTDESC_MSB` and `BUFFER_ADDRESS_MSB` shall be used only above 32 address bits. | `DESC.NXTDESC_MSB`, `DESC.BUFFER_ADDRESS_MSB`, `DESC.MM2S_CONTROL.BufferLength`, `DESC.S2MM_CONTROL.BufferLength` |

### 3.2 Descriptor fetch (SG-1)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| SG-FE-01 | A descriptor shall be read as words 0x00 to 0x1C of its 16-word aligned block (`NXTDESC`, `NXTDESC_MSB`, `BUFFER_ADDRESS`, `BUFFER_ADDRESS_MSB`, two reserved words, `CONTROL`, `STATUS`) with one burst; bits 5 to 0 of the descriptor pointers shall be ignored. | `DESC.LAYOUT`, `DESC.NXTDESC`, `DESC.BUFFER_ADDRESS` |
| SG-FE-02 | A write of the tail pointer while the channel runs and has reached the tail (`DMASR.Idle` = 1), or after the start of the channel, shall start fetching: the first time at `CURDESC`, after reaching the tail at the `NXTDESC` of the tail descriptor. A tail pointer write while the engine has not reached the tail shall only move the pause point (interpretation SGI-01 for the trigger word). | `DESCMGMT.TAIL`, `*_TAILDESC`, `*_TAILDESC_MSB` |
| SG-FE-03 | The engine shall process the descriptors of the chain in the order of their `NXTDESC` pointers and pause after completing the descriptor whose address equals the tail pointer; it then reports idle (`DMASR.Idle` = 1). | `DESCMGMT.TAIL`, `*_DMASR.Idle` |
| SG-FE-04 | While a descriptor is being processed, the engine shall fetch the next descriptor of the chain unless the current one is the tail (one descriptor ahead), so that consecutive transfers follow each other without waiting for a fetch. | `DESCMGMT.TAIL` |
| SG-FE-05 | A fetched descriptor with `Cmplt` = 1 is stale: outside cyclic mode it shall not be processed; the channel halts with `DMASR.SGIntErr` and `CURDESC` pointing to it. | `*_DMASR.SGIntErr`, `DESC.MM2S_STATUS.Cmplt`, `DESC.S2MM_STATUS.Cmplt` |
| SG-FE-06 | A fetched descriptor with a buffer length of 0 shall not be transferred; the channel halts with `DMASR.DMAIntErr` and the descriptor status gets `DMAIntErr` (interpretation SGI-02 for the status). | `MM2S_DMASR.DMAIntErr`, `DESC.MM2S_STATUS.DMAIntErr`, `DESC.S2MM_STATUS.DMAIntErr` |
| SG-FE-07 | `CURDESC` shall hold the address of the descriptor being processed: the descriptor whose transfer is in progress or, between transfers, the next one to be processed; after the tail is completed, the tail; after an error, the descriptor of the error. | `*_CURDESC`, `*_CURDESC_MSB` |

### 3.3 Transfers (SG-1)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| SG-TR-01 | MM2S: every descriptor shall give one transfer command with its buffer address, its buffer length, start of packet = `TXSOF` and end of packet = `TXEOF`; the MM2S stream carries the buffers of the descriptors from one with `TXSOF` to the next with `TXEOF` as one packet (interpretation SGI-03 for missing flags). | `DESC.MM2S_CONTROL.BufferLength`, `DESC.MM2S_CONTROL.TXSOF`, `DESC.MM2S_CONTROL.TXEOF`, `SEQ.SG.MM2S` |
| SG-TR-02 | S2MM: every descriptor shall give one transfer command with its buffer address and its buffer length; a packet longer than the buffer continues in the buffer of the next descriptor, and a buffer is completed when it is full or when the packet ends in it. The flags in bits 27 and 26 of `S2MM_CONTROL` shall be ignored (they apply to the micro DMA only). | `DESC.S2MM_CONTROL.BufferLength`, `SEQ.SG.S2MM` |
| SG-TR-03 | With `DMACR.Keyhole` = 1 the commands of the channel shall request non-incrementing bursts (gap G1); the setting shall be taken while the channel is halted or idle. | `*_DMACR.Keyhole` |
| SG-TR-04 | When the S2MM chain has no further descriptor before the tail while a packet is still being received, the rest of the packet shall wait at the stream input (no `TReady`) until the tail pointer is moved (interpretation SGI-04). | `DESCMGMT.TAIL` |

### 3.4 Descriptor update (SG-2)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| SG-UP-01 | When the transfer of a descriptor has ended, the engine shall write its `STATUS` word once: transferred bytes (bits 25 to 0, at most `LengthWidth_g` bits), the error flags of the transfer and `Cmplt` (interpretation SGI-02); no other word of the descriptor shall be written. | `DESC.MM2S_STATUS.TransferredBytes`, `DESC.MM2S_STATUS.Cmplt`, `DESC.S2MM_STATUS.TransferredBytes`, `DESC.S2MM_STATUS.Cmplt` |
| SG-UP-02 | MM2S: the transferred bytes shall be the buffer length after a transfer without error. | `DESC.MM2S_STATUS.TransferredBytes` |
| SG-UP-03 | S2MM: the transferred bytes shall be the number of bytes written to the buffer; `RXSOF` shall be set in the status of the descriptor whose buffer holds the first byte of a packet, `RXEOF` in the status of the descriptor whose buffer holds its last byte. | `DESC.S2MM_STATUS.TransferredBytes`, `DESC.S2MM_STATUS.RXSOF`, `DESC.S2MM_STATUS.RXEOF` |
| SG-UP-04 | The status write of a descriptor shall be answered by the memory before the completion of its packet is reported to the register interface, so that software finds every status of a packet written when it handles the interrupt. | `*_DMASR.IOC_Irq` |
| SG-UP-05 | The completion of a packet shall be reported to the register interface once per packet: MM2S after the descriptor with `TXEOF`, S2MM after the descriptor with `RXEOF` (interpretation SGI-05). | `*_DMASR.IOC_Irq` |

### 3.5 Errors

| ID | Requirement | PG021 items |
| --- | --- | --- |
| SG-ER-01 | A transfer result with the slave error or the decode error shall set the error flag in the status of its descriptor (`DMASlvErr`, `DMADecErr`; S2MM with the internal error as in DR mode), set the same flag in `DMASR`, and halt the channel; `CURDESC` shall point to the descriptor. | `DESC.MM2S_STATUS.DMASlvErr`, `DESC.MM2S_STATUS.DMADecErr`, `DESC.S2MM_STATUS.DMASlvErr`, `DESC.S2MM_STATUS.DMADecErr`, `*_DMASR.DMASlvErr`, `*_DMASR.DMADecErr` |
| SG-ER-02 | A response other than OKAY to a descriptor fetch or update shall halt the channel of the access with an engine error flag (`DMASR.SGSlvErr` or `DMASR.SGDecErr`). | `*_DMASR.SGSlvErr`, `*_DMASR.SGDecErr` |
| SG-ER-03 | An error of one channel shall not stop the other channel; descriptor updates already started shall be completed before the channel reports halted. | `*_DMASR.Halted` |

### 3.6 Halt, soft reset and cyclic mode

| ID | Requirement | PG021 items |
| --- | --- | --- |
| SG-HA-01 | When `DMACR.RS` falls, the engine shall issue no further command and fetch no further descriptor, let the channel end the transfer in progress as in DR mode, write the status of that descriptor, and then report the channel stopped; fetched descriptors that were not started keep their status unchanged, and `CURDESC` points to the first of them. | `*_DMACR.RS`, `*_DMASR.Halted` |
| SG-HA-02 | During the drain of a soft reset the engine shall issue no command and start no fetch, complete the descriptor accesses already accepted by the memory, and report stopped when none is outstanding. | `*_DMACR.Reset` |
| SG-CY-01 | With `DMACR.CyclicBD` = 1 the engine shall ignore `Cmplt` of fetched descriptors and the tail pointer as pause point: after the start by a tail pointer write it processes the ring until the channel is halted or reset; it still writes the status of every descriptor. | `*_DMACR.CyclicBD`, `SEQ.CYCLIC` |

### 3.7 Fault tolerance

| ID | Requirement | PG021 items |
| --- | --- | --- |
| SG-FT-01 | The descriptor buffers of the channels and the data buffers of the descriptor port shall be SECDED-protected FT buffers with ECC events and error injection at the indices 6 to 9 of the extension window. | none (architecture P5) |

### 3.8 Requirements waiting for Open Logic

| ID | Requirement | PG021 items |
| --- | --- | --- |
| SG-ER-04 | The engine error flag of SG-ER-02 shall be `SGSlvErr` for SLVERR and `SGDecErr` for DECERR (gap G5). | `*_DMASR.SGSlvErr`, `*_DMASR.SGDecErr` |

## 4. Interpretations

| ID | PG021 | OpenDMA |
| --- | --- | --- |
| SGI-01 | Table 10 states that a write of `TAILDESC` starts the engine, Table 11 the same for `TAILDESC_MSB`; the order of the two writes of a 64-bit pointer is not described | With `AddrWidth_g` = 32 the write of `TAILDESC` starts it. Above 32 address bits the write of `TAILDESC_MSB` starts it, so that the engine starts with the complete pointer (SG-FE-02). The public drivers write the low word first: the Linux driver (`drivers/dma/xilinx/xilinx_dma.c`, state of commit 7ed1e3070c9b) writes the pointer registers with `xilinx_write`, which uses `lo_hi_writeq` for addresses above 32 bits; the bare-metal driver (`XilinxProcessorIPLib/drivers/axidma/src/xaxidma_bdring.c` of the embeddedsw repository, state of commit a4dab0553492) writes `TDESC` and then `TDESC_MSB` in `XAxiDma_StartBdRingHw` and `XAxiDma_BdRingToHw`, and `CDESC` before `CDESC_MSB` in `XAxiDma_UpdateBdRingCDesc` |
| SGI-02 | The status of a descriptor whose transfer failed is not described beyond the error flags | The status gets the error flags, the bytes transferred until the error and `Cmplt` = 0: the transfer described by the descriptor was not completed (SG-UP-01, SG-ER-01). A stale descriptor (SG-FE-05) is not written |
| SGI-03 | A packet needs a descriptor with `TXSOF` and one with `TXEOF` ("for proper operation") | The data stream ends a packet after each descriptor with `TXEOF`; the next descriptor starts a new packet whether `TXSOF` is set or not. `TXSOF` selects the descriptor whose user application fields go to the control stream (phase c) |
| SGI-04 | A packet larger than the buffer space of the chain gives undefined results | The rest of the packet waits at the stream input until descriptors are added (SG-TR-04); nothing is discarded and no error is set |
| SGI-05 | `IOC_Irq` "for descriptors with the IOC bit set" (Table 6); the descriptor of version 7.1 has no IOC bit, `IOC_Irq` is set at the end of a packet (Table 7) | Every completed packet is an interrupt event; the threshold counter of `odma_registers` decides when `IOC_Irq` is set (SG-UP-05) |
| SGI-06 | `CURDESC` written while the channel runs | Ignored (read-only while running, Table 8) |
| SGI-07 | Keyhole without data realignment needs aligned buffer addresses | The address bits below the memory data width are ignored for keyhole transfers (gap G1, requirement G1-05) |

## 5. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Stale descriptor (`Cmplt` = 1, not cyclic) | Fetched status word | `SGIntErr`, halt, `CURDESC` = the descriptor (SG-FE-05) |
| Buffer length 0 | Fetched control word | `DMAIntErr` in `DMASR` and in the status, halt (SG-FE-06) |
| SLVERR or DECERR of a data transfer | Result of the channel | Error flags in the status and in `DMASR`, halt (SG-ER-01) |
| SLVERR or DECERR of a descriptor access | Response of the descriptor port | `SGSlvErr` or `SGDecErr`, halt (SG-ER-02, SG-ER-04) |
| S2MM packet larger than the chain up to the tail | No descriptor before the tail | The rest waits at the stream input (SG-TR-04) |
| Single or double error in an FT buffer | SEC and DED outputs of the buffers | Counted at indices 6 to 9 (SG-FT-01) |

## 6. Configuration parameters

| Generic | Range | Description |
| --- | --- | --- |
| `IncludeMm2s_g`, `IncludeS2mm_g` | boolean | Channels with a descriptor engine |
| `AddrWidth_g` | 32 to 64 | Address bits of the descriptor pointers, buffer addresses and the descriptor port |
| `LengthWidth_g` | 8 to 26 | Bits of the buffer lengths and transferred bytes |
