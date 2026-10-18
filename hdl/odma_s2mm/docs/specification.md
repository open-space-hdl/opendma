# odma_s2mm: Specification

## 1. Overview

`odma_s2mm` is the stream to memory channel of OpenDMA (architecture section 7.3): S2-1 receives the S2MM stream
into an FT data buffer and cuts each packet into chunks of one memory burst, S2-2 writes the complete chunks into the
buffer of the transfer command through an AXI4 write master and returns one transfer result per command. The channel
executes the commands of the register interface (DR mode) and of the Scatter/Gather engine (SG mode) through the
same internal interface (command, result, run, drain, stopped; module architecture of `odma_registers`, section 3).

This specification covers phases a and b: one packet per transfer, with `Split_g` (Scatter/Gather Mode) packets
spread over several buffers, and keyhole writes. The status stream S2-3 (phase c) follows.

## 2. Partner behaviour

| Interface | Partner | Behaviour the specification accounts for |
| --- | --- | --- |
| `S_S2mm_*` | Stream peer (AXI4-Stream master) | Sends packets of any length from one byte, beats with gaps of any length, also stops in the middle of a packet for any time; marks the last beat with `TLast`; valid bytes contiguous from lane 0 in the last beat; may send a last beat without valid bytes; `TKeep` of other beats is not relied upon |
| `M_AxiS2mm_*` | Memory through an AXI4 interconnect | Accepts write bursts in any order of ready; answers every burst with one response in the order of the bursts (no IDs), OKAY, SLVERR or DECERR |
| Command, result, run, drain, stopped | `odma_registers` (DR mode), `odma_sg` (SG mode) | Present one command at a time, possibly long before the packet arrives (SG mode: the engine presents the next command while the channel still works on the previous one, and it waits at the interface until the channel takes it; DR mode: the next command only after the result); take the results in the order of the commands; lower `Run` to halt, also after every result with an error (architecture D7), and raise `Drain` for a soft reset |
| Write master | `olo_ft_axi_master_full` at 4.7.0-ft.8 | Takes write data only after the command (alignment); writes the bytes of a command of 1 to 2**`LengthWidth_g` - 1 bytes from any address with strobes; in high-latency mode issues a burst only when its data is buffered; signals `Wr_Done`, or `Wr_Error` with the response code of the first failing burst (`Wr_ErrorResp`), per command; with `CmdWr_Fixed` FIXED bursts of at most 16 beats at the AXI word of the address, the bytes packed from lane 0; at least four clock cycles per command |
| Stream split | `olo_base_stream_split` at 4.7.0-ft.8 (with `Split_g`) | Cuts the packets into segments of a size in bytes taken from its command input; every segment starts in lane 0, ends with `Out_Last` and is full except its last beat; `Out_InLast` on the last beat of the segment in which the packet ends; takes no input beat while no segment is active; a packet without bytes gives one beat with `Out_Be` all '0'; the segment command must not depend combinationally on `In_Ready` or the outputs |

## 3. Requirements

### 3.1 Interfaces

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-IF-01 | The memory port shall be an AXI4 write master with `AddrWidth_g` address bits and `MemWidth_g` data bits, bursts of full-width beats (INCR, FIXED for keyhole, S2-SG-04), `AwCache` 0011, `AwProt` 000 and no ID signals. | none (interface, architecture section 6) |
| S2-IF-02 | The stream port shall be an AXI4-Stream slave with `StreamWidth_g` data bits, `TKeep` and `TLast`. | `STRM.S2MM` |
| S2-IF-03 | The channel shall accept a command only while `Run` is '1', `Drain` is '0' and no transfer is in progress other than one whose result waits only for its write responses (S2-RS-06), and shall return exactly one result per accepted command. | none (internal interface) |

