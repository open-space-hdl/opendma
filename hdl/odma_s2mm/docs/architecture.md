# odma_s2mm: Architecture and Design Description

## 1. Block diagram

![Block diagram of odma_s2mm: with Split_g the stream split olo_base_stream_split in front of the chunk former S2-1,
the data buffer and the chunk buffer, and the write command block S2-2 with the segment register, the stage of the
feed jobs olo_base_pl_stage and the write master olo_ft_axi_master_full](img/odma_s2mm_arch.drawio.svg)

## 2. Entities

| Entity | Block | Content |
| --- | --- | --- |
| `odma_s2mm` | Module top | Instances of the blocks below, the buffers and the write master, the stopped level |
| `odma_s2mm_pkg` | S2-1, S2-2 | The chunk descriptor, the longest burst of the write master |
| `odma_s2mm_chunker` | S2-1 | Stream input (with `Split_g` through the stream split and its segment input), cut into chunks, byte count of a chunk, chunk descriptors, discard of an interrupted packet |
| `odma_s2mm_write` | S2-2 | Transfer commands, length and address checks, the segment register, write commands per chunk, feed jobs and the feeder, responses, overflow, flush, results with the start and end of packet |
| `olo_base_stream_split` | S2-1 | Stream split at the end of every buffer (with `Split_g`) |
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
| `Res_Sof` | 1 | out | The buffer is the first buffer of its packet (S2-SG-02) |
| `Run`, `Drain`, `Stopped` | 1 | in, in, out | Channel control |
| `S_S2mm_Data`, `_Keep`, `_Last`, `_Valid`, `_Ready` | | in/out | S2MM stream |
| `M_Axi_Aw*`, `M_Axi_W*`, `M_Axi_B*` | | out/in | AXI4 write master (`AwAddr`, `AwLen`, `AwSize`, `AwBurst`, `AwLock`, `AwCache`, `AwProt`, `AwValid`, `AwReady`, `WData`, `WStrb`, `WLast`, `WValid`, `WReady`, `BResp`, `BValid`, `BReady`) |
| `Ecc_Sec`, `Ecc_Ded` | 3 | out | ECC events of the data buffer (bit 0, index 1 of the extension window), the chunk buffer (bit 1, index 2), the write data buffer (bit 2, index 3); one pulse per word read from the buffer |
| `EccInj_Valid` | 3 | in | Error injection per buffer, same order |
| `EccInj_Double` | 1 | in | '1' double, '0' single error |
| `EccInj_Data` | 1 | in | '1' data bits, '0' parity bits (section 5.6) |

Generics as in section 6 of the specification; the core sets `Split_g` = `IncludeSg_g`. `ChunkBeats_c` = B x
`MemWidth_g` / `StreamWidth_g` with B the smaller of `BurstBeats_g` and the beats of 4 KB (4096 / (`MemWidth_g` / 8)).

## 4. Chunk former (S2-1, `odma_s2mm_chunker`)

### 4.1 Normal operation

While `Run` = '1', `Drain` = '0' and the data and chunk buffers have space, the input is ready. Every beat goes into
the data buffer. A beat ends a chunk when the beat count of the chunk reaches the register `Limit` or the beat has
`TLast`; in the same clock cycle the block writes the descriptor of the chunk into the chunk buffer, and `Limit`
takes the register `Rest` for the next chunk. Without `Split_g` both stay at `ChunkBeats_c` - 1, so every chunk
has `ChunkBeats_c` beats; with `Split_g` they follow the chunk plan of the buffer (section 4.2):

| Field | Width | Content |
| --- | --- | --- |
| `Bytes` | 16 | Bytes of the chunk: beats x `StreamWidth_g` / 8, for the last chunk of a packet the full beats plus `keepBytes(TKeep)` of the last beat (I10) |
| `Beats` | 16 | Beats of the chunk in the data buffer |
| `Pend` | 1 | The chunk ends the transfer: the packet ends, or with `Split_g` the buffer is full |
| `Discard` | 1 | The chunk is the stored part of an interrupted packet: it is not written |
| `PktEnd` | 1 | The chunk ends the packet (`Pend` and the packet end; with `Split_g` `Out_InLast`; '1' with `Discard`) |

