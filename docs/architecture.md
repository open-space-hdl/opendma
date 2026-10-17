# OpenDMA Architecture

Version 0.1. This file is the reference for the architecture and is versioned with the code.

## 1 Purpose, scope and references

This document defines the architecture of OpenDMA, a direct memory access (DMA) core that moves data between AXI4
memory and AXI4-Stream peripherals. Its register map, descriptor format and programming sequences are those of the
AMD AXI DMA as published in the product guide \[PG021\], so that software written for that core runs on OpenDMA
unchanged. Together with \[PG021\] this document is the complete basis for the implementation: it fixes the building
blocks, their interfaces, the items of the published interface each block owns and the Open Logic entities each
block is built from.

### In scope

The scope is developed in four phases (section 11):

- **Phase a, Direct Register Mode.** Memory to stream (MM2S) and stream to memory (S2MM) channels started by
  address and length registers, the control and status registers of both channels, interrupt on complete and on
  error, the error flags of the data movers, graceful halt, soft and hard reset, the reset outputs for the stream
  peers. Transfers start at any byte address and have any length up to `2**LengthWidth_g - 1` bytes; they are split
  into bursts of the configured size and at 4 KB boundaries. Address widths of 32 to 64 bits, memory data widths of
  32 to 1024 bits, stream data widths of 8 to 1024 bits.
- **Phase b, Scatter/Gather Mode.** Descriptor chains in memory, current and tail descriptor pointers, packets
  described by several descriptors, completion status written back to the descriptors, stale descriptor detection,
  the errors of the descriptor engine, cyclic descriptor mode, interrupt coalescing (threshold) and the delay timer,
  keyhole transfers (non-incrementing bursts).
- **Phase c, control and status streams.** The user application fields of the descriptors sent on a control stream
  (MM2S) and received from a status stream (S2MM), the receive length taken from the status stream; the micro DMA
  configuration.
- **Phase d, software on hardware.** The bare-metal and Linux drivers of a processor system operating OpenDMA on a
  target board.

Fault-tolerance additions that \[PG021\] does not have (ECC event counters, error injection, configuration readback)
sit in an extension register window outside the compatible register map (D12).

### Out of scope

- The multichannel mode of \[PG021\] (its section "Multichannel DMA Support", the register SG_CTL of Table 15, the
  descriptor formats of Tables 41 and 42, the stream sideband signals TID, TDEST and TUSER, two-dimensional
  transfers). \[PG021\] announces its discontinuation in favour of a separate core.
- Asynchronous clocks for the AXI interfaces (\[PG021\] section "Clocking", Table 43). OpenDMA runs in one clock
  domain (D1); an asynchronous configuration is a possible later extension (section 11).
- The timing figures of \[PG021\] Tables 1 and 2 (latency and throughput of the AMD implementation). OpenDMA states
  its own performance in the user guide.
- The debug vector `axi_dma_tstvec` and the integration files of the vendor tool (IP packaging, the active-low reset
  `axi_resetn`, the signal names of the vendor block). A vendor wrapper with these names is a possible later adapter.

### Target technology

OpenDMA contains no vendor code. All buffers are Open Logic fault-tolerant entities, the memory interfaces are AXI4
masters, the data interfaces AXI4-Stream and the register interface AXI4-Lite. The core runs on any FPGA.

### Project

