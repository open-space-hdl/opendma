---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VUnit testbench of odma_s2mm: the test cases TC-S2-01 to TC-S2-14 of the verification plan. The
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
        BufferBeats_g : positive := 64
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
    signal Res_Ready    : std_logic                     := '1';
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
            BufferBeats_g => BufferBeats_g
        )
        port map (
            Clk          => Clk,
            Cmd_Valid    => Cmd_Valid,
            Cmd_Ready    => Cmd_Ready,
            Cmd_Addr     => Cmd_Addr,
            Cmd_Length   => Cmd_Length,
            Res_Ready    => Res_Ready,
            Run          => ChRun,
            Drain        => ChDrain,
            Stopped      => Stopped,
            Gen          => Gen,
            StreamClear  => StreamClear,
            EccInjValid  => EccInjValid,
            EccInjDouble => EccInjDouble,
            EccInjData   => EccInjData,
            Obs          => Obs
        );

    p_control : process is
        variable Dst_v   : Addr_t;
        variable Src_v   : Addr_t;
        variable Len_v   : natural;
        variable Len2_v  : natural;
        variable Res_v   : natural;
        variable Cnt_v   : natural;
        variable Cnt2_v  : natural;
        variable Pkts_v  : natural;
        variable Sec_v   : Nat3_a;
        variable Ded_v   : Nat3_a;
        variable Seed1_v : positive := 5;
        variable Seed2_v : positive := 93;
        variable Rand_v  : real;
        variable Resp_v  : std_logic_vector(1 downto 0);

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- One transfer command, after its handshake
        procedure sendCmd (
            dst : Addr_t;
            len : natural) is
        begin
            Cmd_Addr   <= std_logic_vector(dst);
            Cmd_Length <= len;
            Cmd_Valid  <= '1';
            wait until rising_edge(Clk) and Cmd_Ready = '1' for 1 ms;
            check_value(Cmd_Ready, '1', ERROR, "command accepted");
            Cmd_Valid  <= '0';
        end procedure;

        -- One packet of the stream generator
        procedure send (
            src   : Addr_t;
            bytes : natural;
            mode  : KeepMode_t := KeepNormal) is
        begin
            work.odma_s2mm_tb_pkg.Pkts_v.push(src, bytes, mode);
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
                check_value(Obs.AwCount, Cnt_v, ERROR, "no write burst");
                waitPackets(2);
                check_value(Obs.Beats, (5 + StreamBytes_c - 1) / StreamBytes_c, ERROR, "the packet waits in the buffer");
                -- The packet goes to the next transfer
                prefill(region(1), 5);
                sendCmd(region(1), 5);
                waitRes(4);
                checkRes(3, 5, '1', ErrNone_c, "packet after the rejected commands");
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
                Len_v       := minimum(10 * ChunkBytes_c, MaxLen_c);
                -- Complete chunks before the halt: three, or fewer when the buffer is shorter
                Cnt2_v := maximum(0, minimum(3, MaxLen_c / ChunkBytes_c - 1));
                prefill(region(2), Len_v);
                clearStream;
                send(source(2), Len_v);
                sendCmd(region(2), Len_v);
                wait until Obs.Beats >= Cnt2_v * ChunkBeats_c + ChunkBeats_c / 2 for 10 ms;
                ChRun  <= '0';
                waitRes(2);
                check_value(Obs.Results(1).Eof, '0', ERROR, "no end of packet after the halt");
                check_value(Obs.Results(1).Err, ErrNone_c, ERROR, "no error after the halt");
                Cnt_v  := Obs.Results(1).Bytes;
                check_value(Cnt_v mod ChunkBytes_c = 0 and Cnt_v >= Cnt2_v * ChunkBytes_c, ERROR,
                            "complete chunks written: " & to_string(Cnt_v) & " bytes");
                wait until Stopped = '1' for 1 ms;
                check_value(Obs.Packets, 0, ERROR, "Stopped before the TLast of the rest");
                waitPackets(1);
                checkMem(region(2), Len_v, Cnt_v, source(2), "packet interrupted by the halt");
                -- After the packet: a halt in the clock cycle after its last beat, when its descriptor is stored but
                -- not yet at the output of the chunk buffer, gives the normal result
                ChRun       <= '1';
                Gen.Percent <= 100;
                Len_v       := minimum(2 * StreamBytes_c + 3, MaxLen_c);
                prefill(region(4), Len_v);
                sendCmd(region(4), Len_v);
                cycles(10);
                Cnt_v       := Obs.Packets;
                send(source(6), Len_v);
                wait until Obs.Packets > Cnt_v for 1 ms;
                ChRun       <= '0';
                waitRes(3);
                checkRes(2, Len_v, '1', ErrNone_c, "halt in the clock cycle after the end of the packet");
                checkMem(region(4), Len_v, Len_v, source(6), "halt in the clock cycle after the end of the packet");
                -- Data of later packets received before the halt is discarded, the next packet after the restart
                -- is written completely
                ChRun <= '1';
                send(source(3), 3 * StreamBytes_c);
                send(source(4), 5 * StreamBytes_c);
                waitPackets(3);
                cycles(50);
                ChRun <= '0';
                cycles(200);
                ChRun <= '1';
                Len_v := minimum(2 * ChunkBytes_c + 9, MaxLen_c);
                transfer(region(3), Len_v, source(5), Len_v, "packet after the restart");

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
                wait until Obs.AwCount >= 1 for 10 ms;
                ChDrain     <= '1';
                cycles(2);
                Cnt_v       := Obs.Beats;
                wait until Stopped = '1' for 1 ms;
                check_value(Stopped, '1', ERROR, "Stopped after the drain");
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
                        -- The packet waits in the buffers for the command, its first words at their outputs
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

            elsif run("test_long_packet") then
                log(ID_LOG_HDR, "TC-S2-14 a long packet with gaps and backpressure");
                Len_v       := minimum(MaxLen_c, maximum(65536, 16384 * StreamBytes_c));
                Mem_v.setStall(0, 30);
                Gen.Percent <= 50;
                transfer(region(1), Len_v, source(1), Len_v, "long packet");
            end if;

        end loop;

        odmaTestEnd(runner);
        wait;
    end process;

end architecture;
