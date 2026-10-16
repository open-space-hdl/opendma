# odma_s2mm: Specification

## 1. Overview

`odma_s2mm` is the stream to memory channel of OpenDMA (architecture section 7.3): S2-1 receives the S2MM stream
into an FT data buffer and cuts each packet into chunks of one memory burst, S2-2 writes the complete chunks into the
buffer of the transfer command through an AXI4 write master and returns one transfer result per command. The channel
executes the commands of the register interface (DR mode) and later of the Scatter/Gather engine through the same
internal interface (command, result, run, drain, stopped; module architecture of `odma_registers`, section 3).

This specification covers phase a: one packet per transfer, the packet written into one buffer. Packets spread over
several buffers (phase b, gap G10), keyhole writes (phase b, gap G1) and the status stream S2-3 (phase c) follow.

## 2. Partner behaviour

| Interface | Partner | Behaviour the specification accounts for |
| --- | --- | --- |
| `S_S2mm_*` | Stream peer (AXI4-Stream master) | Sends packets of any length from one byte, beats with gaps of any length, also stops in the middle of a packet for any time; marks the last beat with `TLast`; valid bytes contiguous from lane 0 in the last beat; may send a last beat without valid bytes; `TKeep` of other beats is not relied upon |
| `M_AxiS2mm_*` | Memory through an AXI4 interconnect | Accepts write bursts in any order of ready; answers every burst with one response in the order of the bursts (no IDs), OKAY, SLVERR or DECERR |
| Command, result, run, drain, stopped | `odma_registers` (DR mode) | Issues one command at a time in DR mode, possibly long before the packet arrives; takes every result at once; lowers `Run` to halt and raises `Drain` for a soft reset |
| Write master | `olo_ft_axi_master_full` at 4.7.0-ft.6 | Takes write data only after the command (alignment); writes the bytes of a command of 1 to 2**`LengthWidth_g` - 1 bytes from any address with strobes; in high-latency mode issues a burst only when its data is buffered; signals `Wr_Done` or `Wr_Error` per command; at least four clock cycles per command; the response code of a failed command needs gap G5 |

## 3. Requirements

### 3.1 Interfaces

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-IF-01 | The memory port shall be an AXI4 write master with `AddrWidth_g` address bits and `MemWidth_g` data bits, INCR bursts of full-width beats, `AwCache` 0011, `AwProt` 000 and no ID signals. | none (interface, architecture section 6) |
| S2-IF-02 | The stream port shall be an AXI4-Stream slave with `StreamWidth_g` data bits, `TKeep` and `TLast`. | `STRM.S2MM` |
| S2-IF-03 | The channel shall accept a command only while `Run` is '1', `Drain` is '0' and no transfer is in progress, and shall return exactly one result per accepted command. | none (internal interface) |

### 3.2 Stream input and chunks (S2-1)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-ST-01 | The channel shall accept stream beats into its data buffer only while `Run` is '1' and the buffer has space; while the channel is halted, `S_S2mm_Ready` shall be '0', except while the rest of an interrupted packet is discarded (S2-HA-01) (interpretation I9). | `STRM.S2MM` |
| S2-ST-02 | The bytes of a beat without `TLast` shall all be taken; of a beat with `TLast`, the bytes up to the first lane whose `TKeep` bit is not set; a last beat without valid bytes shall end the packet (interpretation I10). | `STRM.S2MM` |
| S2-ST-03 | A packet shall be cut into chunks of one burst, `ChunkBeats` = B x `MemWidth_g` / `StreamWidth_g` beats with B the smaller of `BurstBeats_g` and the beats of 4 KB (4096 / (`MemWidth_g` / 8)), the last chunk ending with the packet; a chunk shall be written only when all its beats are in the data buffer. | none (architecture D5) |

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
| S2-RS-02 | A packet longer than the buffer: the bytes that fit shall be written, the rest of the packet discarded up to its `TLast`, and the result shall carry the internal error code (architecture D6). | `S2MM_DMASR.DMAIntErr` |
| S2-RS-03 | A write response other than OKAY shall give the result an error code, the slave error or the decode error, and no end of packet; after the first error no further write shall be issued for the packet, and the rest of the packet shall be discarded up to its `TLast`. | `S2MM_DMASR.DMASlvErr` |
| S2-RS-04 | A result with an error or without the end of packet shall be returned once no write of the transfer is outstanding, without waiting for the `TLast` of a packet that is being discarded. | none (architecture D7) |

