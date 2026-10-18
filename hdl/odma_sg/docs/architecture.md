# odma_sg: Architecture and Design Description

## 1. Block diagram

![Block diagram of odma_sg: one channel engine per channel (SG-1 descriptor fetch and SG-2 descriptor update) with
its descriptor buffer olo_ft_fifo_sync, the command and result interfaces towards the channels and the control
interface towards the register interface, and the descriptor port SG-3 with two round-robin arbiters olo_base_arb_rr
and the AXI4 master olo_ft_axi_master_simple](img/odma_sg_arch.drawio.svg)

## 2. Entities

| Entity | Block | Content |
| --- | --- | --- |
| `odma_sg` | Module top | One channel engine per included channel, the descriptor port, the ECC signals of the four FT buffers |
| `odma_sg_channel` | SG-1, SG-2 | One per channel (generic `Mm2s_g`): tail pointer handling, fetch requests and the assembly of the fetched words, the descriptor buffer, the checks of a descriptor, transfer commands, the queue of the commands without result, the status update, the current descriptor pointer, idle, stopped, the events towards the register interface |
| `odma_sg_port` | SG-3 | Arbitration of the fetches and of the updates of both channels, the AXI4 master, the routing of the read data, the end of every access with its error code |
| `olo_ft_fifo_sync` (one per channel) | SG-1 | Descriptor buffer: the fields of up to two fetched descriptors that have not been issued |
| `olo_base_arb_rr` (two) | SG-3 | Fetch arbiter and update arbiter, two requesters each |
| `olo_ft_axi_master_simple` | SG-3 | AXI4 master with the ECC-protected read and write data buffers, 32 data bits |

The descriptor port uses `olo_ft_axi_master_simple`, not `olo_ft_axi_master_full`: every descriptor access is a
burst of whole 32-bit words at an address aligned to 64 bytes, which needs no alignment logic, and the simple master
takes a command in fewer clock cycles (architecture gap G7). Its read and write data buffers are the FT buffers 8
and 9.

## 3. Ports of `odma_sg`

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, reset (the core reset `CoreRst`) |
| `Mm2s_Run` | 1 | in | `MM2S_DMACR.RS` of the register interface: the channel runs; a rising edge starts the channel |
| `Mm2s_Drain` | 1 | in | Drain of a soft reset |
| `Mm2s_CurDesc` | `AddrWidth_g` | in | `MM2S_CURDESC` and `MM2S_CURDESC_MSB` as written by software, taken at the start |
| `Mm2s_Tail`, `Mm2s_TailWr` | `AddrWidth_g`, 1 | in | `MM2S_TAILDESC` and `MM2S_TAILDESC_MSB`; a pulse at the triggering write while the channel runs (interpretation SGI-01) |
| `Mm2s_Cyclic`, `Mm2s_Keyhole` | 1 | in | `MM2S_DMACR.CyclicBD`, `MM2S_DMACR.Keyhole` |
| `Mm2s_CurPtr` | `AddrWidth_g` | out | Current descriptor pointer (SG-FE-07), bits 5 to 0 zero |
| `Mm2s_Idle` | 1 | out | The engine has reached the tail and nothing is pending (`MM2S_DMASR.Idle`) |
| `Mm2s_Stopped` | 1 | out | Nothing outstanding (section 8) |
| `Mm2s_Pkt` | 1 | out | Pulse: a packet completed, its status written (SG-UP-04, SG-UP-05) |
| `Mm2s_ErrValid` | 1 | out | Pulse: an error of the channel |
| `Mm2s_ErrXfer`, `Mm2s_ErrSg` | 2, 2 | out | With `Mm2s_ErrValid`: the transfer error (`XferErr_t`: `DMAIntErr`, `DMASlvErr`, `DMADecErr`) and the engine error (the same codes for `SGIntErr`, `SGSlvErr`, `SGDecErr`), `ErrNone_c` where none |
| `Mm2sCmd_Valid`, `Mm2sCmd_Ready` | 1 | out, in | Transfer command to `odma_mm2s` |
| `Mm2sCmd_Addr`, `Mm2sCmd_Length` | `AddrWidth_g`, `LengthWidth_g` | out | Buffer address and buffer length of the descriptor |
| `Mm2sCmd_Sof`, `Mm2sCmd_Eof`, `Mm2sCmd_Keyhole` | 1 | out | `TXSOF`, `TXEOF` of the descriptor, keyhole |
| `Mm2sRes_Valid`, `Mm2sRes_Ready` | 1 | in, out | Transfer result of `odma_mm2s` |
| `Mm2sRes_Bytes`, `Mm2sRes_Eof`, `Mm2sRes_Err` | `LengthWidth_g`, 1, 2 | in | Transferred bytes, end of packet (the `TXEOF` of the command), error code |
| `S2mm_*` | as MM2S | | The same control interface for the S2MM channel |
| `S2mmCmd_Valid`, `S2mmCmd_Ready`, `S2mmCmd_Addr`, `S2mmCmd_Length`, `S2mmCmd_Keyhole` | as MM2S | | Transfer command to `odma_s2mm`, without start and end of packet |
| `S2mmRes_Valid`, `S2mmRes_Ready`, `S2mmRes_Bytes`, `S2mmRes_Eof`, `S2mmRes_Err` | as MM2S | | Transfer result of `odma_s2mm`: bytes written, the packet ended in the buffer, error code |
| `S2mmRes_Sof` | 1 | in | The buffer is the first buffer of a packet (`odma_s2mm` S2-SG-02, interpretation SGI-13) |
| `M_Axi_Ar*`, `M_Axi_R*`, `M_Axi_Aw*`, `M_Axi_W*`, `M_Axi_B*` | `AddrWidth_g` address, 32 data bits | out/in | Descriptor port: AXI4 master without ID signals (`ArAddr`, `ArLen`, `ArSize`, `ArBurst`, `ArLock`, `ArCache`, `ArProt`, `ArValid`, `ArReady`, `RData`, `RResp`, `RLast`, `RValid`, `RReady`, `AwAddr`, `AwLen`, `AwSize`, `AwBurst`, `AwLock`, `AwCache`, `AwProt`, `AwValid`, `AwReady`, `WData`, `WStrb`, `WLast`, `WValid`, `WReady`, `BResp`, `BValid`, `BReady`) |
| `Ecc_Sec`, `Ecc_Ded` | 4 | out | ECC events of the MM2S descriptor buffer (bit 0, index 6 of the extension window), the S2MM descriptor buffer (bit 1, index 7), the read data buffer (bit 2, index 8) and the write data buffer (bit 3, index 9) of the descriptor port; one pulse per word read from the buffer |
| `EccInj_Valid` | 4 | in | Error injection per buffer, same order |
| `EccInj_Double`, `EccInj_Data` | 1 | in | Error type and mode of the injection, as in the channels |

