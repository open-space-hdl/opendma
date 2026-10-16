# odma_s2mm: Architecture and Design Description

## 1. Block diagram

![Block diagram of odma_s2mm: the chunk former S2-1 with olo_base_chunker, the data buffer and the chunk buffer, and
the write command block S2-2 with the address check and the write master olo_ft_axi_master_full](img/odma_s2mm_arch.drawio.svg)

## 2. Entities

| Entity | Block | Content |
| --- | --- | --- |
| `odma_s2mm` | Module top | Instances of the blocks below and of the write master, the stopped level |
| `odma_s2mm_chunker` | S2-1 | Stream input, `olo_base_chunker`, byte count of a chunk, chunk descriptors, discard of an interrupted packet |
| `odma_s2mm_write` | S2-2 | Transfer commands, address check, write commands per chunk, data feed, responses, overflow, flush, results |
| `olo_base_chunker` | S2-1 | Cut of a packet into chunks of `ChunkBeats_c` = `BurstBeats_g` x `MemWidth_g` / `StreamWidth_g` beats |
| `olo_ft_fifo_sync` (two) | S2-1 to S2-2 | Data buffer (`StreamWidth_g` bits, `BufferBeats_g` entries), chunk buffer (descriptors, 32 entries) |
| `olo_ft_axi_master_full` | S2-2 | AXI4 write master with the ECC-protected write data buffer of two chunks (read side not implemented) |

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
| `Ecc_Sec`, `Ecc_Ded` | 3 | out | ECC events of the data buffer (bit 0, index 1 of the extension window), the chunk buffer (bit 1, index 2), the write data buffer (bit 2, index 3) |
| `EccInj_Valid` | 3 | in | Error injection per buffer, same order |
| `EccInj_Double` | 1 | in | '1' double, '0' single error |

Generics as in section 6 of the specification.

## 4. Chunk former (S2-1, `odma_s2mm_chunker`)

### 4.1 Normal operation

While `Run` = '1', `Drain` = '0' and the data and chunk buffers have space, the input is ready. `olo_base_chunker`
marks the last beat of each chunk (`Out_Last`) and of each packet (`Out_InLast`). Every beat goes into the data
buffer. At the last beat of a chunk the block writes a descriptor into the chunk buffer:

| Field | Width | Content |
| --- | --- | --- |
| `Bytes` | 16 | Bytes of the chunk: beats x `StreamWidth_g` / 8, for the last chunk of a packet the full beats plus `keepBytes(TKeep)` of the last beat (I10) |
| `Beats` | 16 | Beats of the chunk in the data buffer |
| `Pend` | 1 | The chunk ends a packet |
| `Discard` | 1 | The chunk is the stored part of an interrupted packet: it is not written |

The descriptor of a chunk is written in the clock cycle after its last beat enters the data buffer, so a descriptor
never refers to beats that are not yet buffered (S2-ST-03).

### 4.2 Halt and drain

| Situation | Behaviour |
| --- | --- |
| `Run` falls between packets | The input is not ready until `Run` rises again (S2-ST-01) |
| `Run` falls inside a packet | The block writes the descriptor {`Bytes` 0, `Beats` of the incomplete chunk, `Pend` '1', `Discard` '1'}, then accepts and drops input beats up to the `TLast` of the packet (`S_S2mm_Ready` = '1' in this phase), then behaves as between packets |
| `Drain` = '1' | The input is not ready; no further descriptor is written |

The block reports `PacketOpen` (a packet started and its `TLast` not yet taken) to S2-2.

## 5. Write command (S2-2, `odma_s2mm_write`)

### 5.1 Transfer

A command is accepted in `Idle_s` when `Run` = '1' and `Drain` = '0'. `beyondTop(Cmd_Addr, Cmd_Length)` rejects a
buffer beyond the top of the address space with the result {0 bytes, no end of packet, `ErrDec_c`} (S2-WR-04);
otherwise the block takes descriptors from the chunk buffer:

