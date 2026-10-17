# odma_mm2s: Architecture and Design Description

## 1. Block diagram

![Block diagram of odma_mm2s: the read command block MM-1 with the address check and the read master
olo_ft_axi_master_full, the transfer and response buffers, and the stream output MM-2 with the TKeep and TLast logic,
the register stage or, with Join_g, the stream join olo_base_stream_join, and the result](img/odma_mm2s_arch.drawio.svg)

## 2. Entities

| Entity | Block | Content |
| --- | --- | --- |
| `odma_mm2s` | Module top | Instances of the blocks below and of the read master, the stopped level |
| `odma_mm2s_command` | MM-1 | Command acceptance, address and length check, read commands, transfer entries, response codes |
| `odma_mm2s_stream` | MM-2 | Stream output with `TKeep` and `TLast`, transfer results, discard during a drain; with `Join_g` the closing beat of a packet ended by a halt |
| `olo_ft_axi_master_full` | MM-1 | AXI4 read master with the ECC-protected read data buffer (write side not implemented) |
| `olo_ft_fifo_sync` (two) | MM-1 to MM-2 | Transfer buffer {length, end of packet, code} and response buffer {error code}, 8 entries each |
| `olo_base_pl_stage` | MM-2 | Register stage of the stream output (without `Join_g`) |
| `olo_base_stream_join` | MM-2 | Stream join of the buffers of a packet (with `Join_g`, in place of the register stage) |

## 3. Ports of `odma_mm2s`

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, reset (the core reset `CoreRst`) |
| `Cmd_Valid`, `Cmd_Ready` | 1 | in, out | Transfer command |
| `Cmd_Addr`, `Cmd_Length` | `AddrWidth_g`, `LengthWidth_g` | in | Buffer address and length |
| `Cmd_Sof`, `Cmd_Eof`, `Cmd_Keyhole` | 1 | in | Start and end of packet, keyhole (phase b) |
| `Res_Valid`, `Res_Ready` | 1 | out, in | Transfer result |
| `Res_Bytes`, `Res_Eof`, `Res_Err` | `LengthWidth_g`, 1, 2 | out | Transferred bytes, end of packet, error code |
| `Run`, `Drain`, `Stopped` | 1 | in, in, out | Channel control |
| `M_Axi_Ar*`, `M_Axi_R*` | | out/in | AXI4 read master (`ArAddr`, `ArLen`, `ArSize`, `ArBurst`, `ArLock`, `ArCache`, `ArProt`, `ArValid`, `ArReady`, `RData`, `RResp`, `RLast`, `RValid`, `RReady`) |
| `M_Mm2s_Data`, `_Keep`, `_Last`, `_Valid`, `_Ready` | | out/in | MM2S stream |
| `Ecc_Sec`, `Ecc_Ded` | 3 | out | ECC events of the read data buffer (bit 0, index 0 of the extension window), the transfer buffer (bit 1, index 4) and the response buffer (bit 2, index 5); one pulse per word read from the buffer |
| `EccInj_Valid` | 3 | in | Error injection per buffer, same order |
| `EccInj_Double` | 1 | in | '1': flip two bits, '0': flip one bit of the next codeword written to the buffer |
| `EccInj_Data` | 1 | in | '1': flip data bits, '0': flip parity bits (section 6) |

Generics as in section 6 of the specification. The core sets `Join_g` = `IncludeSg_g`.

## 4. Read command (MM-1, `odma_mm2s_command`)

A command is accepted when `Run` = '1', `Drain` = '0' and the transfer buffer has a free entry. For an accepted
command the block

1. checks the length and the buffer with `beyondTop(Cmd_Addr, Cmd_Length)` (`odma_pkg`); a keyhole command skips the
   buffer check, because all its beats access the memory word at the address (MM-SG-03);
2. if the length is not 0 and the buffer fits: writes the entry {length, end of packet, `ErrNone_c`} into the
   transfer buffer and issues one read command to `olo_ft_axi_master_full` (`CmdRd_Addr` = `Cmd_Addr`,
   `CmdRd_Size` = `Cmd_Length`, `CmdRd_Fixed` = `Cmd_Keyhole`, `CmdRd_LowLat` = '0'); for a FIXED command the
   master ignores the address bits below the memory width and packs the bytes from lane 0, so the stream output
   needs no change;
3. otherwise writes the entry {length, end of packet, code} only, without a read: `ErrInt_c` for the length 0
   (MM-RD-06), `ErrDec_c` for a buffer beyond the top of the address space (MM-RD-04).

