---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Definitions of the S2MM channel: the chunk descriptor between the chunk former and the write
-- command block, and the chunk size.
--
-- Documentation: hdl/odma_s2mm/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_s2mm_pkg is

    -- Chunk descriptor {Discard, Pend, Beats, Bytes}
    type Desc_r is record
        Bytes   : unsigned(15 downto 0); -- Bytes of the chunk
        Beats   : unsigned(15 downto 0); -- Beats of the chunk in the data buffer
        Pend    : std_logic;             -- The chunk ends a packet
        Discard : std_logic;             -- The stored part of an interrupted packet, not written
    end record;

    constant DescWidth_c : positive := 34;

    function toSlv (desc : Desc_r) return std_logic_vector;

    function toDesc (slv : std_logic_vector(DescWidth_c - 1 downto 0)) return Desc_r;

    -- Longest burst of the write master: at most the beats of 4 KB, since no AXI burst crosses 4 KB
    function masterBeats (
        burstBeats : positive;
        memWidth   : positive) return positive;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body odma_s2mm_pkg is

    function toSlv (desc : Desc_r) return std_logic_vector is
    begin
        return desc.Discard & desc.Pend & std_logic_vector(desc.Beats) & std_logic_vector(desc.Bytes);
    end function;

    function toDesc (slv : std_logic_vector(DescWidth_c - 1 downto 0)) return Desc_r is
        variable Desc_v : Desc_r;
    begin
        Desc_v.Bytes   := unsigned(slv(15 downto 0));
        Desc_v.Beats   := unsigned(slv(31 downto 16));
        Desc_v.Pend    := slv(32);
        Desc_v.Discard := slv(33);
        return Desc_v;
    end function;

    function masterBeats (
        burstBeats : positive;
        memWidth   : positive) return positive is
    begin
        return minimum(burstBeats, 4096 / (memWidth / 8));
    end function;

end package body;
