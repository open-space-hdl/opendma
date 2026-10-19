# odma_mm2s: Specification

## 1. Overview

`odma_mm2s` is the memory to stream channel of OpenDMA (architecture section 7.2): MM-1 reads the buffer of a
transfer command through an AXI4 read master, MM-2 sends it on the MM2S stream and returns one transfer result per
command. The channel executes the commands of the register interface (DR mode) and of the Scatter/Gather engine
(SG mode) through the same internal interface (command, result, run, drain, stopped; module architecture of
`odma_registers`, section 3).

This specification covers phases a and b: transfers that are one packet each, with `Join_g` (Scatter/Gather Mode)
packets of several commands, and keyhole reads. The control stream MM-3 (phase c) follows.

## 2. Partner behaviour

| Interface | Partner | Behaviour the specification accounts for |
| --- | --- | --- |
| `M_AxiMm2s_*` | Memory through an AXI4 interconnect | Accepts read bursts in any order of ready; returns read data in the order of the bursts (no IDs); may hold `RValid` low at any time; may answer any beat with SLVERR or DECERR, also a beat that is not the last one |
| `M_Mm2s_*` | Stream peer (AXI4-Stream slave) | May hold `TReady` low for any time, also forever; expects `TLast` on the last beat of a packet and `TKeep` contiguous from lane 0 in the last beat |
| Command, result, run, drain, stopped | `odma_registers` (DR mode), `odma_sg` (SG mode) | DR mode: one command at a time, every command one packet. SG mode: up to two commands ahead, a packet over several commands from the one with the start to the one with the end of packet; on a halt or an error no further command, so a packet can stay without its end. Both take every result at once, lower `Run` to halt and raise `Drain` for a soft reset (module architecture of `odma_registers`, sections 4 and 6) |
| Read master | `olo_ft_axi_master_full` at 4.7.0-ft.8 | Accepts a command of 1 to 2**`LengthWidth_g` - 1 bytes at any address; delivers the bytes right-aligned from lane 0 with `Rd_Last` on the last word; signals `Rd_Done`, or `Rd_Error` with the response code of the first failing beat (`Rd_ErrorResp`), per command when the AXI reads are complete, before the data is consumed; with `CmdRd_Fixed` FIXED bursts of at most 16 beats at the AXI word of the address, the bytes packed from lane 0; at least four clock cycles per command; no abort of an accepted command |
| Stream join | `olo_base_stream_join` at 4.7.0-ft.8 (with `Join_g`) | Packs the valid bytes of the input beats (`In_Be` contiguous from lane 0) into full beats, the last beat of a packet partial; holds up to one beat of bytes until the next input beat or `In_Last`; an empty beat with `In_Last` ends the packet with `Out_Last` on the bytes held; registered outputs; `Rst` clears the held bytes |

## 3. Requirements

### 3.1 Interfaces

| ID | Requirement | PG021 items |
| --- | --- | --- |
| MM-IF-01 | The memory port shall be an AXI4 read master with `AddrWidth_g` address bits and `MemWidth_g` data bits, bursts of full-width beats (INCR, FIXED for keyhole, MM-SG-03), `ArCache` 0011, `ArProt` 000 and no ID signals. | none (interface, architecture section 6) |
| MM-IF-02 | The stream port shall be an AXI4-Stream master with `StreamWidth_g` data bits, `TKeep` and `TLast`. | `STRM.MM2S` |
| MM-IF-03 | The channel shall accept a command only while `Run` is '1' and `Drain` is '0', and shall return exactly one result per accepted command, in the order of the commands. | none (internal interface) |

