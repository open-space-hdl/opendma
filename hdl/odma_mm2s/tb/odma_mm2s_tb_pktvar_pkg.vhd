---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- The queue of the packets that the stream checker of the bench of odma_mm2s expects, shared by the
-- harness and the testbench, in a package of its own: a shared variable of a protected type is
-- declared after the protected body.
--
-- Documentation: hdl/odma_mm2s/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library work;
    use work.odma_mm2s_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_mm2s_tb_pktvar_pkg is

    shared variable Pkts_v : PktQueue_t;

end package;
