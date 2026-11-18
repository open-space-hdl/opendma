# OpenDMA Conventions

OpenDMA follows the coding conventions of Open Logic and the module development process of the architecture
document. This page lists the rules and the few OpenDMA-specific additions.

## VHDL coding

- The [Open Logic coding conventions](../open-logic/doc/Conventions.md) apply in full: port names
  `<Interface>_<Signal>`, generics `_g`, constants `_c`, variables `_v`, types `_t`, FSM types `<Name>Fsm_t` with
  states `_s`, functions in `lowerCamelCase`, four spaces of indentation, no tabs, no trailing whitespace.
- Entities are named `odma_<function>` (for example `odma_mm2s`). All OpenDMA sources are compiled into the VHDL
  library `opendma`; Open Logic is compiled into the library `olo`.
- Language: VHDL-2008.
- Entities with non-trivial state use the two-process pattern of Open Logic: all registers in one `TwoProcess_r`
  record, signals `r` and `r_next`, a combinational process starting with `v := r;` and ending with
  `r_next <= v;`, a sequential process with `r <= r_next;` and the reset override at its end.
- Resets are synchronous and high-active. Only state registers are reset.
- The actual of a port is a name (signal, constant, index or slice of one), never an expression such as
  `to_integer(...)` or a concatenation: declare a signal or constant of the port's subtype and associate it.
  QuestaSim with full optimisation can give the implicit signal of an expression actual a range that matches neither
  the port nor the expression and stop the simulation.
- A record field that is an array of arrays uses a fully constrained array type (`type T is array (0 to N - 1) of
  E`), not an index constraint on an unconstrained array type (`U : T(0 to N - 1)`): through an alias of an element
  of an array of records, xsim 2025.2 can give such a field the element constraint of another field. Vectors of
  scalars (`std_logic_vector`, `unsigned`, `signed`) have no element constraint and are not affected.
- Every data path between blocks is a valid / ready stream (AXI4-Stream handshake semantics) or a valid-only stream
  of one-cycle events where the receiver is never slower than the source.
- Packet streams carry the first byte of a packet in byte lane 0 (`TData(7:0)`). All bytes of a beat are valid
  except in the last beat of a packet, whose valid bytes are contiguous from lane 0 (`TKeep`). The byte at the lowest
  memory address of a buffer is the first byte of its stream data.
- Standard functions (FIFOs, RAMs, crossings, synchronisers, arbiters, pipeline stages, AXI masters) are
  instantiated from Open Logic, never rewritten. FIFOs, RAMs, AXI masters and crossings use the fault-tolerant
  `olo_ft_*` entities; every Open Logic crossing, reset generator and input synchroniser is instantiated with
  `SyncTmr_g => true`.
- State machines have a `when others` branch that returns to a defined recovery state; the reset leads to that state
  from any state.
- Every line that implements a requirement is traceable through the module specification. Comments name the item of
  the published register interface where it helps the reader, by its register field or descriptor field name (for
  example `-- MM2S_DMACR.Reset` or `-- S2MM_STATUS.RXEOF`).
- File header: copyright line and authors, then a 1 to 2 sentence description that links to the module
  documentation. Never write "all rights reserved".
- Never use em-dashes in code, comments or documentation. Use UTF-8 only.
- VSG 3.27 with the Open Logic configuration in `lint/config` must report no errors and no warnings:
  `python lint/lint.py`. Safe automatic fixes: `python lint/lint.py --fix`.
- The design must be synthesizable in a technology-independent way: `python lint/synth_check.py` elaborates the core
  top level with the synthesis of GHDL (after `python run.py --compile`) at the generic values of the verification
  report of the core and fails on errors and inferred latches; inconsistent configurations must stop with the
  message of the core. It runs in CI after the regression.
- Generic ranges are verified: every value of a generic that changes the structure is simulated, the ends of every
  numeric range are at least synthesised, other values are excluded by an assertion or listed as unverified; the
  verification report of the core has the table. `to_01` and other simulation-only functions are not used in RTL.
- The synthesis sources analyse with `ghdl -a --std=08` without `-frelaxed` and without warnings. Attribute
  specifications use literals, because the expression of an attribute specification must be locally static. Only
  Open Logic and UVVM need `-frelaxed`.
- The register map has one description, `hdl/odma_registers/regs/odma_regs.yml`. `python tools/regmap.py` generates
  the VHDL package `odma_regs_pkg`, the register map page and the C header `sw/odma_regs.h` from it;
  `python tools/regmap.py --check` fails in CI when a generated file is out of date. The registers of the published
  interface keep the register and field names of PG021; the C header prefixes them with `ODMA_`.
- `compile_order.txt` lists the synthesis sources of the library `opendma` in compile order. After adding, removing
  or renaming a source file, regenerate it with `python run.py --compile-order`; the CI fails when it is out of date.
- Traceability: every requirement of a specification is verified by at least one test case of the verification plan,
  every item of the published interface in the traceability matrix (architecture section 10) by the test cases of its
  requirements, and every test case of a plan is run by a testbench. `python tools/compliance.py` writes the
  compliance matrix; `python tools/compliance.py --check` fails on a gap. A module without a testbench is in
  specification: its requirements and the items it owns are listed as planned until its testbench exists. A core is
  admitted only when every module has its testbench, so no module of an admitted core is in specification.

## The published interface

