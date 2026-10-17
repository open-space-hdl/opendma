---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of odma_s2mm: the DUT, the AXI memory model on the write port, a stream generator on
-- the stream port, and monitors of the results and of the AXI4 port.
--
-- Documentation: hdl/odma_s2mm/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library olo;

library work;
    use work.odma_pkg.all;
    use work.odma_tb_mem_pkg.all;
    use work.odma_s2mm_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_s2mm_th is
    generic (
        AddrWidth_g   : positive;
        LengthWidth_g : positive;
        MemWidth_g    : positive;
        StreamWidth_g : positive;
        BurstBeats_g  : positive;
        BufferBeats_g : positive;
        Split_g       : boolean
    );
    port (
        Clk          : out   std_logic;
        Cmd_Valid    : in    std_logic;
        Cmd_Ready    : out   std_logic;
        Cmd_Addr     : in    std_logic_vector(63 downto 0);
        Cmd_Length   : in    natural;
        Cmd_Keyhole  : in    std_logic;
        Res_Ready    : in    std_logic;
        Run          : in    std_logic;
        Drain        : in    std_logic;
        RstIn        : in    std_logic;                      -- '1': reset of the DUT (the core reset)
        Stopped      : out   std_logic;
        Gen          : in    GenCfg_r;
        StreamClear  : in    std_logic;                      -- A change restarts the stream counters
        FixedAddr    : in    std_logic_vector(63 downto 0);  -- Expected address of FIXED bursts
        EccInjValid  : in    std_logic_vector(2 downto 0);
        EccInjDouble : in    std_logic;
        EccInjData   : in    std_logic;
        Obs          : out   Obs_r
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_s2mm_th is

    constant KeepWidth_c : positive := StreamWidth_g / 8;
    constant Log2Bytes_c : natural  := olo.olo_base_pkg_math.log2(MemWidth_g / 8);

    signal Clk_i   : std_logic := '0';
    signal Rst     : std_logic := '1';
    signal DutRst  : std_logic;
    signal Res_Sof : std_logic;

    -- DUT
    signal DutAddr   : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal DutLength : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal Res_Valid : std_logic;
    signal Res_Bytes : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal Res_Eof   : std_logic;
    signal Res_Err   : XferErr_t;
    signal S_Data    : std_logic_vector(StreamWidth_g - 1 downto 0) := (others => '0');
    signal S_Keep    : std_logic_vector(KeepWidth_c - 1 downto 0)   := (others => '0');
    signal S_Last    : std_logic                                    := '0';
    signal S_Valid   : std_logic                                    := '0';
    signal S_Ready   : std_logic;
    signal AwAddr    : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal AwLen     : std_logic_vector(7 downto 0);
    signal AwSize    : std_logic_vector(2 downto 0);
    signal AwBurst   : std_logic_vector(1 downto 0);
    signal AwLock    : std_logic;
    signal AwCache   : std_logic_vector(3 downto 0);
    signal AwProt    : std_logic_vector(2 downto 0);
    signal AwValid   : std_logic;
    signal AwReady   : std_logic;
    signal WData     : std_logic_vector(MemWidth_g - 1 downto 0);
    signal WStrb     : std_logic_vector(MemWidth_g / 8 - 1 downto 0);
    signal WLast     : std_logic;
    signal WValid    : std_logic;
    signal WReady    : std_logic;
    signal BResp     : std_logic_vector(1 downto 0);
    signal BValid    : std_logic;
    signal BReady    : std_logic;
    signal EccSec    : std_logic_vector(2 downto 0);
    signal EccDed    : std_logic_vector(2 downto 0);

    -- Unused read side of the memory model
    signal ArAddr  : std_logic_vector(AddrWidth_g - 1 downto 0) := (others => '0');
    signal ArLen   : std_logic_vector(7 downto 0)               := (others => '0');
    signal ArSize  : std_logic_vector(2 downto 0)               := (others => '0');
    signal ArBurst : std_logic_vector(1 downto 0)               := "01";
    signal Zero    : std_logic                                  := '0';
    signal One     : std_logic                                  := '1';

    signal Obs_i : Obs_r := (
                              Cycle     => 0,
                             ResCount  => 0,
                             Results   => (others => (Bytes => 0, Sof => '0', Eof => '0', Err => "00", Cycle => 0)),
                              Beats     => 0,
                             FirstBeat => 0,
                             LastBeat  => 0,
                             Packets   => 0,
                             LastSent  => 0,
                             RunBeats  => 0,
                             RunPkts   => 0,
                             AwCount   => 0,
                             BCount    => 0,
                             AwBadAttr => 0,
                             AwFixed   => 0,
                             AwFixLong => 0,
                             AwFixAddr => 0,
                             WGaps     => 0,
                             EccSec    => (others => 0),
                              EccDed    => (others => 0)
                          );

begin

    Clk_i <= not Clk_i after ClkPeriod_c / 2;
    Rst   <= '1', '0' after 10 * ClkPeriod_c;
    Clk   <= Clk_i;
    Obs   <= Obs_i;

    DutAddr   <= Cmd_Addr(AddrWidth_g - 1 downto 0);
    DutLength <= std_logic_vector(to_unsigned(Cmd_Length, LengthWidth_g));

    -----------------------------------------------------------------------------------------------
    -- DUT
    -----------------------------------------------------------------------------------------------
    DutRst <= Rst or RstIn;

    i_dut : entity work.odma_s2mm
        generic map (
            AddrWidth_g   => AddrWidth_g,
            LengthWidth_g => LengthWidth_g,
            MemWidth_g    => MemWidth_g,
            StreamWidth_g => StreamWidth_g,
            BurstBeats_g  => BurstBeats_g,
            BufferBeats_g => BufferBeats_g,
            Split_g       => Split_g
        )
        port map (
            Clk           => Clk_i,
            Rst           => DutRst,
            Cmd_Valid     => Cmd_Valid,
            Cmd_Ready     => Cmd_Ready,
            Cmd_Addr      => DutAddr,
            Cmd_Length    => DutLength,
            Cmd_Keyhole   => Cmd_Keyhole,
            Res_Valid     => Res_Valid,
            Res_Ready     => Res_Ready,
            Res_Bytes     => Res_Bytes,
            Res_Eof       => Res_Eof,
            Res_Err       => Res_Err,
            Res_Sof       => Res_Sof,
            Run           => Run,
            Drain         => Drain,
            Stopped       => Stopped,
            S_S2mm_Data   => S_Data,
            S_S2mm_Keep   => S_Keep,
            S_S2mm_Last   => S_Last,
            S_S2mm_Valid  => S_Valid,
            S_S2mm_Ready  => S_Ready,
            M_Axi_AwAddr  => AwAddr,
            M_Axi_AwLen   => AwLen,
            M_Axi_AwSize  => AwSize,
            M_Axi_AwBurst => AwBurst,
            M_Axi_AwLock  => AwLock,
            M_Axi_AwCache => AwCache,
            M_Axi_AwProt  => AwProt,
            M_Axi_AwValid => AwValid,
            M_Axi_AwReady => AwReady,
            M_Axi_WData   => WData,
            M_Axi_WStrb   => WStrb,
            M_Axi_WLast   => WLast,
            M_Axi_WValid  => WValid,
            M_Axi_WReady  => WReady,
            M_Axi_BResp   => BResp,
            M_Axi_BValid  => BValid,
            M_Axi_BReady  => BReady,
            Ecc_Sec       => EccSec,
            Ecc_Ded       => EccDed,
            EccInj_Valid  => EccInjValid,
            EccInj_Double => EccInjDouble,
            EccInj_Data   => EccInjData
        );

    -----------------------------------------------------------------------------------------------
    -- Memory
    -----------------------------------------------------------------------------------------------
    i_mem : entity work.odma_tb_axi_ram
        generic map (
            Index_g     => 0,
            AddrWidth_g => AddrWidth_g,
            DataWidth_g => MemWidth_g
        )
        port map (
            Clk     => Clk_i,
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
            ArValid => Zero,
            ArReady => open,
            RData   => open,
            RResp   => open,
            RLast   => open,
            RValid  => open,
            RReady  => One
        );

    -----------------------------------------------------------------------------------------------
    -- Stream generator: the packets of the queue, byte n of a packet from the source address a is
    -- odmaMemByte(a + n, SrcSeed_c)
    -----------------------------------------------------------------------------------------------
    p_gen : process (Clk_i) is
        variable Seed1_v  : positive   := 23;
        variable Seed2_v  : positive   := 991;
        variable Rand_v   : real;
        variable Active_v : boolean    := false;
        variable Src_v    : unsigned(63 downto 0);
        variable Bytes_v  : natural;
        variable Mode_v   : KeepMode_t := KeepNormal;
        variable Sent_v   : natural;
        variable Rem_v    : natural;
        variable Hs_v     : boolean;
    begin
        if rising_edge(Clk_i) then
            Hs_v := S_Valid = '1' and S_Ready = '1';
            -- The beat taken: the bytes it carries, the end of the packet
            if Hs_v then
                Sent_v := minimum(Sent_v + KeepWidth_c, Bytes_v);
                if S_Last = '1' then
                    Active_v := false;
                end if;
            end if;
            -- A new beat when no beat waits for its handshake
            if S_Valid = '0' or Hs_v then
                if not Active_v and Pkts_v.count > 0 then
                    Src_v    := Pkts_v.headSrc;
                    Bytes_v  := Pkts_v.headBytes;
                    Mode_v   := Pkts_v.headMode;
                    Sent_v   := 0;
                    Active_v := true;
                    Pkts_v.pop;
                end if;
                uniform(Seed1_v, Seed2_v, Rand_v);
                if Active_v and Gen.Hold = '0' and Rand_v * 100.0 < real(Gen.Percent) then
                    S_Valid <= '1';
                    Rem_v   := Bytes_v - Sent_v;

                    for i in 0 to KeepWidth_c - 1 loop
                        S_Data(8 * i + 7 downto 8 * i) <= odmaMemByte(Src_v + Sent_v + i, SrcSeed_c);
                    end loop;

                    if Mode_v = KeepZeroLast then
                        -- Full beats, then one last beat without valid bytes
                        S_Keep <= (others => '1') when Rem_v > 0 else (others => '0');
                        S_Last <= '1' when Rem_v = 0 else '0';
                    elsif Rem_v > KeepWidth_c then
                        S_Last <= '0';
                        S_Keep <= (others => '1');
                        if Mode_v = KeepHoles then

                            for i in 0 to KeepWidth_c - 1 loop
                                uniform(Seed1_v, Seed2_v, Rand_v);
                                S_Keep(i) <= '1' when Rand_v < 0.7 else '0';
                            end loop;

                        end if;
                    else
                        S_Last <= '1';

                        for i in 0 to KeepWidth_c - 1 loop
                            if i < Rem_v then
                                S_Keep(i) <= '1';
                            elsif Mode_v = KeepGapLast and i > Rem_v then
                                S_Keep(i) <= '1';
                            else
                                S_Keep(i) <= '0';
                            end if;
                        end loop;

                    end if;
                else
                    S_Valid <= '0';
                end if;
            end if;
            -- The stream source is reset with the core, as a stream peer on S2mm_RstOut of odma_core is (the reset
            -- output for the S2MM stream peer of PG021): the packet in progress ends without its TLast, the queued
            -- packets stay
            if RstIn = '1' then
                Active_v := false;
                S_Valid  <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Monitors
    -----------------------------------------------------------------------------------------------
    p_monitor : process (Clk_i) is
        variable O_v        : Obs_r;
        variable ClearOld_v : std_logic := '0';
        variable InW_v      : boolean   := false; -- Between the first and the last data beat of a write burst
    begin
        if rising_edge(Clk_i) then
            O_v := Obs_i;

            -- Stream counters restart
            if StreamClear /= ClearOld_v then
                ClearOld_v := StreamClear;
                O_v.Beats  := 0;
            end if;

            -- Results
            if Res_Valid = '1' and Res_Ready = '1' then
                O_v.Results(O_v.ResCount mod MaxResults_c) := (Bytes => to_integer(unsigned(Res_Bytes)),
                                                               Sof => Res_Sof,
                                                               Eof => Res_Eof,
                                                               Err => Res_Err,
                                                               Cycle => Obs_i.Cycle);
                O_v.ResCount                               := O_v.ResCount + 1;
            end if;

            -- Stream handshakes
            if S_Valid = '1' and S_Ready = '1' then
                if O_v.Beats = 0 then
                    O_v.FirstBeat := Obs_i.Cycle;
                end if;
                O_v.Beats    := O_v.Beats + 1;
                O_v.LastBeat := Obs_i.Cycle;
                if S_Last = '1' then
                    O_v.Packets  := O_v.Packets + 1;
                    O_v.LastSent := Obs_i.Cycle;
                end if;
                -- The beats the channel took while it ran; after the fall of Run it takes only the rest of an
                -- interrupted packet
                if Run = '1' then
                    O_v.RunBeats := O_v.RunBeats + 1;
                    if S_Last = '1' then
                        O_v.RunPkts := O_v.RunPkts + 1;
                    end if;
                end if;
            end if;

            -- AXI4 write port: attributes, gaps between the data beats of a burst
            if AwValid = '1' and AwReady = '1' then
                O_v.AwCount := O_v.AwCount + 1;
                if AwBurst = "00" then
                    -- FIXED burst of a keyhole command (S2-SG-04)
                    O_v.AwFixed := O_v.AwFixed + 1;
                    if unsigned(AwLen) > 15 then
                        O_v.AwFixLong := O_v.AwFixLong + 1;
                    end if;
                    if AwAddr /= FixedAddr(AddrWidth_g - 1 downto 0) then
                        O_v.AwFixAddr := O_v.AwFixAddr + 1;
                    end if;
                end if;
                if to_integer(unsigned(AwSize)) /= Log2Bytes_c or (AwBurst /= "01" and AwBurst /= "00") or AwLock /= '0' or
                   AwCache /= "0011" or AwProt /= "000" then
                    O_v.AwBadAttr := O_v.AwBadAttr + 1;
                end if;
            end if;
            if InW_v and WReady = '1' and WValid = '0' then
                O_v.WGaps := O_v.WGaps + 1;
            end if;
            if WValid = '1' and WReady = '1' then
                InW_v := WLast = '0';
            end if;
            if BValid = '1' and BReady = '1' then
                O_v.BCount := O_v.BCount + 1;
            end if;

            -- ECC events
            for i in 0 to 2 loop
                if EccSec(i) = '1' then
                    O_v.EccSec(i) := O_v.EccSec(i) + 1;
                end if;
                if EccDed(i) = '1' then
                    O_v.EccDed(i) := O_v.EccDed(i) + 1;
                end if;
            end loop;

            O_v.Cycle := Obs_i.Cycle + 1;
            Obs_i     <= O_v;
        end if;
    end process;

end architecture;
