# odma_core: Architecture and Design Description

## 1. Block diagram

![Block diagram of odma_core: the MM2S channel odma_mm2s between the MM2S memory port and the MM2S stream; in the
middle row the optional Scatter/Gather engine odma_sg with the descriptor port and the register interface
odma_registers with the register port, the interrupt and the reset outputs; the S2MM channel odma_s2mm between the
S2MM stream and the S2MM memory port; transfer commands and results between the middle row and each channel, channel
control and ECC events between the register interface and each channel, pointers, events and the ECC events 6 to 9
between the engine and the register interface](img/odma_core_arch.drawio.svg)

## 2. Entities

| Entity | Block | Content |
| --- | --- | --- |
| `odma_core` | CO-1 | Instances of the modules of the configuration, the selection of the command source (section 5), the index map of the FT buffers, the idle values of a port that is not included, the packet start detector (section 7), the consistency checks of the generics |
| `odma_registers` | RG-1 to RG-4 | Registers of both channels, the DR and SG state machines, interrupts, soft reset, extension window (module `odma_registers`) |
| `odma_sg` | SG-1 to SG-3 | Scatter/Gather engine with the descriptor port (module `odma_sg`), generate `g_sg` with `IncludeSg_g` |
| `odma_mm2s` | MM-1, MM-2 | MM2S channel (module `odma_mm2s`), generate `g_mm2s` with `IncludeMm2s_g` |
| `odma_s2mm` | S2-1, S2-2 | S2MM channel (module `odma_s2mm`), generate `g_s2mm` with `IncludeS2mm_g` |

The only logic of `odma_core` is the packet start detector: two registers per channel. Everything else is wiring,
constants and assertions; it instantiates no Open Logic entity of its own.

## 3. Ports

The ports are the external interfaces of the top-level architecture (section 6) for phases a and b.

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock and synchronous high-active reset of the whole core |
| `S_AxiLite_Ar*`, `S_AxiLite_Aw*`, `S_AxiLite_W*`, `S_AxiLite_B*`, `S_AxiLite_R*` | address 10, data 32 | in/out | AXI4-Lite register port |
| `M_AxiMm2s_Ar*`, `M_AxiMm2s_R*` | address `AddrWidth_g`, data `Mm2sMemWidth_g` | out/in | AXI4 read master of the MM2S channel (`ArAddr`, `ArLen`, `ArSize`, `ArBurst`, `ArLock`, `ArCache`, `ArProt`, `ArValid`, `ArReady`, `RData`, `RResp`, `RLast`, `RValid`, `RReady`) |
| `M_Mm2s_Data`, `_Keep`, `_Last`, `_Valid`, `_Ready` | data `Mm2sStreamWidth_g` | out/in | MM2S stream |
| `S_S2mm_Data`, `_Keep`, `_Last`, `_Valid`, `_Ready` | data `S2mmStreamWidth_g` | in/out | S2MM stream |
| `M_AxiS2mm_Aw*`, `M_AxiS2mm_W*`, `M_AxiS2mm_B*` | address `AddrWidth_g`, data `S2mmMemWidth_g` | out/in | AXI4 write master of the S2MM channel (`AwAddr`, `AwLen`, `AwSize`, `AwBurst`, `AwLock`, `AwCache`, `AwProt`, `AwValid`, `AwReady`, `WData`, `WStrb`, `WLast`, `WValid`, `WReady`, `BResp`, `BValid`, `BReady`) |
| `M_AxiSg_Ar*`, `M_AxiSg_R*`, `M_AxiSg_Aw*`, `M_AxiSg_W*`, `M_AxiSg_B*` | address `AddrWidth_g`, data 32 | out/in | AXI4 master of the Scatter/Gather engine for the descriptor fetches and status writes of both channels (the signals of both masters above); used with `IncludeSg_g` only |
| `Mm2s_Irq`, `S2mm_Irq` | 1 | out | Channel interrupts, level, high-active |
| `Ecc_Irq` | 1 | out | ECC interrupt of the extension window, level, high-active |
| `Mm2s_RstOut`, `S2mm_RstOut` | 1 | out | Reset outputs for the stream peers, high-active |

The inputs of a channel's memory port and stream and the inputs of the descriptor port have default values, so that
a configuration without that channel or without `IncludeSg_g` can leave them open.

## 4. Connections

