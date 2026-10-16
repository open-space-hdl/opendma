# odma_core: Specification

## 1. Overview

`odma_core` is the top level of OpenDMA (architecture section 7.5, block CO-1). It instantiates the register
interface `odma_registers` and the channels `odma_mm2s` and `odma_s2mm` of the configuration, connects them through
the internal interfaces of the architecture (transfer command, transfer result, channel control, ECC events) and
checks the consistency of its generics. It has no function of its own beyond the wiring, the idle values of a
channel that the configuration does not include and the index map of the FT buffers; its requirements describe the
behaviour of the assembled core as software and the system see it.

This specification covers phase a, Direct Register Mode. The Scatter/Gather engine (phase b), the control and status
streams and the micro DMA configuration (phase c) follow.

## 2. Partner behaviour

| Interface | Partner | Behaviour the specification accounts for |
| --- | --- | --- |
| `S_AxiLite_*` | Processor through an AXI4-Lite interconnect | Issues reads and writes independently on the read and write channels, one access per channel at a time; a write of `DMACR.Reset` may come while transfers are in progress; polls `DMASR` and `DMACR.Reset` |
| `M_AxiMm2s_*`, `M_AxiS2mm_*` | Memory through an AXI4 interconnect | As in the specifications of `odma_mm2s` and `odma_s2mm` (section 2): any backpressure and latency, responses in order, OKAY, SLVERR or DECERR |
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
| CO-CF-02 | A configuration without a channel (`IncludeMm2s_g` and `IncludeS2mm_g` false), with `IncludeSg_g`, `StsCntrlStrm_g`, `UseRxLength_g` or `MicroDma_g` true, or with generics that `coreConfigError` of `odma_pkg` rejects shall stop the elaboration with a message that names the generic. | none (configuration check) |
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
| CO-FT-01 | The FT buffers of the channels shall appear in the extension window at the indices of the `odma_registers` architecture (section 8): 0 MM2S read data, 1 S2MM data, 2 S2MM chunk, 3 S2MM write data, 4 MM2S transfer, 5 MM2S response. An injection at an index shall reach that buffer only; the corrected single error of a transfer through it shall be counted at that index only and set the SEC flag and `Ecc_Irq` when enabled; indices of an excluded channel or of a later phase shall count nothing. Without `ExtRegs_g` the window reads 0 and `Ecc_Irq` stays low. | none (extension) |
| CO-FT-02 | In data mode of the error injection (`ECC_INJECT.Data`), a single error injected at any index shall be corrected, so that data, lengths and results are unchanged; a double error shall corrupt the word of its buffer, which is passed on as read: index 0 and 1 a byte of the stream or of the memory, index 3 a byte written to the memory, index 4 the length of the MM2S packet, index 5 the result code of the MM2S transfer, index 2 the length of the S2MM chunk. | none (extension) |

### 3.6 Requirements of phase b

| ID | Requirement | PG021 items |
| --- | --- | --- |
| CO-SG-01 | With `IncludeSg_g` the core shall contain the Scatter/Gather engine `odma_sg` and its descriptor port `M_AxiSg_*`; the consistency checks shall accept `IncludeSg_g` = true. | `MAP.SG` |
| CO-SG-02 | The Scatter/Gather programming sequence of the MM2S channel (\[PG021\] chapter 4: `CURDESC`, run/stop bit and interrupt enables, `TAILDESC`) shall send the buffers of a descriptor chain as the packets its `TXSOF` and `TXEOF` flags define, write the status of every descriptor and raise the interrupt per packet as the threshold allows. | `SEQ.SG.MM2S` |
| CO-SG-03 | The Scatter/Gather programming sequence of the S2MM channel shall write received packets into the buffers of the chain, a packet over as many buffers as it needs, with the transferred bytes, `RXSOF` and `RXEOF` in the status of each descriptor. | `SEQ.SG.S2MM` |
| CO-SG-04 | Software that processes the completed descriptors and moves the tail pointer while the channels run shall keep both channels working without loss of data. | `DESCMGMT.TAIL` |
| CO-SG-05 | In cyclic mode both channels shall process their descriptor rings until they are halted or reset. | `SEQ.CYCLIC` |

## 4. Interpretations

The core adds no interpretation of \[PG021\]; it inherits those of `odma_registers`, `odma_mm2s` and `odma_s2mm`
(their specifications, section 4).

## 5. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Inconsistent generics | Assertions of `odma_core` at elaboration | Elaboration stops with a message naming the generic (CO-CF-02) |
| Transfer error of a channel | Result of the channel | Channel halts with its error flags; the other channel continues (CO-ER-01, CO-ER-02) |
| Single or double error in an FT buffer | SEC and DED outputs of the buffers | Counted at the index of the buffer (CO-FT-01); the word of a double error is passed on as read (CO-FT-02) |

## 6. Configuration parameters

The generics, their ranges and defaults are those of architecture section 6 ("Generics"). In phase a, `IncludeSg_g`,
`StsCntrlStrm_g`, `UseRxLength_g` and `MicroDma_g` must be false and at least one channel must be included
(CO-CF-02).
