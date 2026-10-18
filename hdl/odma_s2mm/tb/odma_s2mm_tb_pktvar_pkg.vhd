---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- The queue of the packets the stream generator of the bench of odma_s2mm sends, shared by the
-- harness and the testbench, in a package of its own: a shared variable of a protected type is
-- declared after the protected body.
--
-- Documentation: hdl/odma_s2mm/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library work;
    use work.odma_s2mm_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_s2mm_tb_pktvar_pkg is

    shared variable Pkts_v : PktQueue_t;

end package;
