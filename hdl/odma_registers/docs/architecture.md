# odma_registers: Architecture and Design Description

## 1. Block diagram

![Block diagram of odma_registers: the AXI4-Lite slave and the register bank RG-1 with the channel state machines,
the command and result interfaces of both channels and the control interface of the descriptor engines, the two
interrupt controllers RG-2, the reset controller RG-3 with the reset outputs and the extension window RG-4 with the
ECC monitor](img/odma_registers_arch.drawio.svg)

## 2. Entities

| Entity | Block | Content |
| --- | --- | --- |
| `odma_registers` | RG-1 and the module top | `olo_axi_lite_slave`, register decode, the state machine and the registers of each channel, the transfer command and result interfaces (Direct Register Mode), the control interface of the descriptor engines (Scatter/Gather Mode), instances of the entities below |
| `odma_interrupt` | RG-2 | One per channel: `IOC_Irq`, `Dly_Irq`, `Err_Irq`, their write-one-to-clear, the interrupt output; in Scatter/Gather Mode (`Sg_g`) the threshold counter and the delay timer |
| `odma_soft_reset` | RG-3 | Soft reset sequence, the core reset and the reset outputs |
| `odma_extension` | RG-4 | Extension window: identification, configuration readback, `olo_ft_ecc_monitor`, ECC flags and `Ecc_Irq`, error injection |

All entities run in `Clk`. `odma_soft_reset` is reset by `Rst` only; every other register of the core, including
the registers of this module, is reset by the core reset `CoreRst` = `Rst` or the reset phase of a soft reset.

## 3. Ports of `odma_registers`

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, synchronous high-active reset |
| `CoreRst` | 1 | out | Reset of the channels: `Rst` or the reset phase of a soft reset |
| `S_AxiLite_*` | 10-bit address, 32-bit data | in/out | AXI4-Lite slave (`ArAddr`, `ArValid`, `ArReady`, `AwAddr`, `AwValid`, `AwReady`, `WData`, `WStrb`, `WValid`, `WReady`, `BResp`, `BValid`, `BReady`, `RData`, `RResp`, `RValid`, `RReady`) |
| `Mm2sCmd_Valid`, `Mm2sCmd_Ready` | 1 | out, in | Transfer command handshake of the MM2S channel |
| `Mm2sCmd_Addr` | `AddrWidth_g` | out | Buffer address |
| `Mm2sCmd_Length` | `LengthWidth_g` | out | Bytes of the transfer |
| `Mm2sCmd_Sof`, `Mm2sCmd_Eof` | 1 | out | Start and end of packet ('1' in DR mode) |
| `Mm2sCmd_Keyhole` | 1 | out | Non-incrementing bursts (phase b; '0' in DR mode, interpretation I1) |
| `Mm2sRes_Valid`, `Mm2sRes_Ready` | 1 | in, out | Transfer result handshake of the MM2S channel (`Mm2sRes_Ready` = '1') |
| `Mm2sRes_Bytes` | `LengthWidth_g` | in | Transferred bytes |
| `Mm2sRes_Err` | 2 | in | Error code (`XferErr_t` of `odma_pkg`) |
| `Mm2s_Run` | 1 | out | The channel may accept commands |
| `Mm2s_Drain` | 1 | out | Stop accepting and issuing, drain the accepted transfers (soft reset) |
| `Mm2s_Stopped` | 1 | in | No transfer accepted and not completed, no AXI transaction outstanding |
| `Mm2sRes_Eof` | 1 | in | End of packet: the transfer completed |
| `S2mmCmd_Valid`, `S2mmCmd_Ready`, `S2mmCmd_Addr`, `S2mmCmd_Length`, `S2mmCmd_Keyhole` | as MM2S | | Transfer command of the S2MM channel; `S2mmCmd_Length` is the buffer length; the command has no start and end of packet |
| `S2mmRes_*`, `S2mm_Run`, `S2mm_Drain`, `S2mm_Stopped` | as MM2S | | The same for the S2MM channel; `S2mmRes_Bytes` is the bytes written, `S2mmRes_Eof` the end of the packet in the buffer |
| `Mm2sSg_CurDesc` | `AddrWidth_g` | out | Scatter/Gather Mode: the value `MM2S_CURDESC` reads, taken by the engine at the rising edge of `Mm2s_Run` |
| `Mm2sSg_Tail`, `Mm2sSg_TailWr` | `AddrWidth_g`, 1 | out | `MM2S_TAILDESC` and a pulse one clock cycle after the triggering write while the channel runs |
| `Mm2sSg_Cyclic`, `Mm2sSg_Keyhole` | 1 | out | `MM2S_DMACR.CyclicBD`, `MM2S_DMACR.Keyhole` |
| `Mm2sSg_CurPtr`, `Mm2sSg_Idle` | `AddrWidth_g`, 1 | in | Current descriptor pointer and idle level of the engine |
| `Mm2sSg_Pkt` | 1 | in | Pulse: a packet completed (threshold counter) |
| `Mm2sSg_ErrValid`, `Mm2sSg_ErrXfer`, `Mm2sSg_ErrSg` | 1, 2, 2 | in | Error report of the engine: transfer error and engine error (`XferErr_t`) |
| `Mm2s_PktStart` | 1 | in | Pulse: the first beat of a packet passed the stream port of the channel (delay timer) |
| `S2mmSg_*`, `S2mm_PktStart` | as MM2S | | The same for the S2MM channel |
| `Mm2s_Irq`, `S2mm_Irq`, `Ecc_Irq` | 1 | out | Interrupt outputs |
| `Mm2s_RstOut`, `S2mm_RstOut` | 1 | out | Reset outputs of the stream peers |
| `Ecc_Sec`, `Ecc_Ded` | `EccBuffers_c` | in | SEC and DED event pulses of the FT buffers (index per section 8) |
| `EccInj_Valid` | `EccBuffers_c` | out | Error injection strobe per FT buffer |
| `EccInj_Double` | 1 | out | '1': flip two bits, '0': flip one bit of the injected codeword |
| `EccInj_Data` | 1 | out | '1': flip data bits, '0': flip parity bits of the injected codeword |