### 3.2 Reading the buffer (MM-1)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| MM-RD-01 | The channel shall read the bytes from the command address up to the address plus the length minus 1, at any start address and for every length from 1 to 2**`LengthWidth_g` - 1, and only the memory words that contain them. | `FEAT.UNALIGNED` |
| MM-RD-02 | No read burst shall cross a 4 KB address boundary or have more than `BurstBeats_g` beats. | `FEAT.4K`, `FEAT.BURST` |
| MM-RD-03 | A read burst shall be requested only when the data buffer of the channel can take all its beats, so that a stream peer that holds `TReady` low never holds the R channel of the memory. | none (architecture D3) |
| MM-RD-04 | A command whose buffer reaches beyond the top of the address space shall cause no read and no stream beat; its result shall carry the decode error and 0 bytes (interpretation I5). | `MM2S_DMASR.DMADecErr` |
| MM-RD-05 | With the stream peer always ready, a memory that takes every read burst at once and returns its beats without wait states, and at least 8 stream beats per burst (`BurstBeats_g` x `MemWidth_g` / `StreamWidth_g` >= 8), the channel shall send one stream beat per clock cycle during a transfer of 64 bursts. | none (performance) |
| MM-RD-06 | A command of length 0 shall cause no read and no stream beat; its result shall carry the internal error code and 0 bytes (interpretation M3). | none (internal interface) |

### 3.3 Stream output (MM-2)

| ID | Requirement | PG021 items |
| --- | --- | --- |
| MM-ST-01 | The bytes of a transfer shall be sent in address order, the byte at the command address in lane 0 of the first beat; every beat shall carry `StreamWidth_g` / 8 bytes except the last beat of the transfer, whose `TKeep` marks the remaining bytes contiguous from lane 0 (with `Join_g`, of a packet: MM-SG-01). | `STRM.MM2S` |
| MM-ST-02 | `TLast` shall be set on the last beat of a transfer whose command has the end of packet. | `STRM.MM2S` |
| MM-ST-03 | The result of a transfer shall be returned only after its last beat has been accepted by the stream peer; it shall carry the length of the command as the transferred bytes and the end of packet of the command. | none (architecture D4) |

### 3.4 Errors

| ID | Requirement | PG021 items |
| --- | --- | --- |
| MM-ER-01 | A read response other than OKAY on any beat of a transfer shall give its result an error code, the slave error or the decode error. | `MM2S_DMASR.DMASlvErr` |
| MM-ER-02 | A transfer with an error response shall still send all its beats with the `TKeep` and `TLast` of MM-ST-01 and MM-ST-02 (interpretation I11). | `MM2S_DMASR.DMASlvErr` |
| MM-ER-03 | The error code of MM-ER-01 shall be the slave error for SLVERR and for EXOKAY (interpretation I14) and the decode error for DECERR; with responses of both kinds in one transfer, the first one decides. | `MM2S_DMASR.DMASlvErr`, `MM2S_DMASR.DMADecErr` |

### 3.5 Halt and drain

| ID | Requirement | PG021 items |
| --- | --- | --- |
| MM-HA-01 | When `Run` falls, the channel shall accept no new command and complete the accepted transfers on the stream with their results (interpretation I8); `Stopped` shall be '1' while no accepted command is without result and no read burst is outstanding. | `MM2S_DMACR.RS` |
| MM-HA-02 | While `Drain` is '1', the channel shall accept no command, send no stream beat, discard the read data of the accepted transfers, complete their read bursts on the AXI4 port and return no result; `Stopped` shall rise when no read burst is outstanding. | `MM2S_DMACR.Reset` |
| MM-HA-03 | `Rst` during a transfer shall end it at once, with no further stream beat and no result; after `Rst` the channel shall accept and transfer the next command as after the first reset. | `RST.HARD` |

### 3.6 Fault tolerance

| ID | Requirement | PG021 items |
| --- | --- | --- |
| MM-FT-01 | The read data buffer, the transfer buffer and the response buffer shall be protected by SECDED ECC; every word read from a buffer with a corrected single error or a detected double error shall raise one pulse on the bit of that buffer in `Ecc_Sec` or `Ecc_Ded`; `EccInj_Valid` of a buffer with `EccInj_Double` and `EccInj_Data` shall flip one or two parity bits or data bits of the next codeword written to that buffer. | none (architecture P5) |

### 3.7 Scatter/Gather Mode

