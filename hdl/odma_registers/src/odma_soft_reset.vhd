---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Reset controller (RG-3): the soft reset sequence (drain both channels, then reset the core), the
-- core reset and the reset outputs of the stream peers.
--
-- Documentation: hdl/odma_registers/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_soft_reset is
    port (
        -- Control Signals
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        -- Soft reset request (write of 1 to DMACR.Reset of either channel)
        Start        : in    std_logic;
        -- Channels
        Mm2s_Stopped : in    std_logic;
        S2mm_Stopped : in    std_logic;
        -- Soft reset in progress: DMACR.Reset, drain request of the channels
        Busy         : out   std_logic;
        -- Resets
        CoreRst      : out   std_logic;
        RstOut       : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_soft_reset is

    -- Clock cycles of the reset phase
    constant ResetCycles_c : positive := 16;

    type SoftResetFsm_t is (Idle_s, Drain_s, Reset_s);

    type TwoProcess_r is record
        State : SoftResetFsm_t;
        Cnt   : natural range 0 to ResetCycles_c - 1;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v : TwoProcess_r;
    begin
        v := r;

        case r.State is

            when Idle_s =>
                -- MM2S_DMACR.Reset, S2MM_DMACR.Reset
                if Start = '1' then
                    v.State := Drain_s;
                end if;

            when Drain_s =>
                -- Both channels completed their issued AXI transactions
                if Mm2s_Stopped = '1' and S2mm_Stopped = '1' then
                    v.State := Reset_s;
                    v.Cnt   := ResetCycles_c - 1;
                end if;

            when Reset_s =>
                if r.Cnt = 0 then
                    v.State := Idle_s;
                else
                    v.Cnt := r.Cnt - 1;
                end if;

            -- coverage off
            when others =>
                v.State := Idle_s; -- unreachable, safe recovery
            -- coverage on

        end case;

        r_next <= v;
    end process;

    -- Outputs
    Busy    <= '0' when r.State = Idle_s else '1';
    CoreRst <= '1' when Rst = '1' or r.State = Reset_s else '0';
    RstOut  <= '1' when Rst = '1' or r.State /= Idle_s else '0';

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State <= Idle_s;
            end if;
        end if;
    end process;

end architecture;
