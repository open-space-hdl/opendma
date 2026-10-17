# odma_sg: Verification Plan

## 1. Overview

The engine is verified through its ports. The bench drives the control interface of the register side (`Run`,
`Drain`, `CurDesc`, `Tail`, `TailWr`, `Cyclic`, `Keyhole`) and observes `CurPtr`, `Idle`, `Stopped` and the
events. Two channel models of the harness stand in for `odma_mm2s` and `odma_s2mm`: each accepts commands with a
programmable delay of `Cmd_Ready` and returns one result per command after a programmable delay, holding `Res_Valid`
until `Res_Ready`. The MM2S model accepts up to eight commands, like the transfer buffer of `odma_mm2s`, the S2MM
model one command at a time, like `odma_s2mm`. A result is the default of the model (MM2S: the buffer length, the end
of packet of the command, no error; S2MM: the bytes, start and end of packet queued by the test for the command) or
a result the test queues; both models return the internal error with 0 bytes for a buffer length of 0, as the
channels do. The descriptor port is connected to the AXI memory model of `tb/` (instance 0) with random
backpressure, latency and error responses on address ranges.

The tests build descriptor chains in the memory of the model through its backdoor (`odma_sg_tb_pkg`): every
descriptor word that the engine does not use (reserved words, the user application fields, the ignored pointer and
length bits) holds a value that depends on its address (`odmaMemByte`), so that a write to a wrong word or an
unmasked bit is visible. Before each test the bench fills the memory around the chain with `odmaMemByte` as well.
After the test the bench compares every word of every descriptor block: the `STATUS` word against the value it
computes from the results the models returned, every other word against its initial value. The expected commands,
status words, events and `CurPtr` values come from a reference walk of the chain in the bench (from `CURDESC`
along `NXTDESC` to the tail), never from the RTL.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `odma_sg_tb` | `odma_sg_th` | `odma_sg`; the AXI memory model on `M_Axi_*`; the MM2S and S2MM channel models; monitors of the AR and AW channels (address, length, size, burst, cache, protection of every burst), of the W channel (data and strobes), of the commands, the results, the events and the ECC outputs |

| VUnit configuration | `AddrWidth_g`, `LengthWidth_g`, `IncludeMm2s_g`, `IncludeS2mm_g` | Purpose |
| --- | --- | --- |
| `default` | 32, 14, true, true | Default of PG021 |
| `aw40` | 40, 26, true, true | Upper pointer words, longest length |
| `aw64` | 64, 20, true, true | Widest addresses |
| `lw8` | 32, 8, true, true | Shortest length, ignored length bits |
| `mm2s_only` | 32, 14, true, false | S2MM engine not included: idle values, no accesses for it |
| `s2mm_only` | 48, 16, false, true | MM2S engine not included |

The configurations simulate the boundaries of both numeric generics (`AddrWidth_g` 32 and 64, `LengthWidth_g` 8 and
26) and every combination of the channel generics that the core allows. Every test runs in every configuration
that has the channels it needs; a test of one channel runs for each included channel.

