# odma_s2mm: Architecture and Design Description

## 1. Block diagram

![Block diagram of odma_s2mm: the chunk former S2-1, the data buffer and the chunk buffer, and the write command
block S2-2 with the stage of the feed jobs olo_base_pl_stage and the write master
olo_ft_axi_master_full](img/odma_s2mm_arch.drawio.svg)

## 2. Entities

| Entity | Block | Content |
| --- | --- | --- |
| `odma_s2mm` | Module top | Instances of the blocks below, the buffers and the write master, the stopped level |
| `odma_s2mm_pkg` | S2-1, S2-2 | The chunk descriptor, the longest burst of the write master |
| `odma_s2mm_chunker` | S2-1 | Stream input, cut into chunks, byte count of a chunk, chunk descriptors, discard of an interrupted packet |
| `odma_s2mm_write` | S2-2 | Transfer commands, length and address checks, write commands per chunk, feed jobs and the feeder, responses, overflow, flush, results |
| `olo_ft_fifo_sync` (two) | S2-1 to S2-2 | Data buffer (`StreamWidth_g` bits, `BufferBeats_g` entries), chunk buffer (descriptors, 32 entries) |
| `olo_base_pl_stage` | S2-2 | Stage of the feed jobs between the command part and the feeder (up to two jobs) |
| `olo_ft_axi_master_full` | S2-2 | AXI4 write master with the ECC-protected write data buffer of two chunks (read side not implemented) |

S2-1 counts the beats of each chunk for its descriptor; the chunk end follows from that count, which is the cut that
`olo_base_chunker` makes. A second counter of the same beats in `olo_base_chunker` would add nothing, so S2-1 does not
instantiate it.

## 3. Ports of `odma_s2mm`

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, reset (the core reset `CoreRst`) |
| `Cmd_Valid`, `Cmd_Ready` | 1 | in, out | Transfer command |
| `Cmd_Addr`, `Cmd_Length` | `AddrWidth_g`, `LengthWidth_g` | in | Buffer address and buffer length |
| `Cmd_Keyhole` | 1 | in | Keyhole (phase b) |
| `Res_Valid`, `Res_Ready` | 1 | out, in | Transfer result |
| `Res_Bytes`, `Res_Eof`, `Res_Err` | `LengthWidth_g`, 1, 2 | out | Bytes written, end of packet in the buffer, error code |
| `Run`, `Drain`, `Stopped` | 1 | in, in, out | Channel control |
| `S_S2mm_Data`, `_Keep`, `_Last`, `_Valid`, `_Ready` | | in/out | S2MM stream |
| `M_Axi_Aw*`, `M_Axi_W*`, `M_Axi_B*` | | out/in | AXI4 write master (`AwAddr`, `AwLen`, `AwSize`, `AwBurst`, `AwLock`, `AwCache`, `AwProt`, `AwValid`, `AwReady`, `WData`, `WStrb`, `WLast`, `WValid`, `WReady`, `BResp`, `BValid`, `BReady`) |
| `Ecc_Sec`, `Ecc_Ded` | 3 | out | ECC events of the data buffer (bit 0, index 1 of the extension window), the chunk buffer (bit 1, index 2), the write data buffer (bit 2, index 3); one pulse per word read from the buffer |
| `EccInj_Valid` | 3 | in | Error injection per buffer, same order |
| `EccInj_Double` | 1 | in | '1' double, '0' single error |
| `EccInj_Data` | 1 | in | '1' data bits, '0' parity bits (section 5.6) |

Generics as in section 6 of the specification. `ChunkBeats_c` = B x `MemWidth_g` / `StreamWidth_g` with B the smaller
of `BurstBeats_g` and the beats of 4 KB (4096 / (`MemWidth_g` / 8)).

## 4. Chunk former (S2-1, `odma_s2mm_chunker`)

### 4.1 Normal operation

While `Run` = '1', `Drain` = '0' and the data and chunk buffers have space, the input is ready. Every beat goes into
the data buffer. A beat ends a chunk when the chunk has `ChunkBeats_c` beats or the beat has `TLast`; in the same
clock cycle the block writes the descriptor of the chunk into the chunk buffer:

| Field | Width | Content |
| --- | --- | --- |
| `Bytes` | 16 | Bytes of the chunk: beats x `StreamWidth_g` / 8, for the last chunk of a packet the full beats plus `keepBytes(TKeep)` of the last beat (I10) |
| `Beats` | 16 | Beats of the chunk in the data buffer |
| `Pend` | 1 | The chunk ends a packet |
| `Discard` | 1 | The chunk is the stored part of an interrupted packet: it is not written |

A descriptor never refers to beats that are not in the data buffer (S2-ST-03): its last beat is written in the same
clock cycle, and S2-2 takes the beats from the data buffer only through its handshake.

### 4.2 Halt and drain

| Situation | Behaviour |
| --- | --- |
| `Run` falls between packets | The input is not ready until `Run` rises again (S2-ST-01) |
| `Run` falls inside a packet | The block writes the descriptor {`Bytes` 0, `Beats` of the incomplete chunk, `Pend` '1', `Discard` '1'}, then accepts and drops input beats up to the `TLast` of the packet (`S_S2mm_Ready` = '1' in this phase), then behaves as between packets |
| `Drain` = '1' | The input is not ready; no further descriptor is written |

The block reports `PacketOpen` (a packet started and its `TLast` not yet taken, also while the rest is discarded) to
S2-2.

## 5. Write command (S2-2, `odma_s2mm_write`)

### 5.1 Structure

S2-2 has a command part and a feeder. The command part takes the descriptors, issues one write command per chunk
to the master and passes a feed job {beats to the master, beats to drop} per descriptor through an
`olo_base_pl_stage` to the feeder. The feeder moves the beats of a job from the data buffer to `Wr_Data` and then
drops the other beats of the chunk (a last beat without valid bytes, the beats beyond the buffer, the beats of a
discarded chunk). The stage holds up to two jobs, so the command part issues the next write command while the
feeder still moves the data of the previous chunk.

### 5.2 Transfer

A command is accepted in `Idle_s` when `Run` = '1' and `Drain` = '0'. A buffer length of 0 ends the transfer with the
result {0 bytes, no end of packet, `ErrInt_c`} (S2-WR-06), a buffer beyond the top of the address space
(`beyondTop(Cmd_Addr, Cmd_Length)`) with {0 bytes, no end of packet, `ErrDec_c`} (S2-WR-04); in both cases no
stream data is taken. Otherwise the block takes descriptors from the chunk buffer:

| Descriptor | Action |
| --- | --- |
| Normal, written bytes plus `Bytes` within the buffer | Write command to the master at the command address plus the written bytes with `Bytes` bytes (`CmdWr_LowLat` = '0'); feed job {ceil(`Bytes` / (`StreamWidth_g` / 8)), remaining beats}; written bytes += `Bytes` |
| Normal, beyond the buffer | Overflow: a write command with the bytes that still fit (if any) and their beats, the other beats dropped; `ErrInt_c`; then flush (S2-RS-02) |
| `Discard` = '1' | Its beats are dropped; the transfer ends without the end of packet (S2-HA-01) |
| `Bytes` = 0 and `Pend` = '1' (a last beat without valid bytes after a full chunk) | Its beat is dropped, no write |

After a descriptor with `Pend` = '1' the transfer is complete; the block waits until no write is outstanding and
returns the result {written bytes, end of packet, error code} (S2-RS-01). A counter of the write commands without
response gives the outstanding level.

### 5.3 Errors, halt and flush

- A write response with an error (`Wr_Error`) records the first error code: the constant `WrErrCode_c` =
  `ErrSlv_c` until Open Logic provides the response code (specification section 3.7). No further write command is
  issued for the transfer; the remaining descriptors of the packet are flushed after the result (S2-RS-03).
- Overflow records `ErrInt_c` and flushes the rest of the packet (S2-RS-02).
- `Run` = '0' during a transfer: the descriptors of the packet of the transfer are written up to the descriptor with
  `Pend` or `Discard`. When no descriptor is in the chunk buffer, none is stored for its output and S2-1 has no
  packet open, the transfer ends without the end of packet, with 0 bytes if no byte was received (S2-HA-01). A
  descriptor is stored from the clock cycle after its write on (write level of the chunk buffer), while its output
  follows one clock cycle later: the block uses the write level, so a packet that ended just before the halt is not
  missed.