Generics: `IncludeMm2s_g`, `IncludeS2mm_g`, `AddrWidth_g` and `LengthWidth_g` as in section 6 of the specification.
The ports of a channel that is not included keep their idle values (`CurPtr` 0, `Idle` '0', `Stopped` '1', no
event, `Cmd_Valid` '0', `Res_Ready` '0'), and its buffer counts nothing.

## 4. Channel engine (SG-1, SG-2, `odma_sg_channel`)

### 4.1 State of a channel

| Register | Width | Content |
| --- | --- | --- |
| `NextPtr` | `AddrWidth_g` - 6 | Address of the next descriptor to fetch: `CurDesc` at the start, then `NXTDESC` of the last fetched descriptor |
| `LastPtr` | `AddrWidth_g` - 6 | Address of the last fetched descriptor |
| `TailPtr` | `AddrWidth_g` - 6 | Tail pointer of the engine, taken from `Tail` at every `TailWr` |
| `Started` | 1 | A tail pointer write has been taken since the start: fetching is enabled |
| `AtTail` | 1 | The last fetched descriptor is the tail: no further fetch |
| `BufCnt`, `IssCnt` | 2, 2 | Entries of the descriptor buffer and issued commands without result; with a fetch in progress they form `Count`, the descriptors in the window |
| `Issued` | 2 entries of `AddrWidth_g` - 6 | Queue of the descriptors whose command was accepted by the channel and whose result is outstanding, oldest first |
| `Update` | 1 entry | The result being written back: descriptor address, status word, end of packet, transfer error |
| `ErrStop`, `ErrPtr` | 1, `AddrWidth_g` - 6 | An error occurred: no further fetch or command; the descriptor of the first error |
| `StaleHold` | 1 | A stale descriptor was fetched: no further fetch (section 4.3) |
| `Halted` | 1 | `Run` is '0' and no access, command or status update of the channel is outstanding: `CurPtr` is held, the descriptor buffer is emptied |