A descriptor never refers to beats that are not in the data buffer (S2-ST-03): its last beat is written in the same
clock cycle, and S2-2 takes the beats from the data buffer only through its handshake.

### 4.2 Stream split (`Split_g`)

With `Split_g` the stream passes `olo_base_stream_split` (`Width_g` = `StreamWidth_g`, `MaxSegSize_g` =
2**`LengthWidth_g` - 1) before the chunk former. `In_Be` is all '1' on a beat without `TLast` and the bytes up to
the first lane with `TKeep` '0' on the beat with `TLast` (S2-ST-02, I10), so it is contiguous from lane 0 as the split
requires. The chunk former takes the split output in place of the stream: `Out_Be` gives the bytes of the last beat
of a segment (`keepBytes`), `Out_Last` ends the chunk and the transfer (`Pend`), `Out_InLast` ends the packet
(`PktEnd`, `InPacket` cleared). A segment of the packet without bytes (one beat with `Out_Be` all '0') gives a
descriptor of 0 bytes with `Pend` and `PktEnd` (SGI-13).

Segment commands:

| Source | Segment | When |
| --- | --- | --- |
| Segment register of S2-2 | The buffer length of the accepted command | Written at the command handshake of a transfer that is not rejected (S2-WR-04, S2-WR-06), taken by the split when no segment is active; at most one segment per transfer |
| S2-1 in `Discard_s` | `MaxSegSize_g` (a constant, selected by the state register) | While the rest of an interrupted packet is dropped and the split has no segment for it: the register `NeedSeg` is set when a beat with `Out_Last` but without `Out_InLast` passes (the segment ended inside the packet) and cleared by every segment handshake. A segment of S2-2 that arrives meanwhile waits |

Both inputs of the split come from registers, as `olo_base_stream_split` requires. The split takes a segment in
the clock cycle in which its previous one has ended, while S2-1 sees that end one clock cycle later at the output.
An offer of a discard segment that only depended on `Discard_s` would therefore be taken once more after the last
beat of the discarded packet, and that segment would let the next packet pass without a command; `NeedSeg` offers a
discard segment only when one is missing. The split takes no stream beat
while no segment is active, so a packet waits at the stream input until its command is accepted, and the rest of a
packet until the next command (S2-SG-03, `odma_sg` SG-TR-04).

The stream enters the split only while `Run` = '1' or S2-1 discards (S2-ST-01). The split holds up to two beats (its
carry and its output register), so the chunk former sees a packet later than the stream port. S2-1 keeps two flags:

- `StrmOpen`: a packet entered the split, and its `TLast` has not.
- `EndPend`: the `TLast` of a packet entered the split, and its `Out_InLast` beat has not left it. The split takes no
  beat of the next packet before the end of a packet has left its carry, so at most one packet end is in the split.
  When a new end enters in the clock cycle in which the old one leaves, the new one sets the flag.

A packet counts as open while `InPacket`, `StrmOpen` or `EndPend` is set. That open state keeps the split out of its
reset, and outside `Discard_s` it gives `DescPend` (a descriptor of the open packet is still to come) to S2-2.

A packet whose end is in the split is complete when no segment has ended inside the packet since (`EndPend` set,
`NeedSeg` clear). Its rest then belongs to the active segment, and S2-1 takes it even when `Run` falls, so a packet
that the stream port accepted completely before a halt is written completely (S2-HA-01). A halt cuts an open packet
that is not complete: either `StrmOpen` is set, or its end waits in the split for the next buffer (`NeedSeg` set).
A flush cuts every open packet.

Reset of the split: `Rst`, `Drain`, and `Run` = '0' while no packet is open and S2-1 does not discard. The last case
clears the segment of a transfer that ended before its packet arrived (a command accepted just before a halt): the
next packet then gets the segment of its own command. The segment register of S2-2 needs no clearing of its own:
the split is idle at every command handshake (the segment of the transfer before has ended with its buffer or its
packet, or the reset has cleared it) and takes the segment in the next clock cycle, during a reset as well, since
`Seg_Ready` is '1' while no segment is active.