- In each of these cases the result is returned once no write is outstanding (S2-RS-04). Then the block flushes: it
  takes the remaining descriptors of the packet up to the one with `Pend` and drops their beats. While `Run` = '0'
  in `Idle_s`, it drops every further packet in the chunk buffer, a whole packet at a time (data received for later
  transfers, S2-HA-01). A new command is accepted only after the flush.

### 5.4 Drain

`Drain` = '1': no descriptor is taken and no write command issued; the feeder moves the data of the write commands
the master has accepted from the data buffer (it is complete there, S2-ST-03); the block waits for their responses
and returns no result (S2-HA-02). The core reset after the drain clears the buffers.

### 5.5 Write master

`UserTransactionSizeBits_g` = `LengthWidth_g` + 1 (gap G14 of the architecture: `olo_axi_master_full` of Open
Logic 4.7.0-ft.6 counts the user data words of a write command at the width of the size field without its low bits,
so the count wraps for the sizes in the last user data word below 2**`UserTransactionSizeBits_g`, and the master
issues no further burst; with one more size bit every command stays below 2**(`UserTransactionSizeBits_g` - 1)),
`AxiMaxBeats_g` = B (section 3; no AXI burst crosses 4 KB, and
`olo_axi_master_simple` of Open Logic 4.7.0-ft.6 does not elaborate with more beats than 4 KB holds),
`AxiMaxOpenTransactions_g` = 8, `DataFifoDepth_g` = 2 x `ChunkBeats_c` (the ECC-protected write data buffer in
words of `UserDataWidth_g` bits), `UserDataWidth_g` = `StreamWidth_g`, `AxiDataWidth_g` = `MemWidth_g`,
`ImplRead_g` = false. The master sets the write strobes of the bytes of each command (S2-WR-02), splits at 4 KB and
B and issues a burst only when its data is in its FIFO (S2-WR-03); its fixed `AwCache` 0011 and `AwProt` 000 are
the values of S2-IF-01.

### 5.6 ECC and error injection

`Ecc_Sec` and `Ecc_Ded` of the data and chunk buffers are their flags of the output word qualified with the output
handshake; the write master qualifies the events of its buffer itself. The error injection drives the
`ErrInj_BitFlip` input of the selected buffer. In parity mode (`EccInj_Data` = '0') it flips bit 0 (single error) or
bits 0 and 1 (double error) of the codeword, the overall parity bit and the first Hamming parity bit of the code of
`olo_ft_pkg_ecc`, so an injected error never changes the data: a single error is corrected, a double error is detected
and the word is still delivered unchanged. In data mode (`EccInj_Data` = '1') it flips data bit 0 (codeword bit 3) or
data bits 0 and 1 (codeword bits 3 and 5): a single error is corrected, so the channel passes only when it uses the
corrected output of the buffer, and a double error corrupts the word, which is delivered as read (the destructive test
of the consequence of a double error).

## 6. Stopped

`Stopped` = '1' when S2-2 is in `Idle_s` (no transfer, no flush) or in the drained state, and no write is
outstanding; S2-1 may still be dropping the rest of an interrupted packet (S2-HA-03).

## 7. State machines

`odma_s2mm_chunker`: `Normal_s`, `Discard_s` (drop up to `TLast`); between packets the input is not ready while
`Run` = '0'. `odma_s2mm_write`, command part: `Idle_s`, `Take_s` (next descriptor), `Issue_s` (write command
handshake), `Wait_s` (outstanding writes), `Result_s`, `Flush_s`, `Drained_s` (after a drain, until the core
reset); feeder: `Head_s` (next job), `Feed_s` (beats to the master), `Drop_s` (beats not written). Every
`when others` returns to the first state (architecture D15).

## 8. Timing

- Stream to memory: a chunk is written once its last beat is buffered; its write command follows the descriptor
  after two clock cycles plus the command time of the master.
- Throughput: the channel issues one write command per chunk, and the write master accepts the next command after
  the data of the previous one, about 7 clock cycles of overhead per command. With equal memory and stream widths
  and chunks of C stream beats the channel takes about C / (C + 7) beats per clock cycle once its data buffer is
  full: about 0.7 for chunks of 16 beats (the default of 16-beat bursts at 32 bits), 0.9 for chunks of 64 beats
  (S2-WR-05), 0.97 for 256 beats. Longer bursts raise it. With a memory four or more times wider than the stream the
  write side is faster than the stream and the channel takes one beat per clock cycle; the verification report has
  the measured values.
