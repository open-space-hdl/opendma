# odma_core: Specification

## 1. Overview

`odma_core` is the top level of OpenDMA (architecture section 7.5, block CO-1). It instantiates the register
interface `odma_registers`, the channels `odma_mm2s` and `odma_s2mm` and, with `IncludeSg_g`, the Scatter/Gather
engine `odma_sg` of the configuration, connects them through the internal interfaces of the architecture (transfer
command, transfer result, channel control, descriptor engine control, ECC events) and checks the consistency of its
generics. It has no function of its own beyond the wiring, the idle values of a port that the configuration does not
include, the index map of the FT buffers and the detection of the packet starts at the stream ports; its
requirements describe the behaviour of the assembled core as software and the system see it.

This specification covers phase a, Direct Register Mode, and phase b, Scatter/Gather Mode with packets of one descriptor
each. Packets of several buffers and keyhole transfers wait for Open Logic (gaps G10 and G1, section 3.7). The control
and status streams and the micro DMA configuration (phase c) follow.

## 2. Partner behaviour

| Interface | Partner | Behaviour the specification accounts for |
| --- | --- | --- |
| `S_AxiLite_*` | Processor through an AXI4-Lite interconnect | Issues reads and writes independently on the read and write channels, one access per channel at a time; a write of `DMACR.Reset` may come while transfers are in progress; polls `DMASR` and `DMACR.Reset` |
| `M_AxiMm2s_*`, `M_AxiS2mm_*` | Memory through an AXI4 interconnect | As in the specifications of `odma_mm2s` and `odma_s2mm` (section 2): any backpressure and latency, responses in order, OKAY, SLVERR or DECERR |
| `M_AxiSg_*` | Memory with the descriptor chains through an AXI4 interconnect | As in the specification of `odma_sg` (section 2): any backpressure and latency, responses in order, OKAY, SLVERR or DECERR |
| Descriptor chains | Software (the drivers written for \[PG021\]) | As in the specification of `odma_sg` (section 2): rings of 16-word aligned descriptors with `Cmplt` cleared, `CURDESC` written while halted, the tail pointer written after the start and moved while the channel runs |
| `M_Mm2s_*`, `S_S2mm_*` | Stream peers | As in the specifications of `odma_mm2s` and `odma_s2mm`: the MM2S peer may hold `TReady` low for any time, the S2MM peer sends packets of any length and may pause in a packet |
| `Mm2s_Irq`, `S2mm_Irq`, `Ecc_Irq` | Interrupt controller | Level-sensitive, high-active |
| `Mm2s_RstOut`, `S2mm_RstOut` | Stream peers | Take the reset outputs as synchronous high-active resets |

## 3. Requirements

### 3.1 Interfaces

| ID | Requirement | PG021 items |
| --- | --- | --- |
| CO-IF-01 | All ports of the core shall belong to one clock `Clk` and one synchronous high-active reset `Rst`. | `CLK.SYNC` |
| CO-IF-02 | The core shall have the external interfaces of architecture section 6 for phase a: the AXI4-Lite register port with 10 address and 32 data bits, the MM2S AXI4 read master and MM2S stream, the S2MM stream and S2MM AXI4 write master, the interrupt outputs `Mm2s_Irq`, `S2mm_Irq` and `Ecc_Irq` and the reset outputs `Mm2s_RstOut` and `S2mm_RstOut`. | `STRM.MM2S`, `STRM.S2MM`, `IRQ.OUT`, `RST.OUT` |

### 3.2 Configuration

| ID | Requirement | PG021 items |
| --- | --- | --- |
| CO-CF-01 | The core shall have the generics of architecture section 6 with their ranges and defaults; in every configuration of these ranges both channels shall move data with the address width, the length width, the memory and stream widths and the burst sizes of the configuration, and the configuration words of the extension window shall read the values of the generics. | `FEAT.ADDR64`, `FEAT.WIDTH`, `FEAT.LENWIDTH` |
| CO-CF-02 | A configuration without a channel (`IncludeMm2s_g` and `IncludeS2mm_g` false), with `StsCntrlStrm_g`, `UseRxLength_g` or `MicroDma_g` true, or with generics that `coreConfigError` of `odma_pkg` rejects shall stop the elaboration with a message that names the generic. | none (configuration check) |
| CO-CF-03 | The ports of a channel that the configuration does not include shall keep constant idle values: valid and ready outputs, `WLast`, `TLast` and the interrupt output '0', `ArBurst` and `AwBurst` INCR ("01"), `ArCache` and `AwCache` "0011", all other outputs 0; its registers shall read 0 and ignore writes, and the other channel shall work unchanged. | `FEAT.CHANNEL` |

