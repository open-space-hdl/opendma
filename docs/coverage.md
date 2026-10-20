# OpenDMA: Code Coverage

## 1. Method

The code coverage of the OpenDMA sources is measured with QuestaSim (Questa Pro Microchip Edition 2024.3) over the
complete regression of `run.py`, the same test set that GHDL runs in CI, at a time resolution of 1 fs:

```shell
python run.py --questa --coverage -p 1
```

The sources of `hdl/<module>/src` are compiled with `+cover=sbcef`: statements, branches, conditions, expressions
(focused expression coverage) and state machines. Open Logic, UVVM and the testbenches are not instrumented; Open Logic
is verified by its own regression. `run.py` merges the coverage of all tests into `coverage/coverage.ucdb` and writes
the reports `coverage/coverage_report.txt` (details per instance) and `coverage/coverage_byfile.txt`; a design unit
is covered when any of its instances in any test covers it.

Closure rules:

- Statements, branches, state machine states and transitions: every item is covered by a test or listed with its
  justification in section 4.
- Conditions and expressions: reported, not a closure criterion. Focused expression coverage requires every input
  term to change the result while the other terms do not mask it; many combinations cannot occur by construction.
  Every miss was reviewed for untested behaviour (section 3); the remaining ones are listed with their reason in
  section 4.
- `-- coverage off` / `-- coverage on` enclose the `when others` branch of each of the 12 state machines, whose
  enumerated state type lists every state: the branch recovers from an illegal state, which needs an upset of the
  state register and cannot be reached through the ports.

## 2. Result

The complete regression of 1009 tests on commit 6252594 with Open Logic 4.7.0-ft.8 passes in QuestaSim, as in GHDL:
with code coverage (1 h 54 min) and in the optimised run without it (1 h 51 min), both started on 2026-10-19. The
merged result over all tests:

| File | Statements | Branches | FSM states | FSM transitions | Conditions | Expressions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `odma_core.vhd` | 123 / 123 | 7 / 7 |  |  | 4 / 4 | 4 / 4 |
| `odma_mm2s.vhd` | 13 / 13 |  |  |  |  | **19 / 24** |
| `odma_mm2s_command.vhd` | 27 / 27 | 25 / 25 | 3 / 3 | 4 / 4 | 8 / 8 | 2 / 2 |
| `odma_mm2s_stream.vhd` | 48 / 48 | 52 / 52 | 4 / 4 | 7 / 7 | **36 / 40** | 7 / 7 |
| `odma_pkg.vhd` | 33 / 33 | 24 / 24 |  |  | 17 / 17 |  |
| `odma_extension.vhd` | 73 / 73 | 35 / 35 |  |  |  | 10 / 10 |
| `odma_interrupt.vhd` | 45 / 45 | 34 / 34 |  |  |  | 6 / 6 |
| `odma_registers.vhd` | 254 / 254 | 118 / 118 |  |  | **51 / 53** | **16 / 20** |
| `odma_soft_reset.vhd` | 13 / 13 | 18 / 18 | 3 / 3 | 4 / 4 | 6 / 6 |  |
| `odma_s2mm.vhd` | 12 / 12 | 2 / 2 |  |  |  | **8 / 12** |
| `odma_s2mm_chunker.vhd` | 80 / 80 | 49 / 49 | 2 / 2 | 2 / 2 | **41 / 45** | 15 / 15 |
| `odma_s2mm_pkg.vhd` | 10 / 10 | 2 / 2 |  |  | 2 / 2 |  |
| `odma_s2mm_write.vhd` | 155 / 155 | **131 / 132** | **4 / 10** | **5 / 25** | **66 / 73** | **5 / 8** |
| `odma_sg.vhd` | 41 / 41 |  |  |  |  | 2 / 2 |
| `odma_sg_channel.vhd` | 183 / 183 | 127 / 127 |  |  | 67 / 67 | 18 / 18 |
| `odma_sg_port.vhd` | 79 / 79 | 51 / 51 | **4 / 6** | **4 / 8** | **23 / 30** | **12 / 16** |
| Total | 1189 / 1189 (100.0 %) | 675 / 676 (99.9 %) | 20 / 28 (71.4 %) | 26 / 50 (52.0 %) | 321 / 345 (93.0 %) | 124 / 144 (86.1 %) |