| Signal group | From | To | Description |
| --- | --- | --- | --- |
| `CoreRst` | `odma_registers` (RG-3) | Reset of both channels and of the engine | `Rst`, or the reset phase of a soft reset (`odma_registers` architecture, section 6) |
| `Mm2sCmd_*`, `S2mmCmd_*` | RG-1 (DR mode) or SG-1 (SG mode) | Channel | Transfer commands (section 5) |
| `Mm2sRes_*`, `S2mmRes_*` | Channel | RG-1 (DR mode) or SG-2 (SG mode) | Transfer results (section 5) |
| `Mm2s_Run`, `Mm2s_Drain`, `S2mm_Run`, `S2mm_Drain` | RG-1, RG-3 | Channel and engine | Channel control |
| `Mm2s_Stopped`, `S2mm_Stopped` | Channel, engine | RG-1, RG-3 | Channel stopped, nothing outstanding; in SG mode the AND of the channel and its engine (section 5) |
| `Mm2sSg_*`, `S2mmSg_*` | RG-1, SG-1, SG-2 | Engine, RG-1, RG-2 | Descriptor engine control: `CURDESC`, tail pointer and its triggering write, `CyclicBD`, `Keyhole` to the engine; current descriptor pointer, idle, packet and error events to the register interface |
| `Mm2s_PktStart`, `S2mm_PktStart` | Packet start detector (section 7) | RG-2 | Pulse: the first beat of a packet at the stream port (delay timer) |
| `Ecc_Sec`, `Ecc_Ded` (16 bits) | Channels (3 bits each), engine (4 bits) | RG-4 | ECC events in the order of the buffer indices (section 6) |
| `EccInj_Valid` (16 bits), `EccInj_Double`, `EccInj_Data` | RG-4 | Channels, engine | Error injection strobes, mapped back to the bits of each module, with the error type and the mode |

The channels and the engine are reset by `CoreRst`; the register interface by `Rst` only, so that the soft reset can
complete the register access that started it.

## 5. Direct Register Mode and Scatter/Gather Mode

The register interface drives its command and result signals in both modes; `odma_core` decides with `IncludeSg_g`
who talks to the channels:

| Signal | Generate `g_dr` (not `IncludeSg_g`) | Generate `g_sg` (`IncludeSg_g`) |
| --- | --- | --- |
| Commands to the channels | From the register interface | From `odma_sg`; the command outputs of the register interface stay unused (in SG mode it issues none, `odma_sg` SG-IF-02) |
| Results of the channels | To the register interface | To `odma_sg`; the register interface sees no result valid |
| `Stopped` to the register interface | `Stopped` of the channel | `Stopped` of the channel AND `Stopped` of its engine (`odma_registers` RG-SG-10): a halt ends only after the last status write, a soft reset only when neither the channel nor the engine has an access outstanding |
| Engine outputs to the register interface | Idle values: pointer 0, idle '0', no event, error codes `ErrNone_c` | From `odma_sg` |
| Descriptor port | Idle values (section 8) | From `odma_sg` |
| ECC events 6 to 9 | '0' | From `odma_sg` |

**Packets of several buffers.** The core sets `Join_g` of `odma_mm2s` and `Split_g` of `odma_s2mm` to
`IncludeSg_g`: in SG mode the MM2S channel joins the buffers of a packet with `olo_base_stream_join` and the S2MM
channel splits a packet at the end of every buffer with `olo_base_stream_split`; in DR mode both keep the paths of a
packet per transfer, without the shifters of these entities. `odma_sg` writes `RXSOF` into a status from the result
flag `Res_Sof` of `odma_s2mm` (S2-SG-02).

## 6. FT buffer indices

The channels and the engine report their ECC events in their own bit order; `odma_core` maps them to the indices of
the extension window (`odma_registers` architecture, section 8) with the constants `EccMm2sData_c` to
`EccMm2sResp_c`, `EccSgLo_c` and the function `eccIndex`:

