---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VUnit testbench of odma_mm2s: the test cases TC-MM-01 to TC-MM-14 of the verification plan.
-- Expected stream data is the count pattern of the memory model, never taken from the DUT.
--
-- Documentation: hdl/odma_mm2s/docs/verification_plan.md

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
    use work.odma_mm2s_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_mm2s_tb is
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
architecture sim of odma_mm2s_tb is

    subtype Addr_t is unsigned(63 downto 0);

    constant StreamBytes_c : positive := StreamWidth_g / 8;
    constant MemBytes_c    : positive := MemWidth_g / 8;
    constant BurstBytes_c  : positive := BurstBeats_g * MemBytes_c;
    constant MaxLen_c      : positive := 2**LengthWidth_g - 1;
    -- Stream beats of one burst; MM-RD-05 applies from 8 on
    constant BurstStream_c : positive := BurstBeats_g * MemBytes_c / StreamBytes_c;
    -- Clock cycles without a new burst after which the buffers are full (TC-MM-06): more than the time the
    -- stream side needs for a burst
    constant Quiet_c       : positive := 4 * BurstStream_c + 1000;

    -- Error codes of a result
    constant ErrNone_c : std_logic_vector(1 downto 0) := "00";
    constant ErrInt_c  : std_logic_vector(1 downto 0) := "01";
    constant ErrSlv_c  : std_logic_vector(1 downto 0) := "10";
    constant ErrDec_c  : std_logic_vector(1 downto 0) := "11";

    -- Region k of 64 KB of the memory
    function region (k : natural) return Addr_t is
    begin
        return to_unsigned(k * 65536, 64);
    end function;

    -- Highest byte address of the address space
    function topAddr return Addr_t is
        variable A_v : Addr_t := (others => '0');
    begin
        A_v(AddrWidth_g - 1 downto 0) := (others => '1');
        return A_v;
    end function;

    -- Memory words that contain the bytes from addr to addr + len - 1
    function words (
        addr : Addr_t;
        len  : positive) return natural is
    begin
        return to_integer((addr + len - 1) / MemBytes_c) - to_integer(addr / MemBytes_c) + 1;
    end function;

    signal Clk          : std_logic;
    signal Cmd_Valid    : std_logic                     := '0';
    signal Cmd_Ready    : std_logic;
    signal Cmd_Addr     : std_logic_vector(63 downto 0) := (others => '0');
    signal Cmd_Length   : natural                       := 0;
    signal Cmd_Eof      : std_logic                     := '1';
    signal Res_Ready    : std_logic                     := '1';
    signal ChRun        : std_logic                     := '0';
    signal ChDrain      : std_logic                     := '0';
    signal Stopped      : std_logic;
    signal Ready        : ReadyCfg_r                    := ReadyAlways_c;
    signal StreamClear  : std_logic                     := '0';
    signal EccInjValid  : std_logic_vector(2 downto 0)  := "000";
    signal EccInjDouble : std_logic                     := '0';
    signal Obs          : Obs_r;

