# odma_mm2s: Architecture and Design Description

## 1. Block diagram

![Block diagram of odma_mm2s: the read command block MM-1 with the address check and the read master
olo_ft_axi_master_full, the transfer and response buffers, and the stream output MM-2 with the TKeep and TLast logic
and the result](img/odma_mm2s_arch.drawio.svg)

## 2. Entities

| Entity | Block | Content |
| --- | --- | --- |
| `odma_mm2s` | Module top | Instances of the blocks below and of the read master, the stopped level |
| `odma_mm2s_command` | MM-1 | Command acceptance, address check, read commands, transfer entries, response codes |
| `odma_mm2s_stream` | MM-2 | Stream output with `TKeep` and `TLast`, transfer results, discard during a drain |
| `olo_ft_axi_master_full` | MM-1 | AXI4 read master with the ECC-protected read data buffer (write side not implemented) |
| `olo_ft_fifo_sync` (two) | MM-1 to MM-2 | Transfer buffer and response buffer, 8 entries each |

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
| `Ecc_Sec`, `Ecc_Ded` | 1 | out | ECC events of the read data buffer (index 0 of the extension window) |
| `EccInj_Valid`, `EccInj_Double` | 1 | in | Error injection into the read data buffer |

Generics as in section 6 of the specification.

## 4. Read command (MM-1, `odma_mm2s_command`)

A command is accepted when `Run` = '1', `Drain` = '0' and the transfer buffer has a free entry. For an accepted
command the block

1. checks the buffer with `beyondTop(Cmd_Addr, Cmd_Length)` (`odma_pkg`);
2. if the buffer fits: issues one read command to `olo_ft_axi_master_full` (`CmdRd_Addr` = `Cmd_Addr`, `CmdRd_Size`
   = `Cmd_Length`, `CmdRd_LowLat` = '0') and writes the entry {length, end of packet, rejected = '0'} into the
   transfer buffer;
3. if not: writes the entry {length, end of packet, rejected = '1'} only (no read, MM-RD-04).

The read master splits the command into bursts of at most `BurstBeats_g` beats that stay within 4 KB, issues a burst
only when its internal FIFO can take it (high-latency mode, MM-RD-03) and returns `Rd_Done` or `Rd_Error` with the
response code (gap G5) per command; the block writes the error code of each response into the response buffer
(`ErrNone_c`, `ErrSlv_c`, `ErrDec_c`). A counter of the commands issued to the master and not yet answered gives
the outstanding level for `Stopped`.

The read master runs with `UserTransactionSizeBits_g` = `LengthWidth_g`, `AxiMaxBeats_g` = `BurstBeats_g`,
`AxiMaxOpenTransactions_g` = 8, `DataFifoDepth_g` = `BufferBeats_g` (in stream beats), `UserDataWidth_g` =
`StreamWidth_g`, `AxiDataWidth_g` = `MemWidth_g`, `ImplWrite_g` = false. Its fixed `ArCache` 0011 and `ArProt` 000
are the values of MM-IF-01.

## 5. Stream output (MM-2, `odma_mm2s_stream`)

The block takes the head entry of the transfer buffer.

- Rejected entry: result {0 bytes, end of packet of the entry, `ErrDec_c`} at once, no beat.
- Read entry: every read data word of the master (`Rd_Data`, `Rd_Valid`, `Rd_Last`) becomes one stream beat with the
  handshake passed through (`M_Mm2s_Valid` = `Rd_Valid`, `Rd_Ready` = `M_Mm2s_Ready`). `TKeep` is all ones except
  on the beat with `Rd_Last`, where it is `lastKeep(length, StreamWidth_g / 8)`; `TLast` is `Rd_Last` and the end of
  packet of the entry (MM-ST-01, MM-ST-02). After the handshake of the beat with `Rd_Last`, the block waits for the
  head of the response buffer (the response can arrive before or after the last beat) and returns the result
  {length, end of packet, error code} (MM-ST-03), then pops both entries.

The output path has an `olo_base_pl_stage` (one register stage) so that the stream interface starts at flip-flops;
with the stage the path keeps one beat per clock cycle (MM-RD-05).

Drain (`Drain` = '1'): `M_Mm2s_Valid` is held low and `Rd_Ready` high, the entries and responses are popped
without results as their data and responses arrive. The register stage is cleared. Halt (`Run` = '0'): no change of
this block; MM-1 accepts no new command.

## 6. Stopped

`Stopped` = '1' when the transfer buffer is empty, the response buffer is empty and no command is outstanding at the
read master. During a halt this happens after the last result; during a drain after the last response.

## 7. State machines

`odma_mm2s_command`: `Idle_s` (wait for a command) and `Issue_s` (read command handshake with the master).
`odma_mm2s_stream`: `Head_s` (wait for a transfer entry), `Data_s` (beats of a read entry), `Result_s` (wait for
the response, result handshake). Every `when others` returns to the first state.

## 8. Timing

- Command to the first AR handshake: 4 clock cycles plus the command time of the read master (at least four cycles).
- Read data to the stream: the fall-through of the read data buffer plus one register stage.
- Last beat to the result: one clock cycle when the response is already buffered.