The read master splits the command into bursts of at most `BurstBeats_g` beats that stay within 4 KB, issues a burst
only when its internal FIFO can take it (high-latency mode, MM-RD-03) and returns `Rd_Done` or `Rd_Error` with the
response code of the first failing beat (`Rd_ErrorResp`) per command; the block writes the error code of each
response into the response buffer: `ErrNone_c` for `Rd_Done`, for `Rd_Error` `ErrDec_c` when `Rd_ErrorResp` is
DECERR ("11") and `ErrSlv_c` otherwise (SLVERR, and EXOKAY, interpretation I14; MM-ER-03). A command accepted before a
drain is still issued to the master; its data
is discarded by MM-2. The response buffer never overflows: every response belongs to an entry of the transfer buffer,
which has the same depth.

The read master runs with `UserTransactionSizeBits_g` = `LengthWidth_g` + 1 (gap G14 of the architecture: the
write path of `olo_axi_master_full` of Open Logic 4.7.0-ft.6 stalls after a command whose size lies in the last user
data word below 2**`UserTransactionSizeBits_g`; the read master uses the same setting), `AxiMaxBeats_g` = the smaller of
`BurstBeats_g` and the beats of 4 KB (4096 / (`MemWidth_g` / 8); no AXI burst crosses 4 KB, so the bursts are the
same, and `olo_axi_master_simple` of Open Logic 4.7.0-ft.6 does not elaborate with more beats than 4 KB holds),
`AxiMaxOpenTransactions_g` = 8, `DataFifoDepth_g` = `BufferBeats_g` (in stream beats), `UserDataWidth_g` =
`StreamWidth_g`, `AxiDataWidth_g` = `MemWidth_g`, `ImplWrite_g` = false. Its fixed `ArCache` 0011 and `ArProt` 000
are the values of MM-IF-01. In `olo_ft_axi_master_full`, `DataFifoDepth_g` is the depth of its ECC-protected read
buffer in words of `UserDataWidth_g` bits (stream beats, with `Rd_Last`); the wrapped `olo_axi_master_full` has
internal FIFOs of two bursts of `AxiDataWidth_g` bits, and its high-latency mode requests a burst only when these can
take it. A stream peer that holds `TReady` low therefore fills the read buffer and then the internal FIFOs and stops
further bursts, but never holds the R channel (MM-RD-03).

## 5. Stream output (MM-2, `odma_mm2s_stream`)

The block takes the head entry of the transfer buffer.

- Entry without a read (code not `ErrNone_c`): result {0 bytes, end of packet of the entry, code of the entry}, no
  beat.
- Read entry: every read data word of the master (`Rd_Data`, `Rd_Valid`, `Rd_Last`) becomes one stream beat into
  the register stage with the handshake passed through (stage `In_Valid` = `Rd_Valid`, `Rd_Ready` = stage
  `In_Ready`). `TKeep` is all ones except on the beat with `Rd_Last`, where it is `lastKeep(length, StreamWidth_g /
  8)`, computed when the entry is taken; `TLast` is `Rd_Last` and the end of packet of the entry (MM-ST-01,
  MM-ST-02). After the beat with `Rd_Last` the block waits until the register stage is empty, so that the stream
  peer has accepted the last beat, and for the head of the response buffer (the response can arrive before or after
  the last beat), then returns the result {length, end of packet, error code} (MM-ST-03) and pops both entries.

The output path has an `olo_base_pl_stage` (one register stage) so that the stream interface starts at flip-flops;
with the stage the path keeps one beat per clock cycle (MM-RD-05).

Drain (`Drain` = '1'): the register stage is held in reset, so `M_Mm2s_Valid` is low; read data is taken
(`Rd_Ready` = '1') and discarded, and the entries and responses are popped without results as their data and
responses arrive. Halt (`Run` = '0'): no change of this block; MM-1 accepts no new command.

### 5.1 Stream join (`Join_g`)

With `Join_g` the register stage is replaced by `olo_base_stream_join` (`Width_g` = `StreamWidth_g`), whose outputs
are registered, so the stream interface still starts at flip-flops. The read beats enter the join with `In_Be` =
the `TKeep` above (all '1', `lastKeep` on `Rd_Last`) and `In_Last` = `Rd_Last` and the end of packet of the entry. The
join closes the gap after the last byte of every buffer without the end of packet, so the bytes of the next buffer
follow without gap (MM-SG-01); `TKeep` of the output is `Out_Be`.

