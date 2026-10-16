---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of odma_pkg: AXI4 VVC and a raw driver on the AXI memory model, AXI4-Lite VVC on a
-- register stub that drives two interrupt signals, AXI4-Stream VVCs connected back to back.
--
-- Documentation: hdl/odma_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library olo;

library work;
    use work.odma_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_pkg_th is
    generic (
        ClkPeriod_g : time := 10 ns
    );
    port (
        Mm2sIrq  : out   std_logic;
        S2mmIrq  : out   std_logic;
        RawCmd   : in    natural                       := 0;               -- 1: write burst without WLast,
        -- 2: WLast before the last beat
        RawDone  : out   std_logic;                                                  -- Toggles at the write response
        AddrHigh : in    std_logic_vector(31 downto 0) := (others => '0')  -- Address bits 63 to 32 of the VVC
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_pkg_th is

    constant AddrWidth_c : positive := 64;
    constant VvcWidth_c  : positive := 32; -- Address width of the UVVM AXI4 VVC
    constant DataWidth_c : positive := 64;
    constant RawBeats_c  : positive := 4;

    signal Clk : std_logic := '0';
    signal Rst : std_logic := '1';

    -- AXI4 master VVC side
    signal V_AwAddr  : std_logic_vector(VvcWidth_c - 1 downto 0);
    signal V_ArAddr  : std_logic_vector(VvcWidth_c - 1 downto 0);
    signal V_AwLen   : std_logic_vector(7 downto 0);
    signal V_AwSize  : std_logic_vector(2 downto 0);
    signal V_AwBurst : std_logic_vector(1 downto 0);
    signal V_AwValid : std_logic;
    signal V_WData   : std_logic_vector(DataWidth_c - 1 downto 0);
    signal V_WStrb   : std_logic_vector(DataWidth_c / 8 - 1 downto 0);
    signal V_WLast   : std_logic;
    signal V_WValid  : std_logic;
    signal V_BReady  : std_logic;
    signal V_BValid  : std_logic;

    -- Raw driver side
    signal RawSel    : std_logic                                  := '0';
    signal R_AwAddr  : std_logic_vector(AddrWidth_c - 1 downto 0) := (others => '0');
    signal R_AwValid : std_logic                                  := '0';
    signal R_WData   : std_logic_vector(DataWidth_c - 1 downto 0) := (others => '0');
    signal R_WLast   : std_logic                                  := '0';
    signal R_WValid  : std_logic                                  := '0';
    signal RawDone_i : std_logic                                  := '0';

    -- Memory model side
    signal M_AwAddr  : std_logic_vector(AddrWidth_c - 1 downto 0);
    signal M_AwLen   : std_logic_vector(7 downto 0);
    signal M_AwSize  : std_logic_vector(2 downto 0);
    signal M_AwBurst : std_logic_vector(1 downto 0);
    signal M_AwValid : std_logic;
    signal M_AwReady : std_logic;
    signal M_WData   : std_logic_vector(DataWidth_c - 1 downto 0);
    signal M_WStrb   : std_logic_vector(DataWidth_c / 8 - 1 downto 0);
    signal M_WLast   : std_logic;
    signal M_WValid  : std_logic;
    signal M_WReady  : std_logic;
    signal M_BResp   : std_logic_vector(1 downto 0);
    signal M_BValid  : std_logic;
    signal M_BReady  : std_logic;
    signal M_ArAddr  : std_logic_vector(AddrWidth_c - 1 downto 0);
    signal M_ArLen   : std_logic_vector(7 downto 0);
    signal M_ArSize  : std_logic_vector(2 downto 0);
    signal M_ArBurst : std_logic_vector(1 downto 0);
    signal M_ArValid : std_logic;
    signal M_ArReady : std_logic;
    signal M_RData   : std_logic_vector(DataWidth_c - 1 downto 0);
    signal M_RResp   : std_logic_vector(1 downto 0);
    signal M_RLast   : std_logic;
    signal M_RValid  : std_logic;
    signal M_RReady  : std_logic;

    -- Register stub
    signal L_ArAddr  : std_logic_vector(7 downto 0);
    signal L_ArValid : std_logic;
    signal L_ArReady : std_logic;
    signal L_AwAddr  : std_logic_vector(7 downto 0);
    signal L_AwValid : std_logic;
    signal L_AwReady : std_logic;
    signal L_WData   : std_logic_vector(31 downto 0);
    signal L_WStrb   : std_logic_vector(3 downto 0);
    signal L_WValid  : std_logic;
    signal L_WReady  : std_logic;
    signal L_BResp   : std_logic_vector(1 downto 0);
    signal L_BValid  : std_logic;
    signal L_BReady  : std_logic;
    signal L_RData   : std_logic_vector(31 downto 0);
    signal L_RResp   : std_logic_vector(1 downto 0);
    signal L_RValid  : std_logic;
    signal L_RReady  : std_logic;
    signal Rb_Addr   : std_logic_vector(7 downto 0);
    signal Rb_Wr     : std_logic;
    signal Rb_WrData : std_logic_vector(31 downto 0);
    signal Rb_Rd     : std_logic;
    signal Rb_RdData : std_logic_vector(31 downto 0) := (others => '0');
    signal Rb_RdVld  : std_logic                     := '0';
    signal Scratch   : std_logic_vector(31 downto 0) := (others => '0');
    signal IrqReg    : std_logic_vector(1 downto 0)  := "00";
    signal Countdown : unsigned(31 downto 0)         := (others => '0');

    -- Streams
    signal S_Data  : std_logic_vector(31 downto 0);
    signal S_Keep  : std_logic_vector(3 downto 0);
    signal S_Last  : std_logic;
    signal S_Valid : std_logic;
    signal S_Ready : std_logic;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk <= not Clk after ClkPeriod_g / 2;
    Rst <= '1', '0' after 10 * ClkPeriod_g;

    -----------------------------------------------------------------------------------------------
    -- AXI memory model with the AXI4 VVC or the raw driver
    -----------------------------------------------------------------------------------------------
    i_axi_master : entity work.odma_tb_axi_master
        generic map (
            InstanceIdx_g => 0,
            AddrWidth_g   => VvcWidth_c,
            DataWidth_g   => DataWidth_c
        )
        port map (
            Clk     => Clk,
            AwAddr  => V_AwAddr,
            AwLen   => V_AwLen,
            AwSize  => V_AwSize,
            AwBurst => V_AwBurst,
            AwValid => V_AwValid,
            AwReady => M_AwReady,
            WData   => V_WData,
            WStrb   => V_WStrb,
            WLast   => V_WLast,
            WValid  => V_WValid,
            WReady  => M_WReady,
            BResp   => M_BResp,
            BValid  => V_BValid,
            BReady  => V_BReady,
            ArAddr  => V_ArAddr,
            ArLen   => M_ArLen,
            ArSize  => M_ArSize,
            ArBurst => M_ArBurst,
            ArValid => M_ArValid,
            ArReady => M_ArReady,
            RData   => M_RData,
            RResp   => M_RResp,
            RLast   => M_RLast,
            RValid  => M_RValid,
            RReady  => M_RReady
        );

    M_ArAddr  <= AddrHigh & V_ArAddr;
    M_AwAddr  <= R_AwAddr when RawSel = '1' else AddrHigh & V_AwAddr;
    M_AwLen   <= std_logic_vector(to_unsigned(RawBeats_c - 1, 8)) when RawSel = '1' else V_AwLen;
    M_AwSize  <= "011" when RawSel = '1' else V_AwSize;
    M_AwBurst <= "01" when RawSel = '1' else V_AwBurst;
    M_AwValid <= R_AwValid when RawSel = '1' else V_AwValid;
    M_WData   <= R_WData when RawSel = '1' else V_WData;
    M_WStrb   <= (others => '1') when RawSel = '1' else V_WStrb;
    M_WLast   <= R_WLast when RawSel = '1' else V_WLast;
    M_WValid  <= R_WValid when RawSel = '1' else V_WValid;
    M_BReady  <= '1' when RawSel = '1' else V_BReady;
    V_BValid  <= M_BValid and not RawSel; -- The VVC reports a response without its own burst

    -- Raw driver: one write burst of RawBeats_c beats at 0x1000 with a WLast error
    p_raw : process is
    begin
        wait until RawCmd /= 0;
        wait until rising_edge(Clk);
        RawSel    <= '1';
        R_AwAddr  <= x"0000_0000_0000_1000";
        R_AwValid <= '1';
        wait until rising_edge(Clk) and M_AwReady = '1';
        R_AwValid <= '0';

        for i in 0 to RawBeats_c - 1 loop
            R_WData  <= std_logic_vector(to_unsigned(i + 1, DataWidth_c));
            R_WValid <= '1';
            if RawCmd = 1 then
                R_WLast <= '0';                                   -- Missing on the last beat
            else
                R_WLast <= '1' when i = 1 or i = RawBeats_c - 1 else '0'; -- Early on the second beat
            end if;
            wait until rising_edge(Clk) and M_WReady = '1';
        end loop;

        R_WValid  <= '0';
        R_WLast   <= '0';
        wait until rising_edge(Clk) and M_BValid = '1';
        wait until rising_edge(Clk); -- BValid falls before the VVC sees the channel again
        RawSel    <= '0';
        RawDone_i <= not RawDone_i;
        wait until RawCmd = 0;
    end process;

    RawDone <= RawDone_i;

    i_ram : entity work.odma_tb_axi_ram
        generic map (
            Index_g     => 0,
            AddrWidth_g => AddrWidth_c,
            DataWidth_g => DataWidth_c
        )
        port map (
            Clk     => Clk,
            Rst     => Rst,
            AwAddr  => M_AwAddr,
            AwLen   => M_AwLen,
            AwSize  => M_AwSize,
            AwBurst => M_AwBurst,
            AwValid => M_AwValid,
            AwReady => M_AwReady,
            WData   => M_WData,
            WStrb   => M_WStrb,
            WLast   => M_WLast,
            WValid  => M_WValid,
            WReady  => M_WReady,
            BResp   => M_BResp,
            BValid  => M_BValid,
            BReady  => M_BReady,
            ArAddr  => M_ArAddr,
            ArLen   => M_ArLen,
            ArSize  => M_ArSize,
            ArBurst => M_ArBurst,
            ArValid => M_ArValid,
            ArReady => M_ArReady,
            RData   => M_RData,
            RResp   => M_RResp,
            RLast   => M_RLast,
            RValid  => M_RValid,
            RReady  => M_RReady
        );

    -----------------------------------------------------------------------------------------------
    -- Register stub: 0x00 scratch, 0x04 interrupt bits (bit 0 Mm2sIrq, bit 1 S2mmIrq), 0x08 counts
    -- down to zero from the written value, 0x0C reads 0x12345678
    -----------------------------------------------------------------------------------------------
    i_axilite_master : entity work.odma_tb_axilite_master
        generic map (
            InstanceIdx_g => 0,
            AddrWidth_g   => 8
        )
        port map (
            Clk     => Clk,
            ArAddr  => L_ArAddr,
            ArValid => L_ArValid,
            ArReady => L_ArReady,
            AwAddr  => L_AwAddr,
            AwValid => L_AwValid,
            AwReady => L_AwReady,
            WData   => L_WData,
            WStrb   => L_WStrb,
            WValid  => L_WValid,
            WReady  => L_WReady,
            BResp   => L_BResp,
            BValid  => L_BValid,
            BReady  => L_BReady,
            RData   => L_RData,
            RResp   => L_RResp,
            RValid  => L_RValid,
            RReady  => L_RReady
        );

    i_axilite_slave : entity olo.olo_axi_lite_slave
        generic map (
            AxiAddrWidth_g => 8,
            AxiDataWidth_g => 32
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            S_AxiLite_ArAddr  => L_ArAddr,
            S_AxiLite_ArValid => L_ArValid,
            S_AxiLite_ArReady => L_ArReady,
            S_AxiLite_AwAddr  => L_AwAddr,
            S_AxiLite_AwValid => L_AwValid,
            S_AxiLite_AwReady => L_AwReady,
            S_AxiLite_WData   => L_WData,
            S_AxiLite_WStrb   => L_WStrb,
            S_AxiLite_WValid  => L_WValid,
            S_AxiLite_WReady  => L_WReady,
            S_AxiLite_BResp   => L_BResp,
            S_AxiLite_BValid  => L_BValid,
            S_AxiLite_BReady  => L_BReady,
            S_AxiLite_RData   => L_RData,
            S_AxiLite_RResp   => L_RResp,
            S_AxiLite_RValid  => L_RValid,
            S_AxiLite_RReady  => L_RReady,
            Rb_Addr           => Rb_Addr,
            Rb_Wr             => Rb_Wr,
            Rb_ByteEna        => open,
            Rb_WrData         => Rb_WrData,
            Rb_Rd             => Rb_Rd,
            Rb_RdData         => Rb_RdData,
            Rb_RdValid        => Rb_RdVld
        );

    p_stub : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Countdown /= 0 then
                Countdown <= Countdown - 1;
            end if;
            if Rb_Wr = '1' then

                case Rb_Addr is
                    when x"00" => Scratch <= Rb_WrData;
                    when x"04" => IrqReg <= Rb_WrData(1 downto 0);
                    when x"08" => Countdown <= unsigned(Rb_WrData);
                    when others => null;
                end case;

            end if;
            Rb_RdVld <= Rb_Rd;
            if Rb_Rd = '1' then

                case Rb_Addr is
                    when x"00" => Rb_RdData <= Scratch;
                    when x"04" => Rb_RdData <= (31 downto 2 => '0') & IrqReg;
                    when x"08" => Rb_RdData <= std_logic_vector(Countdown);
                    when x"0C" => Rb_RdData <= x"12345678";
                    when others => Rb_RdData <= (others => '0');
                end case;

            end if;
            if Rst = '1' then
                Scratch   <= (others => '0');
                IrqReg    <= "00";
                Countdown <= (others => '0');
                Rb_RdVld  <= '0';
            end if;
        end if;
    end process;

    Mm2sIrq <= IrqReg(0);
    S2mmIrq <= IrqReg(1);

    -----------------------------------------------------------------------------------------------
    -- AXI4-Stream VVCs back to back: instance 0 transmits, instance 1 expects
    -----------------------------------------------------------------------------------------------
    i_axis_master : entity work.odma_tb_axis_master
        generic map (
            InstanceIdx_g => 0,
            DataWidth_g   => 32
        )
        port map (
            Clk       => Clk,
            Out_Data  => S_Data,
            Out_User  => open,
            Out_Keep  => S_Keep,
            Out_Last  => S_Last,
            Out_Valid => S_Valid,
            Out_Ready => S_Ready
        );

    i_axis_slave : entity work.odma_tb_axis_slave
        generic map (
            InstanceIdx_g => 1,
            DataWidth_g   => 32
        )
        port map (
            Clk      => Clk,
            In_Data  => S_Data,
            In_Keep  => S_Keep,
            In_Last  => S_Last,
            In_Valid => S_Valid,
            In_Ready => S_Ready
        );

end architecture;