| Index | Module bit | Buffer |
| --- | --- | --- |
| 0 | MM2S bit 0 | MM2S read data buffer of `olo_ft_axi_master_full` |
| 1 | S2MM bit 0 | S2MM data buffer |
| 2 | S2MM bit 1 | S2MM chunk buffer |
| 3 | S2MM bit 2 | S2MM write data buffer of `olo_ft_axi_master_full` |
| 4 | MM2S bit 1 | MM2S transfer buffer |
| 5 | MM2S bit 2 | MM2S response buffer |
| 6 | engine bit 0 | MM2S descriptor buffer (`IncludeSg_g`) |
| 7 | engine bit 1 | S2MM descriptor buffer (`IncludeSg_g`) |
| 8 | engine bit 2 | Read data buffer of the descriptor port, `olo_ft_axi_master_simple` (`IncludeSg_g`) |
| 9 | engine bit 3 | Write data buffer of the descriptor port, `olo_ft_axi_master_simple` (`IncludeSg_g`) |
| 10 to 15 | none | '0' (reserved) |

The injection strobes take the same map in the opposite direction; `EccInj_Double` and `EccInj_Data` go to both
channels and to the engine.

## 7. Packet start detector

The delay timer of `odma_registers` stops and clears at the first beat of a packet at the stream port of the channel
(RG-SG-07, interpretation R10). The process `p_comb`/`p_seq` holds per channel the flag `InPkt` (a packet has started
and its `TLast` has not passed) and the pulse `PktStart`:

| Event at the stream port (handshake `Valid` and `Ready`) | `PktStart` in the next clock cycle | `InPkt` |
| --- | --- | --- |
| Beat while `InPkt` = '0' | '1' | '1', or '0' with `TLast` (a packet of one beat) |
| Beat while `InPkt` = '1' | '0' | '0' with `TLast`, otherwise '1' |
| No beat | '0' | unchanged |

`CoreRst` clears both registers, so that a packet abandoned by a soft reset does not hide the start of the next one.
The detector runs in both modes; in DR mode the register interface does not use the pulse.

## 8. Ports that are not included

Without `IncludeMm2s_g` (or `IncludeS2mm_g`) the generate block of the channel is replaced by constant idle values:

| Signal | Idle value |
| --- | --- |
| Command ready, result valid, result bytes, end of packet | '0', 0 |
| Result error code | `ErrNone_c` |
| `Stopped` | '1' (the soft reset never waits for the channel) |
| ECC events | '0' |
| AXI4 outputs | `ArValid`/`AwValid`, `WValid`, `WLast`, `RReady`/`BReady` '0'; `ArBurst`/`AwBurst` "01" (INCR); `ArCache`/`AwCache` "0011"; address, length, size, lock, protection, data and strobes 0 |
| Stream outputs | `M_Mm2s_Valid`, `_Last`, `_Data`, `_Keep` 0; `S_S2mm_Ready` '0' |

The registers of the channel read 0 and ignore writes (`odma_registers`, RG-MAP-03); its interrupt output stays '0'.
With `IncludeSg_g` the engine has no channel part for it (`odma_sg` architecture, section 3).

Without `IncludeSg_g` the descriptor port keeps constant idle values: `ArValid`, `AwValid`, `WValid`, `WLast`,
`RReady` and `BReady` '0'; `ArBurst` and `AwBurst` "01" (INCR); `ArSize` and `AwSize` "010" (4 bytes, the data
width); `ArCache` and `AwCache` "0011"; address, length, lock, protection, data and strobes 0.

## 9. Consistency checks

Assertions of severity failure stop the elaboration of an inconsistent configuration (specification CO-CF-02):

| Check | Message |
| --- | --- |
| `coreConfigError` of `odma_pkg` (address and length width, power-of-two widths, stream not wider than the memory, burst sizes, buffers of at least two bursts) | The prefix `odma_core:` followed by the message of the function, which names the generic |
| `IncludeMm2s_g` or `IncludeS2mm_g` | `IncludeMm2s_g or IncludeS2mm_g must be true` |
| not `StsCntrlStrm_g` and not `UseRxLength_g` | `StsCntrlStrm_g and UseRxLength_g must be false, the control and status streams are not implemented` |
| not `MicroDma_g` | `MicroDma_g must be false, the micro DMA configuration is not implemented` |

`lint/synth_check.py` elaborates and synthesises the core in its boundary configurations, in DR mode and in SG mode,
and checks that each inconsistent configuration stops with its message.

## 10. Timing

The core adds no clock cycle to the data and command paths: their timing is that of the modules (`odma_registers`
architecture section 9, the architectures of `odma_mm2s`, `odma_s2mm` and `odma_sg`). The packet start pulse follows
the first beat of a packet by one clock cycle; the delay timer counts in units of 125 clock cycles, so the cycle is
not visible in `IRQDelaySts`.
