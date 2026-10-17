---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of odma_sg: clock, the DUT, the AXI memory model on the descriptor port, a model of
-- each channel on the command and result interfaces, and the monitors that record the commands,
-- the bursts and write beats of the descriptor port, the events and the ECC pulses.
--
-- Documentation: hdl/odma_sg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.odma_pkg.all;
    use work.odma_sg_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_sg_th is
    generic (
        AddrWidth_g   : positive;
        LengthWidth_g : positive;
        IncludeMm2s_g : boolean;
        IncludeS2mm_g : boolean
    );
    port (
        Clk          : out   std_logic;
        Rst          : in    std_logic;
        Reg          : in    RegDrive_a;
        Cfg          : in    ChanCfg_a;
        EccInjValid  : in    std_logic_vector(3 downto 0);
        EccInjDouble : in    std_logic;
        EccInjData   : in    std_logic;
        Obs          : out   Obs_r
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_sg_th is

    signal Clk_i : std_logic := '0';

    -- Register side of the DUT
    type Ptr_a is array (0 to 1) of std_logic_vector(AddrWidth_g - 1 downto 0);
    type Err_a is array (0 to 1) of XferErr_t;
    type Len_a is array (0 to 1) of std_logic_vector(LengthWidth_g - 1 downto 0);

    signal CurDesc  : Ptr_a;
    signal Tail     : Ptr_a;
    signal CurPtr   : Ptr_a;
    signal Idle     : std_logic_vector(0 to 1);
    signal Stopped  : std_logic_vector(0 to 1);
    signal Pkt      : std_logic_vector(0 to 1);
    signal ErrValid : std_logic_vector(0 to 1);
    signal ErrXfer  : Err_a;
    signal ErrSg    : Err_a;

    -- Command and result interfaces
    signal CmdValid   : std_logic_vector(0 to 1);
    signal CmdReady   : std_logic_vector(0 to 1);
    signal CmdAddr    : Ptr_a;
    signal CmdLength  : Len_a;
    signal CmdSof     : std_logic;
    signal CmdEof     : std_logic;
    signal CmdKeyhole : std_logic_vector(0 to 1);
    signal ResValid   : std_logic_vector(0 to 1) := "00";
    signal ResReady   : std_logic_vector(0 to 1);
    signal ResBytes   : Len_a                    := (others => (others => '0'));
    signal ResSof     : std_logic                := '0';
    signal ResEof     : std_logic_vector(0 to 1) := "00";
    signal ResErr     : Err_a                    := (others => ErrNone_c);

    -- Descriptor port
    signal AwAddr  : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal AwLen   : std_logic_vector(7 downto 0);
    signal AwSize  : std_logic_vector(2 downto 0);
    signal AwBurst : std_logic_vector(1 downto 0);
    signal AwLock  : std_logic;
    signal AwCache : std_logic_vector(3 downto 0);
    signal AwProt  : std_logic_vector(2 downto 0);
    signal AwValid : std_logic;
    signal AwReady : std_logic;
    signal WData   : std_logic_vector(31 downto 0);
    signal WStrb   : std_logic_vector(3 downto 0);
    signal WLast   : std_logic;
    signal WValid  : std_logic;
    signal WReady  : std_logic;
    signal BResp   : std_logic_vector(1 downto 0);
    signal BValid  : std_logic;
    signal BReady  : std_logic;
    signal ArAddr  : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal ArLen   : std_logic_vector(7 downto 0);
    signal ArSize  : std_logic_vector(2 downto 0);
    signal ArBurst : std_logic_vector(1 downto 0);
    signal ArLock  : std_logic;
    signal ArCache : std_logic_vector(3 downto 0);
    signal ArProt  : std_logic_vector(2 downto 0);
    signal ArValid : std_logic;
    signal ArReady : std_logic;
    signal RData   : std_logic_vector(31 downto 0);
    signal RResp   : std_logic_vector(1 downto 0);
    signal RLast   : std_logic;
    signal RValid  : std_logic;
    signal RReady  : std_logic;
    signal EccSec  : std_logic_vector(3 downto 0);
    signal EccDed  : std_logic_vector(3 downto 0);

    -- Channel models: queue of the accepted commands without result
    type Queue_t is array (0 to 7) of natural;          -- command numbers
    type Queue_a is array (0 to 1) of Queue_t;

    signal Q       : Queue_a                  := (others => (others => 0));
    signal QCnt    : Nat_a                    := (others => 0);
    signal Wait_i  : Nat_a                    := (others => 0);
    signal Delay_i : Nat_a                    := (others => 0);
    signal RunPrev : std_logic_vector(0 to 1) := "00";
    signal Halting : std_logic_vector(0 to 1) := "00";

    signal Obs_i : Obs_r;

    -- A vector as a natural
    function len (v : std_logic_vector) return natural is
    begin
        return to_integer(unsigned(v));
    end function;

    -- Commands a channel model accepts without result: MM2S MaxCmds, S2MM one
    function maxQueue (
        ch  : natural;
        cfg : ChanCfg_r) return natural is
    begin
        if ch = Mm2s_c then
            return cfg.MaxCmds;
        end if;
        return 1;
    end function;

begin

    Clk_i <= not Clk_i after ClkPeriod_c / 2;
    Clk   <= Clk_i;
    Obs   <= Obs_i;

    g_reg : for ch in 0 to 1 generate
        CurDesc(ch) <= Reg(ch).CurDesc(AddrWidth_g - 1 downto 0);
        Tail(ch)    <= Reg(ch).Tail(AddrWidth_g - 1 downto 0);
    end generate;

    -----------------------------------------------------------------------------------------------
    -- DUT
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.odma_sg
        generic map (
            IncludeMm2s_g => IncludeMm2s_g,
            IncludeS2mm_g => IncludeS2mm_g,
            AddrWidth_g   => AddrWidth_g,
            LengthWidth_g => LengthWidth_g
        )
        port map (
            Clk             => Clk_i,
            Rst             => Rst,
            Mm2s_Run        => Reg(Mm2s_c).Run,
            Mm2s_Drain      => Reg(Mm2s_c).Drain,
            Mm2s_CurDesc    => CurDesc(Mm2s_c),
            Mm2s_Tail       => Tail(Mm2s_c),
            Mm2s_TailWr     => Reg(Mm2s_c).TailWr,
            Mm2s_Cyclic     => Reg(Mm2s_c).Cyclic,
            Mm2s_Keyhole    => Reg(Mm2s_c).Keyhole,
            Mm2s_CurPtr     => CurPtr(Mm2s_c),
            Mm2s_Idle       => Idle(Mm2s_c),
            Mm2s_Stopped    => Stopped(Mm2s_c),
            Mm2s_Pkt        => Pkt(Mm2s_c),
            Mm2s_ErrValid   => ErrValid(Mm2s_c),
            Mm2s_ErrXfer    => ErrXfer(Mm2s_c),
            Mm2s_ErrSg      => ErrSg(Mm2s_c),
            Mm2sCmd_Valid   => CmdValid(Mm2s_c),
            Mm2sCmd_Ready   => CmdReady(Mm2s_c),
            Mm2sCmd_Addr    => CmdAddr(Mm2s_c),
            Mm2sCmd_Length  => CmdLength(Mm2s_c),
            Mm2sCmd_Sof     => CmdSof,
            Mm2sCmd_Eof     => CmdEof,
            Mm2sCmd_Keyhole => CmdKeyhole(Mm2s_c),
            Mm2sRes_Valid   => ResValid(Mm2s_c),
            Mm2sRes_Ready   => ResReady(Mm2s_c),
            Mm2sRes_Bytes   => ResBytes(Mm2s_c),
            Mm2sRes_Eof     => ResEof(Mm2s_c),
            Mm2sRes_Err     => ResErr(Mm2s_c),
            S2mm_Run        => Reg(S2mm_c).Run,
            S2mm_Drain      => Reg(S2mm_c).Drain,
            S2mm_CurDesc    => CurDesc(S2mm_c),
            S2mm_Tail       => Tail(S2mm_c),
            S2mm_TailWr     => Reg(S2mm_c).TailWr,
            S2mm_Cyclic     => Reg(S2mm_c).Cyclic,
            S2mm_Keyhole    => Reg(S2mm_c).Keyhole,
            S2mm_CurPtr     => CurPtr(S2mm_c),
            S2mm_Idle       => Idle(S2mm_c),
            S2mm_Stopped    => Stopped(S2mm_c),
            S2mm_Pkt        => Pkt(S2mm_c),
            S2mm_ErrValid   => ErrValid(S2mm_c),
            S2mm_ErrXfer    => ErrXfer(S2mm_c),
            S2mm_ErrSg      => ErrSg(S2mm_c),
            S2mmCmd_Valid   => CmdValid(S2mm_c),
            S2mmCmd_Ready   => CmdReady(S2mm_c),
            S2mmCmd_Addr    => CmdAddr(S2mm_c),
            S2mmCmd_Length  => CmdLength(S2mm_c),
            S2mmCmd_Keyhole => CmdKeyhole(S2mm_c),
            S2mmRes_Valid   => ResValid(S2mm_c),
            S2mmRes_Ready   => ResReady(S2mm_c),
            S2mmRes_Bytes   => ResBytes(S2mm_c),
            S2mmRes_Sof     => ResSof,
            S2mmRes_Eof     => ResEof(S2mm_c),
            S2mmRes_Err     => ResErr(S2mm_c),
            M_Axi_AwAddr    => AwAddr,
            M_Axi_AwLen     => AwLen,
            M_Axi_AwSize    => AwSize,
            M_Axi_AwBurst   => AwBurst,
            M_Axi_AwLock    => AwLock,
            M_Axi_AwCache   => AwCache,
            M_Axi_AwProt    => AwProt,
            M_Axi_AwValid   => AwValid,
            M_Axi_AwReady   => AwReady,
            M_Axi_WData     => WData,
            M_Axi_WStrb     => WStrb,
            M_Axi_WLast     => WLast,
            M_Axi_WValid    => WValid,
            M_Axi_WReady    => WReady,
            M_Axi_BResp     => BResp,
            M_Axi_BValid    => BValid,
            M_Axi_BReady    => BReady,
            M_Axi_ArAddr    => ArAddr,
            M_Axi_ArLen     => ArLen,
            M_Axi_ArSize    => ArSize,
            M_Axi_ArBurst   => ArBurst,
            M_Axi_ArLock    => ArLock,
            M_Axi_ArCache   => ArCache,
            M_Axi_ArProt    => ArProt,
            M_Axi_ArValid   => ArValid,
            M_Axi_ArReady   => ArReady,
            M_Axi_RData     => RData,
            M_Axi_RResp     => RResp,
            M_Axi_RLast     => RLast,
            M_Axi_RValid    => RValid,
            M_Axi_RReady    => RReady,
            Ecc_Sec         => EccSec,
            Ecc_Ded         => EccDed,
            EccInj_Valid    => EccInjValid,
            EccInj_Double   => EccInjDouble,
            EccInj_Data     => EccInjData
        );

    -----------------------------------------------------------------------------------------------
    -- Memory of the descriptors
    -----------------------------------------------------------------------------------------------
    i_mem : entity work.odma_tb_axi_ram
        generic map (
            Index_g     => MemSg_c,
            AddrWidth_g => AddrWidth_g,
            DataWidth_g => 32
        )
        port map (
            Clk     => Clk_i,
            Rst     => Rst,
            AwAddr  => AwAddr,
            AwLen   => AwLen,
            AwSize  => AwSize,
            AwBurst => AwBurst,
            AwValid => AwValid,
            AwReady => AwReady,
            WData   => WData,
            WStrb   => WStrb,
            WLast   => WLast,
            WValid  => WValid,
            WReady  => WReady,
            BResp   => BResp,
            BValid  => BValid,
            BReady  => BReady,
            ArAddr  => ArAddr,
            ArLen   => ArLen,
            ArSize  => ArSize,
            ArBurst => ArBurst,
            ArValid => ArValid,
            ArReady => ArReady,
            RData   => RData,
            RResp   => RResp,
            RLast   => RLast,
            RValid  => RValid,
            RReady  => RReady
        );

    -----------------------------------------------------------------------------------------------
    -- Channel models
    -----------------------------------------------------------------------------------------------
    g_ready : for ch in 0 to 1 generate
        -- MM2S: up to MaxCmds commands, S2MM: one at a time; accepted after CmdDelay clock cycles while the
        -- channel runs and does not drain
        CmdReady(ch) <= '1' when Reg(ch).Run = '1' and Reg(ch).Drain = '0' and Halting(ch) = '0' and
                                 Wait_i(ch) >= Cfg(ch).CmdDelay and QCnt(ch) < maxQueue(ch, Cfg(ch)) else
                        '0';
    end generate;

    p_model : process (Clk_i) is
        variable O_v    : Obs_r;
        variable N_v    : natural;
        variable Res_v  : Result_r;
        variable Len_v  : natural;
        variable QCnt_v : natural;
        variable Q_v    : Queue_t;
    begin
        if rising_edge(Clk_i) then
            O_v := Obs_i;

            for ch in 0 to 1 loop
                QCnt_v := QCnt(ch);
                Q_v    := Q(ch);

                -- Delay of the next result (reloaded below)
                if Delay_i(ch) > 0 then
                    Delay_i(ch) <= Delay_i(ch) - 1;
                end if;

                -- Result handshake: the oldest command leaves the queue
                if ResValid(ch) = '1' and ResReady(ch) = '1' then
                    ResValid(ch)     <= '0';
                    O_v.ResCount(ch) := Obs_i.ResCount(ch) + 1;

                    for i in 0 to 6 loop
                        Q_v(i) := Q_v(i + 1);
                    end loop;

                    QCnt_v      := QCnt_v - 1;
                    Delay_i(ch) <= Cfg(ch).ResDelay;
                    if ch = S2mm_c then
                        Halting(ch) <= '0';
                    end if;
                end if;

                -- Command handshake
                if CmdValid(ch) = '1' and CmdReady(ch) = '1' then
                    N_v              := Obs_i.CmdCount(ch);
                    O_v.CmdCount(ch) := N_v + 1;
                    if N_v < LogDepth_c then
                        O_v.Cmds(ch)(N_v).Addr                           := (others => '0');
                        O_v.Cmds(ch)(N_v).Addr(AddrWidth_g - 1 downto 0) := CmdAddr(ch);
                        O_v.Cmds(ch)(N_v).Length                         := len(CmdLength(ch));
                        O_v.Cmds(ch)(N_v).Keyhole                        := CmdKeyhole(ch);
                        O_v.Cmds(ch)(N_v).Cycle                          := Obs_i.Cycle;
                        if ch = Mm2s_c then
                            O_v.Cmds(ch)(N_v).Sof := CmdSof;
                            O_v.Cmds(ch)(N_v).Eof := CmdEof;
                        else
                            O_v.Cmds(ch)(N_v).Sof := '0';
                            O_v.Cmds(ch)(N_v).Eof := '0';
                        end if;
                    end if;
                    Q_v(QCnt_v) := N_v;
                    QCnt_v      := QCnt_v + 1;
                    if QCnt(ch) = 0 then
                        Delay_i(ch) <= Cfg(ch).ResDelay;
                    end if;
                    Wait_i(ch) <= 0;
                elsif CmdValid(ch) = '1' then
                    Wait_i(ch) <= Wait_i(ch) + 1;
                else
                    Wait_i(ch) <= 0;
                end if;
                if QCnt_v > Obs_i.MaxCmds(ch) then
                    O_v.MaxCmds(ch) := QCnt_v;
                end if;

                -- S2MM: Run falls with a command accepted: the transfer ends with HaltBytes bytes
                RunPrev(ch) <= Reg(ch).Run;
                if ch = S2mm_c and RunPrev(ch) = '1' and Reg(ch).Run = '0' and QCnt(ch) > 0 then
                    Halting(ch) <= '1';
                end if;

                -- Result of the oldest command after its delay; a halted S2MM transfer ends also while held
                if QCnt(ch) > 0 and ResValid(ch) = '0' and (Cfg(ch).Hold = '0' or Halting(ch) = '1') and
                   Delay_i(ch) = 0 then
                    N_v   := Q(ch)(0);
                    Len_v := 0;
                    Res_v := ResultDefault_c;
                    if N_v < LogDepth_c then
                        Len_v := Obs_i.Cmds(ch)(N_v).Length;
                        Res_v := Cfg(ch).Results(N_v);
                    end if;
                    if Halting(ch) = '1' then
                        ResBytes(ch) <= std_logic_vector(to_unsigned(Cfg(ch).HaltBytes, LengthWidth_g));
                        ResEof(ch)   <= '0';
                        ResErr(ch)   <= ErrNone_c;
                        if Cfg(ch).HaltBytes > 0 then
                            ResSof <= '1';
                        else
                            ResSof <= '0';
                        end if;
                    elsif Res_v.Valid then
                        if Res_v.Bytes >= 0 then
                            ResBytes(ch) <= std_logic_vector(to_unsigned(Res_v.Bytes, LengthWidth_g));
                        else
                            ResBytes(ch) <= std_logic_vector(to_unsigned(Len_v, LengthWidth_g));
                        end if;
                        ResEof(ch) <= Res_v.Eof;
                        ResErr(ch) <= Res_v.Err;
                        if ch = S2mm_c then
                            ResSof <= Res_v.Sof;
                        end if;
                    elsif Len_v = 0 then
                        -- A buffer length of 0: the internal error without a transfer, as the channels
                        ResBytes(ch) <= (others => '0');
                        ResEof(ch)   <= '0';
                        ResErr(ch)   <= ErrInt_c;
                        if ch = S2mm_c then
                            ResSof <= '0';
                        end if;
                    else
                        ResBytes(ch) <= std_logic_vector(to_unsigned(Len_v, LengthWidth_g));
                        ResErr(ch)   <= ErrNone_c;
                        if ch = Mm2s_c then
                            ResEof(ch) <= Obs_i.Cmds(ch)(N_v).Eof;
                        else
                            ResEof(ch) <= '1';
                            ResSof     <= '1';
                        end if;
                    end if;
                    ResValid(ch) <= '1';
                end if;

                -- A drain ends the commands without results, the reset clears the model
                if Reg(ch).Drain = '1' or Rst = '1' then
                    QCnt_v       := 0;
                    ResValid(ch) <= '0';
                    Halting(ch)  <= '0';
                end if;
                QCnt(ch) <= QCnt_v;
                Q(ch)    <= Q_v;

                -- Events and levels of the DUT
                if Pkt(ch) = '1' then
                    N_v              := Obs_i.PktCount(ch);
                    O_v.PktCount(ch) := N_v + 1;
                    if N_v < LogDepth_c then
                        O_v.PktCycles(ch)(N_v).Cycle := Obs_i.Cycle;
                    end if;
                end if;
                if ErrValid(ch) = '1' then
                    N_v              := Obs_i.ErrCount(ch);
                    O_v.ErrCount(ch) := N_v + 1;
                    if N_v < LogDepth_c then
                        O_v.Errs(ch)(N_v) := (Cycle => Obs_i.Cycle,
                                              Xfer => ErrXfer(ch),
                                              Sg => ErrSg(ch));
                    end if;
                end if;
                O_v.Idle(ch)                             := Idle(ch);
                O_v.Stopped(ch)                          := Stopped(ch);
                O_v.CurPtr(ch)                           := (others => '0');
                O_v.CurPtr(ch)(AddrWidth_g - 1 downto 0) := CurPtr(ch);
            end loop;

            -- Descriptor port
            if ArValid = '1' and ArReady = '1' then
                N_v         := Obs_i.ArCount;
                O_v.ArCount := N_v + 1;
                if N_v < LogDepth_c then
                    O_v.Ars(N_v).Addr                           := (others => '0');
                    O_v.Ars(N_v).Addr(AddrWidth_g - 1 downto 0) := ArAddr;
                    O_v.Ars(N_v).Len                            := len(ArLen) + 1;
                    O_v.Ars(N_v).Size                           := ArSize;
                    O_v.Ars(N_v).Burst                          := ArBurst;
                    O_v.Ars(N_v).Lock                           := ArLock;
                    O_v.Ars(N_v).Cache                          := ArCache;
                    O_v.Ars(N_v).Prot                           := ArProt;
                    O_v.Ars(N_v).Cycle                          := Obs_i.Cycle;
                end if;
            end if;
            if AwValid = '1' and AwReady = '1' then
                N_v         := Obs_i.AwCount;
                O_v.AwCount := N_v + 1;
                if N_v < LogDepth_c then
                    O_v.Aws(N_v).Addr                           := (others => '0');
                    O_v.Aws(N_v).Addr(AddrWidth_g - 1 downto 0) := AwAddr;
                    O_v.Aws(N_v).Len                            := len(AwLen) + 1;
                    O_v.Aws(N_v).Size                           := AwSize;
                    O_v.Aws(N_v).Burst                          := AwBurst;
                    O_v.Aws(N_v).Lock                           := AwLock;
                    O_v.Aws(N_v).Cache                          := AwCache;
                    O_v.Aws(N_v).Prot                           := AwProt;
                    O_v.Aws(N_v).Cycle                          := Obs_i.Cycle;
                end if;
            end if;
            if WValid = '1' and WReady = '1' then
                N_v        := Obs_i.WCount;
                O_v.WCount := N_v + 1;
                if N_v < LogDepth_c then
                    O_v.Ws(N_v).Data := WData;
                    O_v.Ws(N_v).Strb := WStrb;
                    O_v.Ws(N_v).Last := WLast;
                    -- The burst of a single-beat status write is the AW of the same number
                    O_v.Ws(N_v).Addr := (others => '1');
                    if N_v < O_v.AwCount then
                        O_v.Ws(N_v).Addr := O_v.Aws(N_v).Addr;
                    end if;
                end if;
            end if;
            if BValid = '1' and BReady = '1' then
                N_v        := Obs_i.BCount;
                O_v.BCount := N_v + 1;
                if N_v < LogDepth_c then
                    O_v.Bs(N_v) := Obs_i.Cycle;
                end if;
            end if;

            -- ECC events
            for i in 0 to 3 loop
                if EccSec(i) = '1' then
                    O_v.EccSec(i) := Obs_i.EccSec(i) + 1;
                end if;
                if EccDed(i) = '1' then
                    O_v.EccDed(i) := Obs_i.EccDed(i) + 1;
                end if;
            end loop;

            O_v.Cycle := Obs_i.Cycle + 1;
            Obs_i     <= O_v;
        end if;
    end process;

end architecture;