Chunk plan (S2-ST-04): when the split takes the segment of S2-2, S2-1 loads `Limit` and `Rest` from the address of
the transfer (`Seg_Addr`, of which `odma_s2mm` passes the bits below the burst size BB = B x `MemWidth_g` / 8 as
`Seg_Offset`) and its keyhole (`Seg_Keyhole`), both registers of S2-2 that belong to the transfer of the segment
while it waits. With off = address mod BB:

| Buffer | `Limit` (first chunk) | `Rest` (later chunks) | Bursts |
| --- | --- | --- | --- |
| Keyhole | `ChunkBeats_c` - 1 | `ChunkBeats_c` - 1 | FIXED, as without the plan |
| off a multiple of `MemWidth_g` / 8 | `ChunkBeats_c` - 1 | `ChunkBeats_c` - 1 | A chunk covers B memory words: one burst, two where it crosses a 4 KB boundary. Chunks up to the burst boundary would cost one more chunk per buffer and save one burst only per 4 KB boundary crossed |
| off another multiple of `StreamWidth_g` / 8 | `ChunkBeats_c` - 1 - off / (`StreamWidth_g` / 8) | `ChunkBeats_c` - 1 | The first chunk ends at the burst boundary above the address, the later chunks are aligned: one burst each |
| off inside a stream word | `ChunkBeats_c` - 1 - S | `ChunkBeats_c` - 1 - S | S > 0: a chunk of one memory word less than a burst covers B memory words at any offset, one burst unless it crosses a 4 KB boundary (the memory word at the end of a chunk is written by two bursts with complementary strobes); S = 0: a chunk covers B + 1 memory words, two bursts |

S is the generic `ShortBeats_g` of the chunk former, `shortBeats(MemWidth_g, StreamWidth_g, B)` of
`odma_s2mm_pkg`: `MemWidth_g` / `StreamWidth_g` where the short chunks take more beats per clock cycle than two
bursts per chunk, 0 otherwise. Measured with buffers 1 byte above a burst boundary (verification report): the
short chunks gain with a memory wider than the stream and B of 8 or more beats, where the write master issues a
burst only with its data (section 5.5) and each burst costs its command time; with B of 2 or 4 beats a memory
word is a large part of a burst, and with equal widths the low-latency writes make the second burst of a chunk
cheaper than a memory word per burst. So S = `MemWidth_g` / `StreamWidth_g` when `MemWidth_g` > `StreamWidth_g`
and B >= 8, else 0.

The plan is loaded at the segment handshake. Every beat of the buffers before has left the chunk former then:
S2-2 offers the segment of a transfer only after it has accepted its command, which is after it has taken the
descriptor with `Pend` of the transfer before, and S2-1 writes that descriptor with the last beat of the buffer.
So the beat count is 0 at the load, and the first chunk has at least one beat, since off is below BB. The discard
segments of `Discard_s` load no plan; the beats they pass are dropped. The plan does not change the addresses:
S2-2 writes each chunk at the command address plus the bytes written, whatever its size.

### 4.3 Halt and drain

| Situation | Behaviour |
| --- | --- |
| `Run` falls between packets | The input is not ready until `Run` rises again (S2-ST-01) |
| `Run` falls inside a packet | The block writes the descriptor {`Bytes` 0, `Beats` of the incomplete chunk, `Pend` '1', `Discard` '1', `PktEnd` '1'}, then accepts and drops input beats up to the `TLast` of the packet (`S_S2mm_Ready` = '1' in this phase; with `Split_g` the split output up to `Out_InLast`, with the segments of section 4.2), then behaves as between packets. With `Split_g` this applies to a packet that is not complete (section 4.2); the rest of a complete packet is taken from the split up to its end first |
| `FlushReq` of S2-2 inside a packet (`Split_g`) | The same as for the fall of `Run`: S2-2 flushes the rest of a packet after a write error, and with the split that rest passes only with the segments of `Discard_s`. The next packet cannot be caught by the same flush: S2-2 accepts no command until the flush is done, and `NeedSeg` offers no discard segment after the end of the discarded packet, so its beats wait at the stream port |
| `Drain` = '1' | The input is not ready; no further descriptor is written |

