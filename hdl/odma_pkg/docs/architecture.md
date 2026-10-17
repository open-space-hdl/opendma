# odma_pkg: Architecture and Design Description

## 1. Contents

| File | Content |
| --- | --- |
| `src/odma_pkg.vhd` | Error codes of a transfer result `Err*_c`, functions `lastKeep`, `keepBytes`, `beyondTop`, `coreConfigError`, `flipPattern` |
| `tb/odma_pkg_tb.vhd`, `tb/odma_pkg_th.vhd` | Testbench of the package and of the shared verification components |
| `../../tb/` | Shared verification components (section 3) |
| `../../tb/model/` | Model of the programming sequences (section 4) |

## 2. Package `odma_pkg`

| Name | Definition |
| --- | --- |
| `XferErr_t` | `std_logic_vector(1 downto 0)`, the error code of a transfer result |
| `ErrNone_c`, `ErrInt_c`, `ErrSlv_c`, `ErrDec_c` | "00" no error, "01" internal error (`DMAIntErr`), "10" slave error (`DMASlvErr`), "11" decode error (`DMADecErr`); the values of the AXI response codes SLVERR and DECERR |
| `lastKeep(bytes, w)` | `TKeep` of the last beat of a transfer of `bytes` bytes (an `unsigned`) on a stream of `w` bytes: bit i set for i <= (bytes - 1) mod w (PKG-01). `bytes` = 0 gives all bits clear |
| `keepBytes(keep)` | Number of valid bytes of a last beat: the index of the lowest '0' of `keep`, or its length when all bits are set (PKG-02) |
| `beyondTop(addr, bytes)` | True when the buffer from `addr` with `bytes` bytes does not fit below the top of the address space of `addr'length` bits: `addr + bytes - 1` overflows `addr'length` bits; false for `bytes` = 0, since an empty buffer touches no byte (PKG-03) |
| `coreConfigError(...)` | Empty string for a consistent set of core generics, otherwise a message naming the first inconsistent generic (PKG-04); called by an assertion of `odma_core` |
| `flipPattern(width, double, data)` | The `ErrInj_BitFlip` pattern of a codeword of `olo_ft_pkg_ecc` with `width` bits (PKG-11): parity mode the overall parity bit 0 and for a double error the Hamming parity bit 1, so the data never changes; data mode data bit 0 (codeword bit 3) and for a double error data bit 1 (codeword bit 5). Used by the FT buffers of `odma_mm2s`, `odma_s2mm` and `odma_sg` |

The functions are pure and synthesisable; `lastKeep` and `keepBytes` unroll to one comparison per lane, `beyondTop`
to one adder.

## 3. Verification components (`tb/`)

| File | Content |
| --- | --- |
| `odma_tb_pkg.vhd` | `odmaTestEnd`, the AXI4-Stream BFM configuration of the benches, byte array helpers (count pattern, hex conversion) |
| `odma_tb_mem_pkg.vhd`, `odma_tb_memvar_pkg.vhd` | Memory of the AXI memory model as a protected type with one instance per model (section 3.1); the shared variable `Mem_v` |
| `odma_tb_axi_ram.vhd` | AXI memory model (section 3.2) |
| `odma_tb_seq_pkg.vhd` | Sequence player `odmaSequence` and the loader and checker of memory image files (section 3.3) |

### 3.1 Memory

The memory of one model instance is sparse: pages of 4096 bytes, allocated on the first access, found by the page
number (address bits 63 to 12); unwritten bytes read as 0x00. Addresses are `unsigned(63 downto 0)` throughout, so a
test can place buffers anywhere in a 64-bit space, also at the top of a 32-bit space.

| Setting (per instance) | Default | Effect |
| --- | --- | --- |
| `setError(idx, n, first, last, resp, dir)` | none | Error range n (0 to 7): accesses to a byte from `first` to `last` respond with `resp` (SLVERR or DECERR) in direction `dir` (read, write or both). A write beat with a strobed byte in an error range writes none of its bytes and fails the burst |
| `setWindow(idx, first, last)` | whole space | Write window: a strobed byte outside it raises an error alert (PKG-07); the byte is still written, so that the test also sees the damage |
| `setMaxBeats(idx, n)` | 256 | Longest accepted burst (`AxLen` + 1) |
| `setStall(idx, percent)` | 0 | Share of cycles in which the model holds `AwReady`, `WReady`, `ArReady` and `RValid` low (0 to 90) |
| `setLatency(idx, cycles)` | 0 | Additional cycles before the first read beat of a burst and before a write response |

Backdoor and statistics: `write8`, `read8`, `fill` (the bytes of `odmaMemByte`, a function of every address bit
and a seed that no shift of the address reproduces), `clearStats`, `bytesWritten`, `lowestWritten`,
`highestWritten`, `beatsRead`, `bursts` (accepted AW and AR), `maxOutstanding` (largest number of accepted bursts
without response, per direction).

### 3.2 AXI memory model `odma_tb_axi_ram`

An AXI4 slave without ID signals (all transactions in order), generics `Index_g` (instance of `Mem_v`),
`AddrWidth_g` (1 to 64) and `DataWidth_g` (8 to 1024). Up to 16 bursts are accepted per direction before the model
holds its address ready low. Write data is taken for the oldest accepted AW burst; read data is returned in the
order of the AR bursts. Beat addresses follow \[AXI\]: an INCR burst starts at its address and continues at the
following aligned addresses, a FIXED burst accesses the same address with every beat.