### 3.2 Stream input and chunks (S2-1)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-ST-01 | The channel shall accept stream beats into its data buffer only while `Run` is '1' and the buffer has space, with `Split_g` also only while a command is active for them (S2-SG-03); while the channel is halted, `S_S2mm_Ready` shall be '0', except while the rest of an interrupted packet is discarded (S2-HA-01) (interpretation I9). | `STRM.S2MM` |
| S2-ST-02 | The bytes of a beat without `TLast` shall all be taken; of a beat with `TLast`, the bytes up to the first lane whose `TKeep` bit is not set; a last beat without valid bytes shall end the packet (interpretation I10). | `STRM.S2MM` |
| S2-ST-03 | A packet shall be cut into chunks of one burst, `ChunkBeats` = B x `MemWidth_g` / `StreamWidth_g` beats with B the smaller of `BurstBeats_g` and the beats of 4 KB (4096 / (`MemWidth_g` / 8)), the last chunk ending with the packet and, with `Split_g`, a chunk also ending with the buffer; a chunk shall be written only when all its beats are in the data buffer. | none (architecture D5) |

### 3.3 Writing the buffer (S2-2)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-WR-01 | Byte i of a packet shall be written to the command address plus i, at any start address and for every buffer length from 1 to 2**`LengthWidth_g` - 1. | `STRM.S2MM`, `FEAT.UNALIGNED` |
| S2-WR-02 | No byte outside the buffer (command address to address plus length minus 1) shall be written: write strobes are set only for bytes of the buffer that receive packet data. | `STRM.S2MM` |
| S2-WR-03 | No write burst shall cross a 4 KB address boundary or have more than `BurstBeats_g` beats; a burst shall be requested only when its data is in the write master. | `FEAT.4K`, `FEAT.BURST` |
| S2-WR-04 | A command whose buffer reaches beyond the top of the address space shall cause no write and consume no stream data; its result shall carry the decode error and 0 bytes (interpretation I5). | `S2MM_DMASR.DMADecErr` |
| S2-WR-06 | A command with a buffer length of 0 shall cause no write and consume no stream data; its result shall carry the internal error code and 0 bytes (interpretation S4). | none (internal interface) |
| S2-WR-05 | With the memory always ready, the stream sending without gaps and chunks of at least 64 stream beats, the channel shall take at least 0.9 stream beats per clock cycle on average during a packet of 64 chunks. | none (performance) |

### 3.4 Results and errors

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-RS-01 | When the packet ends in the buffer, the result shall carry the number of bytes written, the end of packet and no error, once the write responses of all its bursts have arrived. | none (architecture D5) |
| S2-RS-02 | Without `Split_g`, a packet longer than the buffer: the bytes that fit shall be written, the rest of the packet discarded up to its `TLast`, and the result shall carry the internal error code (architecture D6). | `S2MM_DMASR.DMAIntErr` |
| S2-RS-03 | A write response other than OKAY shall give the result an error code, the slave error or the decode error, and no end of packet; once the error has arrived, no further write shall be issued for the packet, and the rest of the packet shall be discarded up to its `TLast`. Writes that the next transfer of the same packet issued before the error arrived (S2-RS-06) stay; that transfer issues no further write and returns, once `Run` has fallen (architecture D7), a result with the bytes written, without the start and the end of packet and without an error (interpretation SGI-15). While the result of a failed transfer waits for its write responses, no command is accepted. | `S2MM_DMASR.DMASlvErr` |
| S2-RS-04 | A result with an error or without the end of packet shall be returned once no write of the transfer is outstanding, without waiting for the `TLast` of a packet that is being discarded. | none (architecture D7) |
| S2-RS-05 | The error code of S2-RS-03 shall be the slave error for SLVERR and for EXOKAY (interpretation I14) and the decode error for DECERR; with responses of both kinds in one transfer, the first one decides. | `S2MM_DMASR.DMASlvErr`, `S2MM_DMASR.DMADecErr` |
| S2-RS-06 | A transfer that has issued all its writes without an error and ended with the end of its packet, a full buffer of a packet that continues or a discarded packet shall let the channel accept the next command while the write responses of the transfer are outstanding, at most one transfer ahead; the results shall be returned in the order of the commands. | none (performance) |