The block reports `DescPend` to S2-2: a packet is open and its rest is not discarded, so a descriptor of it is still
to come. While the rest of an interrupted packet is discarded, `DescPend` is '0': no descriptor follows, however long
the stream peer takes to deliver the `TLast` of the rest.

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
(`beyondTop(Cmd_Addr, Cmd_Length)`, not checked for a keyhole command, S2-SG-04) with {0 bytes, no end of packet,
`ErrDec_c`} (S2-WR-04); in both cases no stream data is taken. Otherwise the block writes the segment register with
the buffer length (`Split_g`, section 4.2), records the keyhole of the command and takes descriptors from the chunk
buffer:

| Descriptor | Action |
| --- | --- |
| Normal, written bytes plus `Bytes` within the buffer | Write command to the master at the command address plus the written bytes (a keyhole transfer: at the command address) with `Bytes` bytes (`CmdWr_LowLat` of section 5.5, `CmdWr_Fixed` = keyhole of the command); feed job {ceil(`Bytes` / (`StreamWidth_g` / 8)), remaining beats}; written bytes += `Bytes` |
| Normal, beyond the buffer | Overflow: a write command with the bytes that still fit (if any) and their beats, the other beats dropped; `ErrInt_c`; then flush (S2-RS-02) |
| `Discard` = '1' | Its beats are dropped; the transfer ends without the end of packet (S2-HA-01) |
| `Bytes` = 0 and `Pend` = '1' (a last beat without valid bytes after a full chunk) | Its beat is dropped, no write |

After a descriptor with `Pend` = '1' the transfer is complete; the block waits until no write is outstanding and
returns the result {written bytes, end of packet = `PktEnd`, error code} (S2-RS-01, S2-SG-01). A counter of the write
commands without response gives the outstanding level. With `Split_g` a full buffer (`Pend` without `PktEnd`) is a
complete transfer without the end of packet, and the overflow row above cannot occur, because a segment is never
longer than its buffer.

Queued result (S2-RS-06): a transfer that has issued its last write without an error and ended with the end of its
packet, a full buffer or a discarded packet does not wait in `Wait_s`. Its result and its outstanding count move to
the queued result register set (`QValid`, `QBytes`, `QEof`, `QErr`, `QCont`, `QSof`, `QOutst`), and the block returns
to `Idle_s`, so the next command and, with `Split_g`, its segment are accepted while the write responses of the
queued transfer arrive. The next chunk is then in the data buffer and its write command is issued when the last
burst of the queued transfer ends, instead of after its response, its result and the refill of the data buffer.

- Depth: one queued result and one current transfer. A current transfer that ends while a result is queued takes
  the path of `Wait_s` and `Result_s`; the next command waits.
- Order: the write master answers its commands in order, so `Wr_Done` and `Wr_Error` count against the queued
  transfer while `QOutst` is not 0 and against the current transfer after that. The queued result is returned when
  `QOutst` is 0 and before any result of the current transfer; `Result_s` waits while `QValid` is set.
- Start of packet: at the queuing `QSof` takes `Res_Sof` of the queued transfer, and `SofNext` takes the value it gets
  at a result (below), since the queued transfer has no error so far.
- A transfer that ended with a halt (no end of packet, no full buffer, no discard) or with an error is not queued:
  an error that a later response reports would need the flush of the rest of the packet while the next transfer
  already takes it.
- In DR mode the register block issues the next command only after the result, so the queue only moves the return
  of the result from `Result_s` to `Idle_s`, one clock cycle earlier.

Start of packet (S2-SG-02): the register `SofNext` (reset '1') gives `Res_Sof` of a result with bytes or with the
end of packet (a packet without bytes, SGI-13). A result without bytes and without the end of packet (a buffer length
of 0, a buffer beyond the top of the address space, a transfer that has not started) belongs to no packet and has
`Res_Sof` '0'. At every result, and when a result is queued, `SofNext` becomes '0' when the transfer ended with a
full buffer of a packet that continues (`Pend` without `PktEnd`, no error, no discard), otherwise '1': the next
buffer then starts a packet, also after an error or a halt, whose packet rest is discarded. Without `Split_g` every
transfer ends its packet, so `SofNext` is always '1'.

### 5.3 Errors, halt and flush

