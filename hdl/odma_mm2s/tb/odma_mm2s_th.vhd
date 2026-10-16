---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of odma_mm2s: the DUT, the AXI memory model on the read port, a stream checker with
-- TReady control on the stream port, and monitors of the results and of the AXI4 port.
--
-- Documentation: hdl/odma_mm2s/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library olo;
    use olo.olo_base_pkg_math.all;

library work;
    use work.odma_pkg.all;
    use work.odma_tb_memvar_pkg.all;
    use work.odma_mm2s_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_mm2s_th is
    generic (
        AddrWidth_g   : positive;
        LengthWidth_g : positive;
        MemWidth_g    : positive;
        StreamWidth_g : positive;
        BurstBeats_g  : positive;
        BufferBeats_g : positive
    );
    port (
        Clk          : out   std_logic;
        Cmd_Valid    : in    std_logic;
        Cmd_Ready    : out   std_logic;
        Cmd_Addr     : in    std_logic_vector(63 downto 0);
        Cmd_Length   : in    natural;
        Cmd_Eof      : in    std_logic;
        Res_Ready    : in    std_logic;
        Run          : in    std_logic;
        Drain        : in    std_logic;
        Stopped      : out   std_logic;
        Ready        : in    ReadyCfg_r;
        StreamClear  : in    std_logic;                      -- A change restarts the stream counters
        EccInjValid  : in    std_logic_vector(2 downto 0);
        EccInjDouble : in    std_logic;
        Obs          : out   Obs_r
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_mm2s_th is

    constant KeepWidth_c : positive := StreamWidth_g / 8;

    signal Clk_i : std_logic := '0';
    signal Rst   : std_logic := '1';

    -- DUT
    signal DutAddr   : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal DutLength : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal Res_Valid : std_logic;
    signal Res_Bytes : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal Res_Eof   : std_logic;
    signal Res_Err   : XferErr_t;
    signal ArAddr    : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal ArLen     : std_logic_vector(7 downto 0);
    signal ArSize    : std_logic_vector(2 downto 0);
    signal ArBurst   : std_logic_vector(1 downto 0);
    signal ArLock    : std_logic;
    signal ArCache   : std_logic_vector(3 downto 0);
    signal ArProt    : std_logic_vector(2 downto 0);
    signal ArValid   : std_logic;
    signal ArReady   : std_logic;
    signal RData     : std_logic_vector(MemWidth_g - 1 downto 0);
    signal RResp     : std_logic_vector(1 downto 0);
    signal RLast     : std_logic;
    signal RValid    : std_logic;
    signal RReady    : std_logic;
    signal S_Data    : std_logic_vector(StreamWidth_g - 1 downto 0);
    signal S_Keep    : std_logic_vector(KeepWidth_c - 1 downto 0);
    signal S_Last    : std_logic;
    signal S_Valid   : std_logic;
    signal S_Ready   : std_logic := '0';
    signal EccSec    : std_logic_vector(2 downto 0);
    signal EccDed    : std_logic_vector(2 downto 0);

    -- Unused write side of the memory model
    signal AwAddr  : std_logic_vector(AddrWidth_g - 1 downto 0)    := (others => '0');
    signal AwLen   : std_logic_vector(7 downto 0)                  := (others => '0');
    signal AwSize  : std_logic_vector(2 downto 0)                  := (others => '0');
    signal AwBurst : std_logic_vector(1 downto 0)                  := "01";
    signal WData   : std_logic_vector(MemWidth_g - 1 downto 0)     := (others => '0');
    signal WStrb   : std_logic_vector(MemWidth_g / 8 - 1 downto 0) := (others => '0');
    signal Zero    : std_logic                                     := '0';
    signal One     : std_logic                                     := '1';

    signal Obs_i : Obs_r := (
                              Cycle      => 0,
                             ResCount   => 0,
                             Results    => (others => (Bytes => 0, Eof => '0', Err => "00", Cycle => 0)),
                              Beats      => 0,
                             Bytes      => 0,
                             FirstBeat  => 0,
                             LastBeat   => 0,
                             Packets    => 0,
                             StreamErr  => 0,
                             RHeld      => 0,
                             ArCount    => 0,
                             RLastCount => 0,
                             ArBadAttr  => 0,
                             EccSec     => (others => 0),
                              EccDed     => (others => 0)
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
    i_dut : entity work.odma_mm2s
        generic map (
            AddrWidth_g   => AddrWidth_g,
            LengthWidth_g => LengthWidth_g,
            MemWidth_g    => MemWidth_g,
            StreamWidth_g => StreamWidth_g,
            BurstBeats_g  => BurstBeats_g,
            BufferBeats_g => BufferBeats_g
        )
        port map (
            Clk           => Clk_i,
            Rst           => Rst,
            Cmd_Valid     => Cmd_Valid,
            Cmd_Ready     => Cmd_Ready,
            Cmd_Addr      => DutAddr,
            Cmd_Length    => DutLength,
            Cmd_Sof       => One,
            Cmd_Eof       => Cmd_Eof,
            Cmd_Keyhole   => Zero,
            Res_Valid     => Res_Valid,
            Res_Ready     => Res_Ready,
            Res_Bytes     => Res_Bytes,
            Res_Eof       => Res_Eof,
            Res_Err       => Res_Err,
            Run           => Run,
            Drain         => Drain,
            Stopped       => Stopped,
            M_Axi_ArAddr  => ArAddr,
            M_Axi_ArLen   => ArLen,
            M_Axi_ArSize  => ArSize,
            M_Axi_ArBurst => ArBurst,
            M_Axi_ArLock  => ArLock,
            M_Axi_ArCache => ArCache,
            M_Axi_ArProt  => ArProt,
            M_Axi_ArValid => ArValid,
            M_Axi_ArReady => ArReady,
            M_Axi_RData   => RData,
            M_Axi_RResp   => RResp,
            M_Axi_RLast   => RLast,
            M_Axi_RValid  => RValid,
            M_Axi_RReady  => RReady,
            M_Mm2s_Data   => S_Data,
            M_Mm2s_Keep   => S_Keep,
            M_Mm2s_Last   => S_Last,
            M_Mm2s_Valid  => S_Valid,
            M_Mm2s_Ready  => S_Ready,
            Ecc_Sec       => EccSec,
            Ecc_Ded       => EccDed,
            EccInj_Valid  => EccInjValid,
            EccInj_Double => EccInjDouble
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
            AwValid => Zero,
            AwReady => open,
            WData   => WData,
            WStrb   => WStrb,
            WLast   => Zero,
            WValid  => Zero,
            WReady  => open,
            BResp   => open,
            BValid  => open,
            BReady  => One,
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
    -- TReady of the stream peer
    -----------------------------------------------------------------------------------------------
    p_ready : process (Clk_i) is
        variable Seed1_v    : positive  := 17;
        variable Seed2_v    : positive  := 4711;
        variable Rand_v     : real;
        variable Stall_v    : natural   := 0;
        variable Stalled_v  : boolean   := false;
        variable Beats_v    : natural;
        variable ClearOld_v : std_logic := '0';
    begin
        if rising_edge(Clk_i) then
            if StreamClear /= ClearOld_v then
                ClearOld_v := StreamClear;
                Stalled_v  := false;
            end if;
            -- One stall before the beat with the index StallBeat (counted with the handshake of this edge)
            Beats_v := Obs_i.Beats;
            if S_Valid = '1' and S_Ready = '1' then
                Beats_v := Beats_v + 1;
            end if;
            if Ready.StallBeat >= 0 and not Stalled_v and Beats_v = Ready.StallBeat then
                Stalled_v := true;
                Stall_v   := Ready.StallCycles;
            end if;
            uniform(Seed1_v, Seed2_v, Rand_v);
            if Ready.Hold = '1' or Stall_v > 0 then
                S_Ready <= '0';
            elsif Rand_v * 100.0 < real(Ready.Percent) then
                S_Ready <= '1';
            else
                S_Ready <= '0';
            end if;
            if Stall_v > 0 then
                Stall_v := Stall_v - 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Monitors and stream checker
    -----------------------------------------------------------------------------------------------
    p_monitor : process (Clk_i) is
        variable O_v        : Obs_r;
        variable ClearOld_v : std_logic             := '0';
        variable Open_v     : boolean               := false;   -- A packet is in progress
        variable PktAddr_v  : unsigned(63 downto 0) := (others => '0');
        variable PktBytes_v : natural               := 0;
        variable Count_v    : natural               := 0;
        variable Bytes_v    : natural;
        variable Gap_v      : boolean;
        variable Exp_v      : natural;

        procedure streamError (msg : string) is
        begin
            O_v.StreamErr := O_v.StreamErr + 1;
            if O_v.StreamErr <= 5 then
                alert(ERROR, "stream checker: " & msg);
            end if;
        end procedure;

    -- Comment for the style checker: subprograms above, statements below
    begin
        if rising_edge(Clk_i) then
            O_v := Obs_i;

            -- Stream counters restart
            if StreamClear /= ClearOld_v then
                ClearOld_v := StreamClear;
                O_v.Beats  := 0;
                O_v.Bytes  := 0;
            end if;

            -- Results
            if Res_Valid = '1' and Res_Ready = '1' then
                O_v.Results(O_v.ResCount mod MaxResults_c) := (Bytes => to_integer(unsigned(Res_Bytes)),
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
                O_v.Beats := O_v.Beats + 1;
                if S_Last = '1' then
                    O_v.LastBeat := Obs_i.Cycle;
                end if;
                -- Start of a packet: the oldest expected packet
                if not Open_v then
                    if Pkts_v.count = 0 then
                        streamError("beat without an expected packet");
                    else
                        Open_v     := true;
                        PktAddr_v  := Pkts_v.headAddr;
                        PktBytes_v := Pkts_v.headBytes;
                        Count_v    := 0;
                        Pkts_v.pop;
                    end if;
                end if;
                -- Bytes of the memory, TKeep contiguous from lane 0 and all ones except on the last beat
                Bytes_v := 0;
                Gap_v   := false;

                for i in 0 to KeepWidth_c - 1 loop
                    if S_Keep(i) = '1' then
                        if Gap_v then
                            streamError("TKeep not contiguous");
                        end if;
                        Exp_v := to_integer(unsigned(Mem_v.read8(0, PktAddr_v + Count_v + Bytes_v)));
                        if Open_v and to_integer(unsigned(S_Data(8 * i + 7 downto 8 * i))) /= Exp_v then
                            streamError("byte " & to_string(Count_v + Bytes_v) & " of the packet");
                        end if;
                        Bytes_v := Bytes_v + 1;
                    else
                        Gap_v := true;
                    end if;
                end loop;

                Count_v   := Count_v + Bytes_v;
                O_v.Bytes := O_v.Bytes + Bytes_v;
                if Open_v then
                    -- TLast exactly on the beat with the last byte, a partial TKeep only there
                    if (S_Last = '1') /= (Count_v = PktBytes_v) then
                        streamError("TLast after " & to_string(Count_v) & " of " & to_string(PktBytes_v) & " bytes");
                    end if;
                    if Gap_v and S_Last = '0' then
                        streamError("partial TKeep before the end of the packet");
                    end if;
                    if S_Last = '1' or Count_v >= PktBytes_v then
                        Open_v := false;
                        if S_Last = '1' then
                            O_v.Packets := O_v.Packets + 1;
                        end if;
                    end if;
                end if;
            end if;

            -- AXI4 read port
            if RValid = '1' and RReady = '0' then
                O_v.RHeld := O_v.RHeld + 1;
            end if;
            if RValid = '1' and RReady = '1' and RLast = '1' then
                O_v.RLastCount := O_v.RLastCount + 1;
            end if;
            if ArValid = '1' and ArReady = '1' then
                O_v.ArCount := O_v.ArCount + 1;
                if to_integer(unsigned(ArSize)) /= olo.olo_base_pkg_math.log2(MemWidth_g / 8) or ArBurst /= "01" or ArLock /= '0' or
                   ArCache /= "0011" or ArProt /= "000" then
                    O_v.ArBadAttr := O_v.ArBadAttr + 1;
                end if;
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