The generics are those of section 6 of the specification. `EccBuffers_c` = 16, the fixed size of the buffer index
space of the extension window. The inputs of the channels, of the engines and the ECC inputs have defaults
(`Cmd_Ready` '0', `Res_Valid` '0', `Stopped` '1', the engine inputs 0, `Ecc_Sec` and `Ecc_Ded` 0), so that a
channel that is not included, or the engine interface in Direct Register Mode, needs no connection. The control
outputs of a channel that is not included stay '0' (`Cmd_Valid`, `Run`, `Drain`, `Irq`). In Scatter/Gather Mode the
`*_Stopped` input is the AND of `Stopped` of the channel and of its engine (the core combines them), and `*_Run` and
`*_Drain` go to both.

## 4. Register bank (RG-1)

### 4.1 Decode

`olo_axi_lite_slave` (`AxiAddrWidth_g` = 10) turns the AXI4-Lite accesses into single-cycle register reads and
writes. The decode uses the word address (bits 9 to 2); the write strobes are ignored (RG-IF-03). A read of a decoded
register returns its value in the next cycle (`Rb_RdValid` one cycle after `Rb_Rd`); every other read returns 0, so
that the read timeout of the slave never fires and every access completes with OKAY (RG-IF-02). Offsets 0x000 to
0x0FF are the registers of PG021 Table 5, offsets 0x100 to 0x1FF the extension window (`odma_extension`, section 7).
The register map is generated by `tools/regmap.py` from `hdl/odma_registers/regs/odma_regs.yml`.

### 4.2 Channel state machine (DR mode)

One state machine per channel holds the run state and the transfer in progress.

| State | `DMASR.Halted` | `DMASR.Idle` | Meaning |
| --- | --- | --- | --- |
| `Halted_s` | 1 | 0 | After a reset, after a halt or an error |
| `Started_s` | 0 | 0 | Running, no transfer completed yet |
| `Busy_s` | 0 | 0 | Transfer command issued or accepted, result outstanding |
| `Done_s` | 0 | 1 | Running, the last transfer completed |
| `Stopping_s` | 0 | 0 | Halt requested or error: no new command, waiting for the channel to report `Stopped` |