- A write response with an error (`Wr_Error`) records the first error code of the transfer: `ErrDec_c` when
  `Wr_ErrorResp` is DECERR ("11"), `ErrSlv_c` otherwise (SLVERR, and EXOKAY, interpretation I14; S2-RS-05). No further
  write command is issued for the transfer; the remaining descriptors of the packet, up to the one with `PktEnd`, are
  flushed after the result (S2-RS-03). With `Split_g` the block raises `FlushReq` during the flush, so that S2-1
  drops the rest of the packet that has not passed the split yet (section 4.3).
- An error of the queued transfer records its first error code in `QErr`. The current transfer, accepted before the
  error arrived or in the same clock cycle, gets `Stop`: it issues no further write command (a command already
  presented is completed) and leaves `Take_s`. Its result waits until `Run` has fallen, which the command source does
  after every result with an error (architecture D7), so that it has the form of a transfer cut by a halt: the bytes
  written, `Res_Sof` as for any result, no end of packet, also when its packet ended in it, and no error (SGI-15).
- `QCont` tells whether the rest of the packet of the queued transfer is still to come: it is set when a full buffer
  is queued and cleared when a descriptor with `PktEnd` is taken, by the current transfer or by a flush. While it is
  set, the error of the queued transfer asks for the flush of that rest (`FlushPend`): after the result of the current
  transfer, or at once from `Idle_s` without one. A halt that has flushed the rest before the error arrives has
  cleared `QCont`, so the error asks for no second flush, which would wait for an end of packet that does not come. A
  packet of the current transfer that the queued one did not start is discarded with the halt: after the result,
  `Idle_s` drops the data received before the halt (below).
- While the queued result has an error, `Idle_s` accepts no command, so that only the commands accepted before the
  error start.
- Overflow records `ErrInt_c` and the end of packet of the overflowing chunk: when that chunk ends the packet, its
  beats beyond the buffer are dropped and nothing is flushed; otherwise the rest of the packet is flushed (S2-RS-02).
- `Run` = '0' during a transfer: the descriptors of the packet of the transfer are written up to the descriptor with
  `Pend` or `Discard`. When no descriptor is in the chunk buffer, none is stored for its output and S2-1 writes no
  further descriptor (`DescPend` '0', also while S2-1 discards the rest of an earlier packet), the transfer ends
  without the end of packet, with 0 bytes if no byte was received (S2-HA-01). With `Split_g` it withdraws its
  segment if the split has not taken it (the split takes no segment while it discards), so that the segment cannot
  be taken by the next packet when the discard ends. A
  descriptor is stored from the clock cycle after its write on (write level of the chunk buffer), while its output
  follows one clock cycle later: the block uses the write level, so a packet that ended just before the halt is not
  missed. With `Split_g`, a packet whose end is in the split and whose bytes all fit into the buffer of the
  transfer is complete (section 4.2): S2-1 delivers its rest, and the transfer ends with the end of packet. A
  packet whose rest waits in the split for a further buffer is cut like a packet still arriving: S2-1 writes the
  discard descriptor, the result carries the bytes of the complete chunks without the end of packet, and the rest
  is discarded up to its `TLast`.
- In each of these cases the result is returned once no write is outstanding (S2-RS-04). Then the block flushes: it
  takes the remaining descriptors of the packet up to the one with `Pend` and drops their beats. While `Run` = '0'
  in `Idle_s`, it drops every further packet in the chunk buffer, a whole packet (up to `PktEnd`) at a time (data
  received for later transfers, S2-HA-01). A new command is accepted only after the flush.

### 5.4 Drain

`Drain` = '1': no descriptor is taken and no write command issued; the feeder moves the data of the write commands
the master has accepted from the data buffer (it is complete there, S2-ST-03); the block waits for their responses,
also those of a queued transfer, and returns no result, a queued one neither (S2-HA-02). The core reset after the
drain clears the buffers.

### 5.5 Write master

