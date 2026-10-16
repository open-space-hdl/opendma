---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Interrupt controller of one channel (RG-2): the interrupt flags of DMASR with their
-- write-one-to-clear and the interrupt output.
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
entity odma_interrupt is
    port (
        -- Control Signals
        Clk      : in    std_logic;
        Rst      : in    std_logic;
        -- Enables (DMACR)
        Ena_Ioc  : in    std_logic;
        Ena_Err  : in    std_logic;
        -- Events (one clock cycle each)
        Evt_Ioc  : in    std_logic;
        Evt_Err  : in    std_logic;
        -- Write-one-to-clear (DMASR)
        Clr_Ioc  : in    std_logic;
        Clr_Err  : in    std_logic;
        -- Flags and interrupt output
        Flag_Ioc : out   std_logic;
        Flag_Err : out   std_logic;
        Irq      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_interrupt is

    type TwoProcess_r is record
        IocFlag : std_logic;
        ErrFlag : std_logic;
        Irq     : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v : TwoProcess_r;
    begin
        v := r;

        -- DMASR.IOC_Irq, DMASR.Err_Irq: a clear and an event of the same cycle leave the flag set
        if Clr_Ioc = '1' then
            v.IocFlag := '0';
        end if;
        if Evt_Ioc = '1' then
            v.IocFlag := '1';
        end if;
        if Clr_Err = '1' then
            v.ErrFlag := '0';
        end if;
        if Evt_Err = '1' then
            v.ErrFlag := '1';
        end if;

        -- Interrupt output, one clock cycle after the flags
        v.Irq := (r.IocFlag and Ena_Ioc) or (r.ErrFlag and Ena_Err);

        r_next <= v;
    end process;

    -- Outputs
    Flag_Ioc <= r.IocFlag;
    Flag_Err <= r.ErrFlag;
    Irq      <= r.Irq;

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.IocFlag <= '0';
                r.ErrFlag <= '0';
                r.Irq     <= '0';
            end if;
        end if;
    end process;

end architecture;