Descriptor pointers are held without their bits 5 to 0, which are ignored (SG-FE-01), and without the bits at or above
`AddrWidth_g` (SG-IF-03). The descriptors of a channel are processed strictly in order: they are fetched, issued,
completed and updated in the order of the chain. At every clock edge `Count` is at most 2: the buffer count
follows the push and pop of the buffer, the issued count the command handshakes and the results, one result per
accepted command.

### 4.2 Start and tail pointer

A rising edge of `Run` starts the channel: `NextPtr` := `CurDesc`, `Started` := '0', `AtTail` := '0', `ErrStop`
:= '0', `Halted` := '0'. The engine fetches nothing before the first tail pointer write after the start (SG-FE-02).

| `TailWr` while | Action |
| --- | --- |
| `Started` = '0' | `TailPtr` := `Tail`, `Started` := '1': fetching starts at `NextPtr`, the descriptor at `CURDESC` |
| `Idle` = '1' | `TailPtr` := `Tail`, `AtTail` := '0': fetching restarts at `NextPtr`, the `NXTDESC` of the tail, whatever the new value |
| otherwise | `TailPtr` := `Tail`; `AtTail` := `AtTail` and (`LastPtr` = `Tail`): when the tail has already been fetched and the new tail is another descriptor, fetching continues at `NextPtr`; otherwise only the pause point moves |

With 32 address bits `TailWr` is the write of `TAILDESC`, above 32 bits the write of `TAILDESC_MSB`; the register
interface decides it (interpretation SGI-01, `odma_registers` RG-SG-03) and gives no `TailWr` while the channel is
halted.

### 4.3 Fetch

A fetch is requested from the descriptor port when `Run` = '1', `Drain` = '0', `ErrStop` = '0', `Started` = '1',
`AtTail` = '0' and `Count` < 2. The window of two descriptors keeps the engine one descriptor ahead of the one in
progress (SG-FE-04): while descriptor n is being transferred, descriptor n + 1 is fetched and, for MM2S, issued to
the channel, whose transfer buffer queues it; descriptor n + 2 is fetched once the result of n has been taken.
`Cyclic` and `Keyhole` are taken when the fetch is requested (`odma_registers` RG-SG-09).

The request carries `NextPtr`; the port reads the 8 words at offsets 0x00 to 0x1C with one burst (SG-FE-01) and
passes them to the engine in order. The engine keeps the words it needs:

| Word | Offset | Taken |
| --- | --- | --- |
| `NXTDESC`, `NXTDESC_MSB` | 0x00, 0x04 | Bits `AddrWidth_g` - 1 to 6; the upper word only above 32 address bits (SG-IF-03) |
| `BUFFER_ADDRESS`, `BUFFER_ADDRESS_MSB` | 0x08, 0x0C | Bits `AddrWidth_g` - 1 to 0; the upper word only above 32 address bits |
| Reserved | 0x10, 0x14 | Not used |
| `CONTROL` | 0x18 | Bits `LengthWidth_g` - 1 to 0 the buffer length; MM2S: bit 27 `TXSOF`, bit 26 `TXEOF`; S2MM: bits 27 and 26 ignored (SG-TR-02) |
| `STATUS` | 0x1C | Bit 31 `Cmplt` |

At the end of a fetch without error the engine writes the entry of section 6 into the descriptor buffer, `LastPtr`
:= the fetched address, `NextPtr` := `NXTDESC`, and `AtTail` := (fetched address = `TailPtr`) and not `Cyclic`
(SG-FE-03, SG-CY-01). A tail pointer write in the same clock cycle is taken first, so the comparison uses the new
`TailPtr`. A fetched stale descriptor (`Cmplt` = 1 outside cyclic mode) stops further fetch requests at once
(`StaleHold`); its error follows when it reaches the head of the buffer (section 4.4), so no descriptor behind it is
fetched.

A fetch that ends with an error writes nothing into the buffer; the engine sets `ErrStop`, `ErrPtr` := the fetched
address and reports the engine error of the access (SG-ER-02, section 4.7).

### 4.4 Issue

The head entry of the descriptor buffer is checked when it is at the output while `Run` = '1', `Drain` = '0' and
`ErrStop` = '0':

| Head entry | Action |
| --- | --- |
| `Stale` = '1' (`Cmplt` = 1 outside cyclic mode) | Not issued and not written: `ErrStop`, `ErrPtr` := its address, engine error `SGIntErr` (SG-FE-05, interpretation SGI-09) |
| Otherwise | `Cmd_Valid` = '1' while `Run` = '1', `Drain` = '0' and `ErrStop` = '0', with the buffer address, the buffer length, `Sof`, `Eof` (MM2S) and `Keyhole` of the entry; at the handshake the entry is popped and its address enters `Issued` |

