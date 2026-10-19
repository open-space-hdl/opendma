# odma_pkg: Verification Plan

## 1. Overview

The functions of the package are checked against values computed independently in the testbench (loops over all
lane patterns, boundary addresses). `beyondTop` and `coreConfigError` take their arguments through variables of
the bench, so that every call runs in the simulation: a call with literal arguments is evaluated when the bench
is compiled and is not part of the code coverage. The AXI memory model is driven by the UVVM AXI4 VVC with INCR
and FIXED bursts, error ranges, backpressure and latency, and every one of its protocol checks is provoked once
(negative tests). The sequence player executes hand-written sequence files against a register stub; its failure
paths are provoked as well. The model of the programming sequences is checked against hand-written golden files of a
reference scenario.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `odma_pkg_tb` | `odma_pkg_th` | Functions of `odma_pkg`; AXI memory model instance 0 (64-bit address, 64-bit data) driven by an AXI4 VVC (32 address bits, the limit of the UVVM AXI4 VVC; bits 63 to 32 from a harness input) and, for malformed write bursts, by a raw driver of the harness; AXI4-Lite VVC on a register stub (`olo_axi_lite_slave`, registers whose bits drive the two interrupt signals, a register that counts down to a value); AXI4-Stream VVCs connected back to back |

Simulator: GHDL; QuestaSim for the coverage batch. Clock 100 MHz.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_last_keep` (TC-PKG-01) | `lastKeep` for streams of 1, 2, 4, 8, 64 and 128 bytes and lengths 1 to three beats, multiples of the width and 0 | PKG-01 |
| `test_keep_bytes` (TC-PKG-02) | `keepBytes` for all 256 patterns of 8 lanes against a loop of the bench, and for 128 lanes with the first '0' at every position | PKG-02 |
| `test_beyond_top` (TC-PKG-03) | `beyondTop` at 32 and 64 address bits: buffers ending at the top fit, one byte more does not; start at 0; length 1 and the largest length; length 0 at address 0, in the middle and at the top is never beyond the top | PKG-03 |
| `test_config` (TC-PKG-04) | `coreConfigError` accepts the default and the boundary configurations and names the generic of each inconsistent one (memory width 24 and 2048, stream width 4, 24 and 2048 and above the memory width, burst beats 3 and 512, length width 7 and 27, address width 31 and 65, data buffer of one burst; memory width, stream width and data buffer of the S2MM channel) | PKG-04 |
| `test_err_codes` (TC-PKG-05) | Values of the error codes: SLVERR and DECERR equal the AXI response codes | PKG-05 |
| `test_resp_err` (TC-PKG-15) | `respErr` of SLVERR, DECERR and EXOKAY: the slave error, the decode error and the slave error | PKG-13 |
| `test_flip_pattern` (TC-PKG-13) | `flipPattern` for codewords of 8 and 39 bits in the four combinations of single or double error and parity or data mode: exactly the bits 0, 0 and 1, 3, 3 and 5 | PKG-11 |
| `test_mem_bursts` (TC-PKG-06) | INCR bursts of 1, 2, 16 and 256 beats, unaligned start addresses, partial strobes, FIXED bursts of 1 and 16 beats, addresses below and above 2**32 and at the top of the 64-bit space; written data checked through the backdoor and by read bursts; statistics (bytes written, lowest and highest address, bursts, maximum outstanding); repeated with 50 % backpressure and a latency of 20 cycles | PKG-06 |
| `test_mem_errors` (TC-PKG-07) | SLVERR, DECERR and EXOKAY ranges for reads and writes: the response of each burst that touches a range, no byte of a failed write beat written, unaffected bursts with OKAY | PKG-06 |
| `test_mem_fifo` (TC-PKG-14) | A FIFO window: FIXED read bursts of 1 and 16 beats and two bursts back to back at the window word return the consecutive words of the backing range; FIXED write bursts with partial strobes on the last beat write the consecutive backing words (backdoor), the window word itself unchanged; an INCR burst over the neighbouring words is unaffected; a new setting restarts both counters | PKG-12 |
| `test_mem_checks` (TC-PKG-08) | One provocation per protocol check, each expecting exactly one error alert: INCR burst across 4 KB, burst above the configured maximum, FIXED burst of 17 beats, WRAP burst, narrow beat, `WLast` missing on the last beat and set before it (raw driver), a strobed byte outside the write window | PKG-07 |
| `test_seq_player` (TC-PKG-09) | A sequence file with every command (W, R with and without mask, P that matches after a delay, I for both interrupt signals, S and E of the same packet through the looped streams, A, T for two packets, D, L) executes without alert | PKG-08 |
| `test_seq_errors` (TC-PKG-10) | A mismatching R, a P and an I whose timeout expires, an E that does not match the sent packet: each raises one error alert that names its line; a T for a packet index that no S command before the line has sent raises one TB_ERROR alert | PKG-08 |
| `test_mem_fill` (TC-PKG-12) | A fill of 64 KB: every byte is `odmaMemByte` of its address and the seed; windows of 256 bytes at the shifts 1, 2, 3, 64, 256, 4096, 8192 and 32768 bytes differ from the window at the start in at least 200 bytes, and so do windows of the function at the shifts 2**16, 2**20, 2**32 and 2**48; another seed gives other bytes | PKG-10 |
| `test_model_dr` (TC-PKG-11) | The model generates the reference DR scenario (reset, one MM2S and one S2MM transfer with interrupt, one MM2S transfer by polling, a 64-bit buffer address) in the `pre_config` of the test; the sequence, the memory image and the expected memory equal the golden files written by hand from PG021 chapter 4 | PKG-09 |
| `test_timed_waits` (TC-PKG-16) | Each timed wait of `odma_tb_pkg` on a signal, a clock and a counter of the bench. Without an alert: a rise or a count that reaches n within the timeout ends the wait at that time, as does '1' at the first edge that has it; a rise one delta cycle after the start, a rise or a count above n one clock period before the timeout, '1' at the last edge before the timeout. With one error alert each: a rise or a count that reaches n only at the timeout, a '1' or a count that held already and did not change (the wait ends at the timeout), no rise, a count below n, '1' at the edge of the timeout, '1' only after the last edge before the timeout | PKG-14 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| PKG-01 | TC-PKG-01 |
| PKG-02 | TC-PKG-02 |
| PKG-03 | TC-PKG-03 |
| PKG-04 | TC-PKG-04 |
| PKG-05 | TC-PKG-05 |
| PKG-11 | TC-PKG-13 |
| PKG-13 | TC-PKG-15 |
| PKG-06 | TC-PKG-06, TC-PKG-07 |
| PKG-07 | TC-PKG-08 |
| PKG-12 | TC-PKG-14 |
| PKG-08 | TC-PKG-09, TC-PKG-10 |
| PKG-09 | TC-PKG-11 |
| PKG-10 | TC-PKG-12 |
| PKG-14 | TC-PKG-16 |

## 5. Negative tests

| Check | Test |
| --- | --- |
| Memory model: 4 KB boundary, burst length, FIXED length, burst type, beat size, `WLast`, write window | TC-PKG-08 |
| Sequence player: compare, poll timeout, interrupt timeout, stream mismatch, wait for a packet not sent | TC-PKG-10 |
| Timed waits: a condition that held already and did not change, true only at the timeout, never true; for the edge wait a '1' only after the last edge before the timeout | TC-PKG-16 |
