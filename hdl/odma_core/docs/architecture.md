# odma_core: Architecture and Design Description

## 1. Block diagram

![Block diagram of odma_core in phase a: the MM2S channel odma_mm2s between the MM2S memory port and the MM2S
stream, the register interface odma_registers with the register port, the interrupt and the reset outputs, the S2MM
channel odma_s2mm between the S2MM stream and the S2MM memory port; transfer commands and results, channel control
and ECC events with the buffer indices between the register interface and each channel](img/odma_core_arch.drawio.svg)

## 2. Entities

| Entity | Block | Content |
| --- | --- | --- |
| `odma_core` | CO-1 | Instances of the modules of the configuration, the index map of the FT buffers, the idle values of a channel that is not included, the consistency checks of the generics |
| `odma_registers` | RG-1 to RG-4 | Registers of both channels, the DR state machines, interrupts, soft reset, extension window (module `odma_registers`) |
| `odma_mm2s` | MM-1, MM-2 | MM2S channel (module `odma_mm2s`), generate `g_mm2s` with `IncludeMm2s_g` |
| `odma_s2mm` | S2-1, S2-2 | S2MM channel (module `odma_s2mm`), generate `g_s2mm` with `IncludeS2mm_g` |

`odma_core` contains no logic of its own: no register, no state machine, no Open Logic entity. Everything it does is
wiring, constants and assertions.

## 3. Ports

The ports are the external interfaces of the top-level architecture (section 6) for phase a.

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock and synchronous high-active reset of the whole core |
| `S_AxiLite_Ar*`, `S_AxiLite_Aw*`, `S_AxiLite_W*`, `S_AxiLite_B*`, `S_AxiLite_R*` | address 10, data 32 | in/out | AXI4-Lite register port |
| `M_AxiMm2s_Ar*`, `M_AxiMm2s_R*` | address `AddrWidth_g`, data `Mm2sMemWidth_g` | out/in | AXI4 read master of the MM2S channel (`ArAddr`, `ArLen`, `ArSize`, `ArBurst`, `ArLock`, `ArCache`, `ArProt`, `ArValid`, `ArReady`, `RData`, `RResp`, `RLast`, `RValid`, `RReady`) |
| `M_Mm2s_Data`, `_Keep`, `_Last`, `_Valid`, `_Ready` | data `Mm2sStreamWidth_g` | out/in | MM2S stream |
| `S_S2mm_Data`, `_Keep`, `_Last`, `_Valid`, `_Ready` | data `S2mmStreamWidth_g` | in/out | S2MM stream |
| `M_AxiS2mm_Aw*`, `M_AxiS2mm_W*`, `M_AxiS2mm_B*` | address `AddrWidth_g`, data `S2mmMemWidth_g` | out/in | AXI4 write master of the S2MM channel (`AwAddr`, `AwLen`, `AwSize`, `AwBurst`, `AwLock`, `AwCache`, `AwProt`, `AwValid`, `AwReady`, `WData`, `WStrb`, `WLast`, `WValid`, `WReady`, `BResp`, `BValid`, `BReady`) |
| `Mm2s_Irq`, `S2mm_Irq` | 1 | out | Channel interrupts, level, high-active |
| `Ecc_Irq` | 1 | out | ECC interrupt of the extension window, level, high-active |
| `Mm2s_RstOut`, `S2mm_RstOut` | 1 | out | Reset outputs for the stream peers, high-active |

The inputs of a channel's memory port and stream have default values, so that a configuration without that channel
can leave them open.

## 4. Connections

| Signal group | From | To | Description |
| --- | --- | --- | --- |
| `CoreRst` | `odma_registers` (RG-3) | Reset of both channels | `Rst`, or the reset phase of a soft reset (`odma_registers` architecture, section 6) |
| `Mm2sCmd_*`, `S2mmCmd_*` | RG-1 | Channel | Transfer commands of DR mode |
| `Mm2sRes_*`, `S2mmRes_*` | Channel | RG-1 | Transfer results |
| `Mm2s_Run`, `Mm2s_Drain`, `S2mm_Run`, `S2mm_Drain` | RG-1, RG-3 | Channel | Channel control |
| `Mm2s_Stopped`, `S2mm_Stopped` | Channel | RG-1, RG-3 | Channel stopped, nothing outstanding |
| `Ecc_Sec`, `Ecc_Ded` (16 bits) | Channels (3 bits each) | RG-4 | ECC events in the order of the buffer indices (section 5) |
| `EccInj_Valid` (16 bits), `EccInj_Double` | RG-4 | Channels | Error injection strobes, mapped back to the 3 bits of each channel |

The channels are reset by `CoreRst`; the register interface by `Rst` only, so that the soft reset can complete the
register access that started it.

## 5. FT buffer indices

The channels report their ECC events in their own bit order; `odma_core` maps them to the indices of the extension
window (`odma_registers` architecture, section 8) with the constants `EccMm2sData_c` to `EccMm2sResp_c` and the
function `eccIndex`:

| Index | Channel bit | Buffer |
| --- | --- | --- |
| 0 | MM2S bit 0 | MM2S read data buffer of `olo_ft_axi_master_full` |
| 1 | S2MM bit 0 | S2MM data buffer |
| 2 | S2MM bit 1 | S2MM chunk buffer |
| 3 | S2MM bit 2 | S2MM write data buffer of `olo_ft_axi_master_full` |
| 4 | MM2S bit 1 | MM2S transfer buffer |
| 5 | MM2S bit 2 | MM2S response buffer |
| 6 to 15 | none | '0' (phases b and c, reserved) |

The injection strobes take the same map in the opposite direction; `EccInj_Double` goes to both channels.

## 6. Channels that are not included

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

## 7. Consistency checks

Assertions of severity failure stop the elaboration of an inconsistent configuration (specification CO-CF-02):

| Check | Message |
| --- | --- |
| `coreConfigError` of `odma_pkg` (address and length width, power-of-two widths, stream not wider than the memory, burst sizes, buffers of at least two bursts) | The prefix `odma_core:` followed by the message of the function, which names the generic |
| `IncludeMm2s_g` or `IncludeS2mm_g` | `IncludeMm2s_g or IncludeS2mm_g must be true` |
| not `IncludeSg_g` | `IncludeSg_g must be false, Scatter/Gather Mode is not implemented` |
| not `StsCntrlStrm_g` and not `UseRxLength_g` | `StsCntrlStrm_g and UseRxLength_g must be false, the control and status streams are not implemented` |
| not `MicroDma_g` | `MicroDma_g must be false, the micro DMA configuration is not implemented` |

`lint/synth_check.py` elaborates and synthesises the core in its boundary configurations and checks that each
inconsistent configuration stops with its message.

## 8. Timing

The core adds no clock cycle to any path: the timing is that of the modules (`odma_registers` architecture section 9,
the architectures of `odma_mm2s` and `odma_s2mm`).