A buffer length of 0 is issued like any other descriptor: both channels return the internal error without
transferring anything (`odma_mm2s` MM-RD-06, `odma_s2mm` S2-WR-06), and the result path writes `DMAIntErr` into the
status and reports it (SG-FE-06). A buffer beyond the top of the address space returns the decode error in the same
way (architecture D7).

`Cmd_Valid` is qualified with `Run`: both channels accept a command only while `Run` = '1', so a command is withdrawn
exactly when it can no longer be accepted, and a halt never forces a command into the channel. A descriptor whose
command was not accepted stays in the buffer and has not been started.

### 4.5 Result and status update

`Res_Ready` = '1' while the `Update` stage is empty. At the result handshake the head of `Issued` is popped and the
result is classified:

| Result | Action |
| --- | --- |
| 0 bytes, no end of packet, no error, `Run` = '0' (an S2MM transfer halted before any byte arrived, `odma_s2mm` S2-HA-01) | Not started: no status write; `CurPtr` is held at this descriptor until the stop, like the descriptors not issued (SG-HA-01, interpretation SGI-10) |
| Any other | Into the `Update` stage with the status word below; a write of one word at offset 0x1C of the descriptor is requested |

| Status bits | Content |
| --- | --- |
| 25 to 0 | `Res_Bytes`, zero-extended from `LengthWidth_g` bits (SG-UP-01 to SG-UP-03) |
| 26, 27 | S2MM: `RXEOF` = `Res_Eof`, `RXSOF` = `Res_Sof`; MM2S: 0 |
| 28 | `DMAIntErr`: error code `ErrInt_c`; S2MM also `ErrSlv_c` and `ErrDec_c`, as in Direct Register Mode (interpretation I13) |
| 29 | `DMASlvErr`: `ErrSlv_c` |
| 30 | `DMADecErr`: `ErrDec_c` |
| 31 | `Cmplt`: '1' when the error code is `ErrNone_c` (interpretation SGI-02) |

An S2MM transfer that a halt ended inside a packet gets the bytes written and `Cmplt` = '1' without `RXEOF`
(interpretation SGI-11). A result
with an error sets `ErrStop` at the handshake, so that no further command is issued, and `ErrPtr` := its descriptor
unless an earlier error is stored.

When the write of the status ends, the engine raises at most one event in the same clock cycle and empties the
`Update` stage:

| End of the status write | Event |
| --- | --- |
| No error, transfer error `ErrNone_c`, end of packet | `Pkt` (SG-UP-04, SG-UP-05) |
| No error, transfer error `ErrNone_c`, no end of packet | None |
| Transfer error or write error | `ErrValid` with `ErrXfer` = the transfer error and `ErrSg` = the engine error of the write (SG-ER-01, SG-ER-02); a write error also sets `ErrStop` and `ErrPtr` |

So the register interface sets an error flag of a transfer only when software can already read the status of its
descriptor (interpretation SGI-12). The end of packet is `Res_Eof`: for MM2S the `TXEOF` of the command, for S2MM
the end of the packet in the buffer.

### 4.6 Current descriptor pointer and idle

`CurPtr` is a register, loaded from the first matching row in every clock cycle while `Halted` = '0':

| Condition | `CurPtr` (SG-FE-07) |
| --- | --- |
| `ErrStop` = '1' | `ErrPtr`: the descriptor of the first error |
| A result classified as not started was taken (section 4.5) | That descriptor |
| `Issued` not empty | The oldest issued descriptor: its transfer is in progress |
| Descriptor buffer not empty | Its head: the next descriptor to be processed |
| `AtTail` = '1' | `LastPtr`: the tail |
| Otherwise | `NextPtr`: the next descriptor to be fetched, also while it is being fetched |

`Idle` = `Started` and `AtTail` and `Count` = 0 and the `Update` stage empty: the tail has been completed and its
status written (SG-FE-03). In cyclic mode `AtTail` stays '0', so `Idle` stays '0'.

### 4.7 Errors, halt and drain