begin

    test_runner_watchdog(runner, 200 ms);

    i_th : entity work.odma_mm2s_th
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
            Cmd_Eof      => Cmd_Eof,
            Res_Ready    => Res_Ready,
            Run          => ChRun,
            Drain        => ChDrain,
            Stopped      => Stopped,
            Ready        => Ready,
            StreamClear  => StreamClear,
            EccInjValid  => EccInjValid,
            EccInjDouble => EccInjDouble,
            Obs          => Obs
        );

    p_control : process is
        variable Addr_v     : Addr_t;
        variable Len_v      : natural;
        variable Len2_v     : natural;
        variable Res_v      : natural;
        variable Cnt_v      : natural;
        variable Cnt2_v     : natural;
        variable Expected_v : natural  := 0;       -- Packets expected so far
        variable Sec_v      : Nat3_a;
        variable Ded_v      : Nat3_a;
        variable Seed1_v    : positive := 3;
        variable Seed2_v    : positive := 77;
        variable Rand_v     : real;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- One transfer command, after its handshake
        procedure sendCmd (
            addr : Addr_t;
            len  : natural;
            eof  : std_logic := '1') is
        begin
            Cmd_Addr   <= std_logic_vector(addr);
            Cmd_Length <= len;
            Cmd_Eof    <= eof;
            Cmd_Valid  <= '1';
            wait until rising_edge(Clk) and Cmd_Ready = '1' for 1 ms;
            check_value(Cmd_Ready, '1', ERROR, "command accepted");
            Cmd_Valid  <= '0';
        end procedure;

        -- The stream checker expects the bytes of the memory from addr as one packet (count pattern)
        procedure expect (
            addr : Addr_t;
            len  : positive) is
        begin
            Pkts_v.push(to_integer(unsigned(Mem_v.read8(0, addr))), len);
            Expected_v := Expected_v + 1;
        end procedure;

        -- All expected packets received
        procedure streamDone is
        begin
            if Obs.Packets < Expected_v then
                wait until Obs.Packets >= Expected_v for 20 ms;
            end if;
            check_value(Obs.Packets, Expected_v, ERROR, "packets on the stream");
        end procedure;

        procedure waitRes (n : natural) is
        begin
            if Obs.ResCount < n then
                wait until Obs.ResCount >= n for 20 ms;
            end if;
            check_value(Obs.ResCount, n, ERROR, "results");
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

        -- A transfer checked on the stream and its result
        procedure transfer (
            addr : Addr_t;
            len  : positive;
            msg  : string) is
            constant Res_c : natural := Obs.ResCount;
        begin
            expect(addr, len);
            sendCmd(addr, len);
            streamDone;
            waitRes(Res_c + 1);
            checkRes(Res_c, len, '1', ErrNone_c, msg);
        end procedure;

        -- Restarts the stream counters of the harness
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
                log(ID_LOG_HDR, "TC-MM-01 transfers at aligned addresses");
                Mem_v.fill(0, region(1), 65536, 5);

                for i in 0 to 4 loop
                    Len_v := 1 when i = 0 else
                             StreamBytes_c when i = 1 else
                             MemBytes_c when i = 2 else
                             BurstBytes_c when i = 3 else
                             7 * BurstBytes_c / 2;
                    Len_v := minimum(minimum(Len_v, MaxLen_c), 16384);
                    transfer(region(1) + i * 4096, Len_v, "aligned transfer of " & to_string(Len_v) & " bytes");
                end loop;

                -- A transfer without the end of packet continues the packet of the next one
                Len_v  := 4 * StreamBytes_c;
                Len2_v := minimum(2 * StreamBytes_c + 1, MaxLen_c);
                Res_v  := Obs.ResCount;
                expect(region(1) + 32768, Len_v + Len2_v);
                sendCmd(region(1) + 32768, Len_v, '0');
                sendCmd(region(1) + 32768 + Len_v, Len2_v, '1');
                streamDone;
                waitRes(Res_v + 2);
                checkRes(Res_v, Len_v, '0', ErrNone_c, "transfer without the end of packet");
                checkRes(Res_v + 1, Len2_v, '1', ErrNone_c, "transfer with the end of packet");

            elsif run("test_unaligned") then
                log(ID_LOG_HDR, "TC-MM-02 every start offset, reads of the words of the buffer only");
                Mem_v.fill(0, region(1), 65536, 9);

                for ofs in 0 to MemBytes_c - 1 loop

                    for i in 0 to 4 loop
                        Len_v  := 1 when i = 0 else
                                  maximum(MemBytes_c - 1, 1) when i = 1 else
                                  MemBytes_c when i = 2 else
                                  MemBytes_c + 1 when i = 3 else
                                  3 * MemBytes_c;
                        Len_v  := minimum(Len_v, MaxLen_c);
                        Addr_v := region(1) + 4 * MemBytes_c * (ofs mod 8) + ofs;
                        Mem_v.clearStats(0);
                        transfer(Addr_v, Len_v, "offset " & to_string(ofs) & ", " & to_string(Len_v) & " bytes");
                        check_value(Mem_v.beatsRead(0), words(Addr_v, Len_v), ERROR, "memory words read");
                    end loop;

                end loop;

            elsif run("test_bursts") then
                log(ID_LOG_HDR, "TC-MM-03 4 KB boundaries and the burst limit");
                Mem_v.fill(0, region(1), 65536, 11);
                Len_v := minimum(3 * 4096 + 100, MaxLen_c);
                transfer(region(1) + 8192 - 3, Len_v, "transfer across 4 KB boundaries");
                Len_v := minimum(5 * BurstBytes_c + 3, minimum(MaxLen_c, 40000));
                transfer(region(1) + 4096 - minimum(BurstBytes_c, 4096) + 1, Len_v, "transfer of several bursts");
                check_value(Obs.ArBadAttr, 0, ERROR, "ArSize, ArBurst, ArLock, ArCache and ArProt");

            elsif run("test_backpressure") then
                log(ID_LOG_HDR, "TC-MM-04 backpressure of the stream peer and of the memory");
                Mem_v.fill(0, region(1), 65536, 13);
                Mem_v.setStall(0, 50);
                Mem_v.setLatency(0, 30);
                Ready.Percent <= 50;

                for i in 1 to 20 loop
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    Len_v  := 1 + integer(trunc(Rand_v * real(minimum(MaxLen_c, 2000) - 1)));
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    Addr_v := region(1) + integer(trunc(Rand_v * 60000.0));
                    transfer(Addr_v, Len_v, "random transfer " & to_string(i));
                end loop;

            elsif run("test_throughput") then
                log(ID_LOG_HDR, "TC-MM-05 one stream beat per clock cycle");
                Len_v  := minimum(MaxLen_c, 64 * BurstBytes_c);
                Mem_v.fill(0, region(1), Len_v, 15);
                clearStream;
                transfer(region(1), Len_v, "transfer of 64 bursts");
                Cnt_v  := (Len_v + StreamBytes_c - 1) / StreamBytes_c;
                Cnt2_v := Obs.LastBeat - Obs.FirstBeat + 1;
                log(ID_SEQUENCER, "throughput: " & to_string(Cnt_v) & " beats in " & to_string(Cnt2_v) &
                    " clock cycles, " & to_string(BurstStream_c) & " stream beats per burst");
                -- MM-RD-05 applies with at least 8 stream beats per burst
                if BurstStream_c >= 8 then
                    check_value(Cnt2_v <= Cnt_v + 2, ERROR, "clock cycles from the first to the last of " &
                                to_string(Cnt_v) & " beats: " & to_string(Cnt2_v));
                end if;

            elsif run("test_bus_not_held") then
                log(ID_LOG_HDR, "TC-MM-06 a stopped stream peer never holds the R channel");
                Len_v      := minimum(MaxLen_c, 65536);
                Mem_v.fill(0, region(1), Len_v, 17);
                clearStream;
                expect(region(1), Len_v);
                sendCmd(region(1), Len_v);
                wait until Obs.Beats >= 10 for 1 ms;
                Ready.Hold <= '1';
                Cnt_v      := Obs.RHeld;
                -- Wait until no further burst comes for Quiet_c clock cycles, then for twice as long
                Cnt2_v := Obs.ArCount;

                for i in 1 to 100 loop
                    cycles(Quiet_c);
                    exit when Obs.ArCount = Cnt2_v;
                    Cnt2_v := Obs.ArCount;
                end loop;

                cycles(2 * Quiet_c);
                check_value(Obs.ArCount, Cnt2_v, ERROR, "no further read burst while the buffers are full");
                check_value(Obs.RHeld, Cnt_v, ERROR, "R channel held while the stream peer stops");
                -- The bursts issued fit into the buffers: the read data buffer, the internal FIFOs of the master
                -- (two bursts) and the register stages (a few words)
                check_value(Cnt2_v <= (Obs.Bytes + (BufferBeats_g + 4) * StreamBytes_c + 2 * BurstBytes_c +
                                       4 * MemBytes_c) / BurstBytes_c + 2,
                            ERROR, "read bursts bounded by the buffers: " & to_string(Cnt2_v));
                Ready.Hold <= '0';
                streamDone;
                waitRes(1);
                checkRes(0, Len_v, '1', ErrNone_c, "transfer after the stop");

            elsif run("test_queue") then
                log(ID_LOG_HDR, "TC-MM-07 commands back to back, a rejected one between two good ones");
                Mem_v.fill(0, region(1), 65536, 19);
                Len_v := minimum(3 * MemBytes_c + 5, MaxLen_c);
                expect(region(1) + 3, Len_v);
                expect(region(1) + 20000, Len_v);
                sendCmd(region(1) + 3, Len_v);
                sendCmd(topAddr - 3, 8);
                sendCmd(region(1) + 20000, Len_v);
                streamDone;
                waitRes(3);
                checkRes(0, Len_v, '1', ErrNone_c, "first transfer");
                checkRes(1, 0, '1', ErrDec_c, "rejected transfer");
                checkRes(2, Len_v, '1', ErrNone_c, "third transfer");

            elsif run("test_result_timing") then
                log(ID_LOG_HDR, "TC-MM-08 the result follows the handshake of the last beat");
                Mem_v.fill(0, region(1), 65536, 21);
                Len_v := minimum(4 * StreamBytes_c + 1, MaxLen_c);
                -- The stream peer takes the last beat 40 clock cycles late
                Ready <= (Percent => 100, Hold => '0', StallBeat => (Len_v - 1) / StreamBytes_c, StallCycles => 40);
                clearStream;
                transfer(region(1), Len_v, "delayed last beat");
                check_value(Obs.LastBeat - Obs.FirstBeat >= 40, ERROR, "last beat delayed");
                check_value(Obs.Results(0).Cycle > Obs.LastBeat, ERROR, "result after the last beat");

            elsif run("test_read_errors") then
                log(ID_LOG_HDR, "TC-MM-09 error responses of the memory");
                Mem_v.fill(0, region(1), 65536, 23);
                Len_v := minimum(4 * MemBytes_c, MaxLen_c);

                for i in 0 to 2 loop
                    Addr_v := region(1) + i * 4096;
                    Mem_v.clearErrors(0);
                    if i = 0 then
                        Mem_v.setError(0, 0, Addr_v + Len_v / 2, Addr_v + Len_v / 2, ErrSlv_c, TbDirRead);
                    elsif i = 1 then
                        Mem_v.setError(0, 0, Addr_v + Len_v - 1, Addr_v + Len_v - 1, ErrDec_c, TbDirRead);
                    else
                        Mem_v.setError(0, 0, Addr_v, Addr_v, ErrSlv_c, TbDirRead);
                        Mem_v.setError(0, 1, Addr_v + Len_v - 1, Addr_v + Len_v - 1, ErrDec_c, TbDirRead);
                    end if;
                    -- The transfer is sent completely, the result has an error code
                    expect(Addr_v, Len_v);
                    sendCmd(Addr_v, Len_v);
                    streamDone;
                    waitRes(i + 1);
                    check_value(Obs.Results(i).Bytes, Len_v, ERROR, "result bytes");
                    check_value(Obs.Results(i).Err = ErrSlv_c or Obs.Results(i).Err = ErrDec_c, ERROR,
                                "result with an error code");
                end loop;

                -- A transfer after a failed one has no error
                Mem_v.clearErrors(0);
                transfer(region(1) + 4 * 4096, Len_v, "transfer after the failed ones");

            elsif run("test_beyond_top") then
                log(ID_LOG_HDR, "TC-MM-10 the top of the address space, a command of length 0");
                Len_v := minimum(100, MaxLen_c);
                Mem_v.fill(0, topAddr - Len_v + 1, Len_v, 25);
                transfer(topAddr - Len_v + 1, Len_v, "buffer ending at the top of the address space");
                -- One byte beyond the top: no burst, no beat
                Cnt_v := Obs.ArCount;
                clearStream;
                sendCmd(topAddr - Len_v + 2, Len_v);
                waitRes(2);
                checkRes(1, 0, '1', ErrDec_c, "buffer beyond the top");
                -- Length 0: no burst, no beat
                sendCmd(region(1), 0);
                waitRes(3);
                checkRes(2, 0, '1', ErrInt_c, "command of length 0");
                cycles(20);
                check_value(Obs.ArCount, Cnt_v, ERROR, "no read burst");
                check_value(Obs.Beats, 0, ERROR, "no stream beat");

            elsif run("test_halt") then
                log(ID_LOG_HDR, "TC-MM-11 halt during a transfer");
                Mem_v.fill(0, region(1), 65536, 27);
                Ready.Percent <= 50;
                Len_v         := minimum(16 * BurstBytes_c, minimum(MaxLen_c, 16384));
                expect(region(1), Len_v);
                sendCmd(region(1), Len_v);
                ChRun         <= '0';
                Cnt_v         := 0;

                loop
                    wait until rising_edge(Clk);
                    -- Obs shows the results up to the clock edge before
                    exit when Obs.ResCount > 0;
                    if Stopped = '1' then
                        Cnt_v := Cnt_v + 1;
                    end if;
                end loop;

                check_value(Cnt_v, 0, ERROR, "clock cycles with Stopped before the result");
                streamDone;
                checkRes(0, Len_v, '1', ErrNone_c, "transfer completed after the halt");
                cycles(3);
                check_value(Stopped, '1', ERROR, "Stopped after the result");
                -- A command is not accepted while halted
                Cnt_v      := Obs.ArCount;
                Cmd_Addr   <= std_logic_vector(region(1));
                Cmd_Length <= 16;
                Cmd_Valid  <= '1';

                for i in 1 to 100 loop
                    wait until rising_edge(Clk);
                    check_value(Cmd_Ready, '0', ERROR, "no command accepted while halted");
                end loop;

                Cmd_Valid <= '0';
                check_value(Obs.ArCount, Cnt_v, ERROR, "no read while halted");

            elsif run("test_drain") then
                log(ID_LOG_HDR, "TC-MM-12 drain during a transfer with a stalled stream peer");
                Len_v      := minimum(MaxLen_c, 65536);
                Mem_v.fill(0, region(1), Len_v, 29);
                clearStream;
                expect(region(1), Len_v);
                sendCmd(region(1), Len_v);
                wait until Obs.Beats >= 10 for 1 ms;
                Ready.Hold <= '1';
                cycles(20);
                Cnt_v      := Obs.Beats;
                ChDrain    <= '1';
                cycles(2);
                -- The stream peer is ready again, the channel sends nothing
                Ready.Hold <= '0';
                wait until Stopped = '1' for 1 ms;
                check_value(Stopped, '1', ERROR, "Stopped after the drain");
                cycles(20);
                check_value(Obs.Beats, Cnt_v, ERROR, "no stream beat during the drain");
                check_value(Obs.RLastCount, Obs.ArCount, ERROR, "every read burst completed");
                check_value(Obs.ResCount, 0, ERROR, "no result of the drained transfer");
                -- No command is accepted during a drain
                Cmd_Valid <= '1';

                for i in 1 to 100 loop
                    wait until rising_edge(Clk);
                    check_value(Cmd_Ready, '0', ERROR, "no command accepted during the drain");
                end loop;

                Cmd_Valid <= '0';

            elsif run("test_ecc") then
                log(ID_LOG_HDR, "TC-MM-13 single and double errors injected into the three buffers");
                Mem_v.fill(0, region(1), 65536, 31);
                Len_v         := minimum(2 * StreamBytes_c, MaxLen_c);
                Len2_v        := minimum(3 * StreamBytes_c + 1, MaxLen_c);
                Ready.Percent <= 30;

                for b in 0 to 2 loop

                    for d in 0 to 1 loop
                        Sec_v := Obs.EccSec;
                        Ded_v := Obs.EccDed;
                        Res_v := Obs.ResCount;
                        -- A first transfer waits at the stalled stream peer with its data, entry and response
                        Ready.Hold <= '1';
                        Addr_v     := region(1) + (2 * b + d) * 1024;
                        expect(Addr_v, Len_v);
                        sendCmd(Addr_v, Len_v);
                        cycles(200);
                        -- The error goes into the next word written to the buffer: the data, the entry or the
                        -- response of the second transfer, which then waits at the output of the buffer while the
                        -- first transfer completes
                        wait until rising_edge(Clk);
                        EccInjDouble   <= '1' when d = 1 else '0';
                        EccInjValid    <= (others => '0');
                        EccInjValid(b) <= '1';
                        wait until rising_edge(Clk);
                        EccInjValid    <= (others => '0');
                        expect(Addr_v + 512, Len2_v);
                        sendCmd(Addr_v + 512, Len2_v);
                        cycles(200);
                        Ready.Hold     <= '0';
                        streamDone;
                        waitRes(Res_v + 2);
                        checkRes(Res_v, Len_v, '1', ErrNone_c, "first transfer, buffer " & to_string(b));
                        checkRes(Res_v + 1, Len2_v, '1', ErrNone_c, "second transfer, buffer " & to_string(b));
                        cycles(4);

                        for i in 0 to 2 loop
                            Cnt_v  := 1 when i = b and d = 0 else 0;
                            Cnt2_v := 1 when i = b and d = 1 else 0;
                            check_value(Obs.EccSec(i) - Sec_v(i), Cnt_v, ERROR, "Ecc_Sec of buffer " & to_string(i));
                            check_value(Obs.EccDed(i) - Ded_v(i), Cnt2_v, ERROR, "Ecc_Ded of buffer " & to_string(i));
                        end loop;

                    end loop;

                end loop;

            elsif run("test_long_transfer") then
                log(ID_LOG_HDR, "TC-MM-14 a long transfer with backpressure");
                Len_v         := minimum(MaxLen_c, maximum(65536, 16384 * StreamBytes_c));
                Mem_v.fill(0, region(1), Len_v, 33);
                Mem_v.setStall(0, 30);
                Ready.Percent <= 50;
                transfer(region(1), Len_v, "long transfer");
            end if;

        end loop;

        check_value(Obs.StreamErr, 0, ERROR, "errors of the stream checker");
        odmaTestEnd(runner);
        wait;
    end process;

end architecture;