### 3.5 Halt and drain

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-HA-01 | When `Run` falls during a transfer, the channel shall write the chunks of its packet that are complete in the data buffer, discard the rest of the packet up to its `TLast` and return a result with the bytes written and without the end of packet, unless the packet ended among the complete chunks (interpretation I8); a transfer without a received byte ends with a result of 0 bytes. A packet whose `TLast` the stream port has accepted before `Run` falls and whose bytes all fit into the buffer of the transfer counts as ended among the complete chunks: the channel shall write it completely and return the result with the end of packet. With `Split_g` a packet that needs a further buffer shall be cut like a packet still arriving: its result carries no end of packet, the bytes written in complete chunks stay, and the rest is discarded. Data received for later transfers shall be discarded, so that the channel resumes with the next packet that starts after the halt. | `S2MM_DMACR.RS` |
| S2-HA-02 | While `Drain` is '1', the channel shall accept no command and no stream beat, complete the writes already given to the write master with their data, issue no further write and return no result; `Stopped` shall rise when no write is outstanding. | `S2MM_DMACR.Reset` |
| S2-HA-03 | `Stopped` shall be '1' while no transfer is in progress, no write is outstanding and no data received before the fall of `Run` is left in the buffers of the channel for a later transfer, also while the rest of an interrupted packet is still being discarded. | `S2MM_DMACR.RS` |

### 3.6 Fault tolerance

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-FT-01 | The data buffer, the chunk buffer and the write data buffer of the write master shall be protected by SECDED ECC; every corrected single error and every detected double error shall raise one pulse on the `Ecc_Sec` or `Ecc_Ded` bit of its buffer; `EccInj_Valid` of a buffer with `EccInj_Double` and `EccInj_Data` shall flip one or two parity bits or data bits of its next codeword. | none (architecture P5) |

### 3.7 Scatter/Gather Mode

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-SG-01 | With `Split_g`, a packet longer than the buffer of a command shall continue at byte 0 of the buffer of the next command: the result of the full buffer carries its length and no end of packet, and S2-RS-02 does not apply. | `DESC.S2MM_CONTROL.BufferLength`, `STRM.S2MM` |
| S2-SG-02 | The result shall carry the start of packet when its buffer is the first buffer of a packet (it holds the first byte, or the packet has no byte, interpretation SGI-13), and the end of packet when the packet ended in it; a result without bytes and without the end of packet carries neither (interpretation SGI-14). | `DESC.S2MM_STATUS.RXSOF`, `DESC.S2MM_STATUS.RXEOF` |
| S2-SG-03 | With `Split_g`, when no next command is available for the rest of a packet, the rest shall wait at the stream input (`S_S2mm_Ready` = '0') until the next command arrives; a packet that starts while no command is active waits in the same way. | `DESCMGMT.TAIL` |
| S2-SG-04 | A command with keyhole shall write its buffer with FIXED bursts of at most 16 beats at the command address with the bits below the memory data width cleared, every write of the transfer at that address, the bytes packed from lane 0 as for an incrementing write of the same number of memory words, in DR mode and in Scatter/Gather Mode; S2-WR-04 does not apply, because every beat accesses the memory word at that address, which lies in the address space. | `*_DMACR.Keyhole` |

## 4. Interpretations

