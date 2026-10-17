---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of odma_registers: the DUT, the AXI4-Lite VVC on the register port and a model of
-- each channel on the command, result and control ports.
--
-- Documentation: hdl/odma_registers/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library work;
    use work.odma_pkg.all;
    use work.odma_registers_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_registers_th is
    generic (
        AddrWidth_g   : positive;
        LengthWidth_g : positive;
        IncludeMm2s_g : boolean;
        IncludeS2mm_g : boolean;
        ExtRegs_g     : boolean;
        IncludeSg_g   : boolean := false
    );
    port (
        Clk         : out   std_logic;
        HardRst     : in    std_logic;
        Cfg         : in    ChanCfg_a;
        Sg          : in    SgDrive_a := (others => SgDriveIdle_c);
        EccSec      : in    std_logic_vector(15 downto 0);      -- SEC and DED pulses of the FT buffers
        EccDed      : in    std_logic_vector(15 downto 0);
        EccSecOnB   : in    std_logic_vector(15 downto 0);      -- Pulses in the clock cycle in which BValid rises
        EccDedOnB   : in    std_logic_vector(15 downto 0);
        Obs         : out   Obs_r;
        Run         : out   std_logic_vector(0 to 1);
        Drain       : out   std_logic_vector(0 to 1);
        Stopped     : out   std_logic_vector(0 to 1);           -- Of the channel models
        Irq         : out   std_logic_vector(0 to 1);
        RstOut      : out   std_logic_vector(0 to 1);
        CoreRst     : out   std_logic;
        EccIrq      : out   std_logic;
        EccInjValid : out   std_logic_vector(15 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_registers_th is

    signal Clk_i : std_logic := '0';
    signal PoRst : std_logic := '1';
    signal Rst   : std_logic;

    -- Register port
    signal ArAddr  : std_logic_vector(9 downto 0);
    signal ArValid : std_logic;
    signal ArReady : std_logic;
    signal AwAddr  : std_logic_vector(9 downto 0);
    signal AwValid : std_logic;
    signal AwReady : std_logic;
    signal WData   : std_logic_vector(31 downto 0);
    signal WStrb   : std_logic_vector(3 downto 0);
    signal WValid  : std_logic;
    signal WReady  : std_logic;
    signal BResp   : std_logic_vector(1 downto 0);
    signal BValid  : std_logic;
    signal BReady  : std_logic;
    signal RData   : std_logic_vector(31 downto 0);
    signal RResp   : std_logic_vector(1 downto 0);
    signal RValid  : std_logic;
    signal RReady  : std_logic;

    -- Channel ports of the DUT
    signal Mm2sCmd_Addr   : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal Mm2sCmd_Length : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal Mm2sCmd_Sof    : std_logic;
    signal Mm2sCmd_Eof    : std_logic;
    signal S2mmCmd_Addr   : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal S2mmCmd_Length : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal CmdValid       : std_logic_vector(0 to 1);
    signal CmdReady       : std_logic_vector(0 to 1);
    signal CmdKeyhole     : std_logic_vector(0 to 1);
    signal ResValid       : std_logic_vector(0 to 1)                     := "00";
    signal ResReady       : std_logic_vector(0 to 1);
    signal Mm2sRes_Bytes  : std_logic_vector(LengthWidth_g - 1 downto 0) := (others => '0');
    signal S2mmRes_Bytes  : std_logic_vector(LengthWidth_g - 1 downto 0) := (others => '0');
    signal ResEof         : std_logic_vector(0 to 1)                     := "00";
    signal Mm2sRes_Err    : XferErr_t                                    := ErrNone_c;
    signal S2mmRes_Err    : XferErr_t                                    := ErrNone_c;
    signal Run_i          : std_logic_vector(0 to 1);
    signal Drain_i        : std_logic_vector(0 to 1);
    signal Stopped_i      : std_logic_vector(0 to 1);
    signal Irq_i          : std_logic_vector(0 to 1);
    signal RstOut_i       : std_logic_vector(0 to 1);
    signal CoreRst_i      : std_logic;
    signal EccSecIn       : std_logic_vector(15 downto 0);
    signal EccDedIn       : std_logic_vector(15 downto 0);
    signal EccInjValid_i  : std_logic_vector(15 downto 0);
    signal EccInjDouble   : std_logic;
    signal EccInjData     : std_logic;
    signal StoppedDut     : std_logic_vector(0 to 1);

    -- Scatter/Gather engine ports of the DUT
    type SgAddr_a is array (0 to 1) of std_logic_vector(AddrWidth_g - 1 downto 0);
    type SgErr_a is array (0 to 1) of XferErr_t;

    signal SgCurDesc  : SgAddr_a;
    signal SgTail     : SgAddr_a;
    signal SgTailWr   : std_logic_vector(0 to 1);
    signal SgCyclic   : std_logic_vector(0 to 1);
    signal SgKeyhole  : std_logic_vector(0 to 1);
    signal SgCurPtr   : SgAddr_a;
    signal SgIdle     : std_logic_vector(0 to 1);
    signal SgPkt      : std_logic_vector(0 to 1);
    signal SgErrValid : std_logic_vector(0 to 1);
    signal SgErrXfer  : SgErr_a;
    signal SgErrSg    : SgErr_a;
    signal SgPktStart : std_logic_vector(0 to 1);
    signal IrqPrev    : std_logic_vector(0 to 1) := "00";

    -- Channel models
    signal M_Busy    : std_logic_vector(0 to 1) := "00";
    signal M_Wait    : Nat_a                    := (others => 0);
    signal M_Len     : Nat_a                    := (others => 0);
    signal M_ResCnt  : Nat_a                    := (others => 0);
    signal M_ResCntA : std_logic_vector(0 to 1) := "00";   -- The result countdown runs
    signal M_ArmAw   : std_logic_vector(0 to 1) := "00";   -- Waiting for the next AW handshake
    signal M_StopCnt : Nat_a                    := (others => 0);
    signal RunPrev   : std_logic_vector(0 to 1) := "00";
    signal DrainPrev : std_logic_vector(0 to 1) := "00";
    signal StopStart : std_logic_vector(0 to 1);
    signal RunFall   : std_logic_vector(0 to 1);
    signal DrainRise : std_logic_vector(0 to 1);
    signal StopPrev  : std_logic_vector(0 to 1) := "11";
    signal BPrev     : std_logic                := '0';
    signal RPrev     : std_logic                := '0';
    signal CorePrev  : std_logic                := '0';
    signal RstOutCnt : natural                  := 0;
    signal Obs_i     : Obs_r                    := (
                                                     CmdCount     => (others => 0),
                                                     CmdAddr      => (others => (others => '0')),
                                                     CmdLength    => (others => 0),
                                                     CmdSof       => '0',
                                                    CmdEof       => '0',
                                                    CmdKeyhole   => "00",
                                                    ResCount     => (others => 0),
                                                     ResCycle     => (others => 0),
                                                     Cycle        => 0,
                                                    AwCycle      => 0,
                                                    BValidCycle  => 0,
                                                    ArCycle      => 0,
                                                    RValidCycle  => 0,
                                                    DrainCycle   => 0,
                                                    CoreRstCycle => 0,
                                                    CoreRstEarly => 0,
                                                    RstOutLen    => 0,
                                                    RstOutDiffer => 0,
                                                    InjCount     => 0,
                                                    InjIdx       => 0,
                                                    InjDouble    => '0',
                                                    InjData      => '0',
                                                    InjMode      => '0',
                                                    InjMulti     => 0,
                                                    SgCurDesc    => (others => (others => '0')),
                                                     SgStartPtr   => (others => (others => '0')),
                                                     SgTail       => (others => (others => '0')),
                                                     SgTailWr     => (others => 0),
                                                     SgCyclic     => "00",
                                                    SgKeyhole    => "00",
                                                    IrqRiseCycle => (others => 0),
                                                     PktCycle     => (others => 0),
                                                     SgCurDiffer  => (others => 0)
                                                 );

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk_i <= not Clk_i after ClkPeriod_c / 2;
    PoRst <= '1', '0' after 10 * ClkPeriod_c;
    Rst   <= PoRst or HardRst;
    Clk   <= Clk_i;

    -----------------------------------------------------------------------------------------------
    -- DUT
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.odma_registers
        generic map (
            IncludeSg_g       => IncludeSg_g,
            IncludeMm2s_g     => IncludeMm2s_g,
            IncludeS2mm_g     => IncludeS2mm_g,
            StsCntrlStrm_g    => StsCntrlStrm_c,
            UseRxLength_g     => UseRxLength_c,
            MicroDma_g        => MicroDma_c,
            LengthWidth_g     => LengthWidth_g,
            AddrWidth_g       => AddrWidth_g,
            Mm2sMemWidth_g    => Mm2sMemWidth_c,
            Mm2sStreamWidth_g => Mm2sStreamWidth_c,
            Mm2sBurstBeats_g  => Mm2sBurstBeats_c,
            Mm2sBufferBeats_g => Mm2sBufferBeats_c,
            S2mmMemWidth_g    => S2mmMemWidth_c,
            S2mmStreamWidth_g => S2mmStreamWidth_c,
            S2mmBurstBeats_g  => S2mmBurstBeats_c,
            S2mmBufferBeats_g => S2mmBufferBeats_c,
            ExtRegs_g         => ExtRegs_g
        )
        port map (
            Clk               => Clk_i,
            Rst               => Rst,
            CoreRst           => CoreRst_i,
            S_AxiLite_ArAddr  => ArAddr,
            S_AxiLite_ArValid => ArValid,
            S_AxiLite_ArReady => ArReady,
            S_AxiLite_AwAddr  => AwAddr,
            S_AxiLite_AwValid => AwValid,
            S_AxiLite_AwReady => AwReady,
            S_AxiLite_WData   => WData,
            S_AxiLite_WStrb   => WStrb,
            S_AxiLite_WValid  => WValid,
            S_AxiLite_WReady  => WReady,
            S_AxiLite_BResp   => BResp,
            S_AxiLite_BValid  => BValid,
            S_AxiLite_BReady  => BReady,
            S_AxiLite_RData   => RData,
            S_AxiLite_RResp   => RResp,
            S_AxiLite_RValid  => RValid,
            S_AxiLite_RReady  => RReady,
            Mm2sCmd_Valid     => CmdValid(Mm2s_c),
            Mm2sCmd_Ready     => CmdReady(Mm2s_c),
            Mm2sCmd_Addr      => Mm2sCmd_Addr,
            Mm2sCmd_Length    => Mm2sCmd_Length,
            Mm2sCmd_Sof       => Mm2sCmd_Sof,
            Mm2sCmd_Eof       => Mm2sCmd_Eof,
            Mm2sCmd_Keyhole   => CmdKeyhole(Mm2s_c),
            Mm2sRes_Valid     => ResValid(Mm2s_c),
            Mm2sRes_Ready     => ResReady(Mm2s_c),
            Mm2sRes_Bytes     => Mm2sRes_Bytes,
            Mm2sRes_Eof       => ResEof(Mm2s_c),
            Mm2sRes_Err       => Mm2sRes_Err,
            Mm2s_Run          => Run_i(Mm2s_c),
            Mm2s_Drain        => Drain_i(Mm2s_c),
            Mm2s_Stopped      => StoppedDut(Mm2s_c),
            S2mmCmd_Valid     => CmdValid(S2mm_c),
            S2mmCmd_Ready     => CmdReady(S2mm_c),
            S2mmCmd_Addr      => S2mmCmd_Addr,
            S2mmCmd_Length    => S2mmCmd_Length,
            S2mmCmd_Keyhole   => CmdKeyhole(S2mm_c),
            S2mmRes_Valid     => ResValid(S2mm_c),
            S2mmRes_Ready     => ResReady(S2mm_c),
            S2mmRes_Bytes     => S2mmRes_Bytes,
            S2mmRes_Eof       => ResEof(S2mm_c),
            S2mmRes_Err       => S2mmRes_Err,
            S2mm_Run          => Run_i(S2mm_c),
            S2mm_Drain        => Drain_i(S2mm_c),
            S2mm_Stopped      => StoppedDut(S2mm_c),
            Mm2sSg_CurDesc    => SgCurDesc(Mm2s_c),
            Mm2sSg_Tail       => SgTail(Mm2s_c),
            Mm2sSg_TailWr     => SgTailWr(Mm2s_c),
            Mm2sSg_Cyclic     => SgCyclic(Mm2s_c),
            Mm2sSg_Keyhole    => SgKeyhole(Mm2s_c),
            Mm2sSg_CurPtr     => SgCurPtr(Mm2s_c),
            Mm2sSg_Idle       => SgIdle(Mm2s_c),
            Mm2sSg_Pkt        => SgPkt(Mm2s_c),
            Mm2sSg_ErrValid   => SgErrValid(Mm2s_c),
            Mm2sSg_ErrXfer    => SgErrXfer(Mm2s_c),
            Mm2sSg_ErrSg      => SgErrSg(Mm2s_c),
            Mm2s_PktStart     => SgPktStart(Mm2s_c),
            S2mmSg_CurDesc    => SgCurDesc(S2mm_c),
            S2mmSg_Tail       => SgTail(S2mm_c),
            S2mmSg_TailWr     => SgTailWr(S2mm_c),
            S2mmSg_Cyclic     => SgCyclic(S2mm_c),
            S2mmSg_Keyhole    => SgKeyhole(S2mm_c),
            S2mmSg_CurPtr     => SgCurPtr(S2mm_c),
            S2mmSg_Idle       => SgIdle(S2mm_c),
            S2mmSg_Pkt        => SgPkt(S2mm_c),
            S2mmSg_ErrValid   => SgErrValid(S2mm_c),
            S2mmSg_ErrXfer    => SgErrXfer(S2mm_c),
            S2mmSg_ErrSg      => SgErrSg(S2mm_c),
            S2mm_PktStart     => SgPktStart(S2mm_c),
            Mm2s_Irq          => Irq_i(Mm2s_c),
            S2mm_Irq          => Irq_i(S2mm_c),
            Ecc_Irq           => EccIrq,
            Mm2s_RstOut       => RstOut_i(Mm2s_c),
            S2mm_RstOut       => RstOut_i(S2mm_c),
            Ecc_Sec           => EccSecIn,
            Ecc_Ded           => EccDedIn,
            EccInj_Valid      => EccInjValid_i,
            EccInj_Double     => EccInjDouble,
            EccInj_Data       => EccInjData
        );

    Run         <= Run_i;
    Drain       <= Drain_i;
    Stopped     <= Stopped_i;
    Irq         <= Irq_i;
    RstOut      <= RstOut_i;
    CoreRst     <= CoreRst_i;
    EccInjValid <= EccInjValid_i;
    Obs         <= Obs_i;

    -- Model of the Scatter/Gather engines: the testbench drives its signals; with Scatter/Gather Mode the DUT sees
    -- the channel and its engine stopped only when both are (as the core combines them)
    g_sg : for ch in 0 to 1 generate
        SgCurPtr(ch)   <= Sg(ch).CurPtr(AddrWidth_g - 1 downto 0);
        SgIdle(ch)     <= Sg(ch).Idle;
        SgPkt(ch)      <= Sg(ch).Pkt;
        SgErrValid(ch) <= Sg(ch).ErrValid;
        SgErrXfer(ch)  <= Sg(ch).ErrXfer;
        SgErrSg(ch)    <= Sg(ch).ErrSg;
        SgPktStart(ch) <= Sg(ch).PktStart;
        StoppedDut(ch) <= Stopped_i(ch) and Sg(ch).Stopped when IncludeSg_g else Stopped_i(ch);
    end generate;

    -- ECC events, optionally in the clock cycle in which a register write takes effect
    EccSecIn <= EccSec or EccSecOnB when BValid = '1' and BPrev = '0' else EccSec;
    EccDedIn <= EccDed or EccDedOnB when BValid = '1' and BPrev = '0' else EccDed;

    -----------------------------------------------------------------------------------------------
    -- Register port
    -----------------------------------------------------------------------------------------------
    i_axilite : entity work.odma_tb_axilite_master
        generic map (
            InstanceIdx_g => 0,
            AddrWidth_g   => 10
        )
        port map (
            Clk     => Clk_i,
            ArAddr  => ArAddr,
            ArValid => ArValid,
            ArReady => ArReady,
            AwAddr  => AwAddr,
            AwValid => AwValid,
            AwReady => AwReady,
            WData   => WData,
            WStrb   => WStrb,
            WValid  => WValid,
            WReady  => WReady,
            BResp   => BResp,
            BValid  => BValid,
            BReady  => BReady,
            RData   => RData,
            RResp   => RResp,
            RValid  => RValid,
            RReady  => RReady
        );

    -----------------------------------------------------------------------------------------------
    -- Channel models
    -----------------------------------------------------------------------------------------------
    g_ch : for ch in 0 to 1 generate
        -- The command is accepted while the channel may run, after CmdDelay clock cycles
        CmdReady(ch) <= '1' when Run_i(ch) = '1' and Drain_i(ch) = '0' and M_Busy(ch) = '0' and
                                 M_Wait(ch) >= Cfg(ch).CmdDelay else
                        '0';
        -- Stopped falls with Run or Drain for DrainTime clock cycles and while a transfer is accepted
        RunFall(ch)   <= RunPrev(ch) and not Run_i(ch);
        DrainRise(ch) <= Drain_i(ch) and not DrainPrev(ch);
        StopStart(ch) <= '1' when Cfg(ch).DrainTime > 0 and (RunFall(ch) = '1' or DrainRise(ch) = '1') else '0';
        Stopped_i(ch) <= '0' when M_Busy(ch) = '1' or M_StopCnt(ch) > 0 or StopStart(ch) = '1' else '1';
    end generate;

    p_model : process (Clk_i) is
        variable O_v     : Obs_r;
        variable Addr_v  : std_logic_vector(AddrWidth_g - 1 downto 0);
        variable Len_v   : std_logic_vector(LengthWidth_g - 1 downto 0);
        variable Bytes_v : natural;
        variable Strb_v  : natural;
        variable AwHs_v  : boolean;
    begin
        if rising_edge(Clk_i) then
            O_v    := Obs_i;
            AwHs_v := AwValid = '1' and AwReady = '1';

            -- Register port
            BPrev <= BValid;
            if BValid = '1' and BPrev = '0' then
                O_v.BValidCycle := Obs_i.Cycle;
            end if;
            if AwHs_v then
                O_v.AwCycle := Obs_i.Cycle;
            end if;
            RPrev <= RValid;
            if RValid = '1' and RPrev = '0' then
                O_v.RValidCycle := Obs_i.Cycle;
            end if;
            if ArValid = '1' and ArReady = '1' then
                O_v.ArCycle := Obs_i.Cycle;
            end if;

            for ch in 0 to 1 loop
                -- Command
                if ch = Mm2s_c then
                    Addr_v := Mm2sCmd_Addr;
                    Len_v  := Mm2sCmd_Length;
                else
                    Addr_v := S2mmCmd_Addr;
                    Len_v  := S2mmCmd_Length;
                end if;
                if CmdValid(ch) = '1' and CmdReady(ch) = '1' then
                    O_v.CmdCount(ch)                          := Obs_i.CmdCount(ch) + 1;
                    O_v.CmdAddr(ch)                           := (others => '0');
                    O_v.CmdAddr(ch)(AddrWidth_g - 1 downto 0) := Addr_v;
                    O_v.CmdLength(ch)                         := to_integer(unsigned(Len_v));
                    O_v.CmdKeyhole(ch)                        := CmdKeyhole(ch);
                    if ch = Mm2s_c then
                        O_v.CmdSof := Mm2sCmd_Sof;
                        O_v.CmdEof := Mm2sCmd_Eof;
                    end if;
                    M_Busy(ch) <= '1';
                    M_Len(ch)  <= to_integer(unsigned(Len_v));
                    M_Wait(ch) <= 0;
                    if Cfg(ch).ResDelay >= 0 then
                        M_ResCnt(ch)  <= Cfg(ch).ResDelay;
                        M_ResCntA(ch) <= '1';
                    else
                        M_ArmAw(ch) <= '1';
                    end if;
                elsif CmdValid(ch) = '1' then
                    M_Wait(ch) <= M_Wait(ch) + 1;
                else
                    M_Wait(ch) <= 0;
                end if;

                -- Result after the delay or after the next AW handshake
                if M_ArmAw(ch) = '1' and AwHs_v then
                    M_ArmAw(ch) <= '0';
                    if Cfg(ch).ResAfterAw = 1 then
                        ResValid(ch) <= '1';
                    else
                        M_ResCnt(ch)  <= Cfg(ch).ResAfterAw - 2;
                        M_ResCntA(ch) <= '1';
                    end if;
                elsif M_ResCntA(ch) = '1' then
                    if M_ResCnt(ch) = 0 then
                        M_ResCntA(ch) <= '0';
                        ResValid(ch)  <= '1';
                    else
                        M_ResCnt(ch) <= M_ResCnt(ch) - 1;
                    end if;
                end if;
                if Cfg(ch).ResBytes >= 0 then
                    Bytes_v := Cfg(ch).ResBytes;
                else
                    Bytes_v := M_Len(ch);
                end if;
                if ch = Mm2s_c then
                    Mm2sRes_Bytes <= std_logic_vector(to_unsigned(Bytes_v, LengthWidth_g));
                    Mm2sRes_Err   <= Cfg(ch).ResErr;
                else
                    S2mmRes_Bytes <= std_logic_vector(to_unsigned(Bytes_v, LengthWidth_g));
                    S2mmRes_Err   <= Cfg(ch).ResErr;
                end if;
                ResEof(ch) <= Cfg(ch).ResEof;

                if ResValid(ch) = '1' and ResReady(ch) = '1' then
                    ResValid(ch)     <= '0';
                    M_Busy(ch)       <= '0';
                    O_v.ResCount(ch) := Obs_i.ResCount(ch) + 1;
                    O_v.ResCycle(ch) := Obs_i.Cycle;
                end if;

                -- Scatter/Gather engine outputs of the DUT
                O_v.SgCurDesc(ch)                           := (others => '0');
                O_v.SgCurDesc(ch)(AddrWidth_g - 1 downto 0) := SgCurDesc(ch);
                if Run_i(ch) = '1' and RunPrev(ch) = '0' then
                    O_v.SgStartPtr(ch)                           := (others => '0');
                    O_v.SgStartPtr(ch)(AddrWidth_g - 1 downto 0) := SgCurDesc(ch);
                end if;
                if SgTailWr(ch) = '1' then
                    O_v.SgTailWr(ch)                         := Obs_i.SgTailWr(ch) + 1;
                    O_v.SgTail(ch)                           := (others => '0');
                    O_v.SgTail(ch)(AddrWidth_g - 1 downto 0) := SgTail(ch);
                end if;
                O_v.SgCyclic(ch)  := SgCyclic(ch);
                O_v.SgKeyhole(ch) := SgKeyhole(ch);
                IrqPrev(ch)       <= Irq_i(ch);
                if Irq_i(ch) = '1' and IrqPrev(ch) = '0' then
                    O_v.IrqRiseCycle(ch) := Obs_i.Cycle;
                end if;
                if Sg(ch).Pkt = '1' then
                    O_v.PktCycle(ch) := Obs_i.Cycle;
                end if;
                if IncludeSg_g and Run_i(ch) = '1' and RunPrev(ch) = '1' and SgCurDesc(ch) /= SgCurPtr(ch) then
                    O_v.SgCurDiffer(ch) := Obs_i.SgCurDiffer(ch) + 1;
                end if;

                -- Stop timer
                RunPrev(ch)   <= Run_i(ch);
                DrainPrev(ch) <= Drain_i(ch);
                StopPrev(ch)  <= Stopped_i(ch);
                if StopStart(ch) = '1' then
                    M_StopCnt(ch) <= Cfg(ch).DrainTime - 1;
                elsif M_StopCnt(ch) > 0 then
                    M_StopCnt(ch) <= M_StopCnt(ch) - 1;
                end if;

                -- A drain ends the transfer without a result, the core reset resets the model
                if Drain_i(ch) = '1' or CoreRst_i = '1' then
                    M_Busy(ch)    <= '0';
                    M_ArmAw(ch)   <= '0';
                    M_ResCntA(ch) <= '0';
                    ResValid(ch)  <= '0';
                end if;
                if CoreRst_i = '1' then
                    M_StopCnt(ch) <= 0;
                end if;
            end loop;

            -- Soft reset and reset outputs
            if (Drain_i(Mm2s_c) = '1' and DrainPrev(Mm2s_c) = '0') or (Drain_i(S2mm_c) = '1' and DrainPrev(S2mm_c) = '0') then
                O_v.DrainCycle := Obs_i.Cycle;
            end if;
            CorePrev <= CoreRst_i;
            if CoreRst_i = '1' and CorePrev = '0' then
                O_v.CoreRstCycle := Obs_i.Cycle;
                if Rst = '0' and StopPrev /= "11" then
                    O_v.CoreRstEarly := Obs_i.CoreRstEarly + 1;
                end if;
            end if;
            if RstOut_i(Mm2s_c) /= RstOut_i(S2mm_c) then
                O_v.RstOutDiffer := Obs_i.RstOutDiffer + 1;
            end if;
            if RstOut_i(Mm2s_c) = '1' then
                RstOutCnt <= RstOutCnt + 1;
            elsif RstOutCnt > 0 then
                O_v.RstOutLen := RstOutCnt;
                RstOutCnt     <= 0;
            end if;

            -- Error injection strobes
            Strb_v := 0;

            for i in 0 to 15 loop
                if EccInjValid_i(i) = '1' then
                    Strb_v        := Strb_v + 1;
                    O_v.InjIdx    := i;
                    O_v.InjDouble := EccInjDouble;
                    O_v.InjData   := EccInjData;
                end if;
            end loop;

            if Strb_v > 0 then
                O_v.InjCount := Obs_i.InjCount + 1;
            end if;
            if Strb_v > 1 then
                O_v.InjMulti := Obs_i.InjMulti + 1;
            end if;

            O_v.InjMode := EccInjData;
            O_v.Cycle   := Obs_i.Cycle + 1;
            Obs_i       <= O_v;
        end if;
    end process;

end architecture;
