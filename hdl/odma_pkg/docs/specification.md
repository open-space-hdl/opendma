# odma_pkg: Specification

## 1. Overview

`odma_pkg` contains the definitions shared by all OpenDMA modules: the error codes of a transfer result, the byte
lane functions of the stream conventions (P7), the address range check of memory safety (P6) and the consistency
check of the core generics. The shared verification components in `tb/` (AXI memory model, sequence player and the
model of the programming sequences) are verified with this module. The test end procedure `odmaTestEnd` of
`tb/odma_tb_pkg.vhd`, which fails a test on an unexpected alert or on a missing expected alert, is exercised by every
negative test of the repository.

## 2. Requirements

| ID | Requirement | PG021 items |
| --- | --- | --- |
| PKG-01 | The package shall give the `TKeep` of the last beat of a transfer of n bytes on a stream of W bytes: the lanes 0 to ((n - 1) mod W) set, all lanes for n a multiple of W (architecture D4). | none (function of MM-2) |
| PKG-02 | The package shall give the number of valid bytes of a last beat from its `TKeep`: the number of set bits from lane 0 up to the first deasserted bit; bits above it do not count (architecture I10). | none (function of S2-1) |
| PKG-03 | The package shall tell whether a buffer of a given start address and length reaches beyond the top of an address space of `AddrWidth_g` bits, so that its last byte would wrap to a low address (architecture D7, I5). | none (function of MM-1, S2-2) |
| PKG-04 | The package shall check the generics of the core and return a message naming the first inconsistent generic: memory and stream widths powers of two within their ranges, stream width at most the memory width, burst beats a power of two from 2 to 256, length width from 8 to 26, address width from 32 to 64, a data buffer of at least two bursts. | none (function of CO-1) |
| PKG-05 | The package shall define the error codes of a transfer result: none, internal error, slave error, decode error. | none (internal interface of architecture section 7) |
| PKG-06 | The AXI memory model of the testbenches shall be an AXI4 slave with INCR and FIXED bursts, write strobes, addresses of up to 64 bits (sparse storage), at least 16 queued commands per direction, SLVERR and DECERR responses on configurable read and write address ranges (bytes of a failed write are not written), random backpressure on every channel and a configurable response latency. | none (verification) |
| PKG-07 | The AXI memory model shall raise an error alert for a burst that crosses a 4 KB boundary, for a burst longer than its configured maximum or a FIXED burst longer than 16 beats, for a WRAP or reserved burst type, for a beat narrower than the data width, for a missing or early `WLast` and for a strobed byte outside the configured write window. | none (verification) |
| PKG-08 | The sequence player of the testbenches shall execute a sequence file line by line through the AXI4-Lite VVC: register write, read with masked compare, poll until a masked value within a timeout, wait for an interrupt level within a timeout, and delay; a failed compare or an expired timeout shall raise an error alert that names the line. | none (verification) |
| PKG-09 | The model of the programming sequences shall generate, for a described DR transfer set, the sequence file of PG021 chapter 4 (reset, start, address, length, completion by interrupt or polling, status check), the memory image with the source buffers and the expected memory and stream contents, independently of the RTL. | none (verification) |

The requirements of the package trace to no item of the published interface: the functions are verified here and
the items through the requirements of the blocks that use them (MM-1, MM-2, S2-1, S2-2, CO-1). In the same way the
model of the programming sequences (PKG-09) is a verification component; the sequences of PG021 are verified when the
core executes them in the core tests.

## 3. Configuration parameters

None for the package; it has constants and pure functions only. The parameters of the verification components are
listed in the architecture.
