---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of odma_core: clock, reset, DUT, AXI4-Lite VVC on the register port, one AXI memory
-- model on each memory port (instance MemRd_c on the MM2S read port, MemWr_c on the S2MM write
-- port), AXI4-Stream VVCs on the streams (instance 0 transmits on the S2MM stream, instance 1
-- receives the MM2S stream), a second S2MM stream peer that sends one packet on request and
-- abandons it when S2mm_RstOut rises, monitors of the AXI4 transactions, of the S2MM beats during a
-- soft reset and of the idle values of a channel that is not included.
--
-- Documentation: hdl/odma_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library work;
    use work.odma_tb_mem_pkg.all;
    use work.odma_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_core_th is
    generic (
        ClkPeriod_g       : time     := 10 ns;
        IncludeMm2s_g     : boolean  := true;
        IncludeS2mm_g     : boolean  := true;
        LengthWidth_g     : positive := 14;
        AddrWidth_g       : positive := 32;
        Mm2sMemWidth_g    : positive := 32;
        S2mmMemWidth_g    : positive := 32;
        Mm2sStreamWidth_g : positive := 32;
        S2mmStreamWidth_g : positive := 32;
        Mm2sBurstBeats_g  : positive := 16;
        S2mmBurstBeats_g  : positive := 16;
        Mm2sBufferBeats_g : positive := 64;
        S2mmBufferBeats_g : positive := 64;
        ExtRegs_g         : boolean  := true
    );
    port (
        Mm2sIrq    : out   std_logic;
        S2mmIrq    : out   std_logic;
        EccIrq     : out   std_logic;
        Mm2sRstOut : out   std_logic;
        S2mmRstOut : out   std_logic;
        PeerBytes  : in    natural := 0; -- A change from 0 starts a packet of the stream peer
        Obs        : out   CoreObs_r
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_core_th is

    signal Clk : std_logic := '0';
    signal Rst : std_logic := '1';

    -- Register port
    signal L_ArAddr  : std_logic_vector(9 downto 0);
    signal L_ArValid : std_logic;
    signal L_ArReady : std_logic;
    signal L_AwAddr  : std_logic_vector(9 downto 0);
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

    -- MM2S memory port and stream
    signal Rd_ArAddr  : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal Rd_ArLen   : std_logic_vector(7 downto 0);
    signal Rd_ArSize  : std_logic_vector(2 downto 0);
    signal Rd_ArBurst : std_logic_vector(1 downto 0);
    signal Rd_ArLock  : std_logic;
    signal Rd_ArCache : std_logic_vector(3 downto 0);
    signal Rd_ArProt  : std_logic_vector(2 downto 0);
    signal Rd_ArValid : std_logic;
    signal Rd_ArReady : std_logic;
    signal Rd_RData   : std_logic_vector(Mm2sMemWidth_g - 1 downto 0);
    signal Rd_RResp   : std_logic_vector(1 downto 0);
    signal Rd_RLast   : std_logic;
    signal Rd_RValid  : std_logic;
    signal Rd_RReady  : std_logic;
    signal Mm2s_Data  : std_logic_vector(Mm2sStreamWidth_g - 1 downto 0);
    signal Mm2s_Keep  : std_logic_vector(Mm2sStreamWidth_g / 8 - 1 downto 0);
    signal Mm2s_Last  : std_logic;
    signal Mm2s_Valid : std_logic;
    signal Mm2s_Ready : std_logic;

    -- S2MM stream and memory port
    signal S2mm_Data    : std_logic_vector(S2mmStreamWidth_g - 1 downto 0);
    signal S2mm_Keep    : std_logic_vector(S2mmStreamWidth_g / 8 - 1 downto 0);
    signal S2mm_Last    : std_logic;
    signal S2mm_Valid   : std_logic;
    signal S2mm_Ready   : std_logic;
    signal V_Data       : std_logic_vector(S2mmStreamWidth_g - 1 downto 0);
    signal V_Keep       : std_logic_vector(S2mmStreamWidth_g / 8 - 1 downto 0);
    signal V_Last       : std_logic;
    signal V_Valid      : std_logic;
    signal V_Ready      : std_logic;
    signal PeerSel      : std_logic                                            := '0';
    signal P_Data       : std_logic_vector(S2mmStreamWidth_g - 1 downto 0)     := (others => '0');
    signal P_Keep       : std_logic_vector(S2mmStreamWidth_g / 8 - 1 downto 0) := (others => '0');
    signal P_Last       : std_logic                                            := '0';
    signal P_Valid      : std_logic                                            := '0';
    signal S2mmRstOut_i : std_logic;
    signal Wr_AwAddr    : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal Wr_AwLen     : std_logic_vector(7 downto 0);
    signal Wr_AwSize    : std_logic_vector(2 downto 0);
    signal Wr_AwBurst   : std_logic_vector(1 downto 0);
    signal Wr_AwLock    : std_logic;
    signal Wr_AwCache   : std_logic_vector(3 downto 0);
    signal Wr_AwProt    : std_logic_vector(2 downto 0);
    signal Wr_AwValid   : std_logic;
    signal Wr_AwReady   : std_logic;
    signal Wr_WData     : std_logic_vector(S2mmMemWidth_g - 1 downto 0);
    signal Wr_WStrb     : std_logic_vector(S2mmMemWidth_g / 8 - 1 downto 0);
    signal Wr_WLast     : std_logic;
    signal Wr_WValid    : std_logic;
    signal Wr_WReady    : std_logic;
    signal Wr_BResp     : std_logic_vector(1 downto 0);
    signal Wr_BValid    : std_logic;
    signal Wr_BReady    : std_logic;

    signal Mm2sIrq_i : std_logic;
    signal S2mmIrq_i : std_logic;
    signal Obs_i     : CoreObs_r := (0, 0, 0, 0, false, 0, false);

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk <= not Clk after ClkPeriod_g / 2;
    Rst <= '1', '0' after 10 * ClkPeriod_g;

    -----------------------------------------------------------------------------------------------
    -- DUT
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.odma_core
        generic map (
            IncludeMm2s_g     => IncludeMm2s_g,
            IncludeS2mm_g     => IncludeS2mm_g,
            LengthWidth_g     => LengthWidth_g,
            AddrWidth_g       => AddrWidth_g,
            Mm2sMemWidth_g    => Mm2sMemWidth_g,
            S2mmMemWidth_g    => S2mmMemWidth_g,
            Mm2sStreamWidth_g => Mm2sStreamWidth_g,
            S2mmStreamWidth_g => S2mmStreamWidth_g,
            Mm2sBurstBeats_g  => Mm2sBurstBeats_g,
            S2mmBurstBeats_g  => S2mmBurstBeats_g,
            Mm2sBufferBeats_g => Mm2sBufferBeats_g,
            S2mmBufferBeats_g => S2mmBufferBeats_g,
            ExtRegs_g         => ExtRegs_g
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
            M_AxiMm2s_ArAddr  => Rd_ArAddr,
            M_AxiMm2s_ArLen   => Rd_ArLen,
            M_AxiMm2s_ArSize  => Rd_ArSize,
            M_AxiMm2s_ArBurst => Rd_ArBurst,
            M_AxiMm2s_ArLock  => Rd_ArLock,
            M_AxiMm2s_ArCache => Rd_ArCache,
            M_AxiMm2s_ArProt  => Rd_ArProt,
            M_AxiMm2s_ArValid => Rd_ArValid,
            M_AxiMm2s_ArReady => Rd_ArReady,
            M_AxiMm2s_RData   => Rd_RData,
            M_AxiMm2s_RResp   => Rd_RResp,
            M_AxiMm2s_RLast   => Rd_RLast,
            M_AxiMm2s_RValid  => Rd_RValid,
            M_AxiMm2s_RReady  => Rd_RReady,
            M_Mm2s_Data       => Mm2s_Data,
            M_Mm2s_Keep       => Mm2s_Keep,
            M_Mm2s_Last       => Mm2s_Last,
            M_Mm2s_Valid      => Mm2s_Valid,
            M_Mm2s_Ready      => Mm2s_Ready,
            S_S2mm_Data       => S2mm_Data,
            S_S2mm_Keep       => S2mm_Keep,
            S_S2mm_Last       => S2mm_Last,
            S_S2mm_Valid      => S2mm_Valid,
            S_S2mm_Ready      => S2mm_Ready,
            M_AxiS2mm_AwAddr  => Wr_AwAddr,
            M_AxiS2mm_AwLen   => Wr_AwLen,
            M_AxiS2mm_AwSize  => Wr_AwSize,
            M_AxiS2mm_AwBurst => Wr_AwBurst,
            M_AxiS2mm_AwLock  => Wr_AwLock,
            M_AxiS2mm_AwCache => Wr_AwCache,
            M_AxiS2mm_AwProt  => Wr_AwProt,
            M_AxiS2mm_AwValid => Wr_AwValid,
            M_AxiS2mm_AwReady => Wr_AwReady,
            M_AxiS2mm_WData   => Wr_WData,
            M_AxiS2mm_WStrb   => Wr_WStrb,
            M_AxiS2mm_WLast   => Wr_WLast,
            M_AxiS2mm_WValid  => Wr_WValid,
            M_AxiS2mm_WReady  => Wr_WReady,
            M_AxiS2mm_BResp   => Wr_BResp,
            M_AxiS2mm_BValid  => Wr_BValid,
            M_AxiS2mm_BReady  => Wr_BReady,
            Mm2s_Irq          => Mm2sIrq_i,
            S2mm_Irq          => S2mmIrq_i,
            Ecc_Irq           => EccIrq,
            Mm2s_RstOut       => Mm2sRstOut,
            S2mm_RstOut       => S2mmRstOut_i
        );

    S2mmRstOut <= S2mmRstOut_i;

    Mm2sIrq <= Mm2sIrq_i;
    S2mmIrq <= S2mmIrq_i;

    -----------------------------------------------------------------------------------------------
    -- Register port: AXI4-Lite VVC
    -----------------------------------------------------------------------------------------------
    i_axilite_master : entity work.odma_tb_axilite_master
        generic map (
            InstanceIdx_g => 0,
            AddrWidth_g   => 10
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

    -----------------------------------------------------------------------------------------------
    -- Memory models: reads of the MM2S port from instance MemRd_c, writes of the S2MM port into MemWr_c
    -----------------------------------------------------------------------------------------------
    i_ram_rd : entity work.odma_tb_axi_ram
        generic map (
            Index_g     => MemRd_c,
            AddrWidth_g => AddrWidth_g,
            DataWidth_g => Mm2sMemWidth_g
        )
        port map (
            Clk     => Clk,
            Rst     => Rst,
            AwAddr  => (others => '0'),
            AwLen   => (others => '0'),
            AwSize  => (others => '0'),
            AwBurst => "01",
            AwValid => '0',
            AwReady => open,
            WData   => (others => '0'),
            WStrb   => (others => '0'),
            WLast   => '0',
            WValid  => '0',
            WReady  => open,
            BResp   => open,
            BValid  => open,
            BReady  => '1',
            ArAddr  => Rd_ArAddr,
            ArLen   => Rd_ArLen,
            ArSize  => Rd_ArSize,
            ArBurst => Rd_ArBurst,
            ArValid => Rd_ArValid,
            ArReady => Rd_ArReady,
            RData   => Rd_RData,
            RResp   => Rd_RResp,
            RLast   => Rd_RLast,
            RValid  => Rd_RValid,
            RReady  => Rd_RReady
        );

    i_ram_wr : entity work.odma_tb_axi_ram
        generic map (
            Index_g     => MemWr_c,
            AddrWidth_g => AddrWidth_g,
            DataWidth_g => S2mmMemWidth_g
        )
        port map (
            Clk     => Clk,
            Rst     => Rst,
            AwAddr  => Wr_AwAddr,
            AwLen   => Wr_AwLen,
            AwSize  => Wr_AwSize,
            AwBurst => Wr_AwBurst,
            AwValid => Wr_AwValid,
            AwReady => Wr_AwReady,
            WData   => Wr_WData,
            WStrb   => Wr_WStrb,
            WLast   => Wr_WLast,
            WValid  => Wr_WValid,
            WReady  => Wr_WReady,
            BResp   => Wr_BResp,
            BValid  => Wr_BValid,
            BReady  => Wr_BReady,
            ArAddr  => (others => '0'),
            ArLen   => (others => '0'),
            ArSize  => (others => '0'),
            ArBurst => "01",
            ArValid => '0',
            ArReady => open,
            RData   => open,
            RResp   => open,
            RLast   => open,
            RValid  => open,
            RReady  => '1'
        );

    -----------------------------------------------------------------------------------------------
    -- Streams: AXI4-Stream VVCs
    -----------------------------------------------------------------------------------------------
    i_axis_master : entity work.odma_tb_axis_master
        generic map (
            InstanceIdx_g => 0,
            DataWidth_g   => S2mmStreamWidth_g
        )
        port map (
            Clk       => Clk,
            Out_Data  => V_Data,
            Out_User  => open,
            Out_Keep  => V_Keep,
            Out_Last  => V_Last,
            Out_Valid => V_Valid,
            Out_Ready => V_Ready
        );

    S2mm_Data  <= P_Data when PeerSel = '1' else V_Data;
    S2mm_Keep  <= P_Keep when PeerSel = '1' else V_Keep;
    S2mm_Last  <= P_Last when PeerSel = '1' else V_Last;
    S2mm_Valid <= P_Valid when PeerSel = '1' else V_Valid;
    V_Ready    <= S2mm_Ready and not PeerSel;

    -- Stream peer: one packet of PeerBytes bytes (odmaMemByte of the byte index, seed 9); like a peer
    -- connected to S2mm_RstOut it abandons the packet when the reset output rises
    p_peer : process is
        constant Bytes_c : positive := S2mmStreamWidth_g / 8;
        variable Sent_v  : natural;
    begin
        wait until PeerBytes /= 0;
        wait until rising_edge(Clk);
        PeerSel        <= '1';
        Obs_i.PeerDone <= false;
        Sent_v         := 0;

        while Sent_v < PeerBytes and S2mmRstOut_i = '0' loop

            for i in 0 to Bytes_c - 1 loop
                P_Data(8 * i + 7 downto 8 * i) <= odmaMemByte(to_unsigned(Sent_v + i, 64), 9);
                P_Keep(i)                      <= '1' when Sent_v + i < PeerBytes else '0';
            end loop;

            P_Last  <= '1' when Sent_v + Bytes_c >= PeerBytes else '0';
            P_Valid <= '1';
            wait until rising_edge(Clk) and ((P_Valid = '1' and S2mm_Ready = '1') or S2mmRstOut_i = '1');
            if S2mm_Ready = '1' then
                Sent_v := Sent_v + Bytes_c;
            end if;
        end loop;

        P_Valid        <= '0';
        P_Last         <= '0';
        PeerSel        <= '0';
        Obs_i.PeerDone <= true;
        wait until PeerBytes = 0;
    end process;

    i_axis_slave : entity work.odma_tb_axis_slave
        generic map (
            InstanceIdx_g => 1,
            DataWidth_g   => Mm2sStreamWidth_g
        )
        port map (
            Clk      => Clk,
            In_Data  => Mm2s_Data,
            In_Keep  => Mm2s_Keep,
            In_Last  => Mm2s_Last,
            In_Valid => Mm2s_Valid,
            In_Ready => Mm2s_Ready
        );

    -----------------------------------------------------------------------------------------------
    -- Monitor of the AXI4 transactions
    -----------------------------------------------------------------------------------------------
    p_obs : process (Clk) is
        variable RBeat_v : boolean;
        variable WBeat_v : boolean;
    begin
        if rising_edge(Clk) then
            if Rd_ArValid = '1' and Rd_ArReady = '1' then
                Obs_i.ArBursts <= Obs_i.ArBursts + 1;
            end if;
            RBeat_v := Rd_RValid = '1' and Rd_RReady = '1';
            if RBeat_v and Rd_RLast = '1' then
                Obs_i.RBursts <= Obs_i.RBursts + 1;
            end if;
            if Wr_AwValid = '1' and Wr_AwReady = '1' then
                Obs_i.AwBursts <= Obs_i.AwBursts + 1;
            end if;
            WBeat_v := Wr_WValid = '1' and Wr_WReady = '1';
            if Wr_BValid = '1' and Wr_BReady = '1' then
                Obs_i.BResps <= Obs_i.BResps + 1;
            end if;
            if RBeat_v and WBeat_v then
                Obs_i.Overlap <= true;
            end if;
            if S2mm_Valid = '1' and S2mm_Ready = '1' and S2mmRstOut_i = '1' then
                Obs_i.RstBeats <= Obs_i.RstBeats + 1;
            end if;
        end if;
    end process;

    Obs <= Obs_i;

    -----------------------------------------------------------------------------------------------
    -- Idle values of the ports of a channel that is not included (CO-CF-03), checked in every cycle after
    -- the reset
    -----------------------------------------------------------------------------------------------
    p_idle : process (Clk) is
        variable Mm2sReported_v : boolean := false;
        variable S2mmReported_v : boolean := false;
    begin
        if rising_edge(Clk) then
            if not IncludeMm2s_g and not Mm2sReported_v and Rst = '0' then
                if Rd_ArValid /= '0' or Rd_RReady /= '0' or Mm2s_Valid /= '0' or Mm2sIrq_i /= '0' or
                   unsigned(Rd_ArAddr) /= 0 or Rd_ArLen /= x"00" or Rd_ArSize /= "000" or Rd_ArBurst /= "01" or
                   Rd_ArLock /= '0' or Rd_ArCache /= "0011" or Rd_ArProt /= "000" or unsigned(Mm2s_Data) /= 0 or
                   unsigned(Mm2s_Keep) /= 0 or Mm2s_Last /= '0' then
                    alert(ERROR, "a port of the MM2S channel, which is not included, left its idle value", "odma_core_th");
                    Mm2sReported_v := true;
                end if;
            end if;
            if not IncludeS2mm_g and not S2mmReported_v and Rst = '0' then
                if Wr_AwValid /= '0' or Wr_WValid /= '0' or Wr_BReady /= '0' or S2mm_Ready /= '0' or
                   S2mmIrq_i /= '0' or unsigned(Wr_AwAddr) /= 0 or Wr_AwLen /= x"00" or Wr_AwSize /= "000" or
                   Wr_AwBurst /= "01" or Wr_AwLock /= '0' or Wr_AwCache /= "0011" or Wr_AwProt /= "000" or
                   unsigned(Wr_WData) /= 0 or unsigned(Wr_WStrb) /= 0 or Wr_WLast /= '0' then
                    alert(ERROR, "a port of the S2MM channel, which is not included, left its idle value", "odma_core_th");
                    S2mmReported_v := true;
                end if;
            end if;
        end if;
    end process;

end architecture;