- OpenDMA implements the register interface of the AMD AXI DMA as published in its product guide PG021. The
  documentation cites PG021 by section, table and register or descriptor field name. It never copies text, tables or
  figures of PG021, and it names AMD only to state the compatibility.
- Where PG021 leaves a behaviour open or describes it inconsistently, the module specification states the behaviour
  of OpenDMA in its section "Interpretation of the published interface", with the reason.
- No vendor driver code is part of the repository. Software compatibility is verified with the register-level model
  of the programming sequences in `tb/` and, on hardware, with the drivers of the target platform.

## Module development process

Every module goes through the seven phases of the architecture document (section 9):

| Phase | Output |
| --- | --- |
| A Requirements | `hdl/<module>/docs/specification.md`: requirements with IDs, each tracing to items of the published interface |
| B Architecture | `hdl/<module>/docs/architecture.md`: blocks, ports, state machines, data formats |
| C Verification plan | `hdl/<module>/docs/verification_plan.md`: test cases with IDs, requirement coverage |
| D RTL | `hdl/<module>/src/*.vhd` |
| E Testbenches | `hdl/<module>/tb/<entity>_th.vhd` (harness) and `<entity>_tb.vhd` (VUnit runner) |
| F Verification | Regression green, `hdl/<module>/docs/verification_report.md` |
| G Integration | Tests at the next level that cross every seam the module touches |

A module is one group of blocks of the architecture (section 7). Every block keeps its own entity and its own unit
testbench. `hdl/<module>/README.md` links the four documents and explains how to run the tests.

## Diagrams

- Every architecture document has a block diagram; state machines and data formats have one where text alone is
  hard to follow.
- Diagrams are draw.io drawings stored as editable SVG with the drawing embedded (`<name>.drawio.svg`) in the `img/`
  folder next to the document. The SVG is the source: open it in draw.io to change it. It is exported with the light
  theme on an opaque white background, so that it reads in both colour schemes of the documentation site.
- Blocks: light blue for OpenDMA logic, white with a blue outline for an OpenDMA entity instantiated as a whole,
  light grey for an Open Logic entity, drawn inside the block that instantiates it. A dashed outline groups the
  blocks of one entity instance. The title carries the building block ID of the architecture (`MM-1 Read
  command`), the entity follows in grey.
- Connections: thick lines for streams and buses, thin lines for single signals. Every line is horizontal or
  vertical; a dot marks a branch or the junction of lines that share a segment. Ports cross the frame of the
  entity, inputs on the left, outputs on the right where the layout allows.
- State machines: states as rounded boxes, the reset entry as a filled dot, every transition labelled with its
  condition.
- A diagram is at most about 1000 px wide, so that its text stays readable in the content column, and its alt text
  names the blocks it shows.

## Verification

- VUnit runs every test (`run.py`); UVVM supplies VVCs, BFMs, checks, randomisation and functional coverage.
- The harness (`_th`) contains clocks, reset, the DUT and the VVCs, the testbench (`_tb`) contains one
  `if run("<test id>") then` block per test case of the verification plan. The test IDs of the plan and the names
  in `run(...)` are identical.
- A test passes only when the alert counters of every level from WARNING to TB_FAILURE equal the expected alerts,
  whatever the stop limits of the test: the test end procedure of `odma_tb_pkg` compares them and ends the
  simulation with a failure on a difference.
- A timed wait (`wait until <condition> for <timeout>`) ends with a check of its condition, so that a missing event
  fails the test instead of timing out silently: the procedures `odmaWaitHigh`, `odmaWaitHighAtEdge` and
  `odmaWaitAtLeast` of `odma_tb_pkg` wait and check that the condition ended the wait before the timeout. A
  condition that may hold already is tested before the wait, as the wait itself waits for an event. A bounded delay
  after which either outcome is fine says so in a comment.
- Tests observe ports and management interfaces only, never internal signals.
- GHDL is the default simulator; QuestaSim (`python run.py --questa`) runs at the time resolution of GHDL (1 fs) and
  collects the code coverage. Every test passes in both simulators.
- `run.py` gives every GHDL simulation its own copy of the option `ghdl.sim_flags` and stops when a simulation command
  does not carry exactly the generics of its configuration (VUnit 5.0.0.dev7 shares that list between configurations).
- A side effect is never obtained by calling an impure function and discarding its result: QuestaSim may remove such
  a call. Protected types offer a procedure for it.
- Memory is the AXI memory model of `tb/`: written data and descriptors are checked through its backdoor, and it
  injects error responses and backpressure. Stream data is generated and checked by the bench, never by the RTL of the
  core.
- Negative tests inject the fault from the bench (error responses of the memory, packets longer than the buffer,
  invalid descriptors, double errors through the `ErrInj` ports, ...) and expect the status in the registers, the
  descriptors or the interrupt outputs.

## Git

- `develop` holds the integrated state and `main` the released state. Every module or change is developed on a branch
  `feature/<module>` or `bugfix/<topic>` from `develop` and merged into `develop` through a pull request once its
  regression is green.
- `main` receives only release branches `release/x.y.z` cut from `develop` and hotfix branches `hotfix/x.y.z`. The
  full regression in QuestaSim, with and without code coverage, runs on the head of the release branch. Releases are
  tagged `vX.Y.Z` with semantic versioning, below 1.0.0 until the hardware test as part of a reference system of the
  family.
- Commit messages: imperative subject line, body explains what and why.
