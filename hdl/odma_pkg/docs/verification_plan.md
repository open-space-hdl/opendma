# odma_pkg: Verification Plan

## 1. Overview

The functions of the package are checked against values computed independently in the testbench (loops over all
lane patterns, boundary addresses). The AXI memory model is driven by the UVVM AXI4 VVC with INCR and FIXED bursts,
error ranges, backpressure and latency, and every one of its protocol checks is provoked once (negative tests). The
sequence player executes hand-written sequence files against a register stub; its failure paths are provoked as
well. The model of the programming sequences is checked against hand-written golden files of a reference scenario.

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
| `test_config` (TC-PKG-04) | `coreConfigError` accepts the default and the boundary configurations and names the generic of each inconsistent one (memory width 24 and 2048, stream width above the memory width, burst beats 3 and 512, length width 7 and 27, address width 31 and 65, data buffer of one burst) | PKG-04 |
| `test_err_codes` (TC-PKG-05) | Values of the error codes: SLVERR and DECERR equal the AXI response codes | PKG-05 |
| `test_mem_bursts` (TC-PKG-06) | INCR bursts of 1, 2, 16 and 256 beats, unaligned start addresses, partial strobes, FIXED bursts of 1 and 16 beats, addresses below and above 2**32 and at the top of the 64-bit space; written data checked through the backdoor and by read bursts; statistics (bytes written, lowest and highest address, bursts, maximum outstanding); repeated with 50 % backpressure and a latency of 20 cycles | PKG-06 |
| `test_mem_errors` (TC-PKG-07) | SLVERR and DECERR ranges for reads and writes: the response of each burst that touches a range, no byte of a failed write beat written, unaffected bursts with OKAY | PKG-06 |
| `test_mem_checks` (TC-PKG-08) | One provocation per protocol check, each expecting exactly one error alert: INCR burst across 4 KB, burst above the configured maximum, FIXED burst of 17 beats, WRAP burst, narrow beat, `WLast` missing on the last beat and set before it (raw driver), a strobed byte outside the write window | PKG-07 |
| `test_seq_player` (TC-PKG-09) | A sequence file with every command (W, R with and without mask, P that matches after a delay, I for both interrupt signals, S and E of the same packet through the looped streams, A, D, L) executes without alert | PKG-08 |
| `test_seq_errors` (TC-PKG-10) | A mismatching R, a P and an I whose timeout expires, an E that does not match the sent packet: each raises one error alert that names its line | PKG-08 |
| `test_model_dr` (TC-PKG-11) | The model generates the reference DR scenario (reset, one MM2S and one S2MM transfer with interrupt, one MM2S transfer by polling, a 64-bit buffer address) in the `pre_config` of the test; the sequence, the memory image and the expected memory equal the golden files written by hand from PG021 chapter 4 | PKG-09 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| PKG-01 | TC-PKG-01 |
| PKG-02 | TC-PKG-02 |
| PKG-03 | TC-PKG-03 |
| PKG-04 | TC-PKG-04 |
| PKG-05 | TC-PKG-05 |
| PKG-06 | TC-PKG-06, TC-PKG-07 |
| PKG-07 | TC-PKG-08 |
| PKG-08 | TC-PKG-09, TC-PKG-10 |
| PKG-09 | TC-PKG-11 |

## 5. Negative tests

| Check | Test |
| --- | --- |
| Memory model: 4 KB boundary, burst length, FIXED length, burst type, beat size, `WLast`, write window | TC-PKG-08 |
| Sequence player: compare, poll timeout, interrupt timeout, stream mismatch | TC-PKG-10 |