| Situation | Behaviour |
| --- | --- |
| Error (stale descriptor, fetch error, transfer error, write error) | `ErrStop`: no further fetch request and no further command; the issued commands complete, their results are taken and written back (SG-ER-03, interpretation SGI-08); the register interface sets the flags, clears `DMACR.RS` and so lowers `Run` |
| `Run` falls (halt or after an error) | No further fetch request, no command (`Cmd_Valid` qualified with `Run`); a fetch already granted completes and its entry is written into the buffer; the issued commands complete as the channel ends them, and their results are written back (SG-HA-01) |
| `Run` = '0', `Issued` and the `Update` stage empty, no access of the channel outstanding at the port | `Halted` := '1': `CurPtr` keeps its value, the first descriptor that was not started; the descriptor buffer is emptied (one entry per clock cycle, without commands), the entries keep their status in memory |
| `Drain` = '1' | No fetch request, no command, no status write requested; a fetch or a write that the port has already granted completes, read data is discarded; the channels return no result during a drain, so `Issued` keeps its entries until the core reset (SG-HA-02) |

The engine error of a descriptor access is the code of the port (section 5): `SGSlvErr` for SLVERR and `SGDecErr` for
DECERR (SG-ER-04). Every descriptor pointer is aligned to 64 bytes and a descriptor has at most 52 bytes (with the user
application fields of phase c), so no descriptor reaches beyond the top of the address space and no address check is
needed for the descriptor accesses.

## 5. Descriptor port (SG-3, `odma_sg_port`)

The port serves one fetch and one status write at a time; fetches and writes run independently of each other on the
read and write channels of the master.

| Side | Arbiter | Sequence |
| --- | --- | --- |
| Fetch | `olo_base_arb_rr` over the fetch requests of the MM2S engine (bit 1) and the S2MM engine (bit 0) | The grant is registered with its owner; read command of 8 beats at the descriptor address (`CmdRd_LowLat` = '0'); the 8 read words go to the owner (`Rd_Ready` = '1'); after the word with `Rd_Last` and the response (`Rd_Done` or `Rd_Error`, which can come before or after the last word), an end pulse with the error code goes to the owner, at least one clock cycle after the last word, and the arbiter takes the next request |
| Status write | `olo_base_arb_rr` over the write requests of both engines, same order | Write command of 1 beat at the descriptor address + 0x1C (`CmdWr_LowLat` = '0'), the status word with all write strobes; after `Wr_Done` or `Wr_Error` an end pulse with the error code goes to the owner |

The round-robin arbiters give both channels the same share when both request (SG-IF-01); a channel that requests
alone is served at once. During a drain the arbiters grant nothing and the engines withdraw their requests; an access
granted before the drain completes.

`olo_ft_axi_master_simple` generics: `AxiAddrWidth_g` = `AddrWidth_g`, `AxiDataWidth_g` = 32, `AxiMaxBeats_g` = 16,
`AxiMaxOpenTransactions_g` = 2, `UserTransactionSizeBits_g` = 5 (commands of up to 31 beats: 8 beats for a fetch and
1 for a status write, 13 and 6 with the user application fields of phase c), `DataFifoDepth_g` = 32 (2 x
`AxiMaxBeats_g`, the suggestion of Open Logic), `ImplRead_g` and `ImplWrite_g` true. A descriptor access never
crosses a 4 KB boundary and never exceeds `AxiMaxBeats_g`, so each access is one AXI burst: INCR, `AxSize` 4 bytes,
`AxCache` 0011, `AxProt` 000, the fixed values of the master (SG-IF-01). With `CmdWr_LowLat` = '0' the master issues
the burst only when its data is in its write buffer.

The error code of a failed access comes from the response code of the master (`Rd_ErrorResp` with `Rd_Error`,
`Wr_ErrorResp` with `Wr_Error`): DECERR ("11") gives `ErrDec_c`, SLVERR and EXOKAY give `ErrSlv_c` (SG-ER-04,
interpretation I14). The end pulse carries the code of its access.

## 6. Descriptor buffer

One `olo_ft_fifo_sync` per channel, `Depth_g` = 2 (the window, section 4.3), one entry per fetched descriptor, the
fields from bit 0 upwards:

| Field | Width | Content |
| --- | --- | --- |
| `Length` | `LengthWidth_g` | Buffer length |
| `Buffer` | `AddrWidth_g` | `BUFFER_ADDRESS` (and `BUFFER_ADDRESS_MSB`) |
| `Addr` | `AddrWidth_g` - 6 | Address of the descriptor |
| `Sof`, `Eof` | 1, 1 | MM2S: `TXSOF`, `TXEOF`; S2MM: '0' |
| `Stale` | 1 | `Cmplt` = 1 and not `Cyclic` at the fetch |
| `Keyhole` | 1 | `Keyhole` at the fetch |