Protocol checks (error alerts, PKG-07): an INCR burst whose bytes cross a 4 KB boundary; `AxLen` + 1 above the
configured maximum, or above 16 for a FIXED burst; a WRAP burst or a reserved burst type; `AxSize` other than the
data width; `WLast` missing on the last beat or set before it; a strobed byte outside the write window.

What this model does not check or reproduce: AXI ID reordering and interleaving (no ID signals); `AxCache`,
`AxProt`, `AxLock` and `AxQos` (not connected); exclusive accesses; narrow transfers (rejected by the check);
write data before its address (the model takes write data only for an accepted AW burst, which \[AXI\] allows a
slave to do); the timing of a real interconnect beyond the random backpressure and the fixed latency.

### 3.3 Sequence player and files

`odmaSequence(file, ...)` reads a text file and executes one command per line through the AXI4-Lite VVC (register
accesses), the AXI4-Stream VVCs (stream packets) and two interrupt signals. Numbers are hexadecimal with the prefix
`0x` or decimal; `#` starts a comment. A failed compare or an expired timeout raises an error alert with the line
number and the line (PKG-08). The message of a VVC command carries the last 100 characters of the file name, the line
number and the first 60 characters of the line, within the 300 characters of the message field of a VVC command.

| Command | Meaning |
| --- | --- |
| `W <offset> <data>` | Write a register and wait for the completion of the write |
| `R <offset> <expected> [<mask>]` | Read a register and compare the bits set in the mask (default all) |
| `P <offset> <expected> <mask> <timeout>` | Read until the masked value matches, at most `timeout` clock cycles |
| `I <MM2S or S2MM> <0 or 1> <timeout>` | Wait until the interrupt output has the level, at most `timeout` clock cycles |
| `S <bytes>` | Queue a packet on the S2MM stream VVC (bytes in hexadecimal, separated by spaces; at most 16384 bytes, the limit of the VVC) |
| `E <bytes>` | Queue an expected packet on the MM2S stream VVC |
| `A [<timeout>]` | Wait until the stream VVCs have executed their queues, at most `timeout` clock cycles (default 1000000) |
| `D <cycles>` | Wait |
| `L <text>` | Log the text |

The AXI4-Lite VVC executes reads and writes on independent channels; the wait after a write keeps the order of the
file. Register commands, interrupt waits, `A` and `D` first complete the queued register accesses.

Memory image files hold one line per range, `<address> <bytes>`; `odmaLoadImage(idx, file)` writes them through
the backdoor of instance `idx`, `odmaCheckImage(idx, file)` compares them byte by byte and reports the number of
mismatches and the first one.

## 4. Model of the programming sequences (`tb/model/`)

`odma_model.py` describes how software operates OpenDMA, written from \[PG021\] chapter 4 and the register
descriptions of chapter 3, without vendor driver code and independently of the RTL. Its classes:

| Class | Content |
| --- | --- |
| `Regs` | Register offsets and field positions of \[PG021\] Tables 4 to 24 |
| `DrTransfer` | One DR transfer: channel, buffer address, length, data, completion by interrupt or by polling |
| `Scenario` | A list of steps (reset, start, transfers, expected errors and their recovery) and the generator of the files: `sequence.txt`, `memory.txt` (initial memory image), `expected_memory.txt` |

The sequence of a DR transfer follows \[PG021\] chapter 4: `DMACR.RS` = 1 and the interrupt enables, the poll of
`DMASR.Halted` = 0, the address (and its MSB register for addresses above 32 bits), the length as the last write,
then the completion (interrupt, `DMASR.IOC_Irq` and `Idle`), the write-one-to-clear of `IOC_Irq`, for S2MM the
read of the received length. A reset step writes `DMACR.Reset` = 1 of the first included channel and polls until it
reads 0. Further steps:

| Step | Sequence |
| --- | --- |
| `halt` | `DMACR.RS` = 0, poll until `DMASR.Halted` reads 1 |
| `check_cleared` | After a reset: `DMASR` of every included channel halted without error and interrupt flags |
| `concurrent` | Transfers of both channels, every one programmed before the first completion is awaited |
| `failed_transfer` | A transfer that ends with an error: the interrupt, the poll of `DMASR.Halted` (it follows the error when the channel has shut down), the error flags and `Err_Irq` in `DMASR`, the write-one-to-clear of `Err_Irq`; optionally without stream data (buffer beyond the top of the address space) |

A scenario can name the included channels and a guard: the expected memory then holds the given number of zero
bytes before and after every S2MM packet, so that a write outside the packet fails the comparison.

| Scenario | Content | Used by |
| --- | --- | --- |
| `dr_reference` | Reset, one MM2S and one S2MM transfer with interrupt above 4 GB at unaligned addresses, one MM2S transfer by polling | TC-PKG-11 (golden files), TC-CO-01 |
| `dr_random` | Transfers of random channels, lengths (1 byte and the longest length among them) and unaligned addresses, some across 4 KB, by interrupt or polling, then a halt and a restart of each channel; random data without a period | TC-CO-02, TC-CO-05, TC-CO-08 |
| `dr_concurrent` | Long transfers of both channels at the same time | TC-CO-03 |
| `dr_errors` | Read and write errors, an S2MM packet longer than its buffer, buffers beyond the top of the address space, each followed by a transfer of the other channel and a reset | TC-CO-04 |
| `dr_single` | One transfer of one channel without a reset | TC-CO-06 |

`run.py` calls the model in a VUnit `pre_config` of each core test configuration, which writes the files into the
output directory of the test; the bench finds them with `output_path(runner_cfg)`. No generated file is committed.
