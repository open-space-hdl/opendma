# odma_pkg: Verification Report

## 1. Test results

Run on 2026-10-18 in the GHDL CI of the repository, GitHub Actions run 39126587166 on commit b6d359e (its
`results.xml`), with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.03.20:
`python run.py -p 4 --xunit-xml results.xml`, the tests of `odma_pkg_tb`.

| Test ID | Test case | Status |
| --- | --- | --- |
| `test_last_keep` | TC-PKG-01 | PASS |
| `test_keep_bytes` | TC-PKG-02 | PASS |
| `test_beyond_top` | TC-PKG-03 | PASS |
| `test_config` | TC-PKG-04 | PASS |
| `test_err_codes` | TC-PKG-05 | PASS |
| `test_flip_pattern` | TC-PKG-13 | PASS |
| `test_mem_bursts` | TC-PKG-06 | PASS |
| `test_mem_errors` | TC-PKG-07 | PASS |
| `test_mem_checks` | TC-PKG-08 | PASS |
| `test_seq_player` | TC-PKG-09 | PASS |
| `test_seq_errors` | TC-PKG-10 | PASS |
| `test_model_dr` | TC-PKG-11 | PASS |
| `test_mem_fill` | TC-PKG-12 | PASS |
| `test_mem_fifo` | TC-PKG-14 | PASS |
| `test_resp_err` | TC-PKG-15 | PASS |
| `test_timed_waits` | TC-PKG-16 | PASS |

QuestaSim runs with the next batch of features (module workflow of the repository).

## 2. Summary

All 16 test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

- The functions agree with the independent computations of the bench for every tested width and length, and the
  configuration check names the generic of every inconsistent configuration. `respErr` maps DECERR to the decode
  error and SLVERR and EXOKAY to the slave error.
- The fill pattern of the memory model gives every byte of a 64 KB range its `odmaMemByte` value; windows of
  256 bytes shifted by 1 to 32768 bytes and by 2**16 to 2**48 bytes differ from the original in at least 200 bytes,
  so a read from a wrong address cannot return the expected data.
- The AXI memory model stores and returns INCR and FIXED bursts byte-exact at aligned and unaligned addresses, below
  and above 4 GB and at the top of the 64-bit space, with and without backpressure and latency; failed write beats
  leave memory unchanged; an EXOKAY response counts as a failure. A FIFO window maps the k-th read beat and the k-th
  write beat at its word to the k-th word of the backing range, over bursts and transfers. Each of its eight protocol
  checks raises exactly the expected alerts.
- The sequence player executes every command, waits with `T` for single packets while later ones are queued, and
  reports a failed compare, an expired poll, an expired interrupt
  wait and a mismatching stream packet with the line that caused them.
- The timed waits of `odma_tb_pkg` end at the expected time when their condition becomes true before the timeout,
  also one delta cycle after the start and one clock period before the timeout, and raise exactly one error when
  it becomes true only at the timeout, held already and did not change, or never becomes true, and for the edge
  wait when the signal is '1' only after the last edge before the timeout.
- The model of the programming sequences reproduces the hand-written golden files of the reference scenario line by
  line, and its memory image passes the round trip through the loader and the checker.

## 3. Negative tests

| Check | Test | Alerts expected and seen |
| --- | --- | --- |
| Memory model: INCR burst across 4 KB | TC-PKG-08 | 1 |
| Memory model: burst above the configured maximum | TC-PKG-08 | 1 |
| Memory model: FIXED burst of 17 beats | TC-PKG-08 | 1 |
| Memory model: WRAP burst | TC-PKG-08 | 1 |
| Memory model: narrow beat | TC-PKG-08 | 1 |
| Memory model: `WLast` missing, `WLast` early | TC-PKG-08 | 1 each |
| Memory model: strobed bytes outside the write window | TC-PKG-08 | 3 (one per beat) |
| Sequence player: compare, poll, interrupt wait, stream packet, wait for a packet not sent | TC-PKG-10 | 1 each |
| `odmaWaitHigh`: rise at the timeout, '1' that held already, no rise | TC-PKG-16 | 1 each |
| `odmaWaitHighAtEdge`: '1' at the edge of the timeout, '1' only after the last edge before the timeout | TC-PKG-16 | 1 each |
| `odmaWaitAtLeast`: count that reaches n at the timeout, count that held already, count below n | TC-PKG-16 | 1 each |

## 4. Remarks on the environment

- The UVVM AXI4 VVC supports at most 32 address bits; the harness forms address bits 63 to 32 from a harness input,
  which the bench changes only while the VVC is idle.
- The UVVM AXI4 and AXI4-Lite VVCs execute reads and writes on independent channels. The bench completes every burst
  before the next one, and the sequence player completes every register write before its next command.

## 5. Checks of the testbench

Each of the following faults, inserted into a copy of `tb/odma_tb_pkg.vhd`, fails the test case named; the file of
the repository passes it:

| Fault | Failing test case |
| --- | --- |
| `odmaWaitHigh` checks the value only, not that the condition ended the wait before the timeout | TC-PKG-16 |
| `odmaWaitHighAtEdge` checks the value only, not that the condition ended the wait before the timeout | TC-PKG-16 |
| `odmaWaitAtLeast` checks the count only, not that the condition ended the wait before the timeout | TC-PKG-16 |