The width is 2 x `AddrWidth_g` + `LengthWidth_g` - 2 bits: 76 bits at 32 address bits and 14 length bits, 152 bits
at 64 and 26. `NXTDESC` is not stored: it is needed only for the next fetch and is held in `NextPtr`.

## 7. ECC and error injection

`Ecc_Sec` and `Ecc_Ded` of a descriptor buffer are its flags of the output word qualified with the output handshake
(a pop, also when the buffer is emptied after a halt); the master qualifies the events of its read and write data
buffers itself. The error injection drives the `ErrInj_BitFlip` input of the selected buffer with the pattern of
`flipPattern` (`odma_pkg`): parity bits in parity mode (`EccInj_Data` = '0'), data bit 0 or data bits 0 and 1 in
data mode, as in the channels. The function moves from the two channels into `odma_pkg` with this module, unchanged.
A double error in data mode corrupts the word it hits: in a descriptor buffer bits 0 and 1 of the buffer length, in
the read data buffer bits 0 and 1 of the first word of the fetch (`NXTDESC`, bits the engine ignores), in the write
data buffer bits 0 and 1 of the status word (the transferred bytes) in memory.

## 8. Stopped

`Stopped` = '1' when the port has no access of the channel outstanding and either `Drain` = '1', or `Halted` = '1'
and the descriptor buffer is empty, or `Run` = '1', `Issued`, the `Update` stage and the descriptor buffer are
empty and no fetch is requested. During a halt it rises after the last status write and the emptying of the buffer;
during a drain after the last access given to the master. The core combines
it with `Stopped` of the channel for the register interface (`odma_registers` RG-SG-10, RG-RS).

## 9. State machines

`odma_sg_channel`: the fetch part has `Idle_s` (wait for the conditions of section 4.3), `Request_s` (request until
the port grants it), `Words_s` (take the 8 words until the end pulse); issue and result have no state machine of
their own (the descriptor buffer, `Issued` and the `Update` stage hold the state); the update part has `Idle_s`,
`Request_s` and `Wait_s` (until the end pulse of the write). `odma_sg_port`: one state machine per side with
`Idle_s` (arbitration), `Command_s` (command handshake with the master; for a write also the data word), `Data_s`
(fetch: read words to the owner) and `End_s` (wait for the response, end pulse). Every `when others` returns to
`Idle_s` (architecture D15).

## 10. Timing

- Fetch: the request is granted in the next clock cycle when the read side is free; the read command reaches the
  master one clock cycle later, and the first AR handshake follows after the command time of the master. The 8 words
  follow the memory latency L at one word per clock cycle; the entry is in the descriptor buffer one clock cycle
  after the end pulse. A fetch takes about 22 + L clock cycles from the request to the command (verification
  report).
- Issue: `Cmd_Valid` rises in the clock cycle after the entry is written (fall-through of the buffer).
- Update: the write request follows the result handshake by one clock cycle; the status write takes about 6 clock
  cycles plus the latency of the write response. `Pkt` and `ErrValid` are pulses in the clock cycle after the end
  of the write.
- Descriptor rate: with the window of two, one channel processes at most one descriptor per fetch time; with
  buffers that take longer to transfer than a fetch, the transfers of a chain follow each other without a gap on the
  MM2S stream, because the next command is queued in the channel. With both channels active the fetches share the
  read side. The verification report has the measured values.

## 11. Integration

The engine is integrated with three neighbouring modules:

- `odma_registers`: the requirements of its section "Requirements of phase b" (register map of Scatter/Gather Mode,
  `CURDESC` following `CurPtr` while the channel is not halted, `TailWr` per interpretation SGI-01, `Idle` from
  the engine, the engine errors, the interrupt threshold counter and delay timer driven by `Pkt`, `CyclicBD` and
  `Keyhole`), and the FT buffer indices 6 to 9 of section 3.
- `odma_s2mm`: the result flag `Res_Sof` (S2-SG-02) of its stream split, '1' for the first buffer of a packet.
- `odma_core`: with `IncludeSg_g` the engine between the register interface and the channels, the descriptor port
  `M_AxiSg_*`, `Stopped` of each channel combined with `Stopped` of its engine, the indices 6 to 9 in the ECC index
  map.
