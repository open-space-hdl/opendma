---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Interrupt controller of one channel (RG-2): the interrupt flags of DMASR with their
-- write-one-to-clear and the interrupt output. In Scatter/Gather Mode (Sg_g) also the interrupt
-- threshold counter, which sets IOC_Irq after the programmed number of packets, and the delay
-- timer, which sets Dly_Irq when no further packet completes in time.
--
-- Documentation: hdl/odma_registers/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_interrupt is
    generic (
        Sg_g : boolean := false
    );
    port (
        -- Control Signals
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        -- Enables (DMACR)
        Ena_Ioc      : in    std_logic;
        Ena_Dly      : in    std_logic                    := '0';
        Ena_Err      : in    std_logic;
        -- Events (one clock cycle each); Direct Register Mode: Evt_Ioc per completed transfer
        Evt_Ioc      : in    std_logic;
        Evt_Err      : in    std_logic;
        -- Scatter/Gather Mode: packet completed, packet started
        Evt_Pkt      : in    std_logic                    := '0';
        Evt_PktStart : in    std_logic                    := '0';
        -- Threshold and delay (DMACR.IRQThreshold, DMACR.IRQDelay); Thr_Load reloads the counter
        Thr_Value    : in    std_logic_vector(7 downto 0) := x"01";
        Thr_Load     : in    std_logic                    := '0';
        Dly_Value    : in    std_logic_vector(7 downto 0) := x"00";
        -- Write-one-to-clear (DMASR)
        Clr_Ioc      : in    std_logic;
        Clr_Dly      : in    std_logic                    := '0';
        Clr_Err      : in    std_logic;
        -- Flags, counters (DMASR.IRQThresholdSts, DMASR.IRQDelaySts) and interrupt output
        Flag_Ioc     : out   std_logic;
        Flag_Dly     : out   std_logic;
        Flag_Err     : out   std_logic;
        Thr_Count    : out   std_logic_vector(7 downto 0);
        Dly_Count    : out   std_logic_vector(7 downto 0);
        Irq          : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_interrupt is

    -- The delay timer counts in units of 125 clock cycles
    constant DlyUnit_c : positive := 125;

    type TwoProcess_r is record
        IocFlag : std_logic;
        DlyFlag : std_logic;
        ErrFlag : std_logic;
        ThrCnt  : unsigned(7 downto 0);
        DlyRun  : std_logic;
        DlyPre  : natural range 0 to DlyUnit_c - 1;
        DlyCnt  : unsigned(7 downto 0);
        Irq     : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable Ioc_v  : std_logic;
        variable Fire_v : boolean;
    begin
        v := r;

        -- IOC event: per transfer in Direct Register Mode, by the threshold counter in Scatter/Gather Mode
        Ioc_v  := Evt_Ioc;
        Fire_v := false;

        if Sg_g then
            -- Threshold counter: reaching 0 sets IOC_Irq and reloads the counter (RG-SG-06)
            if Evt_Pkt = '1' then
                if r.ThrCnt <= 1 then
                    Ioc_v    := '1';
                    v.ThrCnt := unsigned(Thr_Value);
                else
                    v.ThrCnt := r.ThrCnt - 1;
                end if;
            end if;

            -- Delay timer (RG-SG-07, interpretation R9): stopped and cleared by the start of a packet, started by a
            -- packet completion that did not set IOC_Irq, stopped by one that did
            if Evt_PktStart = '1' then
                v.DlyRun := '0';
                v.DlyCnt := (others => '0');
            end if;
            if Evt_Pkt = '1' then
                v.DlyRun := not Ioc_v;
                v.DlyPre := 0;
                v.DlyCnt := (others => '0');
            elsif r.DlyRun = '1' then
                if r.DlyPre = DlyUnit_c - 1 then
                    v.DlyPre := 0;
                    v.DlyCnt := r.DlyCnt + 1;
                    -- Timeout: Dly_Irq, the timer cleared and the threshold counter reloaded
                    if r.DlyCnt + 1 >= unsigned(Dly_Value) then
                        Fire_v   := true;
                        v.DlyRun := '0';
                        v.DlyCnt := (others => '0');
                        v.ThrCnt := unsigned(Thr_Value);
                    end if;
                else
                    v.DlyPre := r.DlyPre + 1;
                end if;
            end if;
            -- IRQDelay = 0 disables the timer
            if unsigned(Dly_Value) = 0 then
                v.DlyRun := '0';
                v.DlyCnt := (others => '0');
            end if;

            -- A write of the threshold field and the start of the channel reload the counter
            if Thr_Load = '1' then
                v.ThrCnt := unsigned(Thr_Value);
            end if;
        end if;

        -- DMASR.IOC_Irq, DMASR.Dly_Irq, DMASR.Err_Irq: a clear and an event of the same cycle leave the flag set
        if Clr_Ioc = '1' then
            v.IocFlag := '0';
        end if;
        if Ioc_v = '1' then
            v.IocFlag := '1';
        end if;
        if Clr_Dly = '1' then
            v.DlyFlag := '0';
        end if;
        if Fire_v then
            v.DlyFlag := '1';
        end if;
        if Clr_Err = '1' then
            v.ErrFlag := '0';
        end if;
        if Evt_Err = '1' then
            v.ErrFlag := '1';
        end if;

        -- Interrupt output, one clock cycle after the flags
        v.Irq := (r.IocFlag and Ena_Ioc) or (r.DlyFlag and Ena_Dly) or (r.ErrFlag and Ena_Err);

        r_next <= v;
    end process;

    -- Outputs
    Flag_Ioc  <= r.IocFlag;
    Flag_Dly  <= r.DlyFlag;
    Flag_Err  <= r.ErrFlag;
    Thr_Count <= std_logic_vector(r.ThrCnt);
    Dly_Count <= std_logic_vector(r.DlyCnt);
    Irq       <= r.Irq;

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.IocFlag <= '0';
                r.DlyFlag <= '0';
                r.ErrFlag <= '0';
                r.ThrCnt  <= to_unsigned(1, 8);
                r.DlyRun  <= '0';
                r.DlyPre  <= 0;
                r.DlyCnt  <= (others => '0');
                r.Irq     <= '0';
            end if;
        end if;
    end process;

end architecture;