`UserTransactionSizeBits_g` = `LengthWidth_g` + 1 (gap G14 of the architecture: up to Open Logic 4.7.0-ft.6,
`olo_axi_master_full` counted the user data words of a write command at the width of the size field without its
low bits, so the count wrapped for the sizes in the last user data word below 2**`UserTransactionSizeBits_g`, and
the master issued no further burst; 4.7.0-ft.8 corrects the count, and with one more size bit every command stays
below 2**(`UserTransactionSizeBits_g` - 1) in any case), `AxiMaxBeats_g` = B (section 3; no AXI burst crosses
4 KB, gap G13),
`AxiMaxOpenTransactions_g` = 8, `DataFifoDepth_g` = 2 x `ChunkBeats_c` (the ECC-protected write data buffer in
words of `UserDataWidth_g` bits), `UserDataWidth_g` = `StreamWidth_g`, `AxiDataWidth_g` = `MemWidth_g`,
`ImplRead_g` = false. The master sets the write strobes of the bytes of each command (S2-WR-02) and splits at 4 KB
and B (S2-WR-03); its fixed `AwCache` 0011 and `AwProt` 000 are the values of S2-IF-01.

`CmdWr_LowLat` = '1' when `MemWidth_g` = `StreamWidth_g`, else '0' (S2-WR-03, S2-WR-07):

- High latency (a wider memory): the master issues a burst only when its data is in its FIFO, so the beats of the
  burst follow each other. With low latency the width converter of the master would form one memory word per
  `MemWidth_g` / `StreamWidth_g` stream beats and leave W idle between them.
- Low latency (equal widths): the master issues the bursts of a command at once, and W follows the data. S2-2
  issues a write command only for a chunk that is complete in the data buffer (S2-ST-03), and the feeder moves the
  beats of every issued command at one per clock cycle, also during a drain (section 5.4), so every burst gets its
  data without a gap and no burst waits for data that does not come.

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

`Stopped` = '1' when no write is outstanding and S2-2 is in the drained state, or in `Idle_s` (no transfer, no
queued result, no flush) with the chunk buffer empty and no descriptor of S2-1 to come (`DescPend`: a packet is
open and its rest is not discarded). After a halt, `Stopped` thus waits until the data received before it is
flushed: a descriptor left in the chunk buffer, such as the discard descriptor of a packet cut after its first
buffer, would otherwise be taken by the next transfer after a restart. S2-1 may still be dropping the rest of an
interrupted packet (S2-HA-03). A flush that reaches the end of a packet sets `SofNext`, so the next buffer starts a
packet.

## 7. State machines

`odma_s2mm_chunker`: `Normal_s`, `Discard_s` (drop up to `TLast`); between packets the input is not ready while
`Run` = '0'. `odma_s2mm_write`, command part: `Idle_s`, `Take_s` (next descriptor), `Issue_s` (write command
handshake), `Wait_s` (outstanding writes), `Result_s`, `Flush_s`, `Drained_s` (after a drain, until the core
reset); feeder: `Head_s` (next job), `Feed_s` (beats to the master), `Drop_s` (beats not written). Every
`when others` returns to the first state (architecture D15).

## 8. Timing

- Stream to memory: a chunk is written once its last beat is buffered; its write command follows the descriptor
  after two clock cycles plus the command time of the master. With `Split_g` the split holds up to one beat of bytes,
  so a beat reaches the chunk former one input beat later on an aligned stream, and a buffer end inside a beat inserts
  one clock cycle.
- Buffer boundary inside a packet (`Split_g`): S2-2 accepts the next command once the last write command of the
  full buffer is issued (S2-RS-06), so the split takes the next segment while the write responses of the full buffer
  are outstanding, and the stream input does not wait for them, provided the command source has the next command
  ready (the engine presents it, as it fetches one descriptor ahead). The verification report of the core has the
  measured values.
- Throughput: the channel issues one write command per chunk, once the chunk is complete in the data buffer. With
  equal memory and stream widths the write master takes low-latency commands (section 5.5) and issues the burst at
  once: 0.91 beats per clock cycle with chunks of 16 beats (the defaults), 0.31 with chunks of 2. With a wider memory
  it issues a burst once its data are in its own buffer, and a command costs up to about 7 clock cycles: at twice the
  stream width 0.52 beats per clock cycle with chunks of 8 beats, 0.70 with 16 and 0.95 with 64 (S2-WR-05 requires
  0.9 from 64 beats). Longer bursts raise it. With a memory four or more times wider than the stream the write side
  is faster than the stream and the channel takes one beat per clock cycle. A buffer that does not start at a
  multiple of the memory word adds a burst per chunk where the chunk plan of section 4.2 keeps full chunks; the
  verification report has the measured values.
