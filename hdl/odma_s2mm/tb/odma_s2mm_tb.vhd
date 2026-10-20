---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VUnit testbench of odma_s2mm: the test cases TC-S2-01 to TC-S2-27 of the verification plan. The
-- expected memory contents follow from the sent packets and the pre-fill, never from the DUT.
--
-- Documentation: hdl/odma_s2mm/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library vunit_lib;
    context vunit_lib.vunit_context;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library work;
    use work.odma_tb_pkg.all;
    use work.odma_tb_mem_pkg.all;
    use work.odma_tb_memvar_pkg.all;
    use work.odma_s2mm_tb_pkg.all;
    use work.odma_s2mm_tb_pktvar_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_s2mm_tb is
    generic (
        runner_cfg    : string;
        AddrWidth_g   : positive := 32;
        LengthWidth_g : positive := 26;
        MemWidth_g    : positive := 32;
        StreamWidth_g : positive := 32;
        BurstBeats_g  : positive := 16;
        BufferBeats_g : positive := 64;
        Split_g       : boolean  := false
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_s2mm_tb is

    subtype Addr_t is unsigned(63 downto 0);

    constant StreamBytes_c : positive := StreamWidth_g / 8;
    constant MemBytes_c    : positive := MemWidth_g / 8;
    constant MaxLen_c      : positive := 2**LengthWidth_g - 1;
    -- A chunk is one burst of at most 4 KB (specification S2-ST-03)
    constant ChunkBeats_c  : positive := minimum(BurstBeats_g, 4096 / MemBytes_c) * MemBytes_c / StreamBytes_c;
    constant ChunkBytes_c  : positive := ChunkBeats_c * StreamBytes_c;
    -- Bytes around a buffer that must keep their pre-fill
    constant Guard_c       : positive := 256;

    -- Beats that the stream split holds between the stream port and the chunk former: its carry and its output
    function splitLag return natural is
    begin
        if Split_g then
            return 2;
        end if;
        return 0;
    end function;

    constant SplitLag_c : natural := splitLag;

    -- Message prefix of one halt of the halt sweep (TC-S2-21)
    function sweepMsg (
        st : natural;
        c  : natural;
        k  : integer) return string is
    begin
        return "halt sweep, memory stall " & to_string(st) & ", length case " & to_string(c) & ", offset " &
               to_string(k) & ": ";
    end function;

    -- Longest FIXED burst: 16 beats, at most the bursts of the write master (S2-SG-04)
    constant FixedBeats_c  : positive := minimum(16, minimum(BurstBeats_g, 4096 / MemBytes_c));
    -- Longest burst of the write master in memory words and the memory words of a 4 KB page (specification S2-ST-03)
    constant MasterBeats_c : positive := minimum(BurstBeats_g, 4096 / MemBytes_c);
    constant PageWords_c   : positive := 4096 / MemBytes_c;

    -- The table of the short chunks of the verification plan (section 2): the beats by which every chunk of a buffer
    -- that starts inside a stream word is shorter, for a memory width, a stream width and B beats of a burst: one
    -- memory word with a memory wider than the stream and B of 8 or more, else none
    function planShort (
        mem    : positive;
        stream : positive;
        beats  : positive) return natural is
    begin
        if mem / stream >= 2 and beats >= 8 then
            return mem / stream;
        end if;
        return 0;
    end function;

    -- Beats by which every chunk of a buffer that starts inside a stream word is shorter in this configuration
    constant Short_c : natural := planShort(MemWidth_g, StreamWidth_g, MasterBeats_c);

    -- AW bursts of one INCR write command of n bytes at the offset off within a 4 KB page: the write master splits at
    -- 4 KB and at MasterBeats_c memory words from the start of the command (S2-WR-03)
    function masterBursts (
        off : natural;
        n   : positive) return positive is
        constant Last_c : natural := (off + n - 1) / MemBytes_c;
        variable W_v    : natural := off / MemBytes_c;
        variable Cnt_v  : natural := 0;
    begin

        while W_v <= Last_c loop
            W_v   := W_v + minimum(MasterBeats_c, PageWords_c - W_v mod PageWords_c);
            Cnt_v := Cnt_v + 1;
        end loop;

        return Cnt_v;
    end function;

    -- Bytes of the next chunk of a buffer at dst whose chunks have reached the offset off within a 4 KB page, by the
    -- chunk plan (S2-ST-03, S2-ST-04): chunks of ChunkBytes_c for a keyhole buffer, at a multiple of the memory word
    -- and without Split_g; at another multiple of the stream width up to the next multiple of the burst size; inside a
    -- stream word ChunkBytes_c less Short_c beats
    function chunkBytes (
        dst     : Addr_t;
        off     : natural;
        keyhole : boolean) return positive is
    begin
        if keyhole or not Split_g or to_integer(dst(11 downto 0)) mod MemBytes_c = 0 then
            return ChunkBytes_c;
        elsif to_integer(dst(11 downto 0)) mod StreamBytes_c = 0 then
            return ChunkBytes_c - off mod ChunkBytes_c;
        end if;
        return ChunkBytes_c - Short_c * StreamBytes_c;
    end function;

    -- AW bursts of len bytes written into a buffer at dst by the chunk plan, each chunk written by the split of the
    -- write master; a keyhole chunk in FIXED bursts of at most FixedBeats_c beats
    function planBursts (
        dst     : Addr_t;
        len     : positive;
        keyhole : boolean := false) return natural is
        variable Off_v : natural := to_integer(dst(11 downto 0));
        variable Rem_v : natural := len;
        variable N_v   : positive;
        variable Cnt_v : natural := 0;
    begin

        while Rem_v > 0 loop
            N_v := minimum(chunkBytes(dst, Off_v, keyhole), Rem_v);
            if keyhole then
                Cnt_v := Cnt_v + ((N_v + MemBytes_c - 1) / MemBytes_c + FixedBeats_c - 1) / FixedBeats_c;
            else
                Cnt_v := Cnt_v + masterBursts(Off_v mod 4096, N_v);
                Off_v := Off_v + N_v;
            end if;
            Rem_v := Rem_v - N_v;
        end loop;

        return Cnt_v;
    end function;

    -- Expected results of the split tests, checked while the commands are sent
    constant MaxCmds_c : positive := 32;

    type CmdNat_a is array (0 to MaxCmds_c - 1) of natural;
    type CmdAddr_a is array (0 to MaxCmds_c - 1) of unsigned(63 downto 0);

    -- Error codes of a result
    constant ErrNone_c : std_logic_vector(1 downto 0) := "00";
    constant ErrInt_c  : std_logic_vector(1 downto 0) := "01";
    constant ErrSlv_c  : std_logic_vector(1 downto 0) := "10";
    constant ErrDec_c  : std_logic_vector(1 downto 0) := "11";

    -- Destination region k of 64 KB, and the source address of the packet data for region k
    function region (k : natural) return Addr_t is
    begin
        return to_unsigned(k * 65536, 64);
    end function;

    function source (k : natural) return Addr_t is
    begin
        return x"0000_7700_0000_0000" + to_unsigned(k * 65536, 64);
    end function;

    -- Highest byte address of the address space
    function topAddr return Addr_t is
        variable A_v : Addr_t := (others => '0');
    begin
        A_v(AddrWidth_g - 1 downto 0) := (others => '1');
        return A_v;
    end function;

    signal Clk          : std_logic;
    signal Cmd_Valid    : std_logic                     := '0';
    signal Cmd_Ready    : std_logic;
    signal Cmd_Addr     : std_logic_vector(63 downto 0) := (others => '0');
    signal Cmd_Length   : natural                       := 0;
    signal Cmd_Keyhole  : std_logic                     := '0';
    signal RstIn        : std_logic                     := '0';
    signal FixedAddr    : std_logic_vector(63 downto 0) := (others => '0');
    signal Res_Ready    : std_logic                     := '1';
    signal ResStall     : natural                       := 0;
    signal ChRun        : std_logic                     := '0';
    signal ChDrain      : std_logic                     := '0';
    signal Stopped      : std_logic;
    signal Gen          : GenCfg_r                      := GenAlways_c;
    signal StreamClear  : std_logic                     := '0';
    signal EccInjValid  : std_logic_vector(2 downto 0)  := "000";
    signal EccInjDouble : std_logic                     := '0';
    signal EccInjData   : std_logic                     := '0';
    signal Obs          : Obs_r;

begin

    test_runner_watchdog(runner, 200 ms);

    i_th : entity work.odma_s2mm_th
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
            Clk          => Clk,
            Cmd_Valid    => Cmd_Valid,
            Cmd_Ready    => Cmd_Ready,
            Cmd_Addr     => Cmd_Addr,
            Cmd_Length   => Cmd_Length,
            Cmd_Keyhole  => Cmd_Keyhole,
            Res_Ready    => Res_Ready,
            Run          => ChRun,
            Drain        => ChDrain,
            RstIn        => RstIn,
            Stopped      => Stopped,
            Gen          => Gen,
            StreamClear  => StreamClear,
            FixedAddr    => FixedAddr,
            EccInjValid  => EccInjValid,
            EccInjDouble => EccInjDouble,
            EccInjData   => EccInjData,
            Obs          => Obs
        );

    -- Receiver of the results (TC-S2-26): Res_Ready low in runs of 1 to 32 clock cycles, each run low with a
    -- probability of ResStall percent; '1' without stalls, '0' at 100 percent
    p_res_ready : process is
        variable S1_v  : positive := 17;
        variable S2_v  : positive := 41;
        variable R_v   : real;
        variable Run_v : natural  := 0;
    begin
        wait until rising_edge(Clk);
        if ResStall = 0 then
            Res_Ready <= '1';
            Run_v     := 0;
        elsif ResStall >= 100 then
            Res_Ready <= '0';
            Run_v     := 0;
        elsif Run_v > 0 then
            Run_v := Run_v - 1;
        else
            uniform(S1_v, S2_v, R_v);
            Res_Ready <= '0' when R_v * 100.0 < real(ResStall) else '1';
            uniform(S1_v, S2_v, R_v);
            Run_v     := integer(floor(R_v * 32.0)) mod 32;
        end if;
    end process;

    p_control : process is
        variable Dst_v    : Addr_t;
        variable Src_v    : Addr_t;
        variable Len_v    : natural;
        variable Len2_v   : natural;
        variable Res_v    : natural;
        variable Cnt_v    : natural;
        variable Cnt2_v   : natural;
        variable Pkts_v   : natural;
        variable Sec_v    : Nat3_a;
        variable Ded_v    : Nat3_a;
        variable Seed1_v  : positive := 5;
        variable Seed2_v  : positive := 93;
        variable Rand_v   : real;
        variable Resp_v   : std_logic_vector(1 downto 0);
        variable N_v      : natural;
        variable SofB_v   : std_logic;
        variable EofB_v   : std_logic;
        variable Off_v    : natural;
        variable Wr_v     : natural;
        variable Sent_v   : natural;
        variable Done_v   : natural;
        variable Win_v    : Addr_t;
        variable Back_v   : Addr_t;
        variable ExpDst_v : CmdAddr_a;
        variable ExpSrc_v : CmdAddr_a;
        variable ExpLen_v : CmdNat_a;
        variable ExpWr_v  : CmdNat_a;
        variable ExpSof_v : std_logic_vector(0 to MaxCmds_c - 1);
        variable ExpEof_v : std_logic_vector(0 to MaxCmds_c - 1);
        variable Lp_v     : natural;
        variable Beats0_v : natural;
        variable Pkts0_v  : natural;
        variable Halt0_v  : natural;
        variable HaltP0_v : natural;
        variable Took_v   : natural;
        variable Start_v  : boolean;
        variable End_v    : boolean;
        variable Exp_v    : natural;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- One transfer command, after its handshake
        procedure sendCmd (
            dst     : Addr_t;
            len     : natural;
            keyhole : std_logic := '0') is
        begin
            Cmd_Addr    <= std_logic_vector(dst);
            Cmd_Length  <= len;
            Cmd_Keyhole <= keyhole;
            Cmd_Valid   <= '1';
            odmaWaitHighAtEdge(Clk, Cmd_Ready, 1 ms, "command accepted");
            Cmd_Valid   <= '0';
            Cmd_Keyhole <= '0';
        end procedure;

        -- Random natural from lo to hi
        procedure rnd (
            lo  : natural;
            hi  : natural;
            res : out natural) is
            variable R_v : real;
        begin
            uniform(Seed1_v, Seed2_v, R_v);
            res := lo + integer(floor(R_v * real(hi - lo + 1))) mod (hi - lo + 1);
        end procedure;

        -- One packet of the stream generator
        procedure send (
            src   : Addr_t;
            bytes : natural;
            mode  : KeepMode_t := KeepNormal) is
        begin
            work.odma_s2mm_tb_pktvar_pkg.Pkts_v.push(src, bytes, mode);
        end procedure;

        procedure waitRes (n : natural) is
        begin
            if Obs.ResCount < n then
                wait until Obs.ResCount >= n for 20 ms;
            end if;
            check_value(Obs.ResCount, n, ERROR, "results");
        end procedure;

        procedure waitPackets (n : natural) is
        begin
            if Obs.Packets < n then
                wait until Obs.Packets >= n for 20 ms;
            end if;
            check_value(Obs.Packets, n, ERROR, "packets sent");
        end procedure;

        procedure checkRes (
            i     : natural;
            bytes : natural;
            eof   : std_logic;
            err   : std_logic_vector(1 downto 0);
            msg   : string) is
        begin
            check_value(Obs.Results(i mod MaxResults_c).Bytes, bytes, ERROR, msg & ": result bytes");
            check_value(Obs.Results(i mod MaxResults_c).Eof, eof, ERROR, msg & ": result end of packet");
            check_value(Obs.Results(i mod MaxResults_c).Err, err, ERROR, msg & ": result error code");
        end procedure;

        -- The destination and the bytes around it get the pre-fill, the write window of the memory model is the buffer
        procedure prefill (
            dst : Addr_t;
            len : positive) is
        begin
            Mem_v.fill(0, dst - Guard_c, len + 2 * Guard_c, DstSeed_c);
            Mem_v.setWindow(0, dst, dst + len - 1);
        end procedure;

        -- The first written bytes of the buffer carry the packet from src, all other bytes keep their pre-fill
        procedure checkMem (
            dst     : Addr_t;
            len     : natural;
            written : natural;
            src     : Addr_t;
            msg     : string) is
            variable A_v   : Addr_t;
            variable Exp_v : std_logic_vector(7 downto 0);
            variable Bad_v : natural := 0;
        begin

            for i in 0 to len + 2 * Guard_c - 1 loop
                A_v := dst - Guard_c + i;
                if i >= Guard_c and i < Guard_c + written then
                    Exp_v := odmaMemByte(src + (i - Guard_c), SrcSeed_c);
                else
                    Exp_v := odmaMemByte(A_v, DstSeed_c);
                end if;
                if Mem_v.read8(0, A_v) /= Exp_v then
                    if Bad_v < 4 then
                        log(ID_SEQUENCER, msg & ": byte at buffer offset " & to_string(i - Guard_c) & " wrong");
                    end if;
                    Bad_v := Bad_v + 1;
                end if;
            end loop;

            check_value(Bad_v, 0, ERROR, msg & ": wrong bytes in and around the buffer");
        end procedure;

        -- A packet of bytes into a buffer of len bytes, checked in memory, and its result
        procedure transfer (
            dst   : Addr_t;
            len   : positive;
            src   : Addr_t;
            bytes : natural;
            msg   : string;
            mode  : KeepMode_t := KeepNormal) is
            constant Res_c : natural := Obs.ResCount;
        begin
            prefill(dst, len);
            send(src, bytes, mode);
            sendCmd(dst, len);
            waitRes(Res_c + 1);
            checkRes(Res_c, bytes, '1', ErrNone_c, msg);
            checkMem(dst, len, bytes, src, msg);
        end procedure;

        -- Checks the results of the split tests that have arrived: bytes, start and end of packet, the buffer
        procedure checkSplit is
            variable I_v : natural;
        begin

            while Done_v < Obs.ResCount - Res_v loop
                I_v    := Done_v mod MaxCmds_c;
                checkRes(Res_v + Done_v, ExpWr_v(I_v), ExpEof_v(I_v), ErrNone_c, "buffer " & to_string(Done_v));
                check_value(Obs.Results((Res_v + Done_v) mod MaxResults_c).Sof, ExpSof_v(I_v), ERROR,
                            "buffer " & to_string(Done_v) & ": start of packet");
                checkMem(ExpDst_v(I_v), ExpLen_v(I_v), ExpWr_v(I_v), ExpSrc_v(I_v), "buffer " & to_string(Done_v));
                Done_v := Done_v + 1;
            end loop;

        end procedure;

        -- A buffer of the split tests: pre-filled, commanded, and its expected result recorded
        procedure splitBuf (
            dst : Addr_t;
            len : positive;
            wr  : natural;
            src : Addr_t;
            sof : std_logic;
            eof : std_logic) is
            constant I_c : natural := Sent_v mod MaxCmds_c;
        begin
            Mem_v.fill(0, dst - Guard_c, len + 2 * Guard_c, DstSeed_c);
            ExpDst_v(I_c) := dst;
            ExpLen_v(I_c) := len;
            ExpWr_v(I_c)  := wr;
            ExpSrc_v(I_c) := src;
            ExpSof_v(I_c) := sof;
            ExpEof_v(I_c) := eof;
            sendCmd(dst, len);
            Sent_v        := Sent_v + 1;
            checkSplit;
        end procedure;

        procedure clearStream is
        begin
            StreamClear <= not StreamClear;
            wait until rising_edge(Clk);
            wait until rising_edge(Clk);
        end procedure;

    -- Comment for the style checker: subprograms above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);
        -- Every burst is checked against the burst limit of the configuration and 4 KB
        Mem_v.setMaxBeats(0, BurstBeats_g);
        wait for 20 * ClkPeriod_c;
        wait until rising_edge(Clk);
        ChRun <= '1';

        while test_suite loop

            if run("test_aligned") then
                log(ID_LOG_HDR, "TC-S2-01 packets into aligned buffers");

                for i in 0 to 4 loop
                    Len_v := 1 when i = 0 else
                             StreamBytes_c when i = 1 else
                             ChunkBytes_c when i = 2 else
                             ChunkBytes_c + 1 when i = 3 else
                             7 * ChunkBytes_c / 2;
                    Len_v := minimum(minimum(Len_v, MaxLen_c), 20000);
                    transfer(region(1 + i), Len_v, source(i), Len_v, "packet of " & to_string(Len_v) & " bytes");
                    -- A larger buffer
                    Len2_v := minimum(Len_v + 100, MaxLen_c);
                    transfer(region(10 + i), Len2_v, source(10 + i), Len_v, "packet of " & to_string(Len_v) &
                             " bytes into " & to_string(Len2_v) & " bytes");
                end loop;

            elsif run("test_unaligned") then
                log(ID_LOG_HDR, "TC-S2-02 every start offset within a memory word");

                for ofs in 0 to MemBytes_c - 1 loop

                    for i in 0 to 4 loop
                        Len_v := 1 when i = 0 else
                                 maximum(MemBytes_c - 1, 1) when i = 1 else
                                 MemBytes_c when i = 2 else
                                 MemBytes_c + 1 when i = 3 else
                                 3 * MemBytes_c;
                        Len_v := minimum(Len_v, MaxLen_c);
                        Dst_v := region(1) + 4096 * i + ofs;
                        transfer(Dst_v, Len_v, source(ofs), Len_v, "offset " & to_string(ofs) & ", " &
                                 to_string(Len_v) & " bytes");
                    end loop;

                end loop;

            elsif run("test_keep") then
                log(ID_LOG_HDR, "TC-S2-03 TKeep of the last beat and of the other beats");

                -- Every number of valid bytes in the last beat
                for k in 1 to StreamBytes_c loop
                    Len_v := minimum(2 * StreamBytes_c + k, MaxLen_c);
                    transfer(region(1) + 1024 * (k mod 32), Len_v, source(k), Len_v, "last beat with " &
                             to_string(k) & " bytes");
                end loop;

                -- A last beat without valid bytes after a full chunk and after a partial chunk
                Len_v := minimum(ChunkBytes_c, (MaxLen_c - 1) / StreamBytes_c * StreamBytes_c);
                transfer(region(2), Len_v + 1, source(100), Len_v, "empty last beat after a full chunk",
                         KeepZeroLast);
                transfer(region(3), 5 * StreamBytes_c, source(101), 2 * StreamBytes_c,
                         "empty last beat after a partial chunk", KeepZeroLast);
                -- Deasserted TKeep bits of beats before the last one are ignored
                Len_v := minimum(3 * ChunkBytes_c + 3, MaxLen_c);
                transfer(region(4), Len_v, source(102), Len_v, "TKeep holes before the last beat", KeepHoles);
                -- A last beat with a gap in TKeep: the bytes up to the gap
                if StreamBytes_c >= 3 then
                    Len_v := minimum(2 * StreamBytes_c + 1, MaxLen_c - 8);
                    transfer(region(5), Len_v + 8, source(103), Len_v, "gap in TKeep of the last beat",
                             KeepGapLast);
                end if;

            elsif run("test_bursts") then
                log(ID_LOG_HDR, "TC-S2-04 4 KB boundaries, the burst limit, data before the burst");
                Len_v := minimum(3 * 4096 + 100, MaxLen_c);
                transfer(region(1) + 8192 - 3, Len_v, source(1), Len_v, "buffer across 4 KB boundaries");
                Len_v := minimum(5 * ChunkBytes_c + 3, minimum(MaxLen_c, 40000));
                transfer(region(2) + 4096 - minimum(ChunkBytes_c, 4096) + 1, Len_v, source(2), Len_v,
                         "buffer of several bursts");
                check_value(Obs.AwBadAttr, 0, ERROR, "AwSize, AwBurst, AwLock, AwCache and AwProt");
                check_value(Obs.WGaps, 0, ERROR, "clock cycles without write data inside a burst");

            elsif run("test_backpressure") then
                log(ID_LOG_HDR, "TC-S2-05 gaps of the stream and backpressure of the memory");
                Mem_v.setStall(0, 50);
                Mem_v.setLatency(0, 30);
                Gen.Percent <= 50;

                for i in 1 to 20 loop
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    Len_v := 1 + integer(trunc(Rand_v * real(minimum(MaxLen_c, 3000) - 1)));
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    Dst_v := region(1 + i) + integer(trunc(Rand_v * 50000.0));
                    transfer(Dst_v, Len_v, source(i), Len_v, "random packet " & to_string(i));
                end loop;

            elsif run("test_throughput") then
                log(ID_LOG_HDR, "TC-S2-06 one stream beat per clock cycle");
                Len_v  := minimum(MaxLen_c, 64 * ChunkBytes_c);
                clearStream;
                transfer(region(1), Len_v, source(1), Len_v, "packet of 64 chunks");
                Cnt_v  := (Len_v + StreamBytes_c - 1) / StreamBytes_c;
                Cnt2_v := Obs.LastBeat - Obs.FirstBeat + 1;
                log(ID_SEQUENCER, "throughput: " & to_string(Cnt_v) & " beats in " & to_string(Cnt2_v) &
                    " clock cycles, " & to_string(ChunkBeats_c) & " beats per chunk");
                -- S2-WR-05 applies to chunks of at least 64 beats: at least 0.9 beats per clock cycle
                if ChunkBeats_c >= 64 then
                    check_value(10 * Cnt_v >= 9 * Cnt2_v, ERROR, "clock cycles from the first to the last of " &
                                to_string(Cnt_v) & " beats: " & to_string(Cnt2_v));
                end if;
                N_v := Cnt2_v;

                -- The same packet into a buffer at the stream width above a burst boundary and into one 1 byte above
                -- (inside a stream word): with Split_g the chunks of the first follow the bursts of the buffer
                -- (S2-ST-04), so it takes the beats at the rate of the aligned buffer within 2 % when it holds at
                -- least 16 chunks; the rates are logged and listed in the verification report
                for k in 1 to 2 loop
                    Off_v  := StreamBytes_c when k = 1 else 1;
                    clearStream;
                    transfer(region(2 + k) + Off_v, Len_v, source(1 + k), Len_v, "packet of 64 chunks at offset " &
                             to_string(Off_v));
                    Cnt2_v := Obs.LastBeat - Obs.FirstBeat + 1;
                    log(ID_SEQUENCER, "throughput at offset " & to_string(Off_v) & ": " & to_string(Cnt_v) &
                        " beats in " & to_string(Cnt2_v) & " clock cycles");
                    if Split_g and k = 1 and Len_v >= 16 * ChunkBytes_c then
                        check_value(98 * Cnt2_v <= 100 * N_v, ERROR, "clock cycles at offset " & to_string(Off_v) &
                                    ": " & to_string(Cnt2_v) & ", aligned " & to_string(N_v));
                    end if;
                end loop;

            elsif run("test_early_data") then
                log(ID_LOG_HDR, "TC-S2-07 a packet before the command, the input of a halted channel");
                -- Halted: the input is not ready
                ChRun <= '0';
                clearStream;
                Len_v := minimum(3 * StreamBytes_c + 1, MaxLen_c);
                send(source(1), Len_v);
                cycles(100);
                check_value(Obs.Beats, 0, ERROR, "no beat taken while halted");
                -- Running: the packet waits in the data buffer for the command
                ChRun <= '1';
                waitPackets(1);
                cycles(100);
                check_value(Obs.AwCount, 0, ERROR, "no write before the command");
                prefill(region(1), Len_v);
                sendCmd(region(1), Len_v);
                waitRes(1);
                checkRes(0, Len_v, '1', ErrNone_c, "packet received before the command");
                checkMem(region(1), Len_v, Len_v, source(1), "packet received before the command");

            elsif run("test_overflow") then
                log(ID_LOG_HDR, "TC-S2-08 packets longer than the buffer");
                -- One byte too long
                Len_v := minimum(2 * ChunkBytes_c + 5, MaxLen_c - 1);
                prefill(region(1), Len_v);
                send(source(1), Len_v + 1);
                sendCmd(region(1), Len_v);
                waitRes(1);
                checkRes(0, Len_v, '0', ErrInt_c, "packet one byte longer than the buffer");
                checkMem(region(1), Len_v, Len_v, source(1), "packet one byte longer than the buffer");
                -- Several chunks too long, sent slowly: the result comes before the TLast of the rest
                Len_v       := minimum(ChunkBytes_c + 3, MaxLen_c);
                prefill(region(2), Len_v);
                Gen.Percent <= 20;
                Pkts_v      := Obs.Packets;
                send(source(2), Len_v + 5 * ChunkBytes_c);
                sendCmd(region(2), Len_v);
                waitRes(2);
                check_value(Obs.Packets, Pkts_v, ERROR, "result before the TLast of the rest of the packet");
                checkRes(1, Len_v, '0', ErrInt_c, "packet several chunks longer than the buffer");
                waitPackets(Pkts_v + 1);
                checkMem(region(2), Len_v, Len_v, source(2), "packet several chunks longer than the buffer");
                -- The next packet is written completely by the next command
                Gen.Percent <= 100;
                Len_v       := minimum(3 * StreamBytes_c + 7, MaxLen_c);
                transfer(region(3), Len_v, source(3), Len_v, "packet after the overflows");

            elsif run("test_write_errors") then
                log(ID_LOG_HDR, "TC-S2-09 error responses of the memory");
                Len_v := minimum(8 * ChunkBytes_c, MaxLen_c);

                for i in 0 to 1 loop
                    -- SLVERR on the first burst, DECERR on the burst of the fourth chunk
                    Dst_v := region(1 + 2 * i);
                    prefill(Dst_v, Len_v);
                    Mem_v.clearErrors(0);
                    -- With a buffer of fewer than eight chunks both errors are on the first byte
                    Cnt2_v := 3 * ChunkBytes_c when i = 1 and Len_v >= 8 * ChunkBytes_c else 0;
                    Resp_v := ErrSlv_c when i = 0 else ErrDec_c;
                    Mem_v.setError(0, 0, Dst_v + Cnt2_v, Dst_v + Cnt2_v, Resp_v, TbDirWrite);
                    send(source(1 + i), Len_v);
                    sendCmd(Dst_v, Len_v);
                    waitRes(i + 1);
                    check_value(Obs.Results(i).Err = ErrSlv_c or Obs.Results(i).Err = ErrDec_c, ERROR,
                                "result with an error code");
                    check_value(Obs.Results(i).Eof, '0', ERROR, "no end of packet after an error");
                    waitPackets(i + 1);
                    cycles(100);
                    -- No write after the error: the last chunk of a packet of eight chunks keeps its pre-fill
                    if Len_v >= 8 * ChunkBytes_c then
                        Cnt_v := 0;

                        for b in Len_v - ChunkBytes_c to Len_v - 1 loop
                            if Mem_v.read8(0, Dst_v + b) /= odmaMemByte(Dst_v + b, DstSeed_c) then
                                Cnt_v := Cnt_v + 1;
                            end if;
                        end loop;

                        check_value(Cnt_v, 0, ERROR, "bytes of the last chunk written after the error");
                    end if;
                end loop;

                -- The next packet is written correctly
                Mem_v.clearErrors(0);
                transfer(region(5), minimum(2 * ChunkBytes_c, MaxLen_c), source(5), minimum(2 * ChunkBytes_c, MaxLen_c),
                         "packet after the errors");

                -- A pending flush whose rest never arrives: SLVERR on the first chunk of a packet whose source stops
                -- before its TLast. Without the split the flush waits for the rest; with the split it ends at once and
                -- S2-1 waits instead. The fall of Run stops the channel within a bound (the open packet is cut), and the
                -- core reset, which also resets the stream source, recovers the channel for the next packet
                Len_v := minimum(4 * ChunkBytes_c, MaxLen_c);
                Dst_v := region(6);
                Res_v := Obs.ResCount;
                prefill(Dst_v, Len_v);
                Mem_v.setError(0, 0, Dst_v, Dst_v, ErrSlv_c, TbDirWrite);
                clearStream;
                send(source(6), Len_v);
                sendCmd(Dst_v, Len_v);
                -- The source stops after one and a half chunks and the beats that the split holds, or after half of a
                -- shorter packet
                odmaWaitAtLeast(Obs.Beats, minimum(ChunkBeats_c + ChunkBeats_c / 2 + SplitLag_c, Len_v / StreamBytes_c / 2),
                                1 ms, "stream beats before the stall");
                Gen.Hold <= '1';
                if Len_v >= 2 * ChunkBytes_c then
                    -- The first chunk is complete: its error result comes, then the flush of the rest
                    waitRes(Res_v + 1);
                    check_value(Obs.Results(Res_v mod MaxResults_c).Err, ErrSlv_c, ERROR, "pending flush: write error");
                    cycles(200);
                    if not Split_g then
                        check_value(Stopped, '0', ERROR, "pending flush: the flush waits for the rest of the packet");
                    end if;
                end if;
                ChRun <= '0';
                if Stopped = '0' then
                    wait until Stopped = '1' for 1000 * ClkPeriod_c;
                end if;
                check_value(Stopped, '1', ERROR, "pending flush: Stopped within 1000 clock cycles after the fall of Run");
                -- Without a complete chunk the transfer ends with its result now
                waitRes(Res_v + 1);
                -- The core reset after the drain, as the soft reset of the core does it
                ChDrain  <= '1';
                odmaWaitHighAtEdge(Clk, Stopped, 1 ms, "Stopped after the drain");
                RstIn    <= '1';
                cycles(2);
                RstIn    <= '0';
                ChDrain  <= '0';
                Gen.Hold <= '0';
                Mem_v.clearErrors(0);
                cycles(10);
                ChRun    <= '1';
                transfer(region(7), minimum(2 * ChunkBytes_c, MaxLen_c), source(7), minimum(2 * ChunkBytes_c, MaxLen_c),
                         "packet after the core reset");

            elsif run("test_beyond_top") then
                log(ID_LOG_HDR, "TC-S2-10 the top of the address space, a buffer length of 0");
                Len_v := minimum(100, MaxLen_c);
                Dst_v := topAddr - Len_v + 1;
                Mem_v.fill(0, Dst_v - Guard_c, Len_v + Guard_c, DstSeed_c);
                Mem_v.setWindow(0, Dst_v, topAddr);
                send(source(1), Len_v);
                sendCmd(Dst_v, Len_v);
                waitRes(1);
                checkRes(0, Len_v, '1', ErrNone_c, "buffer ending at the top of the address space");
                Cnt_v := 0;

                for i in 0 to Len_v - 1 loop
                    if Mem_v.read8(0, Dst_v + i) /= odmaMemByte(source(1) + i, SrcSeed_c) then
                        Cnt_v := Cnt_v + 1;
                    end if;
                end loop;

                check_value(Cnt_v, 0, ERROR, "wrong bytes in the buffer at the top of the address space");
                -- One byte beyond the top and a length of 0: no write, no stream data
                Cnt_v := Obs.AwCount;
                clearStream;
                send(source(2), 5);
                sendCmd(Dst_v + 1, Len_v);
                waitRes(2);
                checkRes(1, 0, '0', ErrDec_c, "buffer beyond the top");
                sendCmd(region(1), 0);
                waitRes(3);
                checkRes(2, 0, '0', ErrInt_c, "buffer length of 0");
                -- A result without bytes and without the end of a packet belongs to no packet
                check_value(Obs.Results(1).Sof, '0', ERROR, "buffer beyond the top: no start of packet");
                check_value(Obs.Results(2).Sof, '0', ERROR, "buffer length of 0: no start of packet");
                check_value(Obs.AwCount, Cnt_v, ERROR, "no write burst");
                if Split_g then
                    -- The split takes no beat without a segment: the packet waits at the stream port
                    check_value(Obs.Beats, 0, ERROR, "the packet waits at the stream port");
                else
                    waitPackets(2);
                    check_value(Obs.Beats, (5 + StreamBytes_c - 1) / StreamBytes_c, ERROR,
                                "the packet waits in the buffer");
                end if;
                -- The packet goes to the next transfer
                prefill(region(1), 5);
                sendCmd(region(1), 5);
                waitRes(4);
                checkRes(3, 5, '1', ErrNone_c, "packet after the rejected commands");
                check_value(Obs.Results(3).Sof, '1', ERROR, "packet after the rejected commands: start of packet");
                checkMem(region(1), 5, 5, source(2), "packet after the rejected commands");

            elsif run("test_halt") then
                log(ID_LOG_HDR, "TC-S2-11 halt before, inside and after a packet");
                -- Before the packet: a result of 0 bytes
                sendCmd(region(1), 1000);
                cycles(20);
                ChRun <= '0';
                waitRes(1);
                checkRes(0, 0, '0', ErrNone_c, "halt before the packet");
                -- Inside the packet: the complete chunks written, the rest discarded, Stopped before the TLast
                ChRun       <= '1';
                Gen.Percent <= 30;
                -- At least 64 beats, so that the rest of the packet still arrives when the channel has stopped
                Len_v := minimum(maximum(10 * ChunkBytes_c, 64 * StreamBytes_c), MaxLen_c);
                -- Complete chunks before the halt: three, or fewer when the buffer is shorter
                Cnt2_v := maximum(0, minimum(3, MaxLen_c / ChunkBytes_c - 1));
                prefill(region(2), Len_v);
                clearStream;
                send(source(2), Len_v);
                sendCmd(region(2), Len_v);
                -- The halt half a chunk after those chunks; the beats are counted at the stream port, so the beats that
                -- the split still holds come on top
                odmaWaitAtLeast(Obs.Beats, Cnt2_v * ChunkBeats_c + ChunkBeats_c / 2 + SplitLag_c, 10 ms,
                                "stream beats before the halt");
                ChRun <= '0';
                waitRes(2);
                check_value(Obs.Results(1).Eof, '0', ERROR, "no end of packet after the halt");
                check_value(Obs.Results(1).Err, ErrNone_c, ERROR, "no error after the halt");
                Cnt_v := Obs.Results(1).Bytes;
                check_value(Cnt_v mod ChunkBytes_c = 0 and Cnt_v >= Cnt2_v * ChunkBytes_c, ERROR,
                            "complete chunks written: " & to_string(Cnt_v) & " bytes");
                odmaWaitHigh(Stopped, 1 ms, "Stopped after the halt inside the packet");
                check_value(Obs.Packets, 0, ERROR, "Stopped before the TLast of the rest");
                waitPackets(1);
                checkMem(region(2), Len_v, Cnt_v, source(2), "packet interrupted by the halt");
                -- After the packet: a halt in the clock cycle after its last beat, when its descriptor is stored but
                -- not yet at the output of the chunk buffer (with the split: while the end of the packet is still in
                -- the split), gives the normal result
                ChRun       <= '1';
                Gen.Percent <= 100;
                Len_v       := minimum(2 * StreamBytes_c + 3, MaxLen_c);
                prefill(region(4), Len_v);
                sendCmd(region(4), Len_v);
                cycles(10);
                Cnt_v       := Obs.Packets;
                send(source(6), Len_v);
                odmaWaitAtLeast(Obs.Packets, Cnt_v + 1, 1 ms, "packet sent before the halt");
                ChRun       <= '0';
                waitRes(3);
                checkRes(2, Len_v, '1', ErrNone_c, "halt in the clock cycle after the end of the packet");
                checkMem(region(4), Len_v, Len_v, source(6), "halt in the clock cycle after the end of the packet");
                -- Data of later packets received before the halt is discarded, the next packet after the restart
                -- is written completely. With the split no beat enters without a command (S2-SG-03): the later
                -- packets wait at the stream port through the halt, and after the restart each one fills the buffer
                -- of its command
                ChRun <= '1';
                send(source(3), 3 * StreamBytes_c);
                send(source(4), 5 * StreamBytes_c);
                if Split_g then
                    cycles(50);
                    Cnt_v := Obs.Beats;
                    ChRun <= '0';
                    cycles(200);
                    check_value(Obs.Beats, Cnt_v, ERROR, "no beat of the later packets without a command");
                    ChRun <= '1';
                    Res_v := Obs.ResCount;

                    for k in 0 to 1 loop
                        Len_v := (3 + 2 * k) * StreamBytes_c;
                        prefill(region(5 + k), Len_v);
                        sendCmd(region(5 + k), Len_v);
                        waitRes(Res_v + k + 1);
                        checkRes(Res_v + k, Len_v, '1', ErrNone_c, "later packet " & to_string(k));
                        checkMem(region(5 + k), Len_v, Len_v, source(3 + k), "later packet " & to_string(k));
                    end loop;

                else
                    waitPackets(3);
                    cycles(50);
                    ChRun <= '0';
                    cycles(200);
                    ChRun <= '1';
                end if;
                Len_v := minimum(2 * ChunkBytes_c + 9, MaxLen_c);
                transfer(region(3), Len_v, source(5), Len_v, "packet after the restart");

                -- A halt inside a packet whose source then stalls: S2-1 discards its rest and waits for the TLast. After
                -- a restart a command is accepted, and Run falls again before the rest arrives: the transfer of that
                -- command ends with a result of 0 bytes, and Stopped rises within a bound although the discard goes on
                -- (S2-HA-01, S2-HA-03). After the second restart the rest arrives while no command is pending: with the
                -- split the segment of the ended transfer is withdrawn, so the next packet goes completely into the
                -- buffer of the next command, which is longer
                Len_v  := minimum(4 * ChunkBytes_c, MaxLen_c);
                Len2_v := minimum(2 * StreamBytes_c, MaxLen_c);
                Mem_v.fill(0, region(7) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.fill(0, region(8) - Guard_c, Len2_v + 2 * Guard_c, DstSeed_c);
                Mem_v.fill(0, region(9) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.setWindow(0, region(7) - Guard_c, region(10));
                Res_v  := Obs.ResCount;
                Pkts_v := Obs.Packets;
                clearStream;
                sendCmd(region(7), Len_v);
                send(source(7), Len_v);
                -- The source stalls after half of the packet and the beats that the split holds
                odmaWaitAtLeast(Obs.Beats, (Len_v / StreamBytes_c) / 2 + SplitLag_c, 1 ms, "stream beats before the stall");
                Gen.Hold <= '1';
                cycles(20);
                ChRun    <= '0';
                waitRes(Res_v + 1);
                Wr_v     := Obs.Results(Res_v mod MaxResults_c).Bytes;
                check_value(Obs.Results(Res_v mod MaxResults_c).Eof, '0', ERROR,
                            "stalled packet cut by the halt: no end of packet");
                check_value(Wr_v mod ChunkBytes_c = 0, ERROR,
                            "stalled packet cut by the halt: complete chunks, " & to_string(Wr_v) & " bytes");
                checkMem(region(7), Len_v, Wr_v, source(7), "stalled packet cut by the halt");
                if Stopped = '0' then
                    wait until Stopped = '1' for 1000 * ClkPeriod_c;
                end if;
                check_value(Stopped, '1', ERROR, "Stopped while the rest of the stalled packet is discarded");
                -- A command after the restart, and the halt again before the rest arrives
                ChRun <= '1';
                sendCmd(region(8), Len2_v);
                cycles(20);
                ChRun <= '0';
                if Stopped = '0' then
                    wait until Stopped = '1' for 1000 * ClkPeriod_c;
                end if;
                check_value(Stopped, '1', ERROR, "Stopped within 1000 clock cycles after the second halt");
                waitRes(Res_v + 2);
                checkRes(Res_v + 1, 0, '0', ErrNone_c, "transfer halted while the rest is discarded");
                -- The rest arrives after the second restart, with no command pending
                ChRun    <= '1';
                cycles(10);
                Gen.Hold <= '0';
                waitPackets(Pkts_v + 1);
                cycles(20);
                -- The next packet, longer than the buffer of the ended transfer
                Cnt_v := minimum(2 * ChunkBytes_c + 3, Len_v);
                send(source(9), Cnt_v);
                sendCmd(region(9), Len_v);
                waitRes(Res_v + 3);
                checkRes(Res_v + 2, Cnt_v, '1', ErrNone_c, "packet after the discard");
                check_value(Obs.Results((Res_v + 2) mod MaxResults_c).Sof, '1', ERROR,
                            "packet after the discard: start of packet");
                checkMem(region(8), Len2_v, 0, source(9), "buffer of the transfer halted during the discard untouched");
                checkMem(region(9), Len_v, Cnt_v, source(9), "packet after the discard, complete and alone");

            elsif run("test_drain") then
                log(ID_LOG_HDR, "TC-S2-12 drain while chunks are written and the stream sends");
                Gen.Percent <= 50;
                Mem_v.setStall(0, 50);
                Mem_v.setLatency(0, 200);
                Len_v       := minimum(20 * ChunkBytes_c, MaxLen_c);
                prefill(region(1), Len_v);
                clearStream;
                send(source(1), Len_v);
                sendCmd(region(1), Len_v);
                odmaWaitAtLeast(Obs.AwCount, 1, 10 ms, "first write burst before the drain");
                ChDrain     <= '1';
                cycles(2);
                Cnt_v       := Obs.Beats;
                odmaWaitHigh(Stopped, 1 ms, "Stopped after the drain");
                cycles(100);
                check_value(Obs.Beats, Cnt_v, ERROR, "no stream beat during the drain");
                check_value(Obs.BCount, Obs.AwCount, ERROR, "every write burst answered");
                check_value(Obs.ResCount, 0, ERROR, "no result during the drain");
                Cmd_Valid   <= '1';

                for i in 1 to 100 loop
                    wait until rising_edge(Clk);
                    check_value(Cmd_Ready, '0', ERROR, "no command accepted during the drain");
                end loop;

                Cmd_Valid <= '0';

                -- A drain while the rest of a failed packet is flushed: SLVERR on the first chunk of a packet whose
                -- source stops before its TLast. Without the split the flush waits for the rest and the drain ends it;
                -- with the split the flush ends at once and the drain meets the channel waiting for data. The core
                -- reset, which also resets the stream source, recovers the channel for the next packet
                RstIn       <= '1';
                cycles(2);
                RstIn       <= '0';
                ChDrain     <= '0';
                Gen.Percent <= 100;
                Mem_v.setStall(0, 0);
                Mem_v.setLatency(0, 0);
                cycles(10);
                Len_v       := minimum(4 * ChunkBytes_c, MaxLen_c);
                Dst_v       := region(6);
                Res_v       := Obs.ResCount;
                prefill(Dst_v, Len_v);
                Mem_v.setError(0, 0, Dst_v, Dst_v, ErrSlv_c, TbDirWrite);
                clearStream;
                send(source(6), Len_v);
                sendCmd(Dst_v, Len_v);
                odmaWaitAtLeast(Obs.Beats, minimum(ChunkBeats_c + ChunkBeats_c / 2 + SplitLag_c, Len_v / StreamBytes_c / 2),
                                1 ms, "stream beats before the stall");
                Gen.Hold    <= '1';
                Exp_v       := 0;
                if Len_v >= 2 * ChunkBytes_c then
                    -- The first chunk is complete: its error result comes, then the flush of the rest
                    waitRes(Res_v + 1);
                    check_value(Obs.Results(Res_v mod MaxResults_c).Err, ErrSlv_c, ERROR, "flush: write error");
                    Exp_v := 1;
                    cycles(200);
                    if not Split_g then
                        check_value(Stopped, '0', ERROR, "flush: the flush waits for the rest of the packet");
                    end if;
                end if;
                -- With the split the channel waits for data, already with Stopped
                ChDrain <= '1';
                if Stopped = '0' then
                    odmaWaitHigh(Stopped, 1 ms, "Stopped after the drain during the flush");
                end if;
                check_value(Stopped, '1', ERROR, "Stopped after the drain during the flush");
                cycles(100);
                check_value(Obs.ResCount, Res_v + Exp_v, ERROR, "no result after the drain during the flush");
                check_value(Obs.BCount, Obs.AwCount, ERROR, "every write burst answered after the drain during the flush");
                RstIn    <= '1';
                cycles(2);
                RstIn    <= '0';
                ChDrain  <= '0';
                Gen.Hold <= '0';
                Mem_v.clearErrors(0);
                cycles(10);
                transfer(region(7), minimum(2 * ChunkBytes_c, MaxLen_c), source(7), minimum(2 * ChunkBytes_c, MaxLen_c),
                         "packet after the drain during the flush and the core reset");

            elsif run("test_ecc") then
                log(ID_LOG_HDR, "TC-S2-13 single and double errors injected into the three buffers");
                -- d = 0: single error, d = 1: double error (parity bits), d = 2: single error on a data bit, which
                -- only a channel that uses the corrected output of the buffer passes
                Len_v := minimum(3 * StreamBytes_c + 1, MaxLen_c);

                for b in 0 to 2 loop

                    for d in 0 to 2 loop
                        Sec_v          := Obs.EccSec;
                        Ded_v          := Obs.EccDed;
                        Res_v          := Obs.ResCount;
                        Dst_v          := region(1 + 3 * b + d);
                        Src_v          := source(1 + 3 * b + d);
                        wait until rising_edge(Clk);
                        EccInjDouble   <= '1' when d = 1 else '0';
                        EccInjData     <= '1' when d = 2 else '0';
                        EccInjValid    <= (others => '0');
                        EccInjValid(b) <= '1';
                        wait until rising_edge(Clk);
                        EccInjValid    <= (others => '0');
                        -- The injection applies to the next word written into the buffer. Without the split the packet
                        -- waits in the buffers for the command, its first words at their outputs; with the split it
                        -- waits at the stream port (S2-SG-03), and its first words pass the buffers after the command
                        prefill(Dst_v, Len_v);
                        send(Src_v, Len_v);
                        cycles(200);
                        sendCmd(Dst_v, Len_v);
                        waitRes(Res_v + 1);
                        checkRes(Res_v, Len_v, '1', ErrNone_c, "buffer " & to_string(b));
                        checkMem(Dst_v, Len_v, Len_v, Src_v, "buffer " & to_string(b));
                        cycles(4);

                        for i in 0 to 2 loop
                            Cnt_v  := 1 when i = b and d /= 1 else 0;
                            Cnt2_v := 1 when i = b and d = 1 else 0;
                            check_value(Obs.EccSec(i) - Sec_v(i), Cnt_v, ERROR, "Ecc_Sec of buffer " & to_string(i));
                            check_value(Obs.EccDed(i) - Ded_v(i), Cnt2_v, ERROR, "Ecc_Ded of buffer " & to_string(i));
                        end loop;

                    end loop;

                end loop;

            elsif run("test_longest_back_to_back") then
                log(ID_LOG_HDR, "TC-S2-16 transfers of the longest length back to back");
                -- The last write command of such a transfer is the longest one of the write master (gap G14); the
                -- case arises with length widths of up to 14 bits
                Len_v := minimum(MaxLen_c, 16383);

                for i in 0 to 2 loop
                    prefill(region(1 + i), Len_v);
                    send(source(1 + i), Len_v);
                    sendCmd(region(1 + i), Len_v);
                    if Obs.ResCount < i + 1 then
                        wait until Obs.ResCount >= i + 1 for 2 ms;
                    end if;
                    check_value(Obs.ResCount, i + 1, ERROR, "transfer " & to_string(i) &
                                " of the longest length completes: the write master accepts a further command");
                    checkRes(i, Len_v, '1', ErrNone_c, "transfer " & to_string(i) & " of the longest length");
                    checkMem(region(1 + i), Len_v, Len_v, source(1 + i), "transfer of the longest length");
                end loop;

            elsif run("test_error_codes") then
                log(ID_LOG_HDR, "TC-S2-15 error codes of the write responses");
                Len_v := minimum(minimum(4 * ChunkBytes_c, MaxLen_c), 16384);
                Res_v := Obs.ResCount;

                -- SLVERR, DECERR, EXOKAY in the second chunk; SLVERR first and DECERR last; DECERR first and SLVERR last.
                -- A write burst has one response: the buffers of the cases with two errors start one memory word before
                -- a 4 KB boundary, which no burst crosses, so that the two errors are in different bursts also when the
                -- buffer fits into one burst (1024-bit memory with a length width of 8 or 12)
                for i in 0 to 4 loop
                    Dst_v := region(1 + i);
                    if i >= 3 then
                        Dst_v := Dst_v + 4096 - MemBytes_c;
                    end if;
                    prefill(Dst_v, Len_v);
                    Mem_v.clearErrors(0);

                    case i is
                        when 0 =>
                            Mem_v.setError(0, 0, Dst_v + minimum(ChunkBytes_c, Len_v - 1), Dst_v + minimum(ChunkBytes_c, Len_v - 1), ErrSlv_c, TbDirWrite);
                            Resp_v := ErrSlv_c;
                        when 1 =>
                            Mem_v.setError(0, 0, Dst_v + minimum(ChunkBytes_c, Len_v - 1), Dst_v + minimum(ChunkBytes_c, Len_v - 1), ErrDec_c, TbDirWrite);
                            Resp_v := ErrDec_c;
                        when 2 =>
                            -- EXOKAY: the slave error, not the internal error code (interpretation I14)
                            Mem_v.setError(0, 0, Dst_v + minimum(ChunkBytes_c, Len_v - 1), Dst_v + minimum(ChunkBytes_c, Len_v - 1), "01", TbDirWrite);
                            Resp_v := ErrSlv_c;
                        when 3 =>
                            Mem_v.setError(0, 0, Dst_v, Dst_v, ErrSlv_c, TbDirWrite);
                            Mem_v.setError(0, 1, Dst_v + Len_v - 1, Dst_v + Len_v - 1, ErrDec_c, TbDirWrite);
                            Resp_v := ErrSlv_c;
                        when others =>
                            Mem_v.setError(0, 0, Dst_v, Dst_v, ErrDec_c, TbDirWrite);
                            Mem_v.setError(0, 1, Dst_v + Len_v - 1, Dst_v + Len_v - 1, ErrSlv_c, TbDirWrite);
                            Resp_v := ErrDec_c;
                    end case;

                    send(source(i), Len_v);
                    sendCmd(Dst_v, Len_v);
                    waitRes(Res_v + i + 1);
                    check_value(Obs.Results((Res_v + i) mod MaxResults_c).Err, Resp_v, ERROR,
                                "error code of case " & to_string(i));
                    check_value(Obs.Results((Res_v + i) mod MaxResults_c).Eof, '0', ERROR,
                                "no end of packet in case " & to_string(i));
                    waitPackets(i + 1);
                end loop;

                Mem_v.clearErrors(0);
                transfer(region(7), minimum(3 * ChunkBytes_c, MaxLen_c), source(7), minimum(3 * ChunkBytes_c, MaxLen_c),
                         "packet after the failed ones");

            elsif run("test_split") then
                log(ID_LOG_HDR, "TC-S2-17 packets over several buffers");
                Gen.Percent <= 70;
                Mem_v.setStall(0, 30);
                Mem_v.setLatency(0, 20);
                Mem_v.setWindow(0, region(1), region(1) + 40 * 5 * 8192 - 1);
                Res_v       := Obs.ResCount;
                Done_v      := 0;
                Sent_v      := 0;

                for p in 0 to 39 loop
                    -- Buffers of the packet: 1 to 5, random lengths (1 byte in packet 2)
                    rnd(1, 5, N_v);
                    Src_v := source(1 + p mod 6) + p * 977;
                    if p = 3 then
                        -- A packet without bytes: one buffer with the start and the end of packet (SGI-13)
                        send(Src_v, 0, KeepZeroLast);
                        splitBuf(region(1) + (5 * p) * 8192 + Guard_c, 64, 0, Src_v, '1', '1');
                        next;
                    end if;
                    -- The lengths: the packet ends in the last buffer; packet 0 ends exactly at a buffer end, packet 1
                    -- in addition with a last beat without valid bytes after it
                    Off_v := 0;

                    for k in 0 to N_v - 1 loop
                        if p = 2 and k = 0 then
                            Len_v := 1;
                        else
                            rnd(1, minimum(minimum(3 * ChunkBytes_c, 4096), MaxLen_c), Len_v);
                        end if;
                        if p = 1 then
                            Len_v := maximum(StreamBytes_c, Len_v - Len_v mod StreamBytes_c);
                        end if;
                        ExpLen_v((Sent_v + k) mod MaxCmds_c) := Len_v;
                        Off_v                                := Off_v + Len_v;
                    end loop;

                    -- Packet bytes: into the last buffer at least one byte
                    Len2_v := ExpLen_v((Sent_v + N_v - 1) mod MaxCmds_c);
                    if p <= 1 then
                        Wr_v := Off_v;
                    else
                        rnd(Off_v - Len2_v + 1, Off_v, Wr_v);
                    end if;
                    if p = 1 then
                        send(Src_v, Wr_v, KeepZeroLast);
                    else
                        send(Src_v, Wr_v);
                    end if;
                    Off_v := 0;

                    for k in 0 to N_v - 1 loop
                        Len_v  := ExpLen_v((Sent_v) mod MaxCmds_c);
                        Dst_v  := region(1) + (5 * p + k) * 8192 + Guard_c;
                        rnd(0, 2 * MemBytes_c, Cnt_v);
                        Dst_v  := Dst_v + Cnt_v;
                        SofB_v := '1' when k = 0 else '0';
                        EofB_v := '1' when k = N_v - 1 else '0';
                        splitBuf(Dst_v, Len_v, minimum(Len_v, Wr_v - Off_v), Src_v + Off_v, SofB_v, EofB_v);
                        Off_v  := Off_v + Len_v;
                    end loop;

                end loop;

                waitRes(Res_v + Sent_v);
                checkSplit;
                Gen.Percent <= 100;
                Mem_v.setStall(0, 0);
                Mem_v.setLatency(0, 0);

            elsif run("test_split_wait") then
                log(ID_LOG_HDR, "TC-S2-18 the rest of a packet waits for the next command");
                -- A packet without a command waits at the input
                Len_v := minimum(3 * ChunkBytes_c, MaxLen_c);
                prefill(region(1), Len_v);
                clearStream;
                send(source(1), Len_v);
                cycles(500);
                check_value(Obs.Beats, 0, ERROR, "no beat without a command");
                Res_v := Obs.ResCount;
                sendCmd(region(1), Len_v);
                waitRes(Res_v + 1);
                checkRes(Res_v, Len_v, '1', ErrNone_c, "packet after its command");
                checkMem(region(1), Len_v, Len_v, source(1), "packet after its command");
                -- The rest of a packet longer than its first buffer waits for the next command
                Len_v  := minimum(2 * ChunkBytes_c, MaxLen_c);
                Len2_v := minimum(3 * ChunkBytes_c, MaxLen_c);
                prefill(region(2), Len_v);
                Mem_v.fill(0, region(3) - Guard_c, Len2_v + 2 * Guard_c, DstSeed_c);
                Mem_v.setWindow(0, region(2) - Guard_c, region(3) + Len2_v + Guard_c);
                Res_v  := Obs.ResCount;
                send(source(2), Len_v + Len2_v);
                sendCmd(region(2), Len_v);
                waitRes(Res_v + 1);
                checkRes(Res_v, Len_v, '0', ErrNone_c, "first buffer of the packet");
                cycles(50);
                Cnt_v  := Obs.Beats;
                cycles(500);
                check_value(Obs.Beats, Cnt_v, ERROR, "no beat while no command is active");
                sendCmd(region(3), Len2_v);
                waitRes(Res_v + 2);
                checkRes(Res_v + 1, Len2_v, '1', ErrNone_c, "second buffer of the packet");
                check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '0', ERROR, "no start of packet in the second buffer");
                checkMem(region(2), Len_v, Len_v, source(2), "first buffer");
                checkMem(region(3), Len2_v, Len2_v, source(2) + Len_v, "second buffer");

            elsif run("test_split_halt") then
                log(ID_LOG_HDR, "TC-S2-19 halt, write error and drain inside a packet of several buffers");
                Len_v := minimum(2 * ChunkBytes_c, MaxLen_c);
                -- The rest after two buffers: longer than one segment of the largest size where the length width allows
                Len2_v := minimum(maximum(MaxLen_c + 100, 4 * ChunkBytes_c), 20000);
                Mem_v.setWindow(0, region(1) - Guard_c, region(9));

                -- Halt while the second buffer is written; the next packet follows directly and must wait for the
                -- restart (S2-HA-01: the channel resumes with the next packet that starts after the halt)
                Gen.Percent <= 50;
                clearStream;
                Res_v       := Obs.ResCount;
                Pkts_v      := Obs.Packets;
                send(source(1), 2 * Len_v + Len2_v);
                send(source(3), minimum(2 * ChunkBytes_c, MaxLen_c));
                Mem_v.fill(0, region(1) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                sendCmd(region(1), Len_v);
                waitRes(Res_v + 1);
                checkRes(Res_v, Len_v, '0', ErrNone_c, "first buffer");
                check_value(Obs.Results(Res_v mod MaxResults_c).Sof, '1', ERROR, "first buffer: start of packet");
                Mem_v.fill(0, region(2) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                sendCmd(region(2), Len_v);
                -- The halt one and a half chunks into the second buffer, or half way where it has less than two
                odmaWaitAtLeast(Obs.Beats, (Len_v + minimum(ChunkBytes_c + ChunkBytes_c / 2, Len_v / 2 + Len_v / 4)) /
                                StreamBytes_c, 1 ms, "stream beats before the halt");
                ChRun <= '0';
                waitRes(Res_v + 2);
                Wr_v  := Obs.Results((Res_v + 1) mod MaxResults_c).Bytes;
                log(ID_SEQUENCER, "bytes of the second buffer at the halt: " & to_string(Wr_v) & " of " &
                    to_string(Len_v));
                check_value(Wr_v < Len_v, ERROR, "second buffer cut by the halt");
                check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Eof, '0', ERROR, "no end of packet after the halt");
                checkMem(region(1), Len_v, Len_v, source(1), "first buffer");
                checkMem(region(2), Len_v, Wr_v, source(1) + Len_v, "second buffer: the complete chunks");
                -- The rest of the packet is discarded up to its TLast
                waitPackets(Pkts_v + 1);
                odmaWaitHigh(Stopped, 1 ms, "Stopped after the discard of the rest");
                check_value(Obs.Packets, Pkts_v + 1, ERROR, "the next packet waits while halted");
                ChRun       <= '1';
                Gen.Percent <= 100;
                Res_v       := Obs.ResCount;
                prefill(region(3), minimum(3 * ChunkBytes_c, MaxLen_c));
                sendCmd(region(3), minimum(3 * ChunkBytes_c, MaxLen_c));
                waitRes(Res_v + 1);
                checkRes(Res_v, minimum(2 * ChunkBytes_c, MaxLen_c), '1', ErrNone_c, "packet after the halt");
                check_value(Obs.Results(Res_v mod MaxResults_c).Sof, '1', ERROR, "packet after the halt: start of packet");
                checkMem(region(3), minimum(3 * ChunkBytes_c, MaxLen_c), minimum(2 * ChunkBytes_c, MaxLen_c), source(3),
                         "packet after the halt, complete");
                waitPackets(Pkts_v + 2);

                -- SLVERR on the first buffer of a packet of three buffers, the next packet directly after it; the write
                -- window over all buffers again (transfer sets it to its buffer)
                Mem_v.setWindow(0, region(1) - Guard_c, region(9));
                Res_v  := Obs.ResCount;
                Pkts_v := Obs.Packets;
                -- A buffer of four chunks and a stream without gaps: the error response of the first chunk comes
                -- while the later chunks still arrive, so the flush meets a chunk with the end of the buffer before
                -- the end of the packet
                Cnt2_v := minimum(4 * ChunkBytes_c, MaxLen_c);
                Mem_v.fill(0, region(4) - Guard_c, Cnt2_v + 2 * Guard_c, DstSeed_c);
                Mem_v.fill(0, region(5) - Guard_c, Len_v + Len2_v + 2 * Guard_c, DstSeed_c);
                Mem_v.setError(0, 0, region(4), region(4), ErrSlv_c, TbDirWrite);
                send(source(4), 3 * Cnt2_v);
                send(source(5), Len_v);
                sendCmd(region(4), Cnt2_v);
                waitRes(Res_v + 1);
                check_value(Obs.Results(Res_v mod MaxResults_c).Err, ErrSlv_c, ERROR, "write error of the first buffer");
                check_value(Obs.Results(Res_v mod MaxResults_c).Eof, '0', ERROR, "no end of packet");
                Mem_v.clearErrors(0);
                sendCmd(region(5), Len_v + Len2_v);
                waitRes(Res_v + 2);
                checkRes(Res_v + 1, Len_v, '1', ErrNone_c, "next packet");
                check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '1', ERROR, "next packet: start of packet");
                checkMem(region(5), Len_v + Len2_v, Len_v, source(5), "next packet, nothing of the failed one");
                waitPackets(Pkts_v + 2);

                -- The same with a short rest of the failed packet and slow write responses: the discard of the rest
                -- ends while S2-2 still waits for the responses of the failed buffer, and the next packet, already at
                -- the split, must not be discarded as well (one discard per flush)
                Res_v  := Obs.ResCount;
                Pkts_v := Obs.Packets;
                Mem_v.setLatency(0, 200);
                Mem_v.fill(0, region(4) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.fill(0, region(5) - Guard_c, Len_v + Len2_v + 2 * Guard_c, DstSeed_c);
                Mem_v.setError(0, 0, region(4), region(4), ErrSlv_c, TbDirWrite);
                send(source(4), Len_v + 2 * StreamBytes_c);
                send(source(6), Len_v);
                sendCmd(region(4), Len_v);
                waitRes(Res_v + 1);
                check_value(Obs.Results(Res_v mod MaxResults_c).Err, ErrSlv_c, ERROR, "write error, slow responses");
                Mem_v.clearErrors(0);
                Mem_v.setLatency(0, 0);
                sendCmd(region(5), Len_v + Len2_v);
                waitRes(Res_v + 2);
                checkRes(Res_v + 1, Len_v, '1', ErrNone_c, "next packet after the short rest");
                check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '1', ERROR,
                            "next packet after the short rest: start of packet");
                checkMem(region(5), Len_v + Len2_v, Len_v, source(6), "next packet after the short rest, complete");
                waitPackets(Pkts_v + 2);

                -- A command accepted just before a halt, without a packet: its segment must not stay in the split. A
                -- left segment of that buffer length would take the whole next packet, longer than its own buffer,
                -- and overflow it
                Res_v := Obs.ResCount;
                Mem_v.fill(0, region(8) - Guard_c, Len_v + Len2_v + 2 * Guard_c, DstSeed_c);
                sendCmd(region(8), Len_v + Len2_v);
                -- The halt in the clock cycle after the command handshake
                ChRun  <= '0';
                waitRes(Res_v + 1);
                checkRes(Res_v, 0, '0', ErrNone_c, "command without a packet before the halt");
                odmaWaitHigh(Stopped, 1 ms, "Stopped after the command without a packet");
                cycles(5);
                ChRun  <= '1';
                Pkts_v := Obs.Packets;
                Mem_v.fill(0, region(9) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.fill(0, region(10) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.setWindow(0, region(1) - Guard_c, region(11));
                send(source(8), Len_v + Len_v / 2);
                sendCmd(region(9), Len_v);
                sendCmd(region(10), Len_v);
                waitRes(Res_v + 3);
                checkRes(Res_v + 1, Len_v, '0', ErrNone_c, "new packet, first buffer");
                check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '1', ERROR, "new packet: start of packet");
                checkRes(Res_v + 2, Len_v / 2, '1', ErrNone_c, "new packet, second buffer");
                checkMem(region(8), Len_v + Len2_v, 0, source(8), "buffer of the command before the halt untouched");
                checkMem(region(9), Len_v, Len_v, source(8), "new packet, first buffer");
                checkMem(region(10), Len_v, Len_v / 2, source(8) + Len_v, "new packet, second buffer");
                waitPackets(Pkts_v + 1);

                -- A halt while the split holds the first beat of a packet (no beat has reached the chunk former):
                -- the packet started before the halt and is discarded; the next packet arrives complete
                Res_v  := Obs.ResCount;
                Pkts_v := Obs.Packets;
                -- A stream with a beat in about 2 % of the clock cycles: the halt follows the first beat at once,
                -- while the split still holds it for the next beat
                Gen.Percent <= 2;
                Mem_v.fill(0, region(9) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.fill(0, region(10) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                clearStream;
                send(source(9), Len_v);
                send(source(10), Len_v / 2);
                sendCmd(region(9), Len_v);
                odmaWaitAtLeast(Obs.Beats, 1, 1 ms, "first stream beat before the halt");
                ChRun       <= '0';
                waitRes(Res_v + 1);
                checkRes(Res_v, 0, '0', ErrNone_c, "packet whose first beat waits in the split at the halt");
                Gen.Percent <= 100;
                waitPackets(Pkts_v + 1);
                odmaWaitHigh(Stopped, 1 ms, "Stopped after the discarded packet");
                ChRun       <= '1';
                sendCmd(region(10), Len_v);
                waitRes(Res_v + 2);
                checkRes(Res_v + 1, Len_v / 2, '1', ErrNone_c, "packet after the discarded one");
                check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '1', ERROR, "start of packet");
                checkMem(region(9), Len_v, 0, source(9), "buffer of the discarded packet untouched");
                checkMem(region(10), Len_v, Len_v / 2, source(10), "packet after the discarded one, complete");
                waitPackets(Pkts_v + 2);

                -- A halt in the clock cycle after the TLast of a packet that ends one byte beyond its buffer: the split
                -- ends the segment with the beat that fills the buffer and holds the last byte with the end of the
                -- packet for the next buffer. The packet is not complete in its buffer, so the halt cuts it: the buffer
                -- holds complete chunks or is full, the byte is discarded, and the next packet arrives complete and alone
                Res_v       := Obs.ResCount;
                Pkts_v      := Obs.Packets;
                Gen.Percent <= 100;
                Mem_v.fill(0, region(11) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.fill(0, region(12) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                -- The write window over the two buffers of this step only
                Mem_v.setWindow(0, region(11) - Guard_c, region(13));
                sendCmd(region(11), Len_v);
                cycles(10);
                send(source(11), Len_v + 1);
                odmaWaitAtLeast(Obs.Packets, Pkts_v + 1, 1 ms, "packet sent before the halt");
                ChRun <= '0';
                waitRes(Res_v + 1);
                Wr_v  := Obs.Results(Res_v mod MaxResults_c).Bytes;
                check_value((Wr_v = Len_v or Wr_v mod ChunkBytes_c = 0) and Wr_v <= Len_v, ERROR,
                            "buffer before the halt: complete chunks or full, " & to_string(Wr_v) & " bytes");
                check_value(Obs.Results(Res_v mod MaxResults_c).Eof, '0', ERROR, "buffer before the halt: no end of packet");
                checkMem(region(11), Len_v, Wr_v, source(11), "buffer before the halt");
                odmaWaitHigh(Stopped, 1 ms, "Stopped after the halt behind the end of the buffer");
                ChRun <= '1';
                send(source(12), Len_v / 2);
                sendCmd(region(12), Len_v);
                waitRes(Res_v + 2);
                checkRes(Res_v + 1, Len_v / 2, '1', ErrNone_c, "packet after the cut one");
                check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '1', ERROR,
                            "packet after the cut one: start of packet");
                checkMem(region(12), Len_v, Len_v / 2, source(12), "packet after the cut one, complete and alone");
                waitPackets(Pkts_v + 2);

                -- A packet of one beat and one of two beats, the halt in the clock cycle after the TLast: no beat of the
                -- packet has reached the chunk former, its end is in the split, so only EndPend keeps it open. It is
                -- written completely with the end of packet, and the next packet arrives complete and alone
                for b in 1 to 2 loop
                    Res_v  := Obs.ResCount;
                    Pkts_v := Obs.Packets;
                    Cnt_v  := (b - 1) * StreamBytes_c + 1;
                    Mem_v.fill(0, region(11) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                    Mem_v.fill(0, region(12) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                    Mem_v.setWindow(0, region(11) - Guard_c, region(13));
                    sendCmd(region(11), Len_v);
                    cycles(10);
                    send(source(13 + b), Cnt_v);
                    odmaWaitAtLeast(Obs.Packets, Pkts_v + 1, 1 ms, "packet sent before the halt");
                    ChRun  <= '0';
                    waitRes(Res_v + 1);
                    checkRes(Res_v, Cnt_v, '1', ErrNone_c, "packet of " & to_string(b) & " beats halted after its TLast");
                    checkMem(region(11), Len_v, Cnt_v, source(13 + b), "packet of " & to_string(b) & " beats");
                    if Stopped = '0' then
                        odmaWaitHigh(Stopped, 1 ms, "Stopped after the halt behind the TLast");
                    end if;
                    ChRun <= '1';
                    send(source(12), Len_v / 2);
                    sendCmd(region(12), Len_v);
                    waitRes(Res_v + 2);
                    checkRes(Res_v + 1, Len_v / 2, '1', ErrNone_c, "packet after the one of " & to_string(b) & " beats");
                    check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '1', ERROR,
                                "packet after the one of " & to_string(b) & " beats: start of packet");
                    checkMem(region(12), Len_v, Len_v / 2, source(12), "packet after the one of " & to_string(b) & " beats");
                    waitPackets(Pkts_v + 2);
                end loop;

                -- A complete packet whose rest in the split meets a full data buffer right after the halt: the memory
                -- holds its write responses back for 2000 clock cycles and stalls, so the eight open transactions of
                -- the write master, its write data buffer and the data buffer fill before the TLast (16 chunks, where
                -- the length width allows) and the stream port stalls; the halt follows the TLast at once. S2-1 takes
                -- the rest once the data buffer has space, and the packet is written with the end of packet
                Len2_v := minimum(16 * ChunkBytes_c, MaxLen_c);
                Res_v  := Obs.ResCount;
                Pkts_v := Obs.Packets;
                Mem_v.fill(0, region(11) - Guard_c, Len2_v + 2 * Guard_c, DstSeed_c);
                Mem_v.fill(0, region(12) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.setWindow(0, region(11) - Guard_c, region(13));
                Mem_v.setStall(0, 90);
                Mem_v.setLatency(0, 2000);
                clearStream;
                sendCmd(region(11), Len2_v);
                send(source(16), Len2_v);
                odmaWaitAtLeast(Obs.Packets, Pkts_v + 1, 10 ms, "packet sent before the halt");
                ChRun  <= '0';
                Cnt_v  := (Len2_v + StreamBytes_c - 1) / StreamBytes_c;
                log(ID_SEQUENCER, "complete packet at a full data buffer: " & to_string(Cnt_v) & " beats in " &
                    to_string(Obs.LastSent - Obs.FirstBeat + 1) & " clock cycles at the stream port");
                waitRes(Res_v + 1);
                checkRes(Res_v, Len2_v, '1', ErrNone_c, "complete packet at a full data buffer");
                checkMem(region(11), Len2_v, Len2_v, source(16), "complete packet at a full data buffer");
                Mem_v.setStall(0, 0);
                Mem_v.setLatency(0, 0);
                if Stopped = '0' then
                    odmaWaitHigh(Stopped, 1 ms, "Stopped after the packet at a full data buffer");
                end if;
                ChRun <= '1';
                send(source(12), Len_v / 2);
                sendCmd(region(12), Len_v);
                waitRes(Res_v + 2);
                checkRes(Res_v + 1, Len_v / 2, '1', ErrNone_c, "packet after the one at a full data buffer");
                check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '1', ERROR,
                            "packet after the one at a full data buffer: start of packet");
                checkMem(region(12), Len_v, Len_v / 2, source(12), "packet after the one at a full data buffer");
                waitPackets(Pkts_v + 2);

                -- Drain inside a packet of several buffers: no further write, no result, Stopped
                Res_v       := Obs.ResCount;
                Gen.Percent <= 30;
                send(source(6), 3 * Len_v);
                Mem_v.fill(0, region(6) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.fill(0, region(7) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                -- The write window from the first to the end of the second buffer of this step
                Mem_v.setWindow(0, region(6), region(7) + Len_v - 1);
                sendCmd(region(6), Len_v);
                waitRes(Res_v + 1);
                sendCmd(region(7), Len_v);
                cycles(10);
                ChDrain <= '1';
                odmaWaitHigh(Stopped, 1 ms, "Stopped after the drain");
                Cnt_v   := Obs.AwCount;
                cycles(200);
                check_value(Obs.AwCount, Cnt_v, ERROR, "no write after the drain");
                check_value(Obs.ResCount, Res_v + 1, ERROR, "no result of the drained buffer");
                check_value(Obs.BCount, Obs.AwCount, ERROR, "every write answered");

            elsif run("test_halt_sweep") then
                log(ID_LOG_HDR, "TC-S2-21 halt at every clock cycle around the end of a packet");
                -- Buffer B of six chunks, more than the data buffer holds, at most the longest length less one byte;
                -- buffer C, one byte longer, for a packet that had not started at the halt; buffer D for the next
                -- packet, of two chunks and three bytes. One write window over the three buffers
                Len_v  := minimum(6 * ChunkBytes_c, MaxLen_c - 1);
                Len2_v := minimum(2 * ChunkBytes_c + 3, Len_v);
                Mem_v.setWindow(0, region(1) - Guard_c, region(4));
                N_v    := 0;

                for st in 0 to 1 loop

                    if st = 1 then
                        -- A slow memory: the data buffer fills, and the stream port stalls inside the long packets
                        Mem_v.setStall(0, 80);
                        Mem_v.setLatency(0, 20);
                    end if;

                    for c in 0 to 6 loop

                        -- Packet lengths at the buffer, the chunk and the beat boundaries
                        Lp_v  := Len_v - 1 when c = 0 else
                                 Len_v when c = 1 else
                                 Len_v + 1 when c = 2 else
                                 ChunkBytes_c - 1 when c = 3 else
                                 ChunkBytes_c + 1 when c = 4 else
                                 StreamBytes_c when c = 5 else
                                 StreamBytes_c + 1;
                        Cnt_v := (Lp_v + StreamBytes_c - 1) / StreamBytes_c;

                        for k in -4 to 6 loop
                            N_v      := N_v + 1;
                            Src_v    := source(1) + N_v * 4096;
                            Back_v   := source(2) + N_v * 4096;
                            Res_v    := Obs.ResCount;
                            Beats0_v := Obs.RunBeats;
                            Pkts0_v  := Obs.RunPkts;
                            Halt0_v  := Obs.HaltBeats;
                            HaltP0_v := Obs.HaltPkts;
                            Mem_v.fill(0, region(1) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                            Mem_v.fill(0, region(2) - Guard_c, Len_v + 1 + 2 * Guard_c, DstSeed_c);
                            Mem_v.fill(0, region(3) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                            sendCmd(region(1), Len_v);
                            send(Src_v, Lp_v);
                            -- The fall of Run: after the beat k beats before the last one (at once where the packet
                            -- has fewer beats), or k clock cycles after the handshake of the TLast
                            if k < 0 then
                                if Cnt_v + k >= 1 and Obs.RunBeats - Beats0_v < Cnt_v + k then
                                    odmaWaitAtLeast(Obs.RunBeats, Beats0_v + Cnt_v + k, 1 ms, sweepMsg(st, c, k) & "beats before the halt");
                                end if;
                            else
                                if Obs.RunPkts = Pkts0_v then
                                    odmaWaitAtLeast(Obs.RunPkts, Pkts0_v + 1, 1 ms, sweepMsg(st, c, k) & "TLast before the halt");
                                end if;
                                cycles(k);
                            end if;
                            ChRun <= '0';
                            -- The next packet waits behind it from the halt on: no beat of it may be taken before the restart
                            send(Back_v, Len2_v);
                            -- What the channel took while it ran
                            cycles(3);
                            Start_v := Obs.RunBeats > Beats0_v;
                            End_v   := Obs.RunPkts > Pkts0_v;
                            Took_v  := Obs.RunBeats - Beats0_v;
                            -- (1) Stopped within a bound, then the restart at once, as a driver that polls Halted
                            if Stopped = '0' then
                                wait until Stopped = '1' for 4000 * ClkPeriod_c;
                            end if;
                            check_value(Stopped, '1', ERROR, sweepMsg(st, c, k) & "Stopped within 4000 clock cycles");
                            ChRun <= '1';
                            -- The result of buffer B
                            waitRes(Res_v + 1);
                            Wr_v := Obs.Results(Res_v mod MaxResults_c).Bytes;
                            if End_v and Lp_v <= Len_v then
                                -- (2) The packet ended before the halt and fits: complete, with the end of packet
                                checkRes(Res_v, Lp_v, '1', ErrNone_c, sweepMsg(st, c, k) & "packet ended before the halt");
                            elsif End_v and not Split_g then
                                -- A packet longer than the buffer without the split: the overflow (S2-RS-02)
                                checkRes(Res_v, Len_v, '0', ErrInt_c, sweepMsg(st, c, k) & "overflow");
                            else
                                -- Cut: complete chunks, or with the split the full buffer, without the end of packet;
                                -- without the split a packet longer than the buffer may meet the overflow first
                                check_value(Obs.Results(Res_v mod MaxResults_c).Eof, '0', ERROR,
                                            sweepMsg(st, c, k) & "cut packet without the end of packet");
                                check_value(Obs.Results(Res_v mod MaxResults_c).Err = ErrNone_c or
                                            (not Split_g and Lp_v > Len_v and Wr_v = Len_v and
                                             Obs.Results(Res_v mod MaxResults_c).Err = ErrInt_c), ERROR,
                                            sweepMsg(st, c, k) & "cut packet: error code");
                                check_value((Wr_v mod ChunkBytes_c = 0 or Wr_v = Len_v) and Wr_v <= minimum(Lp_v, Len_v),
                                            ERROR, sweepMsg(st, c, k) & "cut packet: complete chunks, " &
                                            to_string(Wr_v) & " bytes");
                            end if;
                            -- (3) The start of packet in the first buffer of every packet, none without bytes or end
                            SofB_v := '1' when Wr_v /= 0 or Obs.Results(Res_v mod MaxResults_c).Eof = '1' else '0';
                            check_value(Obs.Results(Res_v mod MaxResults_c).Sof, SofB_v, ERROR,
                                        sweepMsg(st, c, k) & "start of packet of buffer B");
                            -- (4) Buffer B holds the bytes of the result, nothing else is written
                            checkMem(region(1), Len_v, Wr_v, Src_v, sweepMsg(st, c, k) & "buffer B");
                            Res_v := Res_v + 1;
                            if not Start_v then
                                -- The packet had not started: it is the next packet after the restart, written completely
                                -- by the next command
                                sendCmd(region(2), Len_v + 1);
                                waitRes(Res_v + 1);
                                checkRes(Res_v, Lp_v, '1', ErrNone_c, sweepMsg(st, c, k) & "packet after the restart");
                                check_value(Obs.Results(Res_v mod MaxResults_c).Sof, '1', ERROR,
                                            sweepMsg(st, c, k) & "packet after the restart: start of packet");
                                checkMem(region(2), Len_v + 1, Lp_v, Src_v, sweepMsg(st, c, k) & "buffer C");
                                Res_v := Res_v + 1;
                            else
                                checkMem(region(2), Len_v + 1, 0, Src_v, sweepMsg(st, c, k) & "buffer C untouched");
                            end if;
                            -- (3) The next packet: complete, alone and with the start of packet; no byte of the cut packet
                            sendCmd(region(3), Len_v);
                            waitRes(Res_v + 1);
                            checkRes(Res_v, Len2_v, '1', ErrNone_c, sweepMsg(st, c, k) & "next packet");
                            check_value(Obs.Results(Res_v mod MaxResults_c).Sof, '1', ERROR,
                                        sweepMsg(st, c, k) & "next packet: start of packet");
                            checkMem(region(3), Len_v, Len2_v, Back_v, sweepMsg(st, c, k) & "buffer D");
                            -- (5) Taken while halted: only the rest of a cut packet, at most up to its TLast and all of it when the
                            -- TLast came; nothing of a packet that had not started or had ended, so no beat of the next packet
                            Cnt2_v := Obs.HaltBeats - Halt0_v;
                            if Start_v and not End_v then
                                check_value(Cnt2_v <= Cnt_v - Took_v and Obs.HaltPkts - HaltP0_v <= 1 and
                                            (Obs.HaltPkts = HaltP0_v or Cnt2_v = Cnt_v - Took_v), ERROR,
                                            sweepMsg(st, c, k) & "taken while halted: " & to_string(Cnt2_v) & " beats");
                            else
                                check_value(Cnt2_v, 0, ERROR, sweepMsg(st, c, k) & "no beat taken while halted");
                            end if;
                        end loop;

                    end loop;

                end loop;

                Mem_v.setStall(0, 0);
                Mem_v.setLatency(0, 0);
                log(ID_SEQUENCER, "halts: " & to_string(N_v));

            elsif run("test_keyhole") then
                log(ID_LOG_HDR, "TC-S2-20 keyhole writes with FIXED bursts");

                for i in 0 to 5 loop
                    Len_v := 1 when i = 0 else
                             MemBytes_c when i = 1 else
                             16 * MemBytes_c when i = 2 else
                             17 * MemBytes_c when i = 3 else
                             7 * ChunkBytes_c / 2;
                    Len_v := minimum(minimum(Len_v, MaxLen_c), 16384);

                    for ofs in 0 to 1 loop
                        -- The window: the last memory word of a 4 KB page, at an unaligned address for ofs 1; the last
                        -- case the top of the address space
                        if i = 5 then
                            Win_v := topAddr - MemBytes_c + 1;
                        else
                            Win_v := region(1) + (2 * i + ofs + 1) * 4096 - MemBytes_c;
                        end if;
                        if ofs = 1 then
                            Win_v := Win_v + MemBytes_c / 2;
                        end if;
                        Back_v    := region(3) + (2 * i + ofs) * 32768;
                        Mem_v.setFifo(0, Win_v, Back_v);
                        prefill(Back_v, Len_v);
                        FixedAddr <= std_logic_vector(Win_v - (Win_v mod MemBytes_c));
                        Cnt_v     := Obs.AwFixed;
                        Res_v     := Obs.ResCount;
                        send(source(i), Len_v);
                        sendCmd(Win_v, Len_v, '1');
                        waitRes(Res_v + 1);
                        checkRes(Res_v, Len_v, '1', ErrNone_c, "keyhole write of " & to_string(Len_v) & " bytes");
                        checkMem(Back_v, Len_v, Len_v, source(i), "keyhole write: the backing range of the window");
                        -- One write command per chunk, each in FIXED bursts of at most FixedBeats_c beats
                        N_v := (Len_v / ChunkBytes_c) *
                               (((ChunkBytes_c / MemBytes_c) + FixedBeats_c - 1) / FixedBeats_c);
                        if Len_v mod ChunkBytes_c /= 0 then
                            N_v := N_v + ((((Len_v mod ChunkBytes_c) + MemBytes_c - 1) / MemBytes_c) + FixedBeats_c - 1) /
                                   FixedBeats_c;
                        end if;
                        check_value(Obs.AwFixed - Cnt_v, N_v, ERROR, "FIXED bursts of the keyhole write");
                        check_value(Obs.AwFixLong, 0, ERROR, "no FIXED burst longer than 16 beats");
                        check_value(Obs.AwFixAddr, 0, ERROR, "every FIXED burst at the window word");
                        -- An incrementing write after the keyhole write
                        Cnt_v := Obs.AwFixed;
                        transfer(region(2) + 16384, minimum(3 * MemBytes_c, MaxLen_c), source(7),
                                 minimum(3 * MemBytes_c, MaxLen_c), "incrementing write after it");
                        check_value(Obs.AwFixed, Cnt_v, ERROR, "no FIXED burst of an incrementing write");
                    end loop;

                end loop;

                -- Split_g: a keyhole packet over two buffers at the same window continues in the backing range
                if Split_g then
                    Len_v     := minimum(4 * MemBytes_c, MaxLen_c - MaxLen_c mod MemBytes_c);
                    Len2_v    := minimum(3 * MemBytes_c, MaxLen_c);
                    Win_v     := region(1) + 64 * 4096;
                    Back_v    := region(6);
                    Mem_v.setFifo(0, Win_v, Back_v);
                    prefill(Back_v, Len_v + Len2_v);
                    FixedAddr <= std_logic_vector(Win_v);
                    Res_v     := Obs.ResCount;
                    send(source(5), Len_v + Len2_v);
                    sendCmd(Win_v, Len_v, '1');
                    sendCmd(Win_v, Len2_v, '1');
                    waitRes(Res_v + 2);
                    checkRes(Res_v, Len_v, '0', ErrNone_c, "first keyhole buffer");
                    checkRes(Res_v + 1, Len2_v, '1', ErrNone_c, "second keyhole buffer");
                    checkMem(Back_v, Len_v + Len2_v, Len_v + Len2_v, source(5), "keyhole packet over two buffers");
                end if;

            elsif run("test_overlap") then
                log(ID_LOG_HDR, "TC-S2-22 the next command while the write responses are outstanding");
                -- Three packets of different lengths, each ending in its buffer, the write responses 300 clock cycles
                -- late: the second command is accepted before the first result, the third only after it
                Len_v  := minimum(2 * ChunkBytes_c, MaxLen_c);
                Res_v  := Obs.ResCount;
                Pkts_v := Obs.Packets;
                Mem_v.setLatency(0, 300);
                Mem_v.setWindow(0, region(1), region(3) + Len_v - 1);

                for k in 0 to 2 loop
                    Mem_v.fill(0, region(1 + k) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                    send(source(1 + k), Len_v - k);
                end loop;

                sendCmd(region(1), Len_v);
                sendCmd(region(2), Len_v);
                check_value(Obs.ResCount, Res_v, ERROR, "second command accepted before the first result");
                sendCmd(region(3), Len_v);
                check_value(Obs.ResCount >= Res_v + 1, ERROR, "third command accepted only after the first result");
                waitRes(Res_v + 3);

                for k in 0 to 2 loop
                    checkRes(Res_v + k, Len_v - k, '1', ErrNone_c, "packet " & to_string(k) & " in command order");
                    check_value(Obs.Results((Res_v + k) mod MaxResults_c).Sof, '1', ERROR,
                                "packet " & to_string(k) & ": start of packet");
                    checkMem(region(1 + k), Len_v, Len_v - k, source(1 + k), "packet " & to_string(k));
                end loop;

                waitPackets(Pkts_v + 3);

                -- With the split the same for a packet over three buffers: the start of packet only in the first
                -- result, the end only in the last
                if Split_g then
                    Res_v  := Obs.ResCount;
                    Pkts_v := Obs.Packets;

                    for k in 0 to 2 loop
                        Mem_v.fill(0, region(1 + k) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                    end loop;

                    send(source(4), 2 * Len_v + Len_v / 2);
                    sendCmd(region(1), Len_v);
                    sendCmd(region(2), Len_v);
                    check_value(Obs.ResCount, Res_v, ERROR, "second buffer accepted before the first result");
                    sendCmd(region(3), Len_v);
                    check_value(Obs.ResCount >= Res_v + 1, ERROR, "third buffer accepted only after the first result");
                    waitRes(Res_v + 3);

                    for k in 0 to 2 loop
                        Wr_v   := Len_v when k < 2 else Len_v / 2;
                        EofB_v := '1' when k = 2 else '0';
                        SofB_v := '1' when k = 0 else '0';
                        checkRes(Res_v + k, Wr_v, EofB_v, ErrNone_c, "buffer " & to_string(k) & " of the packet");
                        check_value(Obs.Results((Res_v + k) mod MaxResults_c).Sof, SofB_v, ERROR,
                                    "buffer " & to_string(k) & " of the packet: start of packet");
                        checkMem(region(1 + k), Len_v, Wr_v, source(4) + k * Len_v,
                                 "buffer " & to_string(k) & " of the packet");
                    end loop;

                    waitPackets(Pkts_v + 1);
                end if;

                -- 24 packets of random lengths (with the split over one to three buffers) with a random response
                -- latency of 0 to 150 clock cycles per packet and 50 % stall: every result in command order
                Mem_v.setStall(0, 50);
                Mem_v.setWindow(0, region(1), region(1) + 24 * 3 * 8192 - 1);
                Res_v  := Obs.ResCount;
                Done_v := 0;
                Sent_v := 0;

                for p in 0 to 23 loop
                    rnd(0, 150, Cnt2_v);
                    Mem_v.setLatency(0, Cnt2_v);
                    N_v := 1;
                    if Split_g then
                        rnd(1, 3, N_v);
                    end if;
                    Src_v := source(1 + p mod 6) + p * 977;
                    Off_v := 0;

                    for k in 0 to N_v - 1 loop
                        rnd(1, minimum(minimum(3 * ChunkBytes_c, 4096), MaxLen_c), Len_v);
                        ExpLen_v((Sent_v + k) mod MaxCmds_c) := Len_v;
                        Off_v                                := Off_v + Len_v;
                    end loop;

                    -- The packet ends in its last buffer
                    Len2_v := ExpLen_v((Sent_v + N_v - 1) mod MaxCmds_c);
                    rnd(Off_v - Len2_v + 1, Off_v, Wr_v);
                    send(Src_v, Wr_v);
                    Off_v  := 0;

                    for k in 0 to N_v - 1 loop
                        Len_v  := ExpLen_v(Sent_v mod MaxCmds_c);
                        Dst_v  := region(1) + (3 * p + k) * 8192 + Guard_c;
                        rnd(0, 2 * MemBytes_c, Cnt_v);
                        Dst_v  := Dst_v + Cnt_v;
                        SofB_v := '1' when k = 0 else '0';
                        EofB_v := '1' when k = N_v - 1 else '0';
                        splitBuf(Dst_v, Len_v, minimum(Len_v, Wr_v - Off_v), Src_v + Off_v, SofB_v, EofB_v);
                        Off_v  := Off_v + Len_v;
                    end loop;

                end loop;

                waitRes(Res_v + Sent_v);
                checkSplit;
                Mem_v.setStall(0, 0);

                -- A drain while a result is queued, its write responses 400 clock cycles late: Stopped only once every
                -- write is answered, and no result (S2-HA-02)
                Len_v  := minimum(2 * ChunkBytes_c, MaxLen_c);
                Cnt_v  := (Len_v + ChunkBytes_c - 1) / ChunkBytes_c;
                Res_v  := Obs.ResCount;
                Mem_v.setLatency(0, 400);
                Mem_v.fill(0, region(12) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.setWindow(0, region(12), region(12) + Len_v - 1);
                Cnt2_v := Obs.AwCount;
                send(source(12), Len_v);
                sendCmd(region(12), Len_v);
                -- Every burst of the buffer on the bus: its result is queued
                odmaWaitAtLeast(Obs.AwCount, Cnt2_v + Cnt_v, 1 ms, "every burst of the buffer before the drain");
                ChDrain <= '1';
                odmaWaitHigh(Stopped, 1 ms, "Stopped after the drain with a queued result");
                check_value(Obs.BCount, Obs.AwCount, ERROR, "every write answered before Stopped");
                cycles(100);
                check_value(Obs.ResCount, Res_v, ERROR, "no result of the queued buffer after the drain");

            elsif run("test_overlap_error") then
                log(ID_LOG_HDR, "TC-S2-23 write error of a transfer whose result waits for its write responses");
                if Split_g then
                    -- A packet of three buffers, SLVERR on the last chunk of the first buffer, the write responses late
                    -- enough that the second buffer has written chunks when the error arrives. With several chunks per
                    -- buffer, buffers of 16 chunks and the time of four chunks (each its beats and six clock cycles of
                    -- the write master): the second buffer then holds about a third to a half of its chunks, whose
                    -- write commands follow the stream; with one chunk twice the stream time of the buffer
                    Len_v       := minimum(16 * ChunkBytes_c, MaxLen_c);
                    Cnt_v       := (Len_v + ChunkBytes_c - 1) / ChunkBytes_c;
                    Cnt2_v      := 4 * (ChunkBeats_c + 6) when Cnt_v > 1 else 2 * (Len_v / StreamBytes_c) + 100;
                    Res_v       := Obs.ResCount;
                    Pkts_v      := Obs.Packets;
                    Gen.Percent <= 100;

                    for k in 0 to 3 loop
                        Mem_v.fill(0, region(1 + k) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                    end loop;

                    -- The write window over the two buffers that may be written
                    Mem_v.setWindow(0, region(1), region(2) + Len_v - 1);
                    Mem_v.setLatency(0, Cnt2_v);
                    Mem_v.setError(0, 0, region(1) + Len_v - 1, region(1) + Len_v - 1, ErrSlv_c, TbDirWrite);
                    send(source(1), 2 * Len_v + Len_v / 2);
                    sendCmd(region(1), Len_v);
                    sendCmd(region(2), Len_v);
                    check_value(Obs.ResCount, Res_v, ERROR, "second buffer accepted before the first result");
                    -- The third command waits at the interface until the error result, as the engine withdraws it then:
                    -- it is never accepted
                    Cmd_Addr   <= std_logic_vector(region(3));
                    Cmd_Length <= Len_v;
                    Cmd_Valid  <= '1';
                    Took_v     := 0;
                    Lp_v       := Obs.Cycle;

                    -- The handshakes of the clock edges before the one that counts the result
                    while Obs.ResCount = Res_v and Obs.Cycle < Lp_v + 200000 loop
                        wait until rising_edge(Clk);
                        if Cmd_Ready = '1' and Obs.ResCount = Res_v then
                            Took_v := Took_v + 1;
                        end if;
                    end loop;

                    Cmd_Valid <= '0';
                    check_value(Took_v, 0, ERROR, "third command not accepted");
                    check_value(Obs.Results(Res_v mod MaxResults_c).Err, ErrSlv_c, ERROR, "first buffer: write error");
                    check_value(Obs.Results(Res_v mod MaxResults_c).Eof, '0', ERROR, "first buffer: no end of packet");
                    -- The engine halts after the status write of the error: the second result comes only after the halt
                    cycles(Cnt2_v + 200);
                    check_value(Obs.ResCount, Res_v + 1, ERROR, "second result only after the halt");
                    ChRun   <= '0';
                    Halt0_v := Obs.Cycle;
                    waitRes(Res_v + 2);
                    check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Cycle > Halt0_v, ERROR,
                                "second result after the halt");
                    Wr_v    := Obs.Results((Res_v + 1) mod MaxResults_c).Bytes;
                    log(ID_SEQUENCER, "second buffer: " & to_string(Wr_v) & " of " & to_string(Len_v) &
                        " bytes written before the error, response latency " & to_string(Cnt2_v));
                    checkRes(Res_v + 1, Wr_v, '0', ErrNone_c, "second buffer");
                    check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '0', ERROR,
                                "second buffer: no start of packet");
                    check_value(Wr_v > 0 and (Wr_v mod ChunkBytes_c = 0 or Wr_v = Len_v), ERROR,
                                "second buffer: complete chunks written before the error, " & to_string(Wr_v) & " bytes");
                    if Cnt_v > 1 then
                        check_value(Wr_v < Len_v, ERROR, "second buffer: no write after the error, " & to_string(Wr_v) &
                                    " bytes");
                    end if;
                    checkMem(region(2), Len_v, Wr_v, source(1) + Len_v, "second buffer: bytes beyond the failing one");
                    checkMem(region(3), Len_v, 0, source(1), "third buffer: not written");
                    odmaWaitHigh(Stopped, 1000 * ClkPeriod_c, "Stopped within 1000 clock cycles after the second result");
                    waitPackets(Pkts_v + 1);
                    Mem_v.clearErrors(0);
                    Mem_v.setLatency(0, 0);
                    -- After the restart the next packet is complete with the start of packet
                    ChRun <= '1';
                    Mem_v.setWindow(0, region(4), region(4) + Len_v - 1);
                    send(source(4), Len_v / 2);
                    sendCmd(region(4), Len_v);
                    waitRes(Res_v + 3);
                    checkRes(Res_v + 2, Len_v / 2, '1', ErrNone_c, "packet after the restart");
                    check_value(Obs.Results((Res_v + 2) mod MaxResults_c).Sof, '1', ERROR,
                                "packet after the restart: start of packet");
                    checkMem(region(4), Len_v, Len_v / 2, source(4), "packet after the restart, complete and alone");
                    waitPackets(Pkts_v + 2);
                end if;

                -- SLVERR on the last chunk of a packet that ends in its buffer, the next packet at once: the next
                -- command is accepted before the error arrives; that transfer writes nothing after the error and ends
                -- with the halt, which comes 600 clock cycles after the error result, without the end of packet even
                -- when the next packet has arrived completely (S2-RS-03, SGI-15)
                Len_v   := minimum(4 * ChunkBytes_c, MaxLen_c);
                Res_v   := Obs.ResCount;
                Pkts_v  := Obs.Packets;
                Mem_v.fill(0, region(5) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.fill(0, region(6) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                Mem_v.setWindow(0, region(5), region(6) + Len_v - 1);
                Mem_v.setLatency(0, 400);
                Mem_v.setError(0, 0, region(5) + Len_v - 1, region(5) + Len_v - 1, ErrSlv_c, TbDirWrite);
                send(source(5), Len_v);
                send(source(6), Len_v);
                sendCmd(region(5), Len_v);
                sendCmd(region(6), Len_v);
                check_value(Obs.ResCount, Res_v, ERROR, "next command accepted before the error result");
                waitRes(Res_v + 1);
                check_value(Obs.Results(Res_v mod MaxResults_c).Err, ErrSlv_c, ERROR, "packet with the write error");
                check_value(Obs.Results(Res_v mod MaxResults_c).Eof, '0', ERROR, "packet with the write error: no end");
                cycles(600);
                check_value(Obs.ResCount, Res_v + 1, ERROR, "next packet: its result only after the halt");
                ChRun   <= '0';
                Halt0_v := Obs.Cycle;
                waitRes(Res_v + 2);
                check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Cycle > Halt0_v, ERROR,
                            "next packet: its result after the halt");
                Wr_v    := Obs.Results((Res_v + 1) mod MaxResults_c).Bytes;
                log(ID_SEQUENCER, "next packet: " & to_string(Wr_v) & " of " & to_string(Len_v) &
                    " bytes written before the error");
                -- The form of a packet cut by the halt: complete chunks or the whole packet, no end of packet, the
                -- start of packet as received
                check_value(Wr_v mod ChunkBytes_c = 0 or Wr_v = Len_v, ERROR,
                            "next packet cut: " & to_string(Wr_v) & " bytes, complete chunks");
                checkRes(Res_v + 1, Wr_v, '0', ErrNone_c, "next packet cut after the error");
                SofB_v := '1' when Wr_v > 0 else '0';
                check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, SofB_v, ERROR, "next packet: start of packet");
                checkMem(region(6), Len_v, Wr_v, source(6), "next packet cut after the error");
                if Stopped = '0' then
                    odmaWaitHigh(Stopped, 1 ms, "Stopped after the next packet cut");
                end if;
                waitPackets(Pkts_v + 2);
                Mem_v.clearErrors(0);
                Mem_v.setLatency(0, 0);
                ChRun <= '1';

                -- With several chunks: SLVERR on the first chunk, the next command presented after that response and
                -- before the result; it is accepted only after the result (no command while the queued result has an
                -- error)
                if 2 * ChunkBytes_c <= MaxLen_c then
                    Res_v  := Obs.ResCount;
                    Pkts_v := Obs.Packets;
                    Mem_v.fill(0, region(8) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                    Mem_v.fill(0, region(9) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                    Mem_v.setWindow(0, region(8), region(9) + Len_v - 1);
                    Mem_v.setLatency(0, 300);
                    Mem_v.setError(0, 0, region(8), region(8), ErrSlv_c, TbDirWrite);
                    Cnt_v  := Obs.BCount;
                    send(source(8), Len_v);
                    sendCmd(region(8), Len_v);
                    odmaWaitAtLeast(Obs.BCount, Cnt_v + 1, 1 ms, "error response of the first chunk");
                    -- The error reaches S2-2 through the write master a few clock cycles after the response
                    cycles(5);
                    check_value(Obs.ResCount, Res_v, ERROR, "error response before the result");
                    Cmd_Addr   <= std_logic_vector(region(9));
                    Cmd_Length <= Len_v;
                    Cmd_Valid  <= '1';
                    odmaWaitHighAtEdge(Clk, Cmd_Ready, 1 ms, "next command accepted");
                    Cmd_Valid  <= '0';
                    check_value(Obs.ResCount, Res_v + 1, ERROR, "next command accepted only after the error result");
                    send(source(9), Len_v / 2);
                    waitRes(Res_v + 2);
                    check_value(Obs.Results(Res_v mod MaxResults_c).Err, ErrSlv_c, ERROR, "first chunk: write error");
                    checkRes(Res_v + 1, Len_v / 2, '1', ErrNone_c, "packet after the error");
                    check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '1', ERROR,
                                "packet after the error: start of packet");
                    checkMem(region(9), Len_v, Len_v / 2, source(9), "packet after the error");
                    waitPackets(Pkts_v + 2);
                    Mem_v.clearErrors(0);
                    Mem_v.setLatency(0, 0);
                end if;

                -- With the split: a full buffer of a packet that continues is queued, its write responses 400 clock
                -- cycles late, and Run falls right after it is queued, without a next command: the halt discards the
                -- rest of the packet, and the error of the last chunk that arrives after that must not ask for a
                -- second flush: Stopped within 1000 clock cycles after the error result
                if Split_g then
                    Len_v  := minimum(4 * ChunkBytes_c, MaxLen_c);
                    Cnt_v  := (Len_v + ChunkBytes_c - 1) / ChunkBytes_c;
                    Res_v  := Obs.ResCount;
                    Pkts_v := Obs.Packets;
                    Mem_v.fill(0, region(10) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                    Mem_v.fill(0, region(11) - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                    Mem_v.setWindow(0, region(10), region(10) + Len_v - 1);
                    Mem_v.setLatency(0, 400);
                    Mem_v.setError(0, 0, region(10) + Len_v - 1, region(10) + Len_v - 1, ErrSlv_c, TbDirWrite);
                    Cnt2_v := Obs.AwCount;
                    send(source(10), 2 * Len_v);
                    sendCmd(region(10), Len_v);
                    -- Every burst of the buffer on the bus: its write commands are issued and its result is queued
                    odmaWaitAtLeast(Obs.AwCount, Cnt2_v + Cnt_v, 1 ms, "every burst of the buffer before the halt");
                    ChRun <= '0';
                    -- Not stopped while the result waits for its write responses (S2-HA-03)
                    Took_v := 0;
                    Lp_v   := Obs.Cycle;

                    while Obs.ResCount = Res_v and Obs.Cycle < Lp_v + 200000 loop
                        wait until rising_edge(Clk);
                        if Stopped = '1' and Obs.ResCount = Res_v then
                            Took_v := Took_v + 1;
                        end if;
                    end loop;

                    check_value(Took_v, 0, ERROR, "queued buffer: not stopped before its result");
                    waitRes(Res_v + 1);
                    check_value(Obs.Results(Res_v mod MaxResults_c).Err, ErrSlv_c, ERROR, "queued buffer: write error");
                    check_value(Obs.Results(Res_v mod MaxResults_c).Eof, '0', ERROR, "queued buffer: no end of packet");
                    if Stopped = '0' then
                        wait until Stopped = '1' for 1000 * ClkPeriod_c;
                    end if;
                    check_value(Stopped, '1', ERROR, "Stopped within 1000 clock cycles after the error of the queued buffer");
                    waitPackets(Pkts_v + 1);
                    Mem_v.clearErrors(0);
                    Mem_v.setLatency(0, 0);
                    ChRun <= '1';
                    Mem_v.setWindow(0, region(11), region(11) + Len_v - 1);
                    send(source(11), Len_v / 2);
                    sendCmd(region(11), Len_v);
                    waitRes(Res_v + 2);
                    checkRes(Res_v + 1, Len_v / 2, '1', ErrNone_c, "packet after the halted queued buffer");
                    check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Sof, '1', ERROR,
                                "packet after the halted queued buffer: start of packet");
                    checkMem(region(11), Len_v, Len_v / 2, source(11), "packet after the halted queued buffer, alone");
                    waitPackets(Pkts_v + 2);
                end if;

            elsif run("test_chunk_align") then
                log(ID_LOG_HDR, "TC-S2-24 the chunks of a buffer follow its address");

                -- Offsets above a burst boundary, the last two below a 4 KB boundary; at each offset k = 0: five chunks
                -- and 3 bytes, k = 1: a buffer shorter than its first chunk, k = 2 and 3: three chunks with a packet that
                -- ends inside the first and inside the second chunk, k = 4: three chunks exactly (a first chunk up to
                -- the burst boundary adds one chunk to it)
                for c in 0 to 9 loop
                    Off_v := 0 when c = 0 else
                             StreamBytes_c when c = 1 else
                             MemBytes_c when c = 2 else
                             ChunkBytes_c / 2 when c = 3 else
                             ChunkBytes_c - StreamBytes_c when c = 4 else
                             1 when c = 5 else
                             maximum(StreamBytes_c - 1, 1) when c = 6 else
                             MemBytes_c + 1 when c = 7 else
                             4096 - StreamBytes_c when c = 8 else
                             4095;

                    for k in 0 to 4 loop
                        Dst_v  := region(1 + 5 * c + k) + Off_v;
                        Wr_v   := chunkBytes(Dst_v, Off_v, false);
                        Len_v  := 5 * ChunkBytes_c + 3 when k = 0 else
                                  maximum(Wr_v / 2, 1) when k = 1 else
                                  3 * ChunkBytes_c;
                        Len_v  := minimum(Len_v, MaxLen_c);
                        Len2_v := maximum(Wr_v / 2, 1) when k = 2 else
                                  Wr_v + maximum(chunkBytes(Dst_v, Off_v + Wr_v, false) / 2, 1) when k = 3 else
                                  Len_v;
                        Len2_v := minimum(Len2_v, Len_v);
                        Cnt_v  := Obs.AwCount;
                        Cnt2_v := Obs.AwCross;
                        transfer(Dst_v, Len_v, source(c), Len2_v, "offset " & to_string(Off_v) & ", case " &
                                 to_string(k));
                        check_value(Obs.AwCount - Cnt_v, planBursts(Dst_v, Len2_v), ERROR, "offset " &
                                    to_string(Off_v) & ", case " & to_string(k) & ": AW bursts");
                        -- At a multiple of the burst size, and at a multiple of the stream width that is not one of the
                        -- memory word, every chunk lies between two multiples of the burst size
                        if Off_v mod ChunkBytes_c = 0 or
                           (Off_v mod StreamBytes_c = 0 and Off_v mod MemBytes_c /= 0) then
                            check_value(Obs.AwCross - Cnt2_v, 0, ERROR, "offset " & to_string(Off_v) & ", case " &
                                        to_string(k) & ": INCR bursts across a multiple of the burst size");
                        end if;
                    end loop;

                end loop;

                -- A packet over two buffers, the first at the stream width, the second 1 byte above a burst boundary:
                -- each with its own chunk plan
                Len_v  := minimum(2 * ChunkBytes_c + StreamBytes_c, MaxLen_c - MaxLen_c mod StreamBytes_c);
                Len2_v := minimum(3 * ChunkBytes_c, MaxLen_c);
                Dst_v  := region(51) + StreamBytes_c;
                Win_v  := region(52) + 1;
                Res_v  := Obs.ResCount;
                Done_v := 0;
                Sent_v := 0;
                Cnt_v  := Obs.AwCount;
                Mem_v.setWindow(0, Dst_v, Win_v + Len2_v - 1);
                send(source(51), Len_v + Len2_v - 1);
                splitBuf(Dst_v, Len_v, Len_v, source(51), '1', '0');
                splitBuf(Win_v, Len2_v, Len2_v - 1, source(51) + Len_v, '0', '1');
                waitRes(Res_v + 2);
                checkSplit;
                check_value(Obs.AwCount - Cnt_v, planBursts(Dst_v, Len_v) + planBursts(Win_v, Len2_v - 1), ERROR,
                            "packet over two buffers: AW bursts");

                -- A keyhole buffer one memory word above a burst boundary keeps chunks of ChunkBytes_c: N_v chunks give
                -- N_v times the FIXED bursts of a chunk, a resized first chunk one more
                N_v := minimum(3, MaxLen_c / ChunkBytes_c);
                if N_v > 0 then
                    Len_v     := N_v * ChunkBytes_c;
                    Win_v     := region(53) + ChunkBytes_c + MemBytes_c;
                    Back_v    := region(54);
                    Mem_v.setFifo(0, Win_v, Back_v);
                    prefill(Back_v, Len_v);
                    FixedAddr <= std_logic_vector(Win_v);
                    Cnt_v     := Obs.AwFixed;
                    Res_v     := Obs.ResCount;
                    send(source(53), Len_v);
                    sendCmd(Win_v, Len_v, '1');
                    waitRes(Res_v + 1);
                    checkRes(Res_v, Len_v, '1', ErrNone_c, "keyhole buffer one memory word above a burst boundary");
                    checkMem(Back_v, Len_v, Len_v, source(53), "keyhole buffer: the backing range of the window");
                    check_value(Obs.AwFixed - Cnt_v, planBursts(Win_v, Len_v, true), ERROR,
                                "keyhole buffer: FIXED bursts");
                    check_value(Obs.AwFixAddr, 0, ERROR, "every FIXED burst at the window word");
                end if;

            elsif run("test_short_rule") then
                log(ID_LOG_HDR, "TC-S2-25 the short chunks of every configuration of the generic ranges");
                N_v := 0;

                -- Memory widths 32 to 1024, stream widths 8 to the memory width, burst beats 2 to 256 (B at most the
                -- beats of 4 KB)
                for m in 5 to 10 loop

                    for s in 3 to m loop

                        for b in 1 to 8 loop
                            Cnt_v := minimum(2**b, 4096 / (2**m / 8));
                            Exp_v := planShort(2**m, 2**s, Cnt_v);
                            check_value(work.odma_s2mm_pkg.shortBeats(2**m, 2**s, Cnt_v), Exp_v, ERROR,
                                        "short chunks of " & to_string(2**m) & " / " & to_string(2**s) & " bits, " &
                                        to_string(Cnt_v) & " burst beats");
                            N_v   := N_v + 1;
                        end loop;

                    end loop;

                end loop;

                log(ID_SEQUENCER, "configurations: " & to_string(N_v));

            elsif run("test_long_packet") then
                log(ID_LOG_HDR, "TC-S2-14 a long packet with gaps and backpressure");
                Len_v       := minimum(MaxLen_c, maximum(65536, 16384 * StreamBytes_c));
                Mem_v.setStall(0, 30);
                Gen.Percent <= 50;
                transfer(region(1), Len_v, source(1), Len_v, "long packet");

            elsif run("test_result_stall") then
                log(ID_LOG_HDR, "TC-S2-26 results held by their receiver");
                -- Runs of Res_Ready low in 50 to 95 % of the clock cycles, drawn per packet: packets of one buffer, with
                -- Split_g of one to four buffers, commanded back to back; every result in order with its bytes, start
                -- and end of packet, every buffer checked in memory
                Gen.Percent <= 80;
                Mem_v.setStall(0, 20);
                Mem_v.setWindow(0, region(1), region(1) + 16 * 4 * 8192 - 1);
                Res_v       := Obs.ResCount;
                Done_v      := 0;
                Sent_v      := 0;

                for p in 0 to 15 loop
                    rnd(50, 95, Cnt_v);
                    ResStall <= Cnt_v;
                    N_v      := 1;
                    if Split_g then
                        rnd(1, 4, N_v);
                    end if;
                    Src_v := source(1 + p mod 6) + p * 977;
                    Off_v := 0;

                    for k in 0 to N_v - 1 loop
                        rnd(1, minimum(minimum(2 * ChunkBytes_c, 2048), MaxLen_c), Len_v);
                        ExpLen_v((Sent_v + k) mod MaxCmds_c) := Len_v;
                        Off_v                                := Off_v + Len_v;
                    end loop;

                    -- Packet bytes: into the last buffer at least one byte
                    Len2_v := ExpLen_v((Sent_v + N_v - 1) mod MaxCmds_c);
                    rnd(Off_v - Len2_v + 1, Off_v, Wr_v);
                    send(Src_v, Wr_v);
                    Off_v  := 0;

                    for k in 0 to N_v - 1 loop
                        Len_v  := ExpLen_v(Sent_v mod MaxCmds_c);
                        SofB_v := '1' when k = 0 else '0';
                        EofB_v := '1' when k = N_v - 1 else '0';
                        splitBuf(region(1) + (4 * p + k) * 8192 + Guard_c, Len_v, minimum(Len_v, Wr_v - Off_v),
                                 Src_v + Off_v, SofB_v, EofB_v);
                        Off_v  := Off_v + Len_v;
                    end loop;

                end loop;

                ResStall    <= 0;
                waitRes(Res_v + Sent_v);
                checkSplit;
                Gen.Percent <= 100;
                Mem_v.setStall(0, 0);

                -- Res_Ready low: the result of a packet is queued, and the next transfer ends while it waits (its result
                -- waits behind the queued one); with Split_g that transfer is the full first buffer of a packet of two
                -- buffers. Both results follow in order when Res_Ready rises, then the rest of the packet
                Len_v    := minimum(2 * ChunkBytes_c, MaxLen_c);
                Mem_v.setWindow(0, region(20), region(24) - 1);
                Res_v    := Obs.ResCount;
                Done_v   := 0;
                Sent_v   := 0;
                Cnt_v    := Obs.BCount;
                ResStall <= 100;
                send(source(20), Len_v);
                splitBuf(region(20) + Guard_c, Len_v, Len_v, source(20), '1', '1');
                if Split_g then
                    send(source(21), 2 * Len_v - 1);
                    splitBuf(region(21) + Guard_c, Len_v, Len_v, source(21), '1', '0');
                else
                    send(source(21), Len_v);
                    splitBuf(region(21) + Guard_c, Len_v, Len_v, source(21), '1', '1');
                end if;
                odmaWaitAtLeast(Obs.BCount, Cnt_v + planBursts(region(20) + Guard_c, Len_v) +
                                planBursts(region(21) + Guard_c, Len_v), 1 ms, "write responses of both transfers");
                cycles(20);
                check_value(Obs.ResCount, Res_v, ERROR, "no result while Res_Ready is low");
                ResStall <= 0;
                if Split_g then
                    splitBuf(region(22) + Guard_c, Len_v, Len_v - 1, source(21) + Len_v, '0', '1');
                end if;
                waitRes(Res_v + Sent_v);
                checkSplit;

                -- Res_Ready low: a queued result and a result waiting behind it, then Drain: neither is returned, also
                -- not when Res_Ready rises (S2-HA-02); the core reset recovers the channel
                Mem_v.setWindow(0, region(24), region(28) - 1);
                Res_v    := Obs.ResCount;
                Cnt_v    := Obs.BCount;
                ResStall <= 100;
                send(source(24), Len_v);
                sendCmd(region(24) + Guard_c, Len_v);
                send(source(25), Len_v);
                sendCmd(region(25) + Guard_c, Len_v);
                odmaWaitAtLeast(Obs.BCount, Cnt_v + planBursts(region(24) + Guard_c, Len_v) +
                                planBursts(region(25) + Guard_c, Len_v), 1 ms, "write responses before the drain");
                cycles(20);
                ChDrain  <= '1';
                odmaWaitHigh(Stopped, 1 ms, "Stopped after the drain");
                ResStall <= 0;
                cycles(100);
                check_value(Obs.ResCount, Res_v, ERROR, "no result of the drained transfers");
                RstIn    <= '1';
                cycles(2);
                RstIn    <= '0';
                ChDrain  <= '0';
                cycles(10);
                transfer(region(30), Len_v, source(30), Len_v, "packet after the drain and the core reset");

                -- Results that are not queued: transfers that fail with SLVERR on their first burst and transfers halted
                -- before their packet, Res_Ready low in runs drawn per transfer as above. Each result waits for its
                -- handshake with its bytes, end of packet and error code; after the write error the rest of the packet
                -- is flushed, and the channel goes on with the next transfer
                for p in 0 to 11 loop
                    rnd(50, 95, Cnt_v);
                    ResStall <= Cnt_v;
                    Dst_v    := region(32 + p) + Guard_c;
                    Res_v    := Obs.ResCount;
                    prefill(Dst_v, Len_v);
                    if p mod 2 = 0 then
                        Mem_v.setError(0, 0, Dst_v, Dst_v, ErrSlv_c, TbDirWrite);
                        Pkts_v := Obs.Packets;
                        send(source(32 + p), Len_v);
                        sendCmd(Dst_v, Len_v);
                        waitRes(Res_v + 1);
                        check_value(Obs.Results(Res_v mod MaxResults_c).Err, ErrSlv_c, ERROR,
                                    "write error " & to_string(p) & ": result error code");
                        check_value(Obs.Results(Res_v mod MaxResults_c).Eof, '0', ERROR,
                                    "write error " & to_string(p) & ": no end of packet");
                        waitPackets(Pkts_v + 1);
                        Mem_v.clearErrors(0);
                    else
                        sendCmd(Dst_v, Len_v);
                        cycles(20);
                        ChRun <= '0';
                        waitRes(Res_v + 1);
                        checkRes(Res_v, 0, '0', ErrNone_c, "halt before the packet " & to_string(p));
                        ChRun <= '1';
                    end if;
                end loop;

                ResStall <= 0;
                transfer(region(31), Len_v, source(31), Len_v, "packet after the write errors and the halts");

                -- A packet cut by a halt whose first burst answers SLVERR only after the cut: the result of the packet
                -- before is queued and held, so the cut transfer has taken the discard of its packet when its error
                -- arrives (write responses 300 clock cycles late). Its result carries the error and no end of packet,
                -- and no flush follows, since the rest of the cut packet is discarded at the stream port (S2-HA-01): the
                -- packet after the restart is written completely. In the configurations whose longest buffer holds two
                -- chunks
                Len_v  := minimum(maximum(8 * ChunkBytes_c, 64 * StreamBytes_c), MaxLen_c);
                Len2_v := minimum(2 * StreamBytes_c + 3, MaxLen_c);
                if Len_v >= 2 * ChunkBytes_c then
                    Dst_v       := region(50) + Guard_c;
                    Mem_v.fill(0, region(50), Len2_v + 2 * Guard_c, DstSeed_c);
                    Mem_v.fill(0, region(51), Len_v + 2 * Guard_c, DstSeed_c);
                    Mem_v.setWindow(0, region(50), region(52) - 1);
                    Res_v       := Obs.ResCount;
                    Pkts_v      := Obs.Packets;
                    ResStall    <= 100;
                    Mem_v.setLatency(0, 300);
                    Mem_v.setError(0, 0, region(51) + Guard_c, region(51) + Guard_c, ErrSlv_c, TbDirWrite);
                    clearStream;
                    send(source(50), Len2_v);
                    sendCmd(Dst_v, Len2_v);
                    Gen.Percent <= 30;
                    send(source(51), Len_v);
                    sendCmd(region(51) + Guard_c, Len_v);
                    -- The halt one and a half chunks into the second packet, plus the beats that the split holds
                    odmaWaitAtLeast(Obs.Beats, (Len2_v + StreamBytes_c - 1) / StreamBytes_c + ChunkBeats_c +
                                    ChunkBeats_c / 2 + SplitLag_c, 10 ms, "stream beats before the halt");
                    ChRun    <= '0';
                    cycles(1500);
                    check_value(Obs.ResCount, Res_v, ERROR, "late error: no result while Res_Ready is low");
                    rnd(50, 95, Cnt_v);
                    ResStall <= Cnt_v;
                    waitRes(Res_v + 2);
                    ResStall <= 0;
                    checkRes(Res_v, Len2_v, '1', ErrNone_c, "late error: packet before the cut packet");
                    checkMem(Dst_v, Len2_v, Len2_v, source(50), "late error: packet before the cut packet");
                    check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Err, ErrSlv_c, ERROR,
                                "late error: error code of the cut packet");
                    check_value(Obs.Results((Res_v + 1) mod MaxResults_c).Eof, '0', ERROR,
                                "late error: no end of packet of the cut packet");
                    waitPackets(Pkts_v + 2);
                    if Stopped = '0' then
                        wait until Stopped = '1' for 1000 * ClkPeriod_c;
                    end if;
                    check_value(Stopped, '1', ERROR, "late error: Stopped after the cut packet");
                    Gen.Percent <= 100;
                    Mem_v.setLatency(0, 0);
                    Mem_v.clearErrors(0);
                    ChRun       <= '1';
                    Len_v       := minimum(2 * ChunkBytes_c + 9, MaxLen_c);
                    transfer(region(52) + Guard_c, Len_v, source(52), Len_v, "late error: packet after the restart");
                end if;

            elsif run("test_chunk_full") then
                log(ID_LOG_HDR, "TC-S2-27 a full chunk buffer");
                -- 40 packets of one beat before any command. Without Split_g they enter until the chunk buffer (32
                -- descriptors) or the data buffer is full, then the stream waits; with Split_g no beat enters without a
                -- command (S2-SG-03). Each command then takes the next packet into a buffer of two beats: every packet
                -- once, with its bytes and its end, nothing in between
                Len_v := minimum(2 * StreamBytes_c, MaxLen_c);
                Mem_v.setWindow(0, region(1), region(4) - 1);

                for k in 0 to 39 loop
                    send(source(1) + k * 256, 1 + (7 * k) mod StreamBytes_c);
                end loop;

                cycles(500);
                Took_v := Obs.Packets;
                Cnt_v  := Obs.Beats;
                cycles(500);
                check_value(Obs.Beats, Cnt_v, ERROR, "the stream waits while no buffer is given");
                if Split_g then
                    check_value(Cnt_v, 0, ERROR, "no beat without a command");
                else
                    log(ID_SEQUENCER, to_string(Took_v) & " packets of one beat entered without a command");
                    check_value(Took_v < 40, ERROR, "the stream waits for space");
                    if BufferBeats_g > 40 then
                        check_value(Took_v >= 32, ERROR, "the chunk buffer holds 32 packets");
                    end if;
                end if;
                Res_v := Obs.ResCount;

                for k in 0 to 39 loop
                    Dst_v := region(1) + k * 1024 + Guard_c;
                    N_v   := 1 + (7 * k) mod StreamBytes_c;
                    Mem_v.fill(0, Dst_v - Guard_c, Len_v + 2 * Guard_c, DstSeed_c);
                    sendCmd(Dst_v, Len_v);
                    waitRes(Res_v + k + 1);
                    checkRes(Res_v + k, N_v, '1', ErrNone_c, "packet " & to_string(k));
                    checkMem(Dst_v, Len_v, N_v, source(1) + k * 256, "packet " & to_string(k));
                end loop;

                waitPackets(40);
                cycles(100);
                check_value(Obs.ResCount, Res_v + 40, ERROR, "one result per packet");

                -- Without Split_g: a halt while a packet is open and the chunk buffer is full. The packets before fill
                -- all but one descriptor of the chunk buffer, the open packet the last one with its first chunk; the
                -- discard descriptor of the cut waits for space, which the halted channel frees by discarding the
                -- stored packets (data received for later transfers). The rest of the cut packet is discarded up to its
                -- TLast, no write, no result, Stopped; after the restart the next packet is complete in its buffer
                if not Split_g and BufferBeats_g > 40 and BufferBeats_g > Took_v + ChunkBeats_c then
                    Cnt_v  := Obs.AwCount;
                    Pkts_v := Obs.Packets;
                    clearStream;

                    for k in 0 to Took_v - 2 loop
                        send(source(5) + k * 256, 1 + (7 * k) mod StreamBytes_c);
                    end loop;

                    send(source(6), 4 * ChunkBytes_c);
                    odmaWaitAtLeast(Obs.Beats, Took_v - 1 + ChunkBeats_c, 1 ms, "the first chunk of the open packet");
                    cycles(500);
                    check_value(Obs.Beats, Took_v - 1 + ChunkBeats_c, ERROR,
                                "the stream waits with the chunk buffer full and a packet open");
                    ChRun <= '0';
                    if Stopped = '0' then
                        wait until Stopped = '1' for 1000 * ClkPeriod_c;
                    end if;
                    check_value(Stopped, '1', ERROR, "Stopped after the halt with the chunk buffer full");
                    waitPackets(Pkts_v + Took_v);
                    cycles(100);
                    check_value(Obs.AwCount, Cnt_v, ERROR, "no write of the discarded packets");
                    check_value(Obs.ResCount, Res_v + 40, ERROR, "no result without a command");
                    ChRun <= '1';
                    Len_v := minimum(2 * ChunkBytes_c + 5, MaxLen_c);
                    transfer(region(8), Len_v, source(8), Len_v, "packet after the halt with the chunk buffer full");
                end if;

            elsif run("test_job_stage") then
                log(ID_LOG_HDR, "TC-S2-28 the stage of the feed jobs full when the next transfer starts");
                -- A packet of two full chunks with a last beat without valid bytes and a packet of one chunk, both in
                -- the data buffer before their commands, the commands back to back. The write master takes the write
                -- command of the second chunk while the feeder still moves the first one, the job of the empty beat
                -- fills the stage of the feed jobs, the first transfer queues its result, and the next transfer takes
                -- its chunk only when the feeder has freed the stage. In the second round Run falls when the next
                -- command is accepted: its packet is complete in the data buffer and is written completely
                check_value(2 * ChunkBytes_c + 1 <= MaxLen_c, ERROR, "two chunks and a byte within the longest length");
                Len_v := 2 * ChunkBytes_c;

                for k in 0 to 1 loop
                    Res_v  := Obs.ResCount;
                    Pkts_v := Obs.Packets;
                    Mem_v.setWindow(0, region(1), region(2) + ChunkBytes_c - 1);
                    Mem_v.fill(0, region(1) - Guard_c, Len_v + 1 + 2 * Guard_c, DstSeed_c);
                    Mem_v.fill(0, region(2) - Guard_c, ChunkBytes_c + 2 * Guard_c, DstSeed_c);
                    send(source(1 + 2 * k), Len_v, KeepZeroLast);
                    send(source(2 + 2 * k), ChunkBytes_c);
                    waitPackets(Pkts_v + 2);
                    cycles(50);
                    sendCmd(region(1), Len_v + 1);
                    sendCmd(region(2), ChunkBytes_c);
                    if k = 1 then
                        ChRun <= '0';
                    end if;
                    waitRes(Res_v + 2);
                    checkRes(Res_v, Len_v, '1', ErrNone_c, "round " & to_string(k) &
                             ": the packet with the empty last beat");
                    checkRes(Res_v + 1, ChunkBytes_c, '1', ErrNone_c, "round " & to_string(k) & ": the next packet");
                    checkMem(region(1), Len_v + 1, Len_v, source(1 + 2 * k), "round " & to_string(k) &
                             ": the packet with the empty last beat");
                    checkMem(region(2), ChunkBytes_c, ChunkBytes_c, source(2 + 2 * k), "round " & to_string(k) &
                             ": the next packet");
                end loop;

                if Stopped = '0' then
                    odmaWaitHigh(Stopped, 1 ms, "Stopped after the halt");
                end if;
                ChRun <= '1';
                Len_v := minimum(ChunkBytes_c + 3, MaxLen_c);
                transfer(region(3), Len_v, source(5), Len_v, "packet after the restart");
            end if;

            -- Every test case: no clock cycle without write data inside a burst while the memory is ready (S2-WR-07)
            check_value(Obs.WGaps, 0, ERROR, "clock cycles without write data inside a burst");

        end loop;

        odmaTestEnd(runner);
        wait;
    end process;

end architecture;