| Descriptor | Action |
| --- | --- |
| Normal, written bytes plus `Bytes` within the buffer | Write command to the master at the command address plus the written bytes with `Bytes` bytes (`CmdWr_LowLat` = '0'); the first ceil(`Bytes` / (`StreamWidth_g` / 8)) beats of the chunk go to `Wr_Data`, the remaining beats (a last beat without valid bytes) are dropped; written bytes += `Bytes` |
| Normal, beyond the buffer | Overflow: a write command with the bytes that still fit (if any) and their beats, the other beats of the chunk dropped; then flush (S2-RS-02) |
| `Discard` = '1' | Its beats are dropped; the transfer ends without the end of packet (S2-HA-01) |
| `Bytes` = 0 and `Pend` = '1' (a last beat without valid bytes after a full chunk) | Its beat is dropped, no write |

After a descriptor with `Pend` = '1' the transfer is complete; the block waits until no write is outstanding and
returns the result {written bytes, end of packet, error code} (S2-RS-01).

### 5.2 Errors, halt and flush

- A write response with an error (`Wr_Error` with the response code of gap G5) records the first error code; no
  further write command is issued for the transfer; the remaining descriptors of the packet are flushed (S2-RS-03).
- Overflow records `ErrInt_c` and flushes the rest of the packet (S2-RS-02).
- `Run` = '0' during a transfer: the descriptors in the chunk buffer that belong to the packet of the transfer are
  written up to the descriptor with `Pend`; if S2-1 has no packet open and the chunk buffer is empty, the transfer
  ends with 0 bytes (S2-HA-01).
- In each of these cases the result is returned once no write is outstanding (S2-RS-04). Then the block flushes:
  it takes the remaining descriptors of the packet up to the one with `Pend` and drops their beats; after a halt it
  also drops all further descriptors and beats while `Run` = '0' (data received for later transfers, S2-HA-01). A
  new command is accepted only after the flush.

### 5.3 Drain

`Drain` = '1': no descriptor is taken and no write command issued; the data of the write commands the master has
accepted is fed to `Wr_Data` from the data buffer (it is complete there, S2-ST-03); the block waits for their
responses and returns no result (S2-HA-02). The core reset after the drain clears the buffers.

### 5.4 Write master

`UserTransactionSizeBits_g` = `LengthWidth_g`, `AxiMaxBeats_g` = `BurstBeats_g`, `AxiMaxOpenTransactions_g` = 8,
`DataFifoDepth_g` = 2 x `ChunkBeats_c`, `UserDataWidth_g` = `StreamWidth_g`, `AxiDataWidth_g` = `MemWidth_g`,
`ImplRead_g` = false. The master sets the write strobes of the bytes of each command (S2-WR-02), splits at 4 KB and
`BurstBeats_g` and issues a burst only when its data is in its FIFO (S2-WR-03); its fixed `AwCache` 0011 and `AwProt`
000 are the values of S2-IF-01.

## 6. Stopped

`Stopped` = '1' when S2-2 is in `Idle_s` (no transfer, no flush) or, during a drain, when no write is outstanding;
S2-1 may still be dropping the rest of an interrupted packet (S2-HA-03).

## 7. State machines

`odma_s2mm_chunker`: `Normal_s`, `Discard_s` (drop up to `TLast`), `Blocked_s` (halted between packets).
`odma_s2mm_write`: `Idle_s`, `Take_s` (next descriptor), `Feed_s` (data of a write command), `Drop_s` (beats not
written), `Wait_s` (outstanding writes), `Result_s`, `Flush_s`. Every `when others` returns to the first state
(architecture D15).

## 8. Timing

- Stream to memory: a chunk is written once its last beat is buffered; the write command takes at least four clock
  cycles of the master, the data of a chunk one clock cycle per beat.
- With bursts of 16 beats or more the command time of the master overlaps with the data of the previous chunk, so
  that long packets are taken at one beat per clock cycle (S2-WR-05).