| From | Condition | To | Action |
| --- | --- | --- | --- |
| `Halted_s` | `DMACR.RS` written 1, no error flag set | `Started_s` | `Run` = '1' |
| `Halted_s`, `Stopping_s` | non-zero write of the length register | unchanged | The length is stored, no command (interpretation I7) |
| `Started_s`, `Done_s` | non-zero write of the length register | `Busy_s` | Capture address and length, `Cmd_Valid` until `Cmd_Ready` |
| `Busy_s` | result without error, end of packet, no halt pending | `Done_s` | `IOC_Irq` event; S2MM: `S2MM_LENGTH` := `Res_Bytes` |
| `Busy_s` | result with error | `Stopping_s` | Error flags (RG-SR-05, RG-SR-06), `RS` := 0, `Err_Irq` event, `Run` = '0' |
| `Busy_s` | `DMACR.RS` written 0 | `Busy_s` | Halt pending; `Run` = '0' once the command is accepted; the channel completes or ends the transfer in progress (interpretation I8) |
| `Busy_s` | result without error, halt pending | `Stopping_s` | `IOC_Irq` event and S2MM length update only when the result has the end of packet |
| `Started_s`, `Done_s` | `DMACR.RS` written 0 | `Stopping_s` | `Run` = '0' |
| `Stopping_s` | `Stopped` = '1' | `Halted_s` | |
| any | illegal state | `Halted_s` | Recovery (`when others`) |

A command is issued by the state machine only in `Busy_s` and only once (`Cmd_Valid` falls with the handshake). The
command address is a register captured at the length write, so later writes to the address registers do not change
the transfer in progress (RG-AR-08); the command length is the length register, which no write changes in `Busy_s`.
A result is always accepted (`Res_Ready` = '1'). A halt request while the command waits for `Cmd_Ready` keeps `Run`
at '1' until the command is accepted, because a channel accepts commands only while `Run` is '1'; the command is
never withdrawn. `DMACR.RS` = 1 is taken only in `Halted_s` without an error flag; in the other states a write of 1
leaves `RS` unchanged, in particular at 0 while the channel stops (interpretation R8 of the specification). A write
of `DMACR` with `Reset` = 1 only starts the soft reset; the other bits of that write are not taken.

The end-of-packet flag of a result tells whether the transfer completed: an MM2S result always carries it in DR mode
(the channel sends a transfer to its end, also after a halt request), an S2MM result carries it when the packet ended
in the buffer. A halt during an S2MM transfer makes the channel write the chunks complete in its buffer, discard the
rest of the packet up to `TLast` and return a result without the end of packet: no `IOC_Irq`, no length update
(interpretation I8).

### 4.3 Channel state machine (Scatter/Gather Mode)

With `IncludeSg_g` the state machine uses three states: the descriptor engine issues the transfer commands, the
register interface none.

| State | `DMASR.Halted` | `DMASR.Idle` | Meaning |
| --- | --- | --- | --- |
| `Halted_s` | 1 | 0 | After a reset, after a halt or an error |
| `Started_s` | 0 | `Idle` of the engine | Running |
| `Stopping_s` | 0 | 0 | Halt requested or error: waiting for `Stopped` of the channel and its engine (RG-SG-10) |

| From | Condition | To | Action |
| --- | --- | --- | --- |
| `Halted_s` | `DMACR.RS` written 1, no error flag set | `Started_s` | `Run` = '1'; reload of the threshold counter |
| `Started_s` | `DMACR.RS` written 0 | `Stopping_s` | `Run` = '0' |
| any | error report of the engine (`ErrValid`) | `Stopping_s` from `Started_s` | Error flags (RG-SG-05; S2MM `DMAIntErr` also with the slave and the decode error of a transfer), `RS` := 0, `Run` = '0', `Err_Irq` event |
| `Stopping_s` | `Stopped` = '1' | `Halted_s` | |
| any | illegal state | `Halted_s` | Recovery (`when others`) |