### 3.3 Programming sequences

| ID | Requirement | PG021 items |
| --- | --- | --- |
| CO-SQ-01 | The Direct Register Mode programming sequence of the MM2S channel (\[PG021\] chapter 4: run/stop bit and interrupt enables, address, length as the last write, completion by interrupt or by polling `DMASR.Idle`, `IOC_Irq` cleared by writing one) shall send the bytes of the buffer as one packet on the MM2S stream, at any byte address, for every length from 1 to 2**`LengthWidth_g` - 1 and across 4 KB boundaries. | `SEQ.DR.MM2S` |
| CO-SQ-02 | The Direct Register Mode programming sequence of the S2MM channel shall write the received packet into the buffer at any byte address, write no byte outside the packet, and `S2MM_LENGTH` shall read the received length after the completion. | `SEQ.DR.S2MM` |
| CO-SQ-03 | Both channels shall operate at the same time and independently: transfers of the two channels overlap on the memory ports, and a transfer, a halt or an error of one channel shall not change the transfers of the other. | `SEQ.DR.MM2S`, `SEQ.DR.S2MM` |
| CO-SQ-04 | A halt (`DMACR.RS` written 0) between transfers shall set `DMASR.Halted`, and a following start shall resume the channel with the next programmed transfer. | `*_DMACR.RS` |

### 3.4 Errors and soft reset

| ID | Requirement | PG021 items |
| --- | --- | --- |
| CO-ER-01 | A transfer that ends with an error shall halt its channel with the error flags in its `DMASR` and `Err_Irq` set and raise its interrupt output when `Err_IrqEn` is set: a read or write response SLVERR (`DMASlvErr`; S2MM also `DMAIntErr`), a buffer beyond the top of the address space (`DMADecErr` without a memory access; S2MM also `DMAIntErr`), an S2MM packet longer than its buffer (`DMAIntErr`, no byte beyond the buffer). The MM2S channel shall still send the packet of a transfer with a read error. | `*_DMASR.DMASlvErr`, `*_DMASR.DMADecErr`, `S2MM_DMASR.DMAIntErr`, `*_DMASR.Err_Irq` |
| CO-ER-02 | After an error, the other channel shall continue to execute transfers, and a soft reset shall clear the error flags so that both channels work again. | `*_DMACR.Reset` |
| CO-RS-01 | A soft reset written while both channels have transfers in progress shall complete every AXI transaction already accepted by the memory, start none after it, take no S2MM stream beat while it lasts, hold both reset outputs high while it lasts, return the registers to their reset values and reset both channels, which also cancels an error injection pending in one of their FT buffers; afterwards the core shall execute transfers normally, and no stream beat of the interrupted transfers shall appear. | `*_DMACR.Reset`, `RST.OUT` |

### 3.5 Fault tolerance

| ID | Requirement | PG021 items |
| --- | --- | --- |
| CO-FT-01 | The FT buffers of the channels and of the Scatter/Gather engine shall appear in the extension window at the indices of the `odma_registers` architecture (section 8): 0 MM2S read data, 1 S2MM data, 2 S2MM chunk, 3 S2MM write data, 4 MM2S transfer, 5 MM2S response; with `IncludeSg_g` 6 MM2S descriptor buffer, 7 S2MM descriptor buffer, 8 read data and 9 write data of the descriptor port. An injection at an index shall reach that buffer only; the corrected single error of a transfer through it shall be counted at that index only and set the SEC flag and `Ecc_Irq` when enabled; indices of an excluded channel, the indices 6 to 9 without `IncludeSg_g` and the indices 10 to 15 shall count nothing. Without `ExtRegs_g` the window reads 0 and `Ecc_Irq` stays low. | none (extension) |
| CO-FT-02 | In data mode of the error injection (`ECC_INJECT.Data`), a single error injected at any index shall be corrected, so that data, lengths and results are unchanged; a double error shall corrupt the word of its buffer, which is passed on as read: index 0 and 1 a byte of the stream or of the memory, index 3 a byte written to the memory, index 4 the length of the MM2S packet, index 5 the result code of the MM2S transfer, index 2 the length of the S2MM chunk. | none (extension) |

### 3.6 Scatter/Gather Mode