Bold marks a metric with misses; section 4 gives the reason for each of them, except the condition row of
`odma_s2mm_write.vhd` line 265, which TC-S2-28 tests (section 3). The totals of the state machines
contain the two machines of section 4.1.

## 3. Gaps found and closed

The coverage runs showed behaviour that the requirements ask for but no test exercised, and the review of the
condition and expression misses found more. The tests below close these gaps; all of them passed without a change of
the design.

| Gap | Test |
| --- | --- |
| Error messages of the configuration check and `beyondTop` with an empty buffer: called by the tests with literal arguments, which the compiler evaluates, so the calls never ran in the simulation; the range errors of the stream width were not tested at all | TC-PKG-03, TC-PKG-04 (arguments through variables; stream widths 4, 24 and 2048 for both channels) |
| A length written while the channel stops after a halt request | TC-RG-06 (extended) |
| `Rst` during the drain of a soft reset | TC-RG-11 (extended) |
| `Dly_Irq` without `Dly_IrqEn`: no interrupt | TC-RG-22 (extended) |
| S2MM results held by their receiver: a transfer that ends while the queued result waits, a full buffer of a packet behind a queued result, a drain while results wait | TC-S2-26 (new: `Res_Ready` low in random runs) |
| S2MM: a drain while the rest of a failed packet is flushed | TC-S2-12 (extended) |
| SG engine: a fetch error while the channel stops at a transfer error (`CURDESC` keeps the first error) | TC-SG-09 (extended) |
| SG engine: a fetched descriptor that waits for the channel when the result before it fails | TC-SG-08 (extended) |
| SG engine: a drain while a status write waits for the descriptor port; `Run` falls while a fetch waits for it | TC-SG-12, TC-SG-11 (extended) |
| SG engine: `Rst` while a status write is requested, waits for the port, is given to the master or is answered | TC-SG-19 (new) |
| MM2S: `Rst` during a packet | TC-MM-12 (extended; the memory model is reset with the DUT) |
| MM2S with the join: a drain while the closing beat of a packet left open by a halt waits for the stream peer; halt and drain in the same clock cycle while a packet is open between two of its commands | TC-MM-18 (extended) |
| MM2S with the join: a halt between the acceptance of a command of an open packet and its entry at the stream | TC-MM-20 (new: the halt at every clock cycle of that window and after it) |
| A memory width in range that is not a power of 2 and a burst of one beat, rejected by the configuration check | TC-PKG-04 (extended: memory width 48, burst of one beat) |
| S2MM: a write error or a halt result held by its receiver; a write error that arrives after a halt has cut its packet | TC-S2-26 (extended: SLVERR and halt results with `Res_Ready` low in random runs, write responses 300 clock cycles late) |
| S2MM: the chunk buffer full while the data buffer has space, and a halt while it is full and a packet is open | TC-S2-27 (new: 40 packets of one beat before the commands) |
| SG engine: a drain while a fetched descriptor waits at the head of the buffer, fresh or stale | TC-SG-12 (extended: a fresh descriptor; a stale one with the drain 0 to 40 clock cycles after its fetch) |
| MM2S: a drain while transfer entries without a read (a buffer beyond the top of the address space, a command of length 0) wait at the head of the transfer buffer or reach it | TC-MM-10 (extended) |
| S2MM: a transfer that starts while the stage of the feed jobs is full (`odma_s2mm_write` line 265): the write master holds the commands of two chunks whose data the feeder has not moved yet, then a job without a write follows (a last beat without valid bytes); also with `Run` falling then | TC-S2-28 (new) |

## 4. Remaining misses

### 4.1 State machines