### 3.5 Halt and drain

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-HA-01 | When `Run` falls during a transfer, the channel shall write the chunks of its packet that are complete in the data buffer, discard the rest of the packet up to its `TLast` and return a result with the bytes written and without the end of packet, unless the packet ended among the complete chunks (interpretation I8); a transfer without a received byte ends with a result of 0 bytes. Data received for later transfers shall be discarded, so that the channel resumes with the next packet that starts after the halt. | `S2MM_DMACR.RS` |
| S2-HA-02 | While `Drain` is '1', the channel shall accept no command and no stream beat, complete the writes already given to the write master with their data, issue no further write and return no result; `Stopped` shall rise when no write is outstanding. | `S2MM_DMACR.Reset` |
| S2-HA-03 | `Stopped` shall be '1' while no transfer is in progress and no write is outstanding, also while the rest of an interrupted packet is still being discarded. | `S2MM_DMACR.RS` |

### 3.6 Fault tolerance

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-FT-01 | The data buffer, the chunk buffer and the write data buffer of the write master shall be protected by SECDED ECC; every corrected single error and every detected double error shall raise one pulse on the `Ecc_Sec` or `Ecc_Ded` bit of its buffer; `EccInj_Valid` of a buffer with `EccInj_Double` and `EccInj_Data` shall flip one or two parity bits or data bits of its next codeword. | none (architecture P5) |

### 3.7 Requirements waiting for Open Logic

Open Logic 4.7.0-ft.6 reports a failed write command of `olo_ft_axi_master_full` without its response code (gap G5 of
the architecture). Until the release with the response code, the channel gives every failed transfer the slave error
code; the requirement below takes effect with that release.

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-RS-05 | The error code of S2-RS-03 shall be the slave error for SLVERR and the decode error for DECERR; with responses of both kinds in one transfer, the first one decides (gap G5). | `S2MM_DMASR.DMASlvErr`, `S2MM_DMASR.DMADecErr` |

### 3.8 Requirements of phase b

| ID | Requirement | PG021 items |
| --- | --- | --- |
| S2-SG-01 | In Scatter/Gather Mode a packet longer than the buffer of a command shall continue at byte 0 of the buffer of the next command (gap G10): the result of the full buffer carries its length and no end of packet, and S2-RS-02 does not apply. | `DESC.S2MM_CONTROL.BufferLength`, `STRM.S2MM` |
| S2-SG-02 | The result shall carry a start of packet flag when its buffer holds the first byte of a packet, and the end of packet when the packet ended in it. | `DESC.S2MM_STATUS.RXSOF`, `DESC.S2MM_STATUS.RXEOF` |
| S2-SG-03 | When no next command is available for the rest of a packet, the rest shall wait at the stream input (`S_S2mm_Ready` = '0') until the next command arrives. | `DESCMGMT.TAIL` |
| S2-SG-04 | A command with keyhole shall write its buffer with FIXED bursts of at most 16 beats at the command address with the bits below the memory data width cleared (gap G1), in DR mode and in Scatter/Gather Mode. | `*_DMACR.Keyhole` |

## 4. Interpretations

| ID | PG021 | OpenDMA |
| --- | --- | --- |
| I5 | Buffer beyond the top of the address space not described | No write, decode error (S2-WR-04) |
| I8 | `RS` = 0: pending transfers flushed or completed, data integrity not guaranteed | Complete chunks written, the rest discarded up to `TLast`, no end of packet (S2-HA-01) |
| I9 | A few beats accepted before the core is programmed | Beats accepted only while the channel runs (S2-ST-01) |
| I10 | `TKeep` handling not described | S2-ST-02 |
| S1 | Table 24: a buffer shorter than the packet gives undefined results; Table 17: `DMAIntErr` | No byte beyond the buffer, the rest discarded, internal error (S2-RS-02) |
| S2 | Write errors in the middle of a packet are not described | No further write, rest discarded, result once the outstanding writes have answered (S2-RS-03, S2-RS-04) |
| S3 | A double error in a buffer is not part of PG021 | The data is written as read from the buffer and counted (S2-FT-01, extension window); the result is not changed |
| S4 | A buffer length of 0 is an internal error of a descriptor in Scatter/Gather Mode (Table 38, `DMAIntErr`) | The channel ends a command of length 0 without a write and with the internal error code (S2-WR-06); the register interface of DR mode never issues one |

## 5. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Packet longer than the buffer | Byte count of the chunks against the buffer length | Bytes that fit written, rest discarded, internal error (S2-RS-02) |
| SLVERR or DECERR on a write burst | `Wr_Error` of the write master (the response code with gap G5) | Error code, no further write, rest discarded (S2-RS-03, S2-RS-05) |
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