| Situation | Behaviour |
| --- | --- |
| Entry without the end of packet | The result is returned when the beat with `Rd_Last` has entered the join and the response is in (MM-SG-02); its last bytes may still wait in the join for the next buffer. The flag `InPkt` records that a packet is open in the join |
| Entry with the end of packet | The result is returned when the output beat with `TLast` has been accepted by the stream peer (flag `LastOut`, set by that output handshake in `Result_s`) and the response is in (MM-ST-03); `InPkt` is cleared with its last input beat |
| Entry without a read (length 0, buffer beyond the top) | Result at once, as without the join; `InPkt` keeps its value |
| `Run` = '0', MM-1 idle, transfer buffer empty, `InPkt` = '1' | `Close_s`: the block sends the closing beat {`In_Be` all '0', `In_Last` '1'}; the join sends the bytes it holds with `TLast` on the last of them (MM-SG-04, interpretation M4). `Close_s` ends when that output beat has been accepted. A halt and an error (the engine halts the channel after an error) take this path |
| `Drain` = '1' | The join is held in reset, which clears the bytes it holds; `InPkt` is cleared; `Close_s` ends |

Stopped with `Join_g` (section 6) also requires `InPkt` = '0' and the block not in `Close_s`, so a halt ends only
when the stream peer has taken the last beat of the open packet.

ECC: `Ecc_Sec` and `Ecc_Ded` of a buffer are its flags of the output word (time-aligned with the data) qualified
with the output handshake of the buffer, so every word read gives at most one pulse. The error injection drives the
`ErrInj_BitFlip` input of the selected buffer. In parity mode (`EccInj_Data` = '0') it flips bit 0 (single error) or
bits 0 and 1 (double error) of the codeword, the overall parity bit and the first Hamming parity bit of the code of
`olo_ft_pkg_ecc`, so an injected error never changes the data: a single error is corrected, a double error is detected
and the word is still delivered unchanged. In data mode (`EccInj_Data` = '1') it flips data bit 0 (codeword bit 3) or
data bits 0 and 1 (codeword bits 3 and 5): a single error is corrected, so the channel passes only when it uses the
corrected output of the buffer, and a double error corrupts the word, which is delivered as read (the destructive test
of the consequence of a double error).

## 6. Stopped

`Stopped` = '1' when the command block is idle, the transfer buffer is empty and the response buffer is empty, and,
with `Join_g`, no packet is open in the join and no closing beat is pending (section 5.1). A transfer entry with a
read is popped only after the response of the read, so an empty transfer buffer also means that no read command is
outstanding at the read master. During a halt this happens after the last result (with `Join_g` after the closing
beat); during a drain after the last response.

## 7. State machines

`odma_mm2s_command`: `Idle_s` (wait for a command; the command is taken into registers), `Entry_s` (the transfer
entry is written, the code is computed from the registered address and length) and `Issue_s` (read command handshake
with the master, for a read entry only).
`odma_mm2s_stream`: `Head_s` (wait for a transfer entry), `Data_s` (beats of a read entry), `Result_s` (wait for
the empty register stage, with `Join_g` for the conditions of section 5.1, and the response, result handshake; during
a drain the entries are popped without a result), `Close_s` (with `Join_g`: closing beat, then wait for the output
beat with `TLast`). Every `when others` returns to the first state.

## 8. Timing

- Command to the read command of the master: `CmdRd_Valid` rises 2 clock cycles after the command handshake (entry
  written in between); the first AR handshake follows after the command time of the read master (at least four
  cycles).
- Read data to the stream: the fall-through of the read data buffer plus one register stage. With `Join_g` the join
  holds up to one beat of bytes until the next input beat, so an output beat follows its input beat one beat later on
  an aligned stream, and the end of a packet whose last bytes need two output beats inserts one clock cycle; the
  throughput stays one beat per clock cycle otherwise.
- Last beat to the result: `Res_Valid` rises in the clock cycle after the stream handshake of the last beat when
  the response is already buffered.
- Throughput: one stream beat per clock cycle when a burst carries at least 8 stream beats (`BurstBeats_g` x
  `MemWidth_g` / `StreamWidth_g`) and the memory answers without wait states (MM-RD-05). The read master requests a
  burst only when its internal FIFOs of two bursts can take it, so with fewer stream beats per burst the read
  latency of the memory is no longer hidden: with the memory model of the bench, 2 stream beats per burst give 128
  beats in 252 clock cycles.