`odma_s2mm_write` (`r.State`: 1 of 7 states, 0 of 20 transitions) and `odma_sg_port` (`r.Rd`: 1 of 3 states, 0 of 4
transitions) are each the first of two state machines whose case statements are in one combinatorial process.
QuestaSim counts only the reset assignment of the first machine of such a process; the second machines (`r.Feed` of
`odma_s2mm_write`, `r.Wr` of `odma_sg_port`) show all their states and transitions. Exchanging the two case statements
of `odma_sg_port` moves the miss to the other machine, which then shows only its reset state while the first shows all
of its states; unique enumeration literals and type names change nothing. The statement and branch coverage of both
files shows every `when` branch and every assignment of a next state covered, so every state and transition of both
machines is reached. All other state machines are covered completely.

### 4.2 Branches

| Location | Item | Reason |
| --- | --- | --- |
| `odma_s2mm_write.vhd` line 470 | `Drop_s` with `Buf_Valid` = '0' (no assignment) | The chunk former writes the chunk descriptor in the clock cycle of the last beat of its chunk, and the data buffer and the descriptor buffer are `olo_ft_fifo_sync` instances with the same latency: every beat of a job is in the data buffer when the feeder reaches it. |

### 4.3 Conditions and expressions

The rows below are combinations of the input terms that the design cannot produce. The row names are those of the
QuestaSim report (`<term>_0`, `<term>_1`: the term decides the result with the value 0 or 1). The totals of section 2
count input terms: a term is covered when both of its rows are hit.