`CURDESC` is a register with a flag `CurOwn`: while `CurOwn` is '1', `CURDESC` reads the pointer of the engine
(`CurPtr`), otherwise the written value. `CurOwn` becomes '1' one clock cycle after the channel has left
`Halted_s`, so it stays '1' after the halt and `CURDESC` keeps the last pointer of the engine (SG-FE-07). A write of
`CURDESC` or `CURDESC_MSB` in `Halted_s` stores the current value with the written word replaced and clears
`CurOwn`; writes in the other states are ignored (RG-SG-02). The value `CURDESC` reads goes to the engine, which
takes it at the rising edge of `Run`; as `CurOwn` changes only one clock cycle after the start, the engine takes the
value software has written.

`TAILDESC` and `TAILDESC_MSB` are read/write in every state. `TailWr` is a registered pulse: it follows the
triggering write (`TAILDESC` with 32 address bits, `TAILDESC_MSB` above, interpretation SGI-01) by one clock cycle,
together with the updated register, and only when that write takes effect in `Started_s` (RG-SG-03). `Keyhole` and
`CyclicBD` go to the engine as stored in `DMACR` (RG-SG-09). The registers of Direct Register Mode (`*_SA`,
`*_DA`, `*_LENGTH`) do not exist; their offsets read 0 (RG-SG-01).

### 4.4 Registers

| Register | Implementation |
| --- | --- |
| `DMACR` | `RS`, `Keyhole`, `CyclicBD`, `IOC_IrqEn`, `Dly_IrqEn`, `Err_IrqEn`, `IRQThreshold` (write of 0 ignored), `IRQDelay` as flip-flops; bit 1 constant 1; `Reset` reads the busy level of `odma_soft_reset` |
| `DMASR` | `Halted` and `Idle` decoded from the state (Scatter/Gather Mode: `Idle` of the engine in `Started_s`); `SGIncld` constant; error flags as flip-flops set by results or by the error reports of the engine (an S2MM error with the slave or the decode error also sets `DMAIntErr`; the MM2S channel never returns the internal error code in DR mode, so `MM2S_DMASR.DMAIntErr` reads 0 there); interrupt flags from `odma_interrupt`; DR mode: `IRQThresholdSts` = `IRQThreshold`, `Dly_Irq`, `IRQDelaySts` and the engine flags 0; Scatter/Gather Mode: `IRQThresholdSts` and `IRQDelaySts` the counter and the timer of `odma_interrupt` |
| `*_SA`, `*_SA_MSB`, `*_DA`, `*_DA_MSB` | `AddrWidth_g` flip-flops per channel; the bits of the MSB register exist only above 32 address bits |
| `*_LENGTH` | `LengthWidth_g` flip-flops per channel; written by software as RG-AR-07 allows, by the S2MM result on completion |
| `*_CURDESC`, `*_CURDESC_MSB` | Scatter/Gather Mode: `AddrWidth_g` - 6 flip-flops and `CurOwn` per channel (section 4.3) |
| `*_TAILDESC`, `*_TAILDESC_MSB` | Scatter/Gather Mode: `AddrWidth_g` - 6 flip-flops per channel and the `TailWr` pulse |

## 5. Interrupt controller (RG-2, `odma_interrupt`)

Inputs per channel: the enables `Ena_Ioc`, `Ena_Dly` and `Ena_Err` from `DMACR`, the events `Evt_Ioc` and
`Evt_Err` (one cycle each, combinational from the result handshake or the error report), the clears `Clr_Ioc`,
`Clr_Dly` and `Clr_Err` (a write of `DMASR` with a 1 in bit 12, 13 or 14). Flags: `Flag_Ioc` is set by an IOC event,
`Flag_Dly` by a timeout, `Flag_Err` by `Evt_Err`; a clear resets a flag unless an event of the same cycle sets it
(RG-IR-03). Output: `Irq` = registered OR of (`Flag_Ioc` and `Ena_Ioc`), (`Flag_Dly` and `Ena_Dly`) and (`Flag_Err`
and `Ena_Err`) (RG-IR-04, RG-SG-08). In Direct Register Mode `Evt_Ioc` is the IOC event and `Flag_Dly` stays 0.

