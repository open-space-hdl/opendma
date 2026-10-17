---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Observations of the odma_core harness: the AXI4 transactions at the memory ports of the core, the
-- S2MM stream beats taken during a soft reset and the state of the S2MM stream peer.
--
-- Documentation: hdl/odma_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_core_tb_pkg is

    -- Memory model instances (odma_tb_memvar_pkg.Mem_v) of the read port, the write port and the descriptor port
    constant MemRd_c : natural := 0;
    constant MemWr_c : natural := 1;
    constant MemSg_c : natural := 2;

    type CoreObs_r is record
        ArBursts : natural; -- Read bursts accepted by the memory model
        RBursts  : natural; -- Read bursts whose last beat the core took
        AwBursts : natural; -- Write bursts accepted by the memory model
        BResps   : natural; -- Write responses the core took
        Overlap  : boolean; -- A read beat and a write beat were taken in the same clock cycle
        RstBeats : natural; -- S2MM stream beats the core took while S2mm_RstOut was high
        PeerDone : boolean; -- The stream peer of the harness ended its packet (sent or aborted)
        SgFetch  : natural; -- Read bursts and write bursts of the descriptor port
        SgUpdate : natural;
        SgRDone  : natural; -- Read bursts of the descriptor port whose last beat the core took
        SgBDone  : natural; -- Write responses of the descriptor port the core took
    end record;

end package;
