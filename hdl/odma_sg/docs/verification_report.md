# odma_sg: Verification Report

## 1. Test results

Run on 2026-10-20 in the GHDL CI of the repository, GitHub Actions run 39467613918 on commit fee4598 (its
`results.xml`), with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.03.20:
`python run.py -p 4 --xunit-xml results.xml`, the tests of `odma_sg_tb`.

QuestaSim (Questa Pro Microchip Edition 2024.3, time resolution 1 fs) ran the tests of release 0.2.0 on commit ad726b1
with Open Logic 4.7.0-ft.10 (sources and testbenches as in fee4598), with code coverage and in the optimised run without
it, and all of them passed; the code coverage of the core is in `docs/coverage.md`.

The test end changed after this run (`odmaTestEnd`, see the verification report of `odma_pkg`); the tests of this bench
expect no alerts, so their results are unchanged.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `odma_sg_tb` | 107 (19 test cases: 17 in all six configurations, TC-SG-10 in the four with both channels, TC-SG-17 in `default`) | 107 |

Descriptor rate (TC-SG-17, results returned at once, chains of 16 descriptors):

| Channels | Memory latency 0 | Memory latency 20 clock cycles |
| --- | --- | --- |
| One channel | 22 clock cycles per descriptor | 42 clock cycles per descriptor |
| Both channels, per channel | 40 clock cycles per descriptor | 80 clock cycles per descriptor |

With the window of two descriptors a channel fetches descriptor n + 2 after the result of n, so the rate is the time
of one fetch and its entry into the buffer; both channels share the read side of the descriptor port.

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan and the compliance
matrix). VSG reports no errors and no warnings. The sources synthesise with `ghdl --synth` without errors and without
latches in the configurations of section 3; the only warnings are the RAM attributes of the Open Logic buffers that
GHDL does not handle.

Findings:

| Finding | Resolution |
| --- | --- |
| The counters of the window stopped the simulation with a range error right after a clock edge: the buffer output and the command handshake follow the edge one delta cycle after the registers, so one delta cycle combined the pop of the last cycle with the new count. At a clock edge the counts never leave 0 to 2 | The counters are modular 2-bit values and the queue of the issued commands is written without an index from a count, so no delta cycle produces an out-of-range value; no saturation logic |
| A fetch could start in the clock cycle between the arrival of a stale descriptor and its check at the head of the buffer | A fetched stale descriptor stops further fetch requests at once (`StaleHold`, architecture section 4.3); TC-SG-07 checks that nothing behind it is fetched |
| The cyclic test expected a status write for every command; at the halt that ends the ring, the S2MM model ends its transfer without data | Correct behaviour (interpretation SGI-10): the test expects every completed descriptor written |
| TC-SG-18 ran only with the generic defaults of the testbench, outside the six configurations: the test list of the VUnit configuration did not name it | The list names every test; TC-SG-18 runs in all six configurations. The VUnit configuration of every testbench checks that its lists of tests and configurations match the tests of the testbench, so that a test missing from a list stops the run |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised |
| --- | --- | --- | --- |
| `IncludeMm2s_g`, `IncludeS2mm_g` | boolean (at least one true in the core) | both true, MM2S only, S2MM only | both true, MM2S only, S2MM only |
| `AddrWidth_g` | 32 to 64 | 32, 40, 48, 64 | 32, 48, 64 |
| `LengthWidth_g` | 8 to 26 | 8, 14, 16, 20, 26 | 8, 14, 26 |

## 4. Checks of the testbench

Each of the following faults, inserted into a copy of the RTL, fails at least one test case; the RTL of the repository
passes all of them:

| Fault | Failing test case |
| --- | --- |
| A window of three descriptors | TC-SG-04 |
| No pause at the tail | TC-SG-01 |
| A tail pointer write at idle does not restart the engine | TC-SG-03 |
| Fetching continues after a stale descriptor | TC-SG-07 |
| A stale descriptor is issued | TC-SG-07 |
| `Cmplt` set for a failed transfer | TC-SG-08 |
| S2MM status without `DMAIntErr` for a slave error | TC-SG-08 |
| `RXSOF` and `RXEOF` swapped | TC-SG-02 |
| A packet event for a failed transfer | TC-SG-06 |
| A result of 0 bytes taken as not started while the channel runs | TC-SG-02 |
| `CURDESC` not at the descriptor of the first error | TC-SG-08 |
| `Keyhole` not taken at the fetch | TC-SG-14 |
| The tail pauses the engine in cyclic mode | TC-SG-13 |
| The descriptor not started does not hold `CURDESC` | TC-SG-11 |
| Halted before the status writes are answered | TC-SG-11 |
| The end pulse of a fetch before its last word | TC-SG-01 |
| The decode error code for every failed access | TC-SG-09 |
| The slave error code for every failed descriptor fetch | TC-SG-18 |
| The slave error code for every failed status write | TC-SG-18 |
| The priorities of the arbiters swapped | TC-SG-10 |
| The status written to the `CONTROL` word | TC-SG-02 |

One more fault, in a branch that withdrew a granted access when a drain came before the master had taken the
command, survived. It is not equivalent, but its window of about one clock cycle cannot be reached through the ports.
The branch is removed: an access granted before a drain completes (architecture section 5), so the RTL has no
surviving fault of this list.

The recovery branches of the state machines (`when others`) cannot be reached through the ports.