In Scatter/Gather Mode (`Sg_g`) the IOC event comes from the threshold counter, and the delay timer sets `Flag_Dly`:

| Part | Behaviour |
| --- | --- |
| Threshold counter (RG-SG-06) | 8 bits, reset value 1. `Thr_Load` (one clock cycle after the start of the channel and after a write of a non-zero `IRQThreshold`, so that the new value is loaded) loads `IRQThreshold`. A packet event (`Evt_Pkt`) decrements it; at a count of 1 it raises the IOC event instead and reloads `IRQThreshold`, so the counter never reads 0 |
| Delay timer (RG-SG-07, interpretation R9) | A prescaler of 125 clock cycles and an 8-bit timer. A packet event clears both and starts the timer when it did not raise the IOC event, otherwise stops it. The start of a packet (`Evt_PktStart`) stops and clears it; a packet event in the same clock cycle wins. When the timer reaches `IRQDelay` it raises the timeout (`Flag_Dly`), clears itself and reloads the threshold counter. `IRQDelay` = 0 stops and clears it |

The packet event of MM2S comes from the engine after the status write of the descriptor with `TXEOF`, the start of
the next MM2S packet from the stream port of the channel. With descriptors fetched and issued ahead, the next packet
can start before the completion event of the previous one arrives; the timer then runs during that packet, so a
`Dly_Irq` can come while a packet is in progress. This is the case the timer exists for: software is told that
completed packets wait.

## 6. Reset controller (RG-3, `odma_soft_reset`)

| State | `Busy` (`DMACR.Reset`) | `Drain` | `CoreRst` | Reset outputs | Next |
| --- | --- | --- | --- | --- | --- |
| `Idle_s` | 0 | 0 | `Rst` | `Rst` | `Drain_s` on a write of 1 to `DMACR.Reset` of either channel |
| `Drain_s` | 1 | 1 | 0 | 1 | `Reset_s` when `Mm2s_Stopped` and `S2mm_Stopped` (of the included channels) |
| `Reset_s` | 1 | 1 | 1 | 1 | `Idle_s` after 16 clock cycles |

The register writes of software are ignored from `Drain_s` to the end of `Reset_s` (RG-RS-04). `Drain` tells the
channels to stop accepting commands and stream data, to discard read data and to complete the accepted AXI
transactions (architecture D8); `Stopped` reports that nothing is outstanding, and a channel that is not included
counts as stopped. The illegal-state recovery leads to `Idle_s`.

`olo_axi_lite_slave`, `odma_soft_reset` and the read strobe register of the register bank are reset by `Rst` only,
so that an access in progress at the start of the reset phase completes with OKAY. A read during the reset phase
returns the reset values, with `DMACR.Reset` = 1.

## 7. Extension window (RG-4, `odma_extension`)

| Offset | Name | Access | Content |
| --- | --- | --- | --- |
| 0x100 | `EXT_ID` | RO | 0x4F444D41 ("ODMA") |
| 0x104 | `EXT_VERSION` | RO | Bits 23 to 16 major, 15 to 8 minor, 7 to 0 patch level |
| 0x108 | `EXT_CONFIG` | RO | Bit 0 `IncludeSg_g`, 1 `IncludeMm2s_g`, 2 `IncludeS2mm_g`, 3 `StsCntrlStrm_g`, 4 `UseRxLength_g`, 5 `MicroDma_g`; bits 12 to 8 `LengthWidth_g`, 22 to 16 `AddrWidth_g` |
| 0x10C | `EXT_MM2S_CONFIG` | RO | Bits 3 to 0 log2 of the memory width in bytes, 7 to 4 log2 of the stream width in bytes, 11 to 8 log2 of the burst beats, 31 to 12 the buffer depth in stream beats |
| 0x110 | `EXT_S2MM_CONFIG` | RO | The same for the S2MM channel |
| 0x120 | `ECC_INFO` | RO | Bits 7 to 0 the number of buffer indices (16), 12 to 8 the counter width (16) |
| 0x124 | `ECC_CTRL` | W1 | Bit 0: clear all counters |
| 0x128 | `ECC_STATUS` | W1C | Bit 0 a SEC event, bit 1 a DED event was counted since the last clear |
| 0x12C | `ECC_ENABLE` | RW | Bits 0 and 1: the `ECC_STATUS` bits that drive `Ecc_Irq` (reset 0) |
| 0x130 | `ECC_INJECT` | W1 | Bits 3 to 0 the buffer index, bit 8 '1' double, '0' single error, bit 9 '1' injects into the next codeword written to the buffer, bit 10 '1' data bits, '0' parity bits |
| 0x140 + 4 x n | `ECC_COUNT_n` | RC | Bits 15 to 0 the SEC counter, 31 to 16 the DED counter of buffer n (n = 0 to 15); any write clears both |