| Location | Rows not hit | Reason |
| --- | --- | --- |
| `odma_mm2s.vhd` lines 340, 341 (ECC events of the transfer buffer) | `Xfer_OutValid_0` | The flags of `olo_ft_fifo_sync` are not gated with `Out_Valid`; the row needs `Xfer_OutReady` without an entry at the output. The stream pops the transfer buffer only in `Result_s`, which it enters with the entry at the head of the buffer. |
| `odma_mm2s.vhd` lines 342, 343 (ECC events of the response buffer) | `Resp_OutValid_0` | `Resp_Ready` is the pop of an entry with a read, which needs `Resp_Valid` = '1'. |
| `odma_mm2s.vhd` line 349 (`Stopped`) | `Resp_Empty_0` | A response belongs to a transfer entry with a read. The entry is written before the read is issued and popped together with its response, so the response buffer is empty whenever the transfer buffer is. |
| `odma_mm2s_stream.vhd` line 200 (`ResValid`) | `(Xfer_Code /= ErrNone_c)_0`, `(Resp_Valid = '1')_0` | Both need `Result_s` with an entry with a read and no response. `olo_axi_master_full` reports the response of a read (`Rd_Done`, `Rd_Error`) no later than it outputs the last beat, and the read data and the response pass buffers of the same latency; the stream enters `Result_s` after the last beat of the entry, so the response is there. |
| `odma_mm2s_stream.vhd` line 203 (`Pop`) | `(Xfer_Code /= ErrNone_c)_0`, `(Resp_Valid = '1')_0` | As line 200, during a drain. |
| `odma_registers.vhd` lines 311, 312 (`Stopped`) | `Included(0)_0`, `Included(1)_0` | `Included` is set from the generics `IncludeMm2s_g` and `IncludeS2mm_g` and is constant; the core drives the stopped status of a channel that is not included to '1'. |
| `odma_registers.vhd` line 706 (`RdExt`) | `ExtRegs_g_1`, `(Addr_v >= ExtBase_c)_0`, `(Addr_v >= ExtBase_c)_1` | `ExtRegs_g` is a generic; QuestaSim reports the rows of the expression only for the instances with `ExtRegs_g` false. Both values are simulated: the reads of the extension window are tested in TC-RG-01 with `ExtRegs_g` true and in TC-RG-14 with `ExtRegs_g` false. |
| `odma_registers.vhd` line 929 | `(fromUslv >= 0)_0`, `(... <= 15)_0` | The range check of the conversion of the 4-bit buffer field of `ECC_INJECT` (`odma_extension.vhd` line 204), which QuestaSim reports at the last line of the file that instantiates the extension: the value of a 4-bit field is always 0 to 15. |
| `odma_s2mm.vhd` lines 368, 369 (ECC events of the data buffer) | `Data_OutValid_0` | The writer takes data only in `Feed_s` and `Drop_s`, which it reaches only when the beats of the job are in the buffer (section 4.2). |
| `odma_s2mm.vhd` lines 370, 371 (ECC events of the descriptor buffer) | `Desc_OutValid_0` | `Desc_Ready` is set only together with `Desc_Valid` = '1'. |
| `odma_s2mm_chunker.vhd` lines 191, 195, 260 | `Split_g_0` | `Split_g` is a generic: in the configurations without the split the expression is constant. Both values are simulated (the `s_` configurations of the S2MM bench). |
| `odma_s2mm_chunker.vhd` line 334 (`SplitRst`) | `(r.State = Normal_s)_0` | The row needs `Discard_s` without an open packet. With `Split_g` a packet is open (`Open_i`) from its first beat at the stream port until its last beat leaves the split; `Discard_s` is entered while a packet is open and left in the clock cycle in which the last beat of that packet is dropped. |
| `odma_s2mm_write.vhd` line 201 (queued result) | `(r.State /= Drained_s)_0` | The row needs `Drained_s` after the drain has ended. `Drained_s` is left only with `Rst`, and the soft reset holds the drain through its reset phase (`odma_soft_reset`). |
| `odma_s2mm_write.vhd` line 305 | `(Desc_Valid = '0')_0` | The row needs a descriptor at the output of the chunk buffer while `Desc_Stored` = '0'. `Desc_Stored` is the write level of the chunk buffer (`In_Level` of `olo_ft_fifo_sync`), and `olo_base_fifo_sync` behind it counts an entry in the write level until the clock cycle after its read, while its output is valid only with a read level above 0, which never exceeds the write level: `Desc_Valid` = '1' implies `Desc_Stored` = '1'. The reason depends on `olo_base_fifo_sync` and is checked again with each change of the Open Logic version. |
| `odma_s2mm_write.vhd` line 328 | `(r.FlushPend = '0')_0` | `FlushPend` is set only together with an error of the transfer (lines 258, 350) or with `Stop` (line 426), which mask it in this condition. |
| `odma_s2mm_write.vhd` lines 336, 340, 363 | `r.Disc_1`, `(r.Disc = '0')_0` | The rows need `Cont` and `Disc` together. Both are set by the chunk descriptor that ends the transfer, `Cont` by the last chunk of a full buffer and `Disc` by the descriptor of a discarded packet, and both are cleared when the next transfer starts. |
| `odma_s2mm_write.vhd` line 457 | `(Buf_Valid = '1')_0` | `Feed_s` with `Buf_Valid` = '0', for the reason of section 4.2. |
| `odma_s2mm_write.vhd` line 275 | `Desc_v.Pend_1`, `Desc_v.PktEnd_0` | The rows need a chunk without valid bytes that is not the end of its packet. A chunk has no valid bytes only as the last beat of a packet (`TKeep` without a valid byte) or, with `Split_g`, as a packet without bytes. |
| `odma_sg_port.vhd` lines 246, 299, 302, 305, 348, 349 | `(CmdRd_Ready = '1')_0`, `(CmdWr_Ready = '1')_0`, `(Wr_Ready = '1')_0`, `(v.WrDat = '1')_0`, `(r.WrCmd = '0')_0`, `(r.WrDat = '0')_0` | The port starts a fetch only after the fetch before has ended and a status write only after the status write before has ended; `olo_ft_axi_master_simple` then accepts the command, and the one data word of a status write, in the first clock cycle. |
| `odma_sg_port.vhd` line 266 | `(r.RdResp = '1')_0` | The row needs the last word of a fetch before its response. The master reports the response no later than it outputs the last word. |
| `odma_sg_port.vhd` lines 333, 334, 341, 342 | `RdGrantVld_0`, `WrGrantVld_0` | `olo_base_arb_rr` sets `Out_Valid` exactly when a bit of the grant is set. |

## 5. Reproduction

```shell
python run.py --questa --coverage -p 1
vcover report -du=* -details -zeros -code sbf coverage/coverage.ucdb
vcover report -srcfile=* -details -zeros coverage/coverage.ucdb
```

The second command lists the statements, branches and state machine items that are not covered, per design unit; the
third lists all metrics per file, merged over the instances.