Clock 100 MHz. Simulators: GHDL; QuestaSim with and without code coverage in the batch of phase b.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_fetch` (TC-SG-01) | Chains of three descriptors at addresses that use every address bit; pointer bits 5 to 0 set in `CurDesc`, `Tail` and `NXTDESC`, bits above `AddrWidth_g` set in the pointer and address words (and in the upper words with 32 address bits), length bits above `LengthWidth_g` set, S2MM control bits 27 and 26 set: each descriptor is read with one burst of 8 beats at its address (INCR, 4 bytes per beat, `ArCache` 0011, `ArProt` 000), the commands follow the chain with the buffer address, the buffer length, `TXSOF` and `TXEOF` (MM2S) of each descriptor, and the ignored bits have no effect | SG-IF-01, SG-IF-02, SG-IF-03, SG-FE-01, SG-TR-01, SG-TR-02 |
| `test_status` (TC-SG-02) | Results with random byte counts and every combination of start and end of packet: one write burst of one beat at offset 0x1C of each descriptor with all strobes (`AwCache` 0011, `AwProt` 000), the status word with the bytes, `Cmplt`, MM2S bits 27 and 26 zero, S2MM `RXSOF` and `RXEOF`; every other word of every descriptor unchanged | SG-IF-01, SG-UP-01, SG-UP-02, SG-UP-03 |
| `test_tail` (TC-SG-03) | No fetch after the start before the first tail pointer write; fetching from `CurDesc` up to the tail and a pause there, `Idle` only after the status write of the tail, no command beyond the tail until the tail pointer moves; a tail pointer write before the tail is reached moves the pause point; a write after the tail has been fetched but not completed continues the chain; a write at `Idle`, also with the same value, restarts at the `NXTDESC` of the tail | SG-FE-02, SG-FE-03, SG-TR-04 |
| `test_prefetch` (TC-SG-04) | The channel models hold the results: MM2S fetches descriptor n + 1 and issues its command while n is in progress, and fetches n + 2 only after the result of n; S2MM fetches n + 1, which waits for the channel; no fetch beyond the tail | SG-FE-04 |
| `test_curdesc` (TC-SG-05) | `CurPtr` after the start (`CurDesc` without bits 5 to 0), during a transfer (the oldest issued descriptor), between transfers (the next one), after the tail (the tail), after a halt (the first descriptor not started) | SG-FE-07 |
| `test_packet_events` (TC-SG-06) | Write responses delayed by 50 clock cycles: `Pkt` follows the write response of the status of the descriptor with the end of packet, and the status words of the whole packet are in memory at the event; one `Pkt` per packet for MM2S packets of one to three descriptors and S2MM packets over one to three buffers; no `Pkt` for a result with an error | SG-UP-04, SG-UP-05 |
| `test_stale` (TC-SG-07) | The third descriptor of a chain has `Cmplt` = 1: the first two are processed and written, the third is not issued and not written, one `ErrValid` with the engine error `SGIntErr` and no transfer error, no further fetch or command, `CurPtr` = the third; with `Cyclic` = 1 the same chain is processed completely | SG-FE-05, SG-CY-01 |
| `test_transfer_errors` (TC-SG-08) | A descriptor with buffer length 0 and results with the internal, the slave and the decode error, per channel: the status has the error flags (S2MM `DMAIntErr` also with the slave and the decode error), the bytes and `Cmplt` = 0; `ErrValid` with the transfer error after the status write; no command after the error result, while a command already issued completes and is written; `CurPtr` = the descriptor of the error | SG-FE-06, SG-ER-01, SG-ER-03 |
| `test_descriptor_errors` (TC-SG-09) | SLVERR and DECERR on a fetch and on a status write: `ErrValid` with an engine error, nothing issued from a failed fetch, the transfer error of the descriptor reported together with a failed status write, no further fetch or command, `CurPtr` = the descriptor of the access | SG-ER-02 |
| `test_channels` (TC-SG-10) | Chains in both channels at the same time: while both channels request, the fetches and the status writes alternate between the channels; a stale descriptor in one channel stops that channel only, the other completes its chain | SG-IF-01, SG-ER-03 |
| `test_halt` (TC-SG-11) | `Run` falls with two MM2S commands issued and one descriptor fetched: no further fetch or command, both commands complete and are written, the fetched descriptor keeps its status, `CurPtr` = that descriptor, `Stopped` after the last write; S2MM halted before any byte (result of 0 bytes): no status write, `CurPtr` = that descriptor; S2MM halted inside a packet: status with the bytes, `RXSOF`, no `RXEOF`, `Cmplt` = 1; a fetch outstanding at the halt completes without a command; a restart from `CurPtr` continues the chain | SG-HA-01 |
| `test_drain` (TC-SG-12) | `Drain` rises with a fetch and a status write outstanding (memory latency 40 clock cycles): no command, no new access, the outstanding bursts complete, `Stopped` rises, no AXI transaction after it | SG-HA-02 |
| `test_cyclic` (TC-SG-13) | A ring of four descriptors with `Cyclic` = 1 and the tail on the second: three laps, the status of every descriptor written in every lap although `Cmplt` is set from the first lap on, no pause at the tail, `Idle` stays 0; a halt ends the ring | SG-CY-01 |
| `test_keyhole` (TC-SG-14) | `Keyhole` = 1: every command of the chain carries the keyhole flag; a change of `Keyhole` between two chains applies to the descriptors fetched after it | SG-TR-03 |
| `test_ecc` (TC-SG-15) | Single and double errors in each of the four buffers, injected before the start (descriptor buffers: the first entry; read data buffer: the first word of the first fetch; write data buffer: the first status word), parity mode and data mode: one `Ecc_Sec` or `Ecc_Ded` pulse of the buffer; parity mode and single errors leave every command and status correct; a double error in data mode gives the buffer length ^ 3 in the command (descriptor buffer), no change (read data buffer, ignored `NXTDESC` bits) and the transferred bytes ^ 3 in memory (write data buffer) | SG-FT-01 |
| `test_random` (TC-SG-16) | Per channel 40 descriptors in a ring of 16 with random lengths and packet structure (S2MM: random results, a packet continues only in a full buffer), random memory latency and backpressure, random delays of the channel model; the tail moved while the channel runs (software model: every completed descriptor is checked, prepared again and appended): commands, status words, packet events and `CurPtr` against the reference walk | SG-FE-02, SG-FE-03, SG-FE-04, SG-TR-01, SG-TR-02, SG-UP-01, SG-UP-03, SG-UP-05 |
| `test_rate` (TC-SG-17) | Chains of 32 descriptors with results returned at once, memory latency 0 and 20: clock cycles per descriptor for one channel and for both channels, logged for the verification report | none (performance figures) |
| `test_error_codes` (TC-SG-18) | SLVERR, DECERR and EXOKAY on a fetch and on a status write of each channel: the engine error `SGSlvErr` for SLVERR and EXOKAY (interpretation I14), `SGDecErr` for DECERR | SG-ER-04 |

The behaviour of the engine with the real channels (stream join and split, keyhole bursts, halt inside a packet)
is verified at core level (`odma_core`, requirements CO-SG-01 to CO-SG-12).

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| SG-IF-01 | TC-SG-01, TC-SG-02, TC-SG-10 |
| SG-IF-02 | TC-SG-01 |
| SG-IF-03 | TC-SG-01 |
| SG-FE-01 | TC-SG-01 |
| SG-FE-02 | TC-SG-03, TC-SG-16 |
| SG-FE-03 | TC-SG-03, TC-SG-16 |
| SG-FE-04 | TC-SG-04, TC-SG-16 |
| SG-FE-05 | TC-SG-07 |
| SG-FE-06 | TC-SG-08 |
| SG-FE-07 | TC-SG-05 |
| SG-TR-01 | TC-SG-01, TC-SG-16 |
| SG-TR-02 | TC-SG-01, TC-SG-16 |
| SG-TR-03 | TC-SG-14 |
| SG-TR-04 | TC-SG-03 (no command beyond the tail until it moves); the stream side is `odma_s2mm` S2-SG-03 |
| SG-UP-01 | TC-SG-02, TC-SG-16 |
| SG-UP-02 | TC-SG-02 |
| SG-UP-03 | TC-SG-02, TC-SG-16 |
| SG-UP-04 | TC-SG-06 |
| SG-UP-05 | TC-SG-06, TC-SG-16 |
| SG-ER-01 | TC-SG-08 |
| SG-ER-02 | TC-SG-09 |
| SG-ER-03 | TC-SG-08, TC-SG-10 |
| SG-HA-01 | TC-SG-11 |
| SG-HA-02 | TC-SG-12 |
| SG-CY-01 | TC-SG-07, TC-SG-13 |
| SG-FT-01 | TC-SG-15 |
| SG-ER-04 | TC-SG-18 |

## 5. Negative tests

| Check or error path | Test |
| --- | --- |
| Stale descriptor | TC-SG-07 |
| Buffer length 0, transfer errors of the channels | TC-SG-08 |
| SLVERR and DECERR on fetches and status writes | TC-SG-09 |
| Error in one channel while the other works | TC-SG-10 |
| Halt and drain with accesses and commands outstanding | TC-SG-11, TC-SG-12 |
| ECC single and double errors of every buffer | TC-SG-15 |
| Writes to descriptor words other than `STATUS` (comparison of every descriptor word in every test) | TC-SG-01, TC-SG-02, TC-SG-16 |

The recovery of the state machines from an illegal state (`when others`) cannot be reached through the ports; it is
reviewed in the code and listed in the coverage report.

## 6. Functional coverage

| Coverpoint | Requirements | Bins | Goal |
| --- | --- | --- | --- |
| Descriptors per chain | SG-FE-03 | 1, 2 to 4, 5 to 8 | every bin |
| Descriptors per packet | SG-TR-01, SG-UP-05 | 1, 2, 3 | every bin per channel |
| Buffer length | SG-TR-01, SG-TR-02 | 0, 1, 2 to 2**`LengthWidth_g` - 2, 2**`LengthWidth_g` - 1 | every bin |
| Tail pointer write | SG-FE-02 | before the tail is fetched, after it is fetched, at `Idle` | every bin |
| Result error code | SG-ER-01 | none, internal, slave, decode | every bin per channel |
| Descriptor access error | SG-ER-02 | fetch, status write | every bin |
| Both channels requesting the port | SG-IF-01 | fetch, status write | every bin |