| ID | Requirement | PG021 items |
| --- | --- | --- |
| MM-SG-01 | With `Join_g`, the commands of one packet (the first with the start, the last with the end of packet, each with any address and length) shall be sent as one packet: the bytes of each buffer follow the last byte of the buffer before without gap, every beat is full except the last beat of the packet, and `TLast` is set only on that beat. | `STRM.MM2S`, `DESC.MM2S_CONTROL.TXEOF` |
| MM-SG-02 | With `Join_g`, the result of a command without the end of packet shall be returned when the last byte of its buffer has been read and passed on to the stream output; the result of the command with the end of packet as in MM-ST-03. | `DESC.MM2S_STATUS.TransferredBytes` |
| MM-SG-03 | A command with keyhole shall read its buffer with FIXED bursts of at most 16 beats at the command address with the bits below the memory data width cleared; the stream carries the bytes of the successive read beats in order, packed from lane 0 as for an incrementing read of the same number of memory words, the last beat with the remaining bytes of the length. MM-RD-04 does not apply: every beat accesses the memory word at that address, which lies in the address space. | `*_DMACR.Keyhole` |
| MM-SG-04 | With `Join_g`, when `Run` falls inside a packet of several commands, the channel shall complete the accepted commands as in MM-HA-01 and set `TLast` on the last beat of the last of them, so that the stream peer sees the packet ended early (interpretation M4); `Stopped` shall rise only after the stream peer has accepted that beat. | `*_DMACR.RS` |

## 4. Interpretations

| ID | PG021 | OpenDMA |
| --- | --- | --- |
| I5 | Buffer beyond the top of the address space not described | No access, decode error (MM-RD-04) |
| I8 | `RS` = 0: pending transfers flushed or completed | Completed, with `TLast` and result (MM-HA-01) |
| I11 | Streams potentially terminated early on error | The transfer is sent completely (MM-ER-02); the stream peer sees a complete packet, software sees the error |
| M1 | Reads at beat granularity are not described | The other bytes of the first and the last memory word are read and discarded (MM-RD-01, architecture P6) |
| M2 | A double error in the read data buffer is not part of PG021 | The beat is sent as read from the buffer and counted (MM-FT-01, extension window); the transfer result is not changed, so the register interface keeps its PG021 behaviour |
| M4 | `RS` = 0 in Scatter/Gather Mode: "AXI4-Stream outs are potentially terminated early" | A packet of several descriptors ends with `TLast` on the last beat of the descriptor in progress (MM-SG-04) |
| M3 | A buffer length of 0 is an internal error of a descriptor in Scatter/Gather Mode (Table 31, `DMAIntErr`) | The channel ends a command of length 0 without a read and with the internal error code (MM-RD-06); the register interface of DR mode never issues one |
| I14 | Tables 7 and 17 (`DMASlvErr`, `DMADecErr`): the flags for SLVERR and DECERR; an EXOKAY response is not described | EXOKAY to an access that did not request exclusive access is a protocol violation of the slave; it counts as a slave error (MM-ER-03). Observable: an EXOKAY read response sets `DMASlvErr` |

## 5. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| SLVERR, DECERR or EXOKAY on a read beat | `Rd_Error` and `Rd_ErrorResp` of the read master | Transfer completed on the stream, result with the error code (MM-ER-01, MM-ER-02, MM-ER-03) |
| Halt or error inside a packet of several commands | `Run` = '0' with a packet open in the stream join | `TLast` on the last beat of the last accepted command (MM-SG-04) |
| Buffer beyond the top of the address space | `beyondTop` of `odma_pkg` | No access, result with the decode error (MM-RD-04) |
| Command of length 0 | Length of the command | No access, result with the internal error (MM-RD-06) |
| Single or double error in an FT buffer | ECC of the buffer | `Ecc_Sec`, `Ecc_Ded` pulses (MM-FT-01) |

## 6. Configuration parameters

| Generic | Range | Description |
| --- | --- | --- |
| `AddrWidth_g` | 32 to 64 | Address bits of the memory port |
| `LengthWidth_g` | 8 to 26 | Bits of the command length |
| `MemWidth_g` | 32, 64, ..., 1024 | Data bits of the memory port |
| `StreamWidth_g` | 8, 16, ..., `MemWidth_g` | Data bits of the stream |
| `BurstBeats_g` | 2, 4, ..., 256 | Longest read burst |
| `BufferBeats_g` | at least 2 x `BurstBeats_g` x `MemWidth_g` / `StreamWidth_g` | Depth of the read data buffer in stream beats |
| `Join_g` | boolean, default false | true: the stream join of packets of several commands (Scatter/Gather Mode, MM-SG-01, MM-SG-02, MM-SG-04); false: every command is sent with its own `TKeep` of the last beat, as in DR mode |