OpenDMA is an open DMA core based on the Open Logic VHDL Library. The code lives in
[open-space-hdl/opendma](https://github.com/open-space-hdl/opendma) under the PSI HDL Library License, Version 1.0,
the licence of Open Logic. Open Logic is pinned to the tag `4.7.0-ft.8` (f9e7f59) of the branch `fault-tolerant` of
open-space-hdl/open-logic-ft, the fault-tolerant fork of Open Logic.

OpenDMA is an independent implementation written from the published product guide. The repository contains no
code, text, tables or figures of AMD; \[PG021\] is cited by section, table and field name, and the AMD name is used
only to state the compatibility.

### References

| ID | Document | Version used |
| --- | --- | --- |
| \[PG021\] | AMD, AXI DMA LogiCORE IP Product Guide, PG021 | v7.1, 24 June 2025 |
| \[AXI\] | Arm, AMBA AXI Protocol Specification, IHI 0022 | AXI4 and AXI4-Lite |
| \[AXIS\] | Arm, AMBA AXI-Stream Protocol Specification, IHI 0051 | AXI4-Stream |
| \[OLO\] | [Open Logic, fault-tolerant fork, branch fault-tolerant](https://github.com/open-space-hdl/open-logic-ft/tree/fault-tolerant) | 4.7.0-ft.8 (f9e7f59) |

### Conventions

- An item of the published interface is named as in \[PG021\]: a register field as `<REGISTER>.<Field>` (for example
  `MM2S_DMACR.RS`), a descriptor field as `DESC.<WORD>.<Field>` (for example `DESC.S2MM_STATUS.RXEOF`). Behaviour
  that is not a register or descriptor field has an item key of its own (`SEQ.*`, `FEAT.*`, `STRM.*`, `CLK.*`,
  `RST.*`, `IRQ.*`, `MAP.*`), defined in the traceability matrix of section 10 with the \[PG021\] section or table it
  refers to.
- Coding conventions: those of Open Logic (naming, two-process style, synchronous high-active resets, VSG rules), entity
  prefix `odma_`, VHDL library `opendma`; see [conventions.md](conventions.md).
- "FT" (fault-tolerant) means the Open Logic `olo_ft_*` entities: SECDED ECC on every buffer.

| Term | Meaning |
| --- | --- |
| MM2S | Memory to stream channel: reads memory, sends a stream |
| S2MM | Stream to memory channel: receives a stream, writes memory |
| DR mode | Direct Register Mode: a transfer is programmed by an address and a length register (`IncludeSg_g` = false) |
| SG mode | Scatter/Gather Mode: transfers are described by descriptors in memory (`IncludeSg_g` = true) |
| Descriptor | Buffer descriptor (BD) of \[PG021\] Table 25: 16 words in memory, aligned to 64 bytes |
| Packet | One AXI4-Stream packet, ended by `TLast` |
| Buffer | A contiguous memory range given by an address and a length (one DR transfer or one descriptor) |
| Transfer | The movement of one buffer |
| Chunk | The part of an S2MM packet that one write command of the memory master carries (D5) |
| M, W | Memory data width and stream data width of a channel, in bytes |
| IOC | Interrupt on complete |

## 2 Functional overview of the published interface

The core has two independent channels. The MM2S channel reads buffers from memory and sends them as AXI4-Stream
packets; the S2MM channel receives packets and writes them to buffers in memory. Each channel has a control register
(DMACR) with the run/stop bit, the soft reset bit and the interrupt enables, and a status register (DMASR) with the
halted and idle state, the error flags and the interrupt flags. The two channels share one register file behind an
AXI4-Lite port; a soft reset requested through either channel resets the whole core.

In DR mode, software starts a channel with the run/stop bit, writes the buffer address and then the length; the
write of a non-zero length starts the transfer. One MM2S transfer is one packet on the stream. An S2MM transfer
takes the next packet into the buffer; at its end the length register holds the number of bytes received. The end
of a transfer sets the IOC flag.

In SG mode, software builds a chain of descriptors in memory, each with the address and length of a buffer, start
and end of packet flags and a status word. It writes the first descriptor to the current descriptor pointer, starts
the channel and writes the tail descriptor pointer; the core fetches and processes descriptors up to the tail,
writes the status (transferred bytes, flags, errors, completed) back to each descriptor and pauses. A new tail
pointer resumes it. A packet may span several descriptors. Interrupts can be coalesced over a number of packets and
raised by a delay timer after the last packet. In cyclic mode the chain is a ring that the core processes until it
is stopped.

Optional control and status streams carry five user application words per packet from an MM2S descriptor to the
stream peer and from the stream peer into the last S2MM descriptor of a packet.

An error response of the memory, an invalid descriptor or an inconsistent length halts the channel and sets an error
flag; software recovers with a soft reset.

## 3 Design drivers

| Driver | Consequence |
| --- | --- |
| Software compatibility | Register offsets, fields, reset values, access types, descriptor layout and programming sequences as in \[PG021\]; the behaviour is verified with a register-level model of the programming sequences (section 9) and with the drivers on hardware (phase d) |
| Use in space: single event upsets in buffers and registers | SECDED ECC on every buffer, state machines with a recovery state, ECC event counters in the extension window, the TMR of the synthesis tool for all other logic (P5) |
| Protection of the memory | No byte outside the programmed buffer is ever written or read (P6) |
| Technology independence | AXI4, AXI4-Stream and AXI4-Lite interfaces, no vendor primitive (P10) |
| Configurability | Generics that correspond to the user parameters of \[PG021\] Table 44 (D11) |
| Verifiability | Every block verified through its ports against an independent memory model and stream models (P8, section 9) |
| Reuse | The data movers are `olo_ft_axi_master_full`; custom logic is limited to the DMA control (P9) |

## 4 Design goals

| Goal | Implementation |
| --- | --- |
| Drivers run unchanged | Identical register interface (P4) and the interpretations of section 6 where \[PG021\] is open |
| Defined handshakes between blocks | Every internal data path is a valid / ready stream or a stream of one-cycle events (P2) |
| Full stream rate | The data movers run long transfers at one beat per clock cycle on the stream side; the memory side is limited only by the bursts and the memory (D2, D5) |
| Memory bus never held by a stream peer | Read bursts are issued only when the data buffer can take them, write bursts only when their data is buffered (D3) |
| Deterministic error handling | Every error halts the channel with a defined flag; error flags stay until a reset (D7) |
| Fault tolerance | FT buffers, safe state machines (P5) |
| Tests independent of the design hierarchy | Tests observe only ports and the register file (section 9) |

## 5 Design principles

| ID | Principle | Rule for the implementation |
| --- | --- | --- |
| P1 | One function per block | A block implements one function of section 7. Its specification names the items of the published interface it owns; no item is owned by two blocks. |
| P2 | Streams everywhere | Every data path between blocks is a valid / ready stream (Open Logic AXI4-Stream conventions) or a valid-only stream of events. |
| P3 | One clock domain | All blocks run in `Clk` (D1). |
| P4 | The compatible register map is exact | The offsets, fields, reset values and access types of \[PG021\] Tables 4 to 24 are implemented as published; nothing else is placed below offset 0x100. All further registers are in the extension window (D12). The register map is generated from one description (VHDL package, documentation, C header). |
| P5 | Fault tolerance by construction | All buffers are `olo_ft_*` entities (SECDED ECC). State machines have a defined recovery state. ECC events are counted in the extension window. All other logic relies on the triple modular redundancy (TMR) of the synthesis tool (user guide, section "Protection scope"). |
| P6 | Memory safety | A transfer writes only the bytes of its buffer (write strobes) and reads only the memory words that contain them (AXI4 reads have no strobes; the other bytes of the first and the last word are read and discarded): S2MM never writes beyond the buffer length, whatever the stream delivers (D6), and a buffer that wraps around the top of the address space is rejected before any access (D7). |
| P7 | Stream conventions of the family | The first byte of a packet is in byte lane 0, all bytes of a beat are valid except in the last beat, whose valid bytes are contiguous from lane 0 (`TKeep`). The byte at the lowest address of a buffer is the first byte of its stream data. |
| P8 | Verifiable in isolation | Each module has a specification and a testbench that drives only its ports. The memory model, the stream models and the model of the programming sequences are written independently of the RTL. |
| P9 | Reuse before design | A function available in Open Logic (AXI master, FIFO, AXI4-Lite slave, arbiter, pipeline stage, ECC monitor) is instantiated, not rewritten. A missing function is added to Open Logic (section 8). |
| P10 | No vendor code | The core has no vendor primitive. |

## 6 Architecture overview

![Architecture overview of odma_core: the MM2S channel (MM-1 to MM-3) from its AXI4 read master to the MM2S and
control streams, the Scatter/Gather engine (SG-1 to SG-3) with its own AXI4 master, the register interface (RG-1 to
RG-4) with the AXI4-Lite port and the interrupt and reset outputs, and the S2MM channel (S2-1 to S2-3) from the S2MM
and status streams to its AXI4 write master](img/odma_core_overview.drawio.svg)

The register interface holds the registers of both channels and turns a programmed buffer into a transfer command.
In DR mode it issues the command itself; in SG mode the Scatter/Gather engine fetches descriptors, issues one
command per descriptor and writes the status back. Each channel executes its commands with an `olo_ft_axi_master_full`
and reports the result of every transfer (transferred bytes, end of packet, error); the register interface updates
the status registers and the interrupt flags from these results.

### External interfaces

| Interface | Ports | Phase | Content |
| --- | --- | --- | --- |
| Clock and reset | `Clk`, `Rst` | a | One clock; synchronous high-active reset |
| Register port | `S_AxiLite_*` | a | AXI4-Lite slave, 10-bit address, 32-bit data |
| MM2S memory port | `M_AxiMm2s_Ar*`, `M_AxiMm2s_R*` | a | AXI4 read master, `AddrWidth_g` address bits, `Mm2sMemWidth_g` data bits |
| MM2S stream | `M_Mm2s_Data`, `_Keep`, `_Last`, `_Valid`, `_Ready` | a | AXI4-Stream master, `Mm2sStreamWidth_g` data bits |
| S2MM stream | `S_S2mm_Data`, `_Keep`, `_Last`, `_Valid`, `_Ready` | a | AXI4-Stream slave, `S2mmStreamWidth_g` data bits |
| S2MM memory port | `M_AxiS2mm_Aw*`, `M_AxiS2mm_W*`, `M_AxiS2mm_B*` | a | AXI4 write master, `S2mmMemWidth_g` data bits |
| Interrupts | `Mm2s_Irq`, `S2mm_Irq` | a | Level, high-active (D9) |
| Reset outputs | `Mm2s_RstOut`, `S2mm_RstOut` | a | High-active resets for the stream peers (D8) |
| ECC interrupt | `Ecc_Irq` | a | Level, high-active: an enabled ECC event of an FT buffer (extension window, D12; with `ExtRegs_g` only) |
| Descriptor port | `M_AxiSg_*` | b | AXI4 read and write master, 32-bit data |
| Control stream | `M_Cntrl_*`, `Cntrl_RstOut` | c | AXI4-Stream master, 32-bit data |
| Status stream | `S_Sts_*`, `Sts_RstOut` | c | AXI4-Stream slave, 32-bit data |

The ports of a channel that a configuration does not include (`IncludeMm2s_g`, `IncludeS2mm_g`, `IncludeSg_g`,
`StsCntrlStrm_g` false) keep their idle values and ignore their inputs. The AXI4 masters have no ID signals: all
transactions of a port use the same ID, as \[AXI\] allows for masters without reordering.

### Generics

| Generic | \[PG021\] Table 44 parameter | Range | Default | Phase |
| --- | --- | --- | --- | --- |
| `IncludeSg_g` | `c_include_sg` | boolean | false (\[PG021\]: 1) | a (false), b (true) |
| `IncludeMm2s_g`, `IncludeS2mm_g` | `c_include_mm2s`, `c_include_s2mm` | boolean | true | a |
| `LengthWidth_g` | `c_sg_length_width` | 8 to 26 | 14 | a |
| `AddrWidth_g` | `c_addr_width` | 32 to 64 | 32 | a |
| `Mm2sMemWidth_g`, `S2mmMemWidth_g` | `c_m_axi_mm2s_data_width`, `c_m_axi_s2mm_data_width` | 32, 64, 128, 256, 512, 1024 | 32 | a |
| `Mm2sStreamWidth_g`, `S2mmStreamWidth_g` | `c_m_axis_mm2s_tdata_width`, `c_s_axis_s2mm_tdata_width` | 8, 16, ..., 1024, at most the memory width | 32 | a |
| `Mm2sBurstBeats_g`, `S2mmBurstBeats_g` | `c_mm2s_burst_size`, `c_s2mm_burst_size` | 2, 4, ..., 256 | 16 | a |
| `StsCntrlStrm_g` | `c_sg_include_stscntrl_strm` | boolean | false (\[PG021\]: 1) | c |
| `UseRxLength_g` | `c_sg_use_stsapp_length` | boolean | false | c |
| `MicroDma_g` | `c_micro_dma` | boolean | false | c |
| `Mm2sBufferBeats_g`, `S2mmBufferBeats_g` | none: depth of the data buffer of a channel in stream beats | at least two bursts | four bursts | a |
| `ExtRegs_g` | none: extension register window (D12) | boolean | true | a |

The parameters of \[PG021\] Table 44 that have no generic: `c_enable_multi_channel`, `c_num_mm2s_channels` and
`c_num_s2mm_channels` (multichannel mode, out of scope), `c_prmry_is_aclk_async` (one clock domain, D1),
`c_include_mm2s_dre` and `c_include_s2mm_dre` (unaligned transfers are always supported, D2).

Two defaults differ from \[PG021\] on purpose and stay as they are: `IncludeSg_g` and `StsCntrlStrm_g` default to
false, so that the default configuration is the smallest one (DR mode without control and status streams) and an
instantiation that relies on the defaults keeps its configuration when later phases add functions. A configuration
taken from a system with the vendor core sets both generics explicitly.

### Architecture decisions

| ID | Decision | Reason |
| --- | --- | --- |
| D1 | One clock domain `Clk` for the register port, both channels, the descriptor engine and the stream ports | The synchronous configuration of \[PG021\] section "Clocking"; no clock domain crossing in the core. A system with other stream clocks places `olo_ft_fifo_async` at the stream ports |
| D2 | Each channel moves its data with one `olo_ft_axi_master_full`: MM2S with the read side only, S2MM with the write side only; user data width = stream width, AXI data width = memory width, maximum burst = burst size generic, transfer size width = `LengthWidth_g` + 1 (G14) | Transfers at any byte address and of any length in every width configuration (the function of the data realignment engine of \[PG021\], without its limit of 512 stream bits), 4 KB and burst splitting, outstanding bursts and ECC on the data buffers without own logic. Aligned transfers behave identically, so software for a configuration without realignment is unaffected |
| D3 | Both data movers run in their high-latency mode: a read burst is requested only when the read buffer has space for it, a write burst only when its data is in the write buffer | A stalled stream peer never holds the memory bus; a halt or soft reset completes every issued burst without the stream peer (D8) |
| D4 | MM2S sends a buffer as stream data with the first byte in lane 0. In DR mode every transfer is one packet; in SG mode a packet runs from the descriptor with `TXSOF` to the one with `TXEOF`. `TKeep` of the last beat follows from the length; a transfer is complete when its last beat is accepted by the stream peer | P7; the completion reported to software means that the data has left the core |
| D5 | S2MM is store-and-forward per chunk: received beats enter an FT data buffer; a chunk ends after one memory burst of data or at `TLast`; the byte count of a complete chunk (from `TKeep` of its last beat) enters a chunk buffer, and only then is its write command issued | The memory master needs the byte count before the data (section 8, G3); no write is issued for data that has not arrived, and no byte after `TLast` is written |
| D6 | S2MM never writes beyond its buffer. In DR mode a packet longer than `S2MM_LENGTH`: the bytes that fit are written, the rest of the packet is discarded up to its `TLast`, `S2MM_DMASR.DMAIntErr` is set and the channel halts | P6; \[PG021\] Table 17 defines the error for this case. Discarding up to `TLast` keeps the stream in step for the next packet |
| D7 | Every error halts its channel: no new command is issued, issued commands complete, then `DMACR.RS` reads 0 and `DMASR.Halted` 1, `DMASR.Err_Irq` is set. An AXI SLVERR response sets `DMASlvErr`, DECERR `DMADecErr`. A buffer whose last byte lies beyond the top of the address space is rejected with `DMADecErr` before any access. Error flags stay until a reset; while one is set, a write of `RS` = 1 has no effect | \[PG021\] Tables 7 and 17 (graceful halt on error); software recovers with a soft reset. P6 for the address wrap, which \[PG021\] leaves undefined; the decode error is the flag of an invalid address (Tables 7 and 17), and `MM2S_DMASR.DMAIntErr` is fixed at 0 in DR mode (Table 7) |
| D8 | A soft reset (`DMACR.Reset` of either channel) stops both channels at once and completes every issued AXI transaction (read data is discarded, buffered write chunks are written); then the whole core is reset, and `Reset` reads 0 again. The reset outputs of the stream peers are active during the hard reset and during the soft reset. Streams are cut: `M_Mm2s_Valid` may fall before `TLast` | \[PG021\] Tables 6 and 16 (reset of the whole core, pending transfers flushed or completed, streams terminated early, reset outputs of Table 3). The AXI4 memory protocol is never violated; the stream peers restart from their reset outputs |
| D9 | Each channel has one interrupt output, level and high-active: the OR of the IOC, delay and error flags that are enabled, registered | \[PG021\] Table 3 (`mm2s_introut`, `s2mm_introut`) and the enables of Tables 6 and 16 |
| D10 | The register port is `olo_axi_lite_slave` with 32-bit data and a 10-bit address. A write uses all 32 bits of `WData` whatever `WStrb` holds; reserved bits read their defined value (bit 1 of DMACR reads 1); addresses without a register read 0 and ignore writes; every access gets an OKAY response | \[PG021\] section "Register Space" (write data not affected by the strobes) and Tables 4 to 24; a defined response keeps software that probes the map running |
| D11 | Configuration by the generics of section 6 "Generics", named after the user parameters of \[PG021\] Table 44, with the same ranges and, except `IncludeSg_g` and `StsCntrlStrm_g`, the same defaults where a parameter exists | The configuration of an existing system maps one to one; the driver configuration (device tree, generated parameters) stays valid |
| D12 | The extension window 0x100 to 0x1FF (with `ExtRegs_g`) holds an identification and configuration readback, the ECC event counters of all FT buffers (`olo_ft_ecc_monitor` behind the register bank, so that every access keeps the OKAY response of D10), the enables of the ECC interrupt output `Ecc_Irq` and the error injection controls. Software written for \[PG021\] never accesses it; without `ExtRegs_g` it reads 0 and `Ecc_Irq` stays low | P4: FT additions outside the compatible map |
| D13 | (Phase b) The descriptor engine has its own AXI4 master (`M_AxiSg_*`, 32-bit data) shared by both channels through a round-robin arbiter; a descriptor is fetched as a whole (8 words, or 13 with the user application fields) into an FT buffer, one descriptor ahead of the one in progress; the status is written back with one write (STATUS, and APP0 to APP4 of the last S2MM descriptor of a packet with the status stream) | Separate descriptor port as in \[PG021\] Figure 1; prefetching hides the fetch latency between descriptors |
| D14 | (Phase b) Packets of several descriptors are joined (MM2S, `olo_base_stream_join`) and split (S2MM, `olo_base_stream_split`) on the stream side, in SG mode only, so that buffers of any length and address form one contiguous packet | \[PG021\] Tables 30 and 37 allow any buffer length per descriptor; the memory master delivers each buffer starting in lane 0 (section 8, G10) |
| D15 | The state machines have a defined recovery state: the `when others` branch leads to it from an illegal state where the synthesis tool implements the state machine safe, and the reset input restarts it from any state. Their registers rely on the TMR of the synthesis tool like all other logic | Same as the other cores of the family |
| D16 | Registers whose values enter arithmetic, comparisons or conversions, in the core or in the Open Logic entities it drives, are reset; an idle core evaluates no undefined value | Simulation logs of systems with the core stay free of numeric_std metavalue warnings |

### Interpretations of the published interface

Where \[PG021\] is open or inconsistent, OpenDMA behaves as follows. The module specifications repeat the
interpretations that concern them.

| ID | Item | \[PG021\] | OpenDMA |
| --- | --- | --- | --- |
| I1 | `MM2S_DMACR.Keyhole`, `S2MM_DMACR.Keyhole` in DR mode | Table 6 calls the MM2S bit non-functional in DR mode, Table 16 does not restrict the S2MM bit | As published (P4): the MM2S bit is stored but has no function in DR mode; the S2MM bit works in both modes, the MM2S bit in SG mode (phase b) |
| I2 | `MM2S_DMACR.IOC_IrqEn` | Table 6 lists bit 1, Figure 3 and Table 16 bit 12 | Bit 12 in both channels |
| I3 | `DMACR.RS` after an error | The error clears `RS`; restarting without a reset is not described | `RS` = 1 has no effect while an error flag is set (D7) |
| I4 | S2MM packet longer than the buffer in DR mode | Table 24 calls it undefined, Table 17 defines `DMAIntErr` | D6 |
| I5 | Buffer beyond the top of the address space | Not described | Rejected with `DMADecErr` (invalid address), no access (D7) |
| I6 | `MM2S_LENGTH` or `S2MM_LENGTH` written while the channel is busy | Not described (the software checks the idle state first) | The write has no effect |
| I7 | `MM2S_LENGTH` or `S2MM_LENGTH` written while halted | No effect on the DMA operation (Tables 7 and 17) | The value is stored and read back; no transfer starts, also not when `RS` is set later |
| I8 | `DMACR.RS` = 0 during a transfer | Pending transfers flushed or completed | MM2S completes the transfer in progress, including its `TLast`, then halts. S2MM writes the chunks that are complete in its buffer, discards the rest of the packet up to `TLast` and halts without IOC |
| I9 | S2MM stream input before the channel runs | Section "Typical System Interconnect" notes that a few beats are accepted before the core is programmed | Beats are accepted into the data buffer only while the channel runs; while it is halted `S_S2mm_Ready` is low |
| I10 | `TKeep` of S2MM beats | Not described | `TKeep` of a beat without `TLast` is ignored (all bytes are stored); the last beat stores the bytes up to the first deasserted `TKeep` bit (P7) |
| I11 | MM2S transfer with a memory error | Streams potentially terminated early | The data of the transfer is sent completely with `TLast`, then the channel halts with the error flag; software discards the packet |
| I12 | Reset outputs | Active-low `*_reset_out_n` (Table 3) | High-active (Open Logic convention), with the same function |
| I13 | S2MM write error in DR mode | Table 17 sets `DMAIntErr` for any error of the memory write in DR mode, next to the flags of the response | Both are set: `DMAIntErr` and `DMASlvErr` or `DMADecErr` |
| I14 | EXOKAY response | Tables 7 and 17 name SLVERR and DECERR; EXOKAY is not described | OpenDMA never requests exclusive access, so EXOKAY is a protocol violation of the slave; it counts as SLVERR (`DMASlvErr`, `SGSlvErr`). Observable: an EXOKAY response sets the slave error flag of the access |

## 7 Building block specifications

The core has 14 building blocks in five groups. Each block lists its responsibility, the Open Logic entities it is
built from and the items of the published interface it owns (P1).

### 7.1 Register interface (module `odma_registers`)

| ID | Block | Responsibility | Open Logic | \[PG021\] items |
| --- | --- | --- | --- | --- |
| RG-1 | Register bank | Address map, access types and reset values of the registers of both channels; run/stop, halted and idle state per channel; DR mode: address and length registers, start of a transfer by the length write, update of `S2MM_LENGTH` with the received bytes; error flags from the transfer results; SG mode: descriptor pointer registers towards the descriptor engine | `olo_axi_lite_slave` | `MAP.*`, `*_DMACR.RS`, `*_DMACR.Reserved`, `*_DMASR.Halted`, `*_DMASR.Idle`, `*_DMASR.SGIncld`, `*_DMASR.Reserved`, `MM2S_SA*`, `MM2S_LENGTH`, `S2MM_DA*`, `S2MM_LENGTH`, `*_CURDESC*`, `*_TAILDESC*` (register side) |
| RG-2 | Interrupt controller | IOC, delay and error flags (write one to clear), interrupt threshold counter and its status, delay timer and its status, interrupt outputs; one instance per channel | none | `*_DMACR.IOC_IrqEn`, `*_DMACR.Dly_IrqEn`, `*_DMACR.Err_IrqEn`, `*_DMACR.IRQThreshold`, `*_DMACR.IRQDelay`, `*_DMASR.IOC_Irq`, `*_DMASR.Dly_Irq`, `*_DMASR.Err_Irq`, `*_DMASR.IRQThresholdSts`, `*_DMASR.IRQDelaySts`, `IRQ.OUT` |
| RG-3 | Reset controller | Soft reset sequence of D8 (stop, drain, reset), `DMACR.Reset` read back, reset outputs | none | `*_DMACR.Reset`, `RST.*` |
| RG-4 | Extension registers | Identification, configuration readback, ECC event counters and error injection of the FT buffers (D12) | `olo_ft_ecc_monitor` | none (P5) |

### 7.2 MM2S channel (module `odma_mm2s`)

| ID | Block | Responsibility | Open Logic | \[PG021\] items |
| --- | --- | --- | --- | --- |
| MM-1 | Read command | Transfer command to the memory master (address, length, keyhole), address wrap check, error collection (SLVERR, DECERR), halt and drain | `olo_ft_axi_master_full` (read side) | `*_DMASR.DMASlvErr`, `*_DMASR.DMADecErr` (MM2S), `MM2S_DMACR.Keyhole`, `FEAT.4K`, `FEAT.BURST`, `FEAT.UNALIGNED` (MM2S) |
| MM-2 | Stream output | Read data to the MM2S stream: `TKeep` of the last beat, `TLast` at the end of a packet, transfer result when the last beat is accepted; phase b: joining the buffers of a packet (D14) | `olo_base_stream_join` (G10), `olo_base_pl_stage` | `STRM.MM2S`, `DESC.MM2S_CONTROL.TXSOF`, `DESC.MM2S_CONTROL.TXEOF` (stream side) |
| MM-3 | Control stream (phase c) | Flag word and APP0 to APP4 of the first descriptor of a packet on the control stream | `olo_ft_fifo_sync` | `STRM.CNTRL`, `DESC.MM2S_APP` |

### 7.3 S2MM channel (module `odma_s2mm`)

| ID | Block | Responsibility | Open Logic | \[PG021\] items |
| --- | --- | --- | --- | --- |
| S2-1 | Chunk former | Stream input, data buffer, cut into chunks (D5), byte count of the last beat, buffer end and overflow (D6), discard up to `TLast`; phase b: split of a packet at the end of each buffer (D14) | `olo_ft_fifo_sync` (data and chunk buffers), `olo_base_stream_split` (G10) | `STRM.S2MM`, `S2MM_DMASR.DMAIntErr` (DR mode) |
| S2-2 | Write command | Write command per chunk at the running address, address wrap check, transfer result after the write response of its last chunk, error collection, halt and drain | `olo_ft_axi_master_full` (write side) | `*_DMASR.DMASlvErr`, `*_DMASR.DMADecErr` (S2MM), `S2MM_DMACR.Keyhole`, `FEAT.4K`, `FEAT.BURST`, `FEAT.UNALIGNED` (S2MM) |
| S2-3 | Status stream (phase c) | Reception of the flag word and APP0 to APP4, receive length of APP4 | `olo_ft_fifo_sync` | `STRM.STS`, `STRM.RXLENGTH`, `DESC.S2MM_APP*` |

### 7.4 Scatter/Gather engine (module `odma_sg`, phase b)

| ID | Block | Responsibility | Open Logic | \[PG021\] items |
| --- | --- | --- | --- | --- |
| SG-1 | Descriptor fetch | Per channel: tail pointer mode, fetch and prefetch of descriptors, check of the completed bit (stale descriptor) and of the buffer length, cyclic mode, transfer commands from descriptors | `olo_ft_fifo_sync` (descriptor buffer) | `DESC.NXTDESC*`, `DESC.BUFFER_ADDRESS*`, `DESC.*_CONTROL.*`, `*_DMACR.CyclicBD`, `*_DMASR.SGIntErr`, `*_DMASR.DMAIntErr` (SG mode), `DESCMGMT.TAIL`, `*_CURDESC*`, `*_TAILDESC*` (engine side) |
| SG-2 | Descriptor update | Status word of every processed descriptor (transferred bytes, start and end of packet, errors, completed), current descriptor pointer | none | `DESC.*_STATUS.*` |
| SG-3 | Descriptor port | Arbitration of the fetches and updates of both channels on one AXI4 master, its errors | `olo_ft_axi_master_simple`, `olo_base_arb_rr` | `*_DMASR.SGSlvErr`, `*_DMASR.SGDecErr` |

### 7.5 Core (module `odma_core`)

| ID | Block | Responsibility | Open Logic | \[PG021\] items |
| --- | --- | --- | --- | --- |
| CO-1 | Core top level | Instances of the modules per configuration, consistency checks of the generics, idle values of excluded ports | none | `FEAT.ADDR64`, `FEAT.WIDTH`, `FEAT.LENWIDTH`, `FEAT.CHANNEL`, `FEAT.MICRO`, `CLK.SYNC`, `SEQ.*` (verified at core level) |

### Internal interfaces

| Interface | Between | Payload | Protocol |
| --- | --- | --- | --- |
| Transfer command | RG-1 (DR mode) or SG-1 (SG mode) to MM-1, S2-1 and S2-2 | Buffer address, length, start and end of packet (MM2S), keyhole | Valid / ready |
| Transfer result | MM-2, S2-2 to RG-1 (DR mode) or SG-2 (SG mode) | Transferred bytes, end of packet, start of packet (S2MM, phase b), error code | Valid / ready |
| Channel control | RG-1, RG-3 to the channels | Run, halt, drain request; idle and drained state | Levels |
| Descriptor engine control (phase b) | RG-1 to SG-1, SG-1 and SG-2 to RG-1 | Run, drain, `CURDESC`, tail pointer and its triggering write, `CyclicBD`, `Keyhole`; current descriptor pointer, idle, stopped, packet and error events | Levels and events |
| Interrupt events | RG-1, SG-2 to RG-2 | Packet complete, error | Events |
| Packet start (phase b) | CO-1 to RG-2 | The first beat of a packet at each stream port, for the delay timer | Events |
| ECC events | FT buffers to RG-4 | SEC and DED per buffer | Events |
| Register bus | RG-1 to RG-4 and the user | Registers of section 6 | AXI4-Lite (`olo_axi_lite_slave`) |

## 8 Open Logic usage

| Open Logic entity | Used in | Purpose |
| --- | --- | --- |
| `olo_ft_axi_master_full` | MM-1, S2-2 | AXI4 masters with byte-exact unaligned transfers, burst and 4 KB splitting, ECC on the data buffers |
| `olo_ft_axi_master_simple` | SG-3 | AXI4 master of the descriptor port: bursts of aligned 32-bit words, ECC on the read and write data buffers |
| `olo_ft_fifo_sync` | MM-1, MM-2, S2-1, SG-1, MM-3, S2-3 | Transfer and response buffers of MM2S, data and chunk buffers of S2MM, descriptor buffer, control and status stream buffers |
| `olo_base_pl_stage` | MM-2, S2-2 | Register stage of the MM2S stream output (DR mode), stage of the S2MM write jobs |
| `olo_base_stream_join` | MM-2 | Join of the buffers of an MM2S packet in SG mode (G10) |
| `olo_base_stream_split` | S2-1 | Split of an S2MM packet at the end of every buffer in SG mode (G10) |
| `olo_base_arb_rr` | SG-3 | Fair choice between the descriptor accesses of both channels |
| `olo_axi_lite_slave` | RG-1 | AXI4-Lite access to the register file |
| `olo_ft_ecc_monitor` | RG-4 | SEC and DED counters per buffer |

### Gap analysis of `olo_axi_master_full`

`olo_ft_axi_master_full` wraps `olo_axi_master_full` and has its interface and behaviour; the analysis applies to
both at tag 4.7.0-ft.6. G11 is the need of the descriptor port, which uses `olo_ft_axi_master_simple`, the same
wrapper of `olo_axi_master_simple`, instead.

| ID | \[PG021\] needs | `olo_axi_master_full` at 4.7.0-ft.6 | Resolution | Phase |
| --- | --- | --- | --- | --- |
| G1 | Keyhole: MM2S reads and S2MM writes with non-incrementing (FIXED) bursts of at most 16 beats (`DMACR.Keyhole`, Tables 6 and 16) | INCR bursts only; `AxBurst` is a constant | New in open-logic-ft: a per-command option for FIXED bursts in `olo_axi_master_simple`, `olo_axi_master_full` and their ft variants (address not incremented between bursts, bursts of at most min(`AxiMaxBeats_g`, 16) beats, start address aligned to the AXI data width) | b |
| G2 | Lengths up to `2**26 - 1` bytes (`LengthWidth_g` 8 to 26) with addresses of 32 to 64 bits | `UserTransactionSizeBits_g` must be smaller than `AxiAddrWidth_g` - 1 (assertion on the derived beat count) | No gap: the largest length width, 26, with the smallest address width, 32, satisfies the rule. OpenDMA sets `UserTransactionSizeBits_g` = `LengthWidth_g` + 1 (G14); `synth_check` elaborates both ends | a |
| G3 | S2MM packets of unknown length: the data arrives before the length is known | Write data is accepted only after the command (alignment) | No change of Open Logic: S2-1 buffers a chunk completely before its command (D5), in an `olo_ft_fifo_sync` | a |
| G4 | `TKeep` of the last MM2S beat; byte count of the last S2MM beat | No byte enables on the user data interfaces | No change of Open Logic: MM-2 derives `TKeep` from the length, S2-1 the byte count from `TKeep` (I10) | a |
| G5 | SLVERR and DECERR reported separately (`DMASlvErr`, `DMADecErr` in Tables 7, 17, 31 and 38) | `Rd_Error` and `Wr_Error` are pulses without the response code | New in open-logic-ft: the response code of a failed command (the first non-OKAY response, or SLVERR and DECERR flags) next to `Rd_Error` and `Wr_Error` in `olo_axi_master_simple`, `olo_axi_master_full` and their ft variants | a |
| G6 | AXI cache and protection attributes; user signals | `AxCache` = 0011 and `AxProt` = 000 are constants, no `AxUser` | No gap in scope: the register SG_CTL with the descriptor port attributes exists only in the multichannel mode. A generic for coherent systems is a later option at the core ports | - |
| G7 | Many small buffers (SG mode with descriptors of a few beats) | At least four clock cycles per command (alignment logic) | Accepted: one buffer per four clock cycles at most; the user guide states the rate. The micro DMA configuration (phase c) may use `olo_axi_master_simple` | b, c |
| G8 | Halt and soft reset complete or flush pending transfers | No abort of an accepted command | No change of Open Logic: the channels stop issuing commands and drain the accepted ones (D3, D8) | a |
| G9 | MM2S completion when the data has left the core | `Rd_Done` signals the end of the AXI reads, before the data is consumed | No change of Open Logic: MM-2 reports the result at the handshake of the last beat (D4) | a |
| G10 | Packets of several buffers with any lengths and addresses (Tables 30 and 37) | Every command delivers its data starting in lane 0; Open Logic has no stream byte realigner | New in open-logic-ft: a stream realigner that shifts a byte stream by a runtime lane offset with carry between beats (data and `TKeep` in and out), for MM-2 (join) and S2-1 (split) | b |
| G11 | Descriptor fetch and update of 8 to 13 words | `olo_axi_master_simple` moves whole words of the AXI width in bursts of any beat count | No gap: SG-3 uses `olo_ft_axi_master_simple` with 32 data bits; descriptors are aligned to 64 bytes, so no alignment logic is needed | b |
| G12 | Stream width at most the memory width, both powers of two; up to 16 outstanding bursts | `AxiDataWidth_g` an integer multiple of `UserDataWidth_g`; at most 8 open transactions | No gap: every width pair of \[PG021\] Table 44 is valid; 8 open transactions per direction | a |
| G13 | Bursts of up to 256 beats at every data width (`c_mm2s_burst_size`, `c_s2mm_burst_size` up to 256 with up to 1024 bits) | `olo_axi_master_simple` does not elaborate when `AxiMaxBeats_g` exceeds the beats of 4 KB (`4096 / (AxiDataWidth_g / 8)`): a slice of its 4 KB beat count is out of range | No change needed: MM-1 and S2-2 run the masters with at most the beats of 4 KB; no AXI burst crosses 4 KB, so the bursts are the same. The defect is corrected in open-logic-ft | a |
| G14 | Write commands of every length up to 2**`LengthWidth_g` - 1 bytes | `olo_axi_master_full` computes the number of user data words of a write command (size / B + 1, B = `UserDataWidth_g` / 8) at the width of the size field without its low log2(B) bits, so the number wraps to 0 for sizes from 2**`UserTransactionSizeBits_g` - B + 1 to 2**`UserTransactionSizeBits_g` - 1; the master then accepts the next command and its data but issues no further burst (for example a command of 4000 to 4095 bytes with 128-byte user words and `UserTransactionSizeBits_g` 12) | No change needed: MM-1 and S2-2 run the masters with `UserTransactionSizeBits_g` = `LengthWidth_g` + 1, so no command reaches that word count; the rule `UserTransactionSizeBits_g` < `AxiAddrWidth_g` - 1 still holds. The defect is corrected in open-logic-ft | a |

G1, G5 and G10 are additions to open-logic-ft, available from tag 4.7.0-ft.8 (G5 from 4.7.0-ft.7): the ports
`CmdRd_Fixed` and `CmdWr_Fixed` of the masters (G1), `Rd_ErrorResp` and `Wr_ErrorResp` (G5), and the entities
`olo_base_stream_join` and `olo_base_stream_split` (G10). OpenDMA uses them from that tag on: the channels map the
response codes to the slave and the decode error (interpretation I14 for EXOKAY), request FIXED bursts for keyhole
commands, and join and split the buffers of a packet in SG mode only, so that a DR configuration has none of their
shifters.

## 9 Verification architecture

The core is verified with VUnit and UVVM in the seven-phase module workflow (requirements, architecture, verification
plan, RTL, testbenches, verification, integration; see [conventions.md](conventions.md)). Every building block of
section 7 belongs to a module with its own specification, verification plan, testbench and verification report; core
tests cross the seams between the modules. Every test case names the requirements it verifies, and every requirement
names its items of the published interface, so the traceability matrix of section 10 is checked by
`tools/compliance.py`.

| Level | Scope | Bench | Checks |
| --- | --- | --- | --- |
| Unit | `odma_registers`, `odma_mm2s`, `odma_s2mm`, `odma_sg` | `<entity>_th.vhd` (clock, DUT, models) and `<entity>_tb.vhd` (VUnit runner, one `run("test_...")` per test of the verification plan) | UVVM checks; register values against the expected values of the plan; streams and memory against the stream models and the memory model |
| Core | `odma_core` in the configurations of the verification report | AXI4-Lite VVC with the sequence player, AXI memory model on every memory port, AXI4-Stream VVCs on the streams | The programming sequences of \[PG021\] chapter 4 end to end, errors injected by the memory model, soft reset under load, interrupts |
| Software (phase d) | The core in a processor system on hardware | The drivers of the processor system | Transfers of the driver test applications; hardware test report |

### Framework

- VUnit (`run.py`) discovers and runs every test and is the CI regression. UVVM supplies the verification building
  blocks: AXI4-Stream and AXI4-Lite VVCs, alert and log handling, `check_value` / `await_value`, randomisation.
- The AXI memory model (`tb/`) is a behavioural AXI4 slave with random backpressure on every channel, error
  responses (SLVERR, DECERR) on configurable address ranges, backdoor access for checks and protocol checks of
  every burst (4 KB boundary, burst length and type, write strobes inside the buffer).
- The model of the programming sequences (`tb/model/`, Python) describes how software operates the registers and
  descriptors in the words of \[PG021\] chapter 4: reset, start, DR transfers, descriptor chains with their tail
  pointer, cyclic rings, interrupt handling and error recovery. It generates, before each core test, a sequence of
  register accesses (write, read and check, poll until a value, wait for an interrupt), the memory image with
  buffers and descriptors and the expected memory, stream and descriptor contents. The sequence player of `tb/`
  executes the sequence through the AXI4-Lite VVC. The model is written from \[PG021\], independently of the RTL and
  without vendor driver code.
- Simulators: GHDL for every test; QuestaSim with and without code coverage at the end of each batch of features.

### Rules

- Tests observe ports and the register file only (P8).
- A failed check fails the test; a test cannot pass with a failed step.
- Negative tests inject the fault from the bench (error responses of the memory model, packets longer than the
  buffer, invalid descriptors, buffers at the top of the address space, double errors through the error injection of
  the FT buffers) and expect the error flag, the descriptor status or the interrupt; never from an RTL mutation.
- Every commit passes the full regression.

## 10 Requirement traceability matrix

Every item of the published interface in the scope of section 1 has exactly one owner block. "Phase" names the
development phase that implements the item; "First verified at" the lowest verification level at which it can be
fully checked. The compliance matrix, generated from this table, the module specifications and the verification
plans by `tools/compliance.py`, lists the requirements and test cases of every item. An item of a later phase whose
owner module has no specification yet is listed as planned. The prefix `*_` stands for both channels: every row
with it is checked once for `MM2S_` and once for `S2MM_`.

### Register map and access

| Item | \[PG021\] reference | Owner | Also involved | Phase | First verified at |
| --- | --- | --- | --- | --- | --- |
| `MAP.SG` | Table 4, SG mode address map | RG-1 | SG-1 | b | Unit |
| `MAP.DR` | Table 5, DR mode address map | RG-1 |  | a | Unit |
| `MAP.ENDIAN` | Figure 2, little-endian registers | RG-1 |  | a | Unit |
| `MAP.WSTRB` | Register Space, note on the write strobes | RG-1 |  | a | Unit |
| `MAP.ACCESS` | Register Access Type Description (RO, R/W, R/WC) | RG-1 | RG-2 | a | Unit |

### Control registers (Tables 6 and 16)

| Item | \[PG021\] reference | Owner | Also involved | Phase | First verified at |
| --- | --- | --- | --- | --- | --- |
| `*_DMACR.RS` | Tables 6, 16, bit 0 | RG-1 | MM-1, S2-1, S2-2 | a | Unit |
| `*_DMACR.Reserved` | Tables 6, 16, bits 1, 11 to 5, 15 | RG-1 |  | a | Unit |
| `*_DMACR.Reset` | Tables 6, 16, bit 2 | RG-3 | RG-1, MM-1, S2-1, S2-2 | a | Core |
| `*_DMACR.Keyhole` | Tables 6, 16, bit 3 | MM-1 (MM2S), S2-2 (S2MM) | RG-1 | b | Unit |
| `*_DMACR.CyclicBD` | Tables 6, 16, bit 4 | SG-1 | RG-1 | b | Unit |
| `*_DMACR.IOC_IrqEn` | Tables 6, 16, bit 12 (I2) | RG-2 |  | a | Unit |
| `*_DMACR.Dly_IrqEn` | Tables 6, 16, bit 13 | RG-2 |  | b | Unit |
| `*_DMACR.Err_IrqEn` | Tables 6, 16, bit 14 | RG-2 |  | a | Unit |
| `*_DMACR.IRQThreshold` | Tables 6, 16, bits 23 to 16 | RG-2 |  | b | Unit |
| `*_DMACR.IRQDelay` | Tables 6, 16, bits 31 to 24 | RG-2 |  | b | Unit |

### Status registers (Tables 7 and 17)

| Item | \[PG021\] reference | Owner | Also involved | Phase | First verified at |
| --- | --- | --- | --- | --- | --- |
| `*_DMASR.Halted` | Tables 7, 17, bit 0 | RG-1 | MM-1, S2-2 | a | Unit |
| `*_DMASR.Idle` | Tables 7, 17, bit 1 | RG-1 | SG-1 | a | Unit |
| `*_DMASR.Reserved` | Tables 7, 17, bits 2, 7, 11, 15 | RG-1 |  | a | Unit |
| `*_DMASR.SGIncld` | Tables 7, 17, bit 3 | RG-1 |  | a | Unit |
| `MM2S_DMASR.DMAIntErr` | Table 7, bit 4 | SG-1 | RG-1 | b | Unit |
| `S2MM_DMASR.DMAIntErr` | Table 17, bit 4 | S2-1 | RG-1, SG-1, S2-3 | a | Unit |
| `*_DMASR.DMASlvErr` | Tables 7, 17, bit 5 | MM-1 (MM2S), S2-2 (S2MM) | RG-1 | a | Unit |
| `*_DMASR.DMADecErr` | Tables 7, 17, bit 6 | MM-1 (MM2S), S2-2 (S2MM) | RG-1 | a | Unit |
| `*_DMASR.SGIntErr` | Tables 7, 17, bit 8 | SG-1 | RG-1 | b | Unit |
| `*_DMASR.SGSlvErr` | Tables 7, 17, bit 9 | SG-3 | RG-1 | b | Unit |
| `*_DMASR.SGDecErr` | Tables 7, 17, bit 10 | SG-3 | RG-1 | b | Unit |
| `*_DMASR.IOC_Irq` | Tables 7, 17, bit 12 | RG-2 | RG-1, SG-2 | a | Unit |
| `*_DMASR.Dly_Irq` | Tables 7, 17, bit 13 | RG-2 |  | b | Unit |
| `*_DMASR.Err_Irq` | Tables 7, 17, bit 14 | RG-2 |  | a | Unit |
| `*_DMASR.IRQThresholdSts` | Tables 7, 17, bits 23 to 16 | RG-2 |  | b | Unit |
| `*_DMASR.IRQDelaySts` | Tables 7, 17, bits 31 to 24 | RG-2 |  | b | Unit |

### Address, length and descriptor pointer registers

| Item | \[PG021\] reference | Owner | Also involved | Phase | First verified at |
| --- | --- | --- | --- | --- | --- |
| `*_CURDESC` | Tables 8, 18 | SG-1 | RG-1 | b | Unit |
| `*_CURDESC_MSB` | Tables 9, 19 | SG-1 | RG-1 | b | Unit |
| `*_TAILDESC` | Tables 10, 20 | SG-1 | RG-1 | b | Unit |
| `*_TAILDESC_MSB` | Tables 11, 21 | SG-1 | RG-1 | b | Unit |
| `MM2S_SA` | Table 12 | RG-1 | MM-1 | a | Unit |
| `MM2S_SA_MSB` | Table 13 | RG-1 | MM-1 | a | Unit |
| `MM2S_LENGTH` | Table 14 | RG-1 | MM-1 | a | Unit |
| `S2MM_DA` | Table 22 | RG-1 | S2-2 | a | Unit |
| `S2MM_DA_MSB` | Table 23 | RG-1 | S2-2 | a | Unit |
| `S2MM_LENGTH` | Table 24 | RG-1 | S2-1, S2-2 | a | Unit |
| `SG_CTL` | Table 15 | Out of scope (multichannel mode) |  | - | - |

### Descriptors (Tables 25 to 40)

| Item | \[PG021\] reference | Owner | Also involved | Phase | First verified at |
| --- | --- | --- | --- | --- | --- |
| `DESC.LAYOUT` | Table 25, word offsets, 16-word alignment | SG-1 | SG-2 | b | Unit |
| `DESC.NXTDESC` | Tables 26, 33 | SG-1 |  | b | Unit |
| `DESC.NXTDESC_MSB` | Tables 27, 34 | SG-1 |  | b | Unit |
| `DESC.BUFFER_ADDRESS` | Tables 28, 35 | SG-1 | MM-1, S2-2 | b | Unit |
| `DESC.BUFFER_ADDRESS_MSB` | Tables 29, 36 | SG-1 | MM-1, S2-2 | b | Unit |
| `DESC.MM2S_CONTROL.BufferLength` | Table 30, bits 25 to 0 | SG-1 | MM-1 | b | Unit |
| `DESC.MM2S_CONTROL.TXEOF` | Table 30, bit 26 | SG-1 | MM-2 | b | Unit |
| `DESC.MM2S_CONTROL.TXSOF` | Table 30, bit 27 | SG-1 | MM-2, MM-3 | b | Unit |
| `DESC.MM2S_STATUS.TransferredBytes` | Table 31, bits 25 to 0 | SG-2 |  | b | Unit |
| `DESC.MM2S_STATUS.DMAIntErr` | Table 31, bit 28 | SG-2 | SG-1 | b | Unit |
| `DESC.MM2S_STATUS.DMASlvErr` | Table 31, bit 29 | SG-2 | MM-1 | b | Unit |
| `DESC.MM2S_STATUS.DMADecErr` | Table 31, bit 30 | SG-2 | MM-1 | b | Unit |
| `DESC.MM2S_STATUS.Cmplt` | Table 31, bit 31 | SG-2 | SG-1 | b | Unit |
| `DESC.MM2S_APP` | Table 32 | MM-3 | SG-1 | c | Unit |
| `DESC.S2MM_CONTROL.BufferLength` | Table 37, bits 25 to 0 | SG-1 | S2-1 | b | Unit |
| `DESC.S2MM_CONTROL.RXSOF` | Table 37, bit 27 (micro mode) | SG-1 |  | c | Unit |
| `DESC.S2MM_CONTROL.RXEOF` | Table 37, bit 26 (micro mode) | SG-1 |  | c | Unit |
| `DESC.S2MM_STATUS.TransferredBytes` | Table 38, bits 25 to 0 | SG-2 | S2-2 | b | Unit |
| `DESC.S2MM_STATUS.RXEOF` | Table 38, bit 26 | SG-2 | S2-1 | b | Unit |
| `DESC.S2MM_STATUS.RXSOF` | Table 38, bit 27 | SG-2 | S2-1 | b | Unit |
| `DESC.S2MM_STATUS.DMAIntErr` | Table 38, bit 28 | SG-2 | S2-1, SG-1 | b | Unit |
| `DESC.S2MM_STATUS.DMASlvErr` | Table 38, bit 29 | SG-2 | S2-2 | b | Unit |
| `DESC.S2MM_STATUS.DMADecErr` | Table 38, bit 30 | SG-2 | S2-2 | b | Unit |
| `DESC.S2MM_STATUS.Cmplt` | Table 38, bit 31 | SG-2 | SG-1 | b | Unit |
| `DESC.S2MM_APP` | Table 39, APP0 to APP3 | S2-3 | SG-2 | c | Unit |
| `DESC.S2MM_APP4` | Table 40, APP4 and receive length | S2-3 | SG-2 | c | Unit |
| `DESCMGMT.TAIL` | Section "Descriptor Management", tail pointer mode | SG-1 | RG-1 | b | Unit |

### Streams, interrupts, clock and reset

| Item | \[PG021\] reference | Owner | Also involved | Phase | First verified at |
| --- | --- | --- | --- | --- | --- |
| `STRM.MM2S` | Section "MM2S Descriptor Settings and AXI Control Stream", Figure 37 (data stream) | MM-2 | MM-1 | a | Unit |
| `STRM.S2MM` | Section "S2MM Descriptor Settings and AXI Status Stream", Figure 39 (data stream) | S2-1 | S2-2 | a | Unit |
| `STRM.CNTRL` | Section "AXI Control Stream", Figure 38 | MM-3 |  | c | Unit |
| `STRM.STS` | Section "AXI Status Stream", Figure 40 | S2-3 |  | c | Unit |
| `STRM.RXLENGTH` | Section "Customizing and Generating the Core", Use RxLength In Status Stream | S2-3 | S2-1 | c | Unit |
| `IRQ.OUT` | Table 3, interrupt outputs | RG-2 |  | a | Unit |
| `CLK.SYNC` | Section "Clocking", synchronous mode | CO-1 |  | a | Core |
| `CLK.ASYNC` | Section "Clocking", asynchronous mode, Table 43 | Out of scope (D1) |  | - | - |
| `RST.HARD` | Section "Resets" | RG-3 |  | a | Unit |
| `RST.OUT` | Table 3, reset outputs of the streams (I12) | RG-3 |  | a | Unit |

### Features, configuration and programming sequences

| Item | \[PG021\] reference | Owner | Also involved | Phase | First verified at |
| --- | --- | --- | --- | --- | --- |
| `FEAT.4K` | Section "Core Overview", 4 KB address boundary | MM-1 (MM2S), S2-2 (S2MM) |  | a | Unit |
| `FEAT.BURST` | Table 44, `c_mm2s_burst_size`, `c_s2mm_burst_size` | MM-1 (MM2S), S2-2 (S2MM) | S2-1 | a | Unit |
| `FEAT.UNALIGNED` | Table 44, `c_include_mm2s_dre`, `c_include_s2mm_dre` (D2) | MM-1 (MM2S), S2-2 (S2MM) | MM-2, S2-1 | a | Unit |
| `FEAT.ADDR64` | Table 44, `c_addr_width` | CO-1 | RG-1, MM-1, S2-2 | a | Core |
| `FEAT.WIDTH` | Table 44, memory and stream data widths | CO-1 | MM-1, MM-2, S2-1, S2-2 | a | Core |
| `FEAT.LENWIDTH` | Table 44, `c_sg_length_width` | CO-1 | RG-1, SG-1 | a | Core |
| `FEAT.CHANNEL` | Table 44, `c_include_mm2s`, `c_include_s2mm` | CO-1 |  | a | Core |
| `FEAT.MICRO` | Table 44, `c_micro_dma`; section "Customizing and Generating the Core" | CO-1 | MM-1, S2-2 | c | Core |
| `FEAT.MULTICHANNEL` | Section "Multichannel DMA Support" | Out of scope |  | - | - |
| `SEQ.DR.MM2S` | Section "Programming Sequence", Direct Register Mode, MM2S | CO-1 | RG-1, MM-1, MM-2 | a | Core |
| `SEQ.DR.S2MM` | Section "Programming Sequence", Direct Register Mode, S2MM | CO-1 | RG-1, S2-1, S2-2 | a | Core |
| `SEQ.SG.MM2S` | Section "Programming Sequence", Scatter/Gather Mode, MM2S | CO-1 | SG-1, SG-2 | b | Core |
| `SEQ.SG.S2MM` | Section "Programming Sequence", Scatter/Gather Mode, S2MM | CO-1 | SG-1, SG-2 | b | Core |
| `SEQ.CYCLIC` | Section "Cyclic DMA Mode", Figure 48 | CO-1 | SG-1 | b | Core |

## 11 Development plan

1. Foundations: repository, common package, verification components (AXI memory model, stream models, sequence
   player, model of the programming sequences), regression and CI. In open-logic-ft: G5 (response code of failed
   commands).
2. Phase a: register interface (RG-1 to RG-4) with the generated register map, MM2S channel (MM-1, MM-2), S2MM
   channel (S2-1, S2-2), core top level in DR mode with the core tests of the DR programming sequences, user guide,
   synthesizability check, compliance matrix. QuestaSim with and without coverage at the end of the phase.
3. Phase b: in open-logic-ft G1 (FIXED bursts) and G10 (stream join and split); Scatter/Gather engine (SG-1 to
   SG-3), packets of several descriptors, cyclic mode, interrupt coalescing and delay, keyhole. QuestaSim with and
   without coverage for phases a and b together on the Open Logic tag with G1, G5 and G10.
4. Phase c: control and status streams (MM-3, S2-3), receive length, micro DMA.
5. Phase d: synthesis and timing closure on a target board, the drivers of a processor system against the core,
   hardware test report.

Possible later extensions: asynchronous clocks for the stream and memory ports (\[PG021\] Table 43) with
`olo_ft_fifo_async` and `olo_base_cc_*` (`SyncTmr_g` = true); a vendor wrapper with the signal names of the vendor
block; generics for the AXI cache and protection attributes.