| ID | PG021 | OpenDMA |
| --- | --- | --- |
| I5 | Buffer beyond the top of the address space not described | No write, decode error (S2-WR-04) |
| I8 | `RS` = 0: pending transfers flushed or completed, data integrity not guaranteed | Complete chunks written, the rest discarded up to `TLast`, no end of packet; a packet whose `TLast` was accepted and whose bytes fit into the buffer is written completely, one that needs a further buffer is cut (S2-HA-01) |
| I9 | A few beats accepted before the core is programmed | Beats accepted only while the channel runs (S2-ST-01) |
| I10 | `TKeep` handling not described | S2-ST-02 |
| S1 | Table 24: a buffer shorter than the packet gives undefined results; Table 17: `DMAIntErr` | No byte beyond the buffer, the rest discarded, internal error (S2-RS-02) |
| S2 | Write errors in the middle of a packet are not described | No further write, rest discarded, result once the outstanding writes have answered (S2-RS-03, S2-RS-04) |
| S3 | A double error in a buffer is not part of PG021 | The data is written as read from the buffer and counted (S2-FT-01, extension window); the result is not changed |
| S4 | A buffer length of 0 is an internal error of a descriptor in Scatter/Gather Mode (Table 38, `DMAIntErr`) | The channel ends a command of length 0 without a write and with the internal error code (S2-WR-06); the register interface of DR mode never issues one |
| I14 | Tables 7 and 17 (`DMASlvErr`, `DMADecErr`): the flags for SLVERR and DECERR; an EXOKAY response is not described | EXOKAY to an access that did not request exclusive access is a protocol violation of the slave; it counts as a slave error (S2-RS-05). Observable: an EXOKAY write response sets `DMASlvErr` |
| SGI-13 | Table 38 (`S2MM_STATUS.RXSOF`, `RXEOF`): `RXSOF` marks the buffer that holds the start of a packet; a packet without bytes is not described | A packet without bytes (only a last beat without valid bytes) starts and ends in one buffer: its result carries 0 bytes, the start and the end of packet (S2-SG-02). Observable: a status word with 0 transferred bytes and `RXSOF` and `RXEOF` set |
| SGI-14 | Table 38 (`S2MM_STATUS.RXSOF`): the start of packet of a descriptor that receives no byte and no end of packet is not described | A transfer that ends without data and without the end of a packet (a buffer length of 0, a buffer beyond the top of the address space, a transfer that has not started) belongs to no packet: its result carries neither the start nor the end of packet (S2-SG-02). Observable: the status of an S2MM descriptor with a buffer length of 0 or beyond the top of the address space has `RXSOF` = 0 |
| SGI-15 | Tables 16 and 17 (`S2MM_DMACR.RS`, `S2MM_DMASR.Halted`, the error flags), Table 38 (`S2MM_STATUS`): which buffers the channel has written when a write error halts it is not described | The channel accepts the next command while the write responses of the transfer before it are outstanding (S2-RS-06). When such a response reports an error and the packet continues in the next buffer, that buffer can already hold bytes of the packet: no further write follows, the rest of the packet is discarded, and the transfer ends with the halt that follows the error, without the start and the end of packet (S2-RS-03, S2-HA-01). When the failed buffer ended its packet, the next transfer can already have received the start of the next packet, which the halt cuts. Observable: after an S2MM write error, memory beyond the failing buffer can hold bytes of the same packet in the buffer of the next command, whose result has the bytes written, no start and no end of packet and no error |

## 5. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Packet longer than the buffer (without `Split_g`) | Byte count of the chunks against the buffer length | Bytes that fit written, rest discarded, internal error (S2-RS-02) |
| SLVERR, DECERR or EXOKAY on a write burst | `Wr_Error` and `Wr_ErrorResp` of the write master | Error code, no further write, rest discarded (S2-RS-03, S2-RS-05) |
| Buffer beyond the top of the address space | `beyondTop` of `odma_pkg` | No write, decode error (S2-WR-04) |
| Buffer length of 0 | Length of the command | No write, internal error (S2-WR-06) |
| Single or double error in a buffer | ECC of the buffers | `Ecc_Sec`, `Ecc_Ded` pulses (S2-FT-01) |

## 6. Configuration parameters

| Generic | Range | Description |
| --- | --- | --- |
| `AddrWidth_g` | 32 to 64 | Address bits of the memory port |
| `LengthWidth_g` | 8 to 26 | Bits of the buffer length |
| `MemWidth_g` | 32, 64, ..., 1024 | Data bits of the memory port |
| `StreamWidth_g` | 8, 16, ..., `MemWidth_g` | Data bits of the stream |
| `BurstBeats_g` | 2, 4, ..., 256 | Longest write burst |
| `BufferBeats_g` | at least 2 x `BurstBeats_g` x `MemWidth_g` / `StreamWidth_g` | Depth of the data buffer in stream beats |
| `Split_g` | boolean, default false | true: the stream split of packets over several buffers (Scatter/Gather Mode, S2-SG-01, S2-SG-03); false: a packet longer than the buffer is an overflow (S2-RS-02), as in DR mode |
