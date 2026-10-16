# odma_sg

Scatter/Gather engine of OpenDMA (phase b): fetches the descriptors of each channel from memory through its own AXI4
master, turns every descriptor into a transfer command of its channel, writes the status of every processed
descriptor back and reports completed packets and errors to the register interface.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, interpretations of the published interface |

The module is in specification: architecture, verification plan, RTL and testbench follow with phase b.
