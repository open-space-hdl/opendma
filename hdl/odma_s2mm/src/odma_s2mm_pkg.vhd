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

    -- Chunk descriptor {PktEnd, Discard, Pend, Beats, Bytes}
    type Desc_r is record
        Bytes   : unsigned(15 downto 0); -- Bytes of the chunk
        Beats   : unsigned(15 downto 0); -- Beats of the chunk in the data buffer
        Pend    : std_logic;             -- The chunk ends the transfer: the packet or, with the split, the buffer
        Discard : std_logic;             -- The stored part of an interrupted packet, not written
        PktEnd  : std_logic;             -- The chunk ends the packet
    end record;

    constant DescWidth_c : positive := 35;

    function toSlv (desc : Desc_r) return std_logic_vector;

    function toDesc (slv : std_logic_vector(DescWidth_c - 1 downto 0)) return Desc_r;

    -- Longest burst of the write master: at most the beats of 4 KB, since no AXI burst crosses 4 KB
    function masterBeats (
        burstBeats : positive;
        memWidth   : positive) return positive;

    -- Stream beats by which every chunk of a buffer that starts inside a stream word is shorter, so that it fits into
    -- one burst: one memory word in the configurations where that takes more beats per clock cycle than two bursts
    -- per chunk, else 0 (architecture section 4.2)
    function shortBeats (
        memWidth    : positive;
        streamWidth : positive;
        masterBeats : positive) return natural;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body odma_s2mm_pkg is

    function toSlv (desc : Desc_r) return std_logic_vector is
    begin
        return desc.PktEnd & desc.Discard & desc.Pend & std_logic_vector(desc.Beats) & std_logic_vector(desc.Bytes);
    end function;

    function toDesc (slv : std_logic_vector(DescWidth_c - 1 downto 0)) return Desc_r is
        variable Desc_v : Desc_r;
    begin
        Desc_v.Bytes   := unsigned(slv(15 downto 0));
        Desc_v.Beats   := unsigned(slv(31 downto 16));
        Desc_v.Pend    := slv(32);
        Desc_v.Discard := slv(33);
        Desc_v.PktEnd  := slv(34);
        return Desc_v;
    end function;

    function masterBeats (
        burstBeats : positive;
        memWidth   : positive) return positive is
    begin
        return minimum(burstBeats, 4096 / (memWidth / 8));
    end function;

    function shortBeats (
        memWidth    : positive;
        streamWidth : positive;
        masterBeats : positive) return natural is
    begin
        if memWidth = streamWidth and masterBeats >= 8 then
            return memWidth / streamWidth;
        end if;
        return 0;
    end function;

end package body;