The counters are those of `olo_ft_ecc_monitor` (`Channels_g` = 16, `CounterWidth_g` = 16): the window reads a
counter through its read port and clears it with the read-and-clear of the same port on a write. The `In_Valid`
inputs of the monitor are set for the buffers of the configuration only (section 8), so the counters of the other
indices stay 0; `ECC_INJECT` gives no strobe for them either. The `ECC_STATUS` flags are set by the event outputs of
the monitor, `Ecc_Irq` is registered one clock cycle after them. `EccInj_Valid` is a strobe of one clock cycle on the
selected index, `EccInj_Double` and `EccInj_Data` hold the error type and the mode of the last injection (both '0'
after a hard or soft reset); the buffer turns it into the flip pattern
of its `ErrInj_BitFlip` input and applies it to the next codeword written. Without `ExtRegs_g` the window reads 0,
`Ecc_Irq` stays low and no injection strobe is issued.

## 8. FT buffer index

| Index | Buffer | Phase |
| --- | --- | --- |
| 0 | MM2S read data buffer (`olo_ft_axi_master_full`) | a |
| 1 | S2MM data buffer (`olo_ft_fifo_sync` of S2-1) | a |
| 2 | S2MM chunk buffer (`olo_ft_fifo_sync` of S2-1) | a |
| 3 | S2MM write data buffer (`olo_ft_axi_master_full`) | a |
| 4 | MM2S transfer buffer (`olo_ft_fifo_sync` of MM-1) | a |
| 5 | MM2S response buffer (`olo_ft_fifo_sync` of MM-1) | a |
| 6 | MM2S descriptor buffer of the Scatter/Gather engine (`olo_ft_fifo_sync`) | b |
| 7 | S2MM descriptor buffer of the Scatter/Gather engine (`olo_ft_fifo_sync`) | b |
| 8 | Read data buffer of the descriptor port (`olo_ft_axi_master_simple`) | b |
| 9 | Write data buffer of the descriptor port (`olo_ft_axi_master_simple`) | b |
| 10, 11 | Control and status stream buffers | c |
| 12 to 15 | Reserved | |

Buffers of an excluded channel or a later phase count nothing.

## 9. Timing

- Register read: `RValid` rises 3 clock cycles after the clock cycle of the read address handshake (read strobe of
  `olo_axi_lite_slave` in the next cycle, read data one cycle later, `RValid` in the cycle after).
- Register write: with the write data present, `BValid` rises 2 clock cycles after the clock cycle of the write
  address handshake. The write takes effect at the end of the clock cycle in which `BValid` rises.
- A length write raises `Cmd_Valid` in the clock cycle after it takes effect; the state change to `Busy_s` and
  `DMASR.Idle` = 0 are visible to the next read.
- Scatter/Gather Mode: `Run` rises in the clock cycle after the write of `RS` = 1 takes effect; `TailWr` follows
  the triggering tail pointer write by one clock cycle. A packet event updates the threshold counter and `IOC_Irq` at
  the end of its clock cycle; a timeout of the delay timer sets `Dly_Irq` 125 x `IRQDelay` clock cycles after the
  packet event that started it, and the interrupt output follows one clock cycle later.
- A result updates the status registers and the interrupt flags at the end of the clock cycle of its handshake; the
  interrupt output follows one clock cycle later. A clear of a flag (write of `DMASR`) and a result in the same
  clock cycle leave the flag set, so a result whose handshake is in or after the clock cycle in which `BValid` of the
  clearing write rises is never lost.