| ID | Requirement | PG021 items |
| --- | --- | --- |
| CO-SG-01 | With `IncludeSg_g` the core shall contain the Scatter/Gather engine `odma_sg` and its descriptor port `M_AxiSg_*` (AXI4 master, `AddrWidth_g` address bits, 32 data bits), the engine shall issue the transfer commands of both channels, and the consistency checks shall accept `IncludeSg_g` = true; without `IncludeSg_g` the descriptor port shall start no access (its valid and ready outputs '0'). | `MAP.SG` |
| CO-SG-02 | The Scatter/Gather programming sequence of the MM2S channel (\[PG021\] chapter 4: `CURDESC`, run/stop bit and interrupt enables, `TAILDESC`) shall send the buffer of every descriptor with `TXSOF` and `TXEOF` as one packet on the MM2S stream, at any byte address, also across 4 KB boundaries and with descriptors above 32 address bits, write the status of every descriptor (transferred bytes, `Cmplt`), set `IOC_Irq` per packet as the threshold allows and leave `CURDESC` at the tail. | `SEQ.SG.MM2S` |
| CO-SG-03 | The Scatter/Gather programming sequence of the S2MM channel shall write every received packet that fits into the buffer of one descriptor into that buffer, write no byte outside the packet, and write the status of the descriptor with the transferred bytes, `RXSOF`, `RXEOF` and `Cmplt`. | `SEQ.SG.S2MM` |
| CO-SG-04 | Software that processes the completed descriptors and moves the tail pointer while the channels run shall keep both channels working without loss of data, also with backpressure and latency on all memory ports. | `DESCMGMT.TAIL` |
| CO-SG-05 | In cyclic mode both channels shall process their descriptor rings, with the status of every descriptor written in every lap, until they are halted or reset. | `SEQ.CYCLIC` |
| CO-SG-06 | A failed descriptor fetch (`SGSlvErr`), a stale descriptor (`SGIntErr`), a buffer length of 0 (`DMAIntErr` in `DMASR` and in the status) and a failed status write (`SGSlvErr`) shall halt their channel with `Err_Irq`, `CURDESC` at the descriptor of the error and the packets completed before it; a soft reset shall clear the flags so that the channel works again. | `*_DMASR.SGIntErr`, `*_DMASR.SGSlvErr`, `MM2S_DMASR.DMAIntErr` |
| CO-SG-07 | The interrupt delay shall work through the core: a packet completion that does not reach the threshold starts the delay timer, which sets `Dly_Irq` and raises the interrupt output with `Dly_IrqEn` when it expires; the first stream beat of a packet that starts after that completion stops and clears the timer; a packet that starts before it does not (`odma_registers` interpretation R10). | `*_DMACR.IRQDelay`, `*_DMASR.Dly_Irq` |
| CO-SG-08 | A soft reset in Scatter/Gather Mode shall wait until no descriptor access and no data burst of either channel is outstanding, start none after it, and return the registers to their reset values; afterwards the Scatter/Gather programming sequence shall work. | `*_DMACR.Reset` |

### 3.7 Requirements waiting for Open Logic

| ID | Requirement | PG021 items |
| --- | --- | --- |
| CO-SG-09 | The MM2S channel shall send the buffers of the descriptors from one with `TXSOF` to the next with `TXEOF`, each at any address and of any length, as one contiguous packet (gap G10, `odma_mm2s` MM-SG-01). | `SEQ.SG.MM2S` |
| CO-SG-10 | The S2MM channel shall write a packet over as many buffers of the chain as it needs, with `RXSOF` in the status of the first and `RXEOF` in the status of the last descriptor (gap G10, `odma_s2mm` S2-SG-01). | `SEQ.SG.S2MM` |
| CO-SG-11 | With `DMACR.Keyhole` the transfers of the channel shall use non-incrementing bursts, in Direct Register Mode and in Scatter/Gather Mode (gap G1). | `*_DMACR.Keyhole` |

## 4. Interpretations

The core adds no interpretation of \[PG021\]; it inherits those of `odma_registers`, `odma_mm2s`, `odma_s2mm` and
`odma_sg` (their specifications, section 4).

## 5. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Inconsistent generics | Assertions of `odma_core` at elaboration | Elaboration stops with a message naming the generic (CO-CF-02) |
| Transfer error of a channel | Result of the channel | Channel halts with its error flags; the other channel continues (CO-ER-01, CO-ER-02) |
| Error of the Scatter/Gather engine (failed descriptor access, stale descriptor, buffer length 0) | `odma_sg` | Channel halts with the engine error flag, `CURDESC` at the descriptor of the error (CO-SG-06) |
| Single or double error in an FT buffer | SEC and DED outputs of the buffers | Counted at the index of the buffer (CO-FT-01); the word of a double error is passed on as read (CO-FT-02) |

## 6. Configuration parameters

The generics, their ranges and defaults are those of architecture section 6 ("Generics"). Until phase c,
`StsCntrlStrm_g`, `UseRxLength_g` and `MicroDma_g` must be false, and at least one channel must be included
(CO-CF-02).
