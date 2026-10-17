---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VUnit testbench of odma_pkg and of the shared verification components: one run() per test case
-- of the verification plan.
--
-- Documentation: hdl/odma_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library std;
    use std.textio.all;

library vunit_lib;
    context vunit_lib.vunit_context;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axi;
    context bitvis_vip_axi.vvc_context;

library bitvis_vip_axilite;
    context bitvis_vip_axilite.vvc_context;

library bitvis_vip_axistream;
    context bitvis_vip_axistream.vvc_context;

library olo;
    use olo.olo_axi_pkg_protocol.all;

library work;
    use work.odma_pkg.all;
    use work.odma_tb_pkg.all;
    use work.odma_tb_mem_pkg.all;
    use work.odma_tb_memvar_pkg.all;
    use work.odma_tb_seq_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_pkg_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_pkg_tb is

    constant ClkPeriod_c : time     := 10 ns;
    constant Words_c     : positive := 256;

    signal Mm2sIrq  : std_logic;
    signal S2mmIrq  : std_logic;
    signal RawCmd   : natural                       := 0;
    signal RawDone  : std_logic;
    signal AddrHigh : std_logic_vector(31 downto 0) := (others => '0');

    type NatArray_t is array (natural range <>) of natural;

    constant Widths_c : NatArray_t(0 to 5) := (1, 2, 4, 8, 64, 128);

    -- 64-bit words of a count pattern: byte i of the burst is (seed + i) mod 256
    function countWords (
        n    : positive;
        seed : natural) return t_slv_array is
        variable Arr_v : t_slv_array(0 to n - 1)(63 downto 0);
    begin

        for w in 0 to n - 1 loop

            for b in 0 to 7 loop
                Arr_v(w)(8 * b + 7 downto 8 * b) := std_logic_vector(to_unsigned((seed + 8 * w + b) mod 256, 8));
            end loop;

        end loop;

        return Arr_v;
    end function;

    function strobes (
        n   : positive;
        val : std_logic_vector(7 downto 0)) return t_slv_array is
        variable Arr_v : t_slv_array(0 to n - 1)(7 downto 0) := (others => val);
    begin
        return Arr_v;
    end function;

    function a64 (val : std_logic_vector(63 downto 0)) return unsigned is
    begin
        return unsigned(val);
    end function;

begin

    i_th : entity work.odma_pkg_th
        generic map (
            ClkPeriod_g => ClkPeriod_c
        )
        port map (
            Mm2sIrq  => Mm2sIrq,
            S2mmIrq  => S2mmIrq,
            RawCmd   => RawCmd,
            RawDone  => RawDone,
            AddrHigh => AddrHigh
        );

    p_main : process is
        variable Keep_v  : std_logic_vector(127 downto 0);
        variable Exp_v   : natural;
        variable Bad_v   : natural;
        variable Data_v  : t_slv_array(0 to Words_c - 1)(63 downto 0);
        variable Fixed_v : t_slv_array(0 to 15)(63 downto 0);
        variable Zero_v  : t_slv_array(0 to 1)(63 downto 0) := (others => (others => '0'));
        variable Resp_v  : t_xresp_array(0 to 1);
        variable Base_v  : unsigned(63 downto 0);
        variable Diff_v  : natural;
        variable Sh_v    : natural;

        constant One_c : unsigned(63 downto 0) := to_unsigned(1, 64);

        -- Checks n bytes from addr of memory instance 0 against the count pattern from seed
        procedure checkBytes (
            addr : unsigned;
            n    : natural;
            seed : natural;
            msg  : string) is
            variable Bad_v : natural := 0;
        begin

            for i in 0 to n - 1 loop
                if Mem_v.read8(0, resize(addr, 64) + i) /= std_logic_vector(to_unsigned((seed + i) mod 256, 8)) then
                    Bad_v := Bad_v + 1;
                end if;
            end loop;

            check_value(Bad_v, 0, ERROR, msg & ": mismatching bytes");
        end procedure;

        procedure checkZero (
            addr : unsigned;
            n    : natural;
            msg  : string) is
            variable Bad_v : natural := 0;
        begin

            for i in 0 to n - 1 loop
                if Mem_v.read8(0, resize(addr, 64) + i) /= x"00" then
                    Bad_v := Bad_v + 1;
                end if;
            end loop;

            check_value(Bad_v, 0, ERROR, msg & ": bytes written that must not be");
        end procedure;

        procedure checkMsg (
            got : string;
            exp : string) is
        begin
            check_value(got'length >= exp'length and got(got'low to got'low + minimum(exp'length, got'length) - 1) = exp,
                        ERROR, "configuration message '" & got & "' starts with '" & exp & "'");
        end procedure;

        -- Compares two text files line by line
        procedure compareFiles (
            got : string;
            exp : string) is
            file G_v : text;
            file E_v : text;

            variable SG_v     : file_open_status;
            variable SE_v     : file_open_status;
            variable LG_v     : line;
            variable LE_v     : line;
            variable LineNo_v : natural := 0;
            variable Bad_v    : natural := 0;
        begin
            file_open(SG_v, G_v, got, read_mode);
            file_open(SE_v, E_v, exp, read_mode);
            check_value(SG_v = open_ok and SE_v = open_ok, TB_ERROR, "open " & got & " and " & exp);

            while not endfile(E_v) loop
                readline(E_v, LE_v);
                LineNo_v := LineNo_v + 1;
                if endfile(G_v) then
                    Bad_v := Bad_v + 1;
                    log(ID_SEQUENCER, "line " & integer'image(LineNo_v) & " missing: " & LE_v.all);
                else
                    readline(G_v, LG_v);
                    if LG_v.all /= LE_v.all then
                        Bad_v := Bad_v + 1;
                        log(ID_SEQUENCER, "line " & integer'image(LineNo_v) & ": " & LG_v.all & " expected " & LE_v.all);
                    end if;
                end if;
            end loop;

            check_value(endfile(G_v), ERROR, got & ": no lines beyond the expected ones");
            check_value(Bad_v, 0, ERROR, got & " against " & exp & ": differing lines");
            file_close(G_v);
            file_close(E_v);
        end procedure;

        procedure rawBurst (cmd : positive) is
        begin
            RawCmd <= cmd;
            wait on RawDone;
            RawCmd <= 0;
            wait for 2 * ClkPeriod_c;
        end procedure;

        procedure axiIdle is
        begin
            await_completion(AXI_VVCT, 0, 1 ms, "AXI VVC idle");
        end procedure;

        -- One write burst through the AXI4 VVC (one beat per element of data) and its completion: the VVC
        -- runs reads and writes on independent channels, so every access completes before the next one
        procedure memWrite (
            addr  : unsigned(31 downto 0);
            data  : t_slv_array;
            msg   : string;
            burst : t_axburst                          := INCR;
            strb  : t_slv_array                        := C_EMPTY_SLV_ARRAY;
            resp  : bitvis_vip_axi.axi_bfm_pkg.t_xresp := OKAY;
            size  : positive                           := 8) is
        begin
            axi_write(
                VVCT             => AXI_VVCT,
                vvc_instance_idx => 0,
                awaddr           => addr,
                awlen            => to_unsigned(data'length - 1, 8),
                awsize           => size,
                awburst          => burst,
                wdata            => data,
                wstrb            => strb,
                bresp_exp        => resp,
                msg              => msg);
            axiIdle;
        end procedure;

        -- One read burst through the AXI4 VVC, compared with data and the responses resp
        procedure memCheck (
            addr  : unsigned(31 downto 0);
            data  : t_slv_array;
            msg   : string;
            burst : t_axburst                                := INCR;
            resp  : bitvis_vip_axi.axi_bfm_pkg.t_xresp_array := C_EMPTY_XRESP_ARRAY) is
        begin
            axi_check(
                VVCT             => AXI_VVCT,
                vvc_instance_idx => 0,
                araddr           => addr,
                arlen            => to_unsigned(data'length - 1, 8),
                arsize           => 8,
                arburst          => burst,
                rdata_exp        => data,
                rresp_exp        => resp,
                msg              => msg);
            axiIdle;
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);
        wait for 20 * ClkPeriod_c;

        while test_suite loop

            if run("test_last_keep") then
                log(ID_LOG_HDR, "TC-PKG-01 lastKeep");

                for wi in Widths_c'range loop

                    for n in 0 to 3 * 128 loop
                        Exp_v  := Widths_c(wi);
                        exit when n > 3 * Exp_v;
                        Keep_v := (others => '0');
                        if n > 0 then

                            for i in 0 to (n - 1) mod Exp_v loop
                                Keep_v(i) := '1';
                            end loop;

                        end if;
                        check_value(lastKeep(to_unsigned(n, 26), Exp_v), Keep_v(Exp_v - 1 downto 0), ERROR,
                                    "lastKeep(" & integer'image(n) & ", " & integer'image(Exp_v) & ")");
                    end loop;

                end loop;

            elsif run("test_keep_bytes") then
                log(ID_LOG_HDR, "TC-PKG-02 keepBytes");

                for p in 0 to 255 loop
                    Exp_v := 8;

                    for i in 7 downto 0 loop
                        if (p / 2 ** i) mod 2 = 0 then
                            Exp_v := i;
                        end if;
                    end loop;

                    check_value(keepBytes(std_logic_vector(to_unsigned(p, 8))), Exp_v, ERROR,
                                "keepBytes of 8 lanes, pattern " & integer'image(p));
                end loop;

                for k in 0 to 128 loop
                    Keep_v := (others => '1');
                    if k < 128 then
                        Keep_v(k) := '0';
                    end if;
                    check_value(keepBytes(Keep_v), k, ERROR, "keepBytes of 128 lanes, first '0' at " & integer'image(k));
                end loop;

            elsif run("test_beyond_top") then
                log(ID_LOG_HDR, "TC-PKG-03 beyondTop");
                check_value(beyondTop(x"FFFF_FFFF", to_unsigned(1, 26)), false, ERROR, "32 bit: last byte at the top");
                check_value(beyondTop(x"FFFF_FFFF", to_unsigned(2, 26)), true, ERROR, "32 bit: one byte beyond the top");
                check_value(beyondTop(x"FFFF_FF00", to_unsigned(256, 26)), false, ERROR, "32 bit: 256 bytes to the top");
                check_value(beyondTop(x"FFFF_FF00", to_unsigned(257, 26)), true, ERROR, "32 bit: 257 bytes");
                check_value(beyondTop(x"0000_0000", to_unsigned(2 ** 26 - 1, 26)), false, ERROR, "32 bit: largest length at 0");
                check_value(beyondTop(x"FC00_0001", to_unsigned(2 ** 26 - 1, 26)), false, ERROR, "32 bit: largest length to the top");
                check_value(beyondTop(x"FC00_0002", to_unsigned(2 ** 26 - 1, 26)), true, ERROR, "32 bit: largest length, one beyond");
                check_value(beyondTop(a64(x"FFFF_FFFF_FFFF_FFFF"), to_unsigned(1, 26)), false, ERROR, "64 bit: last byte at the top");
                check_value(beyondTop(a64(x"FFFF_FFFF_FFFF_FFFF"), to_unsigned(2, 26)), true, ERROR, "64 bit: one byte beyond");
                check_value(beyondTop(a64(x"0000_0000_FFFF_FFFF"), to_unsigned(2, 26)), false, ERROR, "64 bit: across 4 GB");
                -- An empty buffer touches no byte: never beyond the top, also at address 0 (no underflow)
                check_value(beyondTop(x"0000_0000", to_unsigned(0, 26)), false, ERROR, "32 bit: empty buffer at 0");
                check_value(beyondTop(x"8000_0000", to_unsigned(0, 26)), false, ERROR, "32 bit: empty buffer");
                check_value(beyondTop(x"FFFF_FFFF", to_unsigned(0, 26)), false, ERROR, "32 bit: empty buffer at the top");
                check_value(beyondTop(a64(x"0000_0000_0000_0000"), to_unsigned(0, 26)), false, ERROR,
                            "64 bit: empty buffer at 0");
                check_value(beyondTop(a64(x"FFFF_FFFF_FFFF_FFFF"), to_unsigned(0, 26)), false, ERROR,
                            "64 bit: empty buffer at the top");

            elsif run("test_config") then
                log(ID_LOG_HDR, "TC-PKG-04 coreConfigError");
                check_value(coreConfigError(32, 14, 32, 32, 16, 64, 32, 32, 16, 64) = "", ERROR, "default configuration");
                check_value(coreConfigError(64, 26, 1024, 1024, 256, 512, 32, 8, 2, 32) = "", ERROR,
                            "boundary configuration");
                check_value(coreConfigError(32, 8, 1024, 8, 2, 512, 1024, 8, 2, 512) = "", ERROR, "widest ratio");
                checkMsg(coreConfigError(31, 14, 32, 32, 16, 64, 32, 32, 16, 64), "AddrWidth_g");
                checkMsg(coreConfigError(65, 14, 32, 32, 16, 64, 32, 32, 16, 64), "AddrWidth_g");
                checkMsg(coreConfigError(32, 7, 32, 32, 16, 64, 32, 32, 16, 64), "LengthWidth_g");
                checkMsg(coreConfigError(32, 27, 32, 32, 16, 64, 32, 32, 16, 64), "LengthWidth_g");
                checkMsg(coreConfigError(32, 14, 24, 8, 16, 64, 32, 32, 16, 64), "Mm2sMemWidth_g");
                checkMsg(coreConfigError(32, 14, 2048, 32, 16, 2048, 32, 32, 16, 64), "Mm2sMemWidth_g");
                checkMsg(coreConfigError(32, 14, 32, 64, 16, 64, 32, 32, 16, 64), "Mm2sStreamWidth_g must not be larger");
                checkMsg(coreConfigError(32, 14, 32, 32, 3, 64, 32, 32, 16, 64), "Mm2sBurstBeats_g");
                checkMsg(coreConfigError(32, 14, 32, 32, 512, 2048, 32, 32, 16, 64), "Mm2sBurstBeats_g");
                checkMsg(coreConfigError(32, 14, 32, 32, 16, 16, 32, 32, 16, 64), "Mm2sBufferBeats_g");
                checkMsg(coreConfigError(32, 14, 32, 32, 16, 64, 24, 8, 16, 64), "S2mmMemWidth_g");
                checkMsg(coreConfigError(32, 14, 32, 32, 16, 64, 32, 32, 16, 31), "S2mmBufferBeats_g");

            elsif run("test_err_codes") then
                log(ID_LOG_HDR, "TC-PKG-05 error codes");
                check_value(ErrNone_c, "00", ERROR, "ErrNone_c");
                check_value(ErrInt_c, "01", ERROR, "ErrInt_c");
                check_value(ErrSlv_c, AxiResp_SlvErr_c, ERROR, "ErrSlv_c equals SLVERR");
                check_value(ErrDec_c, AxiResp_DecErr_c, ERROR, "ErrDec_c equals DECERR");

            elsif run("test_resp_err") then
                log(ID_LOG_HDR, "TC-PKG-15 error code of a failed AXI response");
                check_value(respErr("10"), ErrSlv_c, ERROR, "SLVERR gives the slave error");
                check_value(respErr("11"), ErrDec_c, ERROR, "DECERR gives the decode error");
                check_value(respErr("01"), ErrSlv_c, ERROR, "EXOKAY gives the slave error, not the internal error");

            elsif run("test_flip_pattern") then
                log(ID_LOG_HDR, "TC-PKG-13 flip pattern of the error injection");
                check_value(flipPattern(8, '0', '0'), x"01", ERROR, "parity mode, single error");
                check_value(flipPattern(8, '1', '0'), x"03", ERROR, "parity mode, double error");
                check_value(flipPattern(8, '0', '1'), x"08", ERROR, "data mode, single error");
                check_value(flipPattern(8, '1', '1'), x"28", ERROR, "data mode, double error");
                check_value(flipPattern(39, '0', '0'), std_logic_vector(to_unsigned(16#01#, 39)), ERROR, "39 bits, parity, single");
                check_value(flipPattern(39, '1', '0'), std_logic_vector(to_unsigned(16#03#, 39)), ERROR, "39 bits, parity, double");
                check_value(flipPattern(39, '0', '1'), std_logic_vector(to_unsigned(16#08#, 39)), ERROR, "39 bits, data, single");
                check_value(flipPattern(39, '1', '1'), std_logic_vector(to_unsigned(16#28#, 39)), ERROR, "39 bits, data, double");

            elsif run("test_mem_bursts") then
                log(ID_LOG_HDR, "TC-PKG-06 memory model bursts");

                for pass in 0 to 1 loop
                    if pass = 1 then
                        log(ID_SEQUENCER, "with 50 % backpressure and a latency of 20 cycles");
                        Mem_v.setStall(0, 50);
                        Mem_v.setLatency(0, 20);
                    end if;
                    Mem_v.clearStats(0);
                    -- INCR bursts of 1, 16 and 256 beats, aligned
                    memWrite(x"0001_0100", countWords(1, 1), "INCR 1 beat");
                    memWrite(x"0001_1000", countWords(16, 2), "INCR 16 beats");
                    memWrite(x"0001_2000", countWords(256, 3), "INCR 256 beats");
                    checkBytes(x"0001_0100", 8, 1, "INCR 1 beat");
                    checkBytes(x"0001_1000", 128, 2, "INCR 16 beats");
                    checkBytes(x"0001_2000", 2048, 3, "INCR 256 beats");
                    check_value(Mem_v.bytesWritten(0), 8 + 128 + 2048, ERROR, "statistics: bytes written");
                    check_value(std_logic_vector(Mem_v.lowestWritten(0)), x"0000_0000_0001_0100", ERROR,
                                "statistics: lowest address");
                    check_value(std_logic_vector(Mem_v.highestWritten(0)), x"0000_0000_0001_27FF", ERROR,
                                "statistics: highest address");
                    memCheck(x"0001_2000", countWords(256, 3), "read back 256 beats");
                    check_value(Mem_v.beatsRead(0), 256, ERROR, "statistics: read beats");
                    check_value(Mem_v.bursts(0), 4, ERROR, "statistics: bursts");
                    check_value(Mem_v.maxOutstanding(0, true) >= 1, ERROR, "statistics: outstanding writes");

                    -- Unaligned start with partial strobes: bytes 3 to 7 of the first beat, 0 to 2 of the second
                    memWrite(x"0001_3003", countWords(2, 16#40#), "unaligned INCR", INCR, (x"F8", x"07"));
                    checkZero(x"0001_3000", 3, "unaligned INCR, before the start");
                    checkBytes(x"0001_3003", 8, 16#43#, "unaligned INCR");
                    checkZero(x"0001_300B", 5, "unaligned INCR, after the end");

                    -- FIXED bursts: every beat at the same address
                    memWrite(x"0001_4000", countWords(16, 16#80#), "FIXED 16 beats", FIXED);
                    memWrite(x"0001_4100", countWords(1, 16#20#), "FIXED 1 beat", FIXED);
                    checkBytes(x"0001_4000", 8, 16#80# + 15 * 8, "FIXED 16 beats: the last beat remains");
                    checkZero(x"0001_4008", 8, "FIXED 16 beats: no increment");
                    checkBytes(x"0001_4100", 8, 16#20#, "FIXED 1 beat");
                    Fixed_v        := countWords(16, 16#80#);
                    Data_v(0 to 3) := (others => Fixed_v(15));
                    memCheck(x"0001_4000", Data_v(0 to 3), "FIXED read of 4 beats", FIXED);

                    -- Above 4 GB and at the top of the 64-bit space (address bits 63 to 32 from the harness,
                    -- changed only while the VVC is idle)
                    AddrHigh <= x"0000_0001";
                    memWrite(x"0000_0000", countWords(4, 16#11#), "INCR above 4 GB");
                    AddrHigh <= x"FFFF_FFFF";
                    memWrite(x"FFFF_FFF0", countWords(2, 16#22#), "INCR at the top");
                    memCheck(x"FFFF_FFF0", countWords(2, 16#22#), "read back at the top");
                    AddrHigh <= x"0000_0000";
                    checkBytes(a64(x"0000_0001_0000_0000"), 32, 16#11#, "INCR above 4 GB");
                    checkBytes(a64(x"FFFF_FFFF_FFFF_FFF0"), 16, 16#22#, "INCR at the top");
                    checkZero(x"0000_0000", 8, "address 0 untouched");
                end loop;

                Mem_v.setStall(0, 0);
                Mem_v.setLatency(0, 0);

            elsif run("test_mem_errors") then
                log(ID_LOG_HDR, "TC-PKG-07 memory model error responses");
                Mem_v.setError(0, 0, x"0002_6010", x"0002_601F", "10", TbDirWrite);
                Mem_v.setError(0, 1, x"0002_7000", x"0002_7007", "11", TbDirRead);
                Mem_v.setError(0, 2, x"0002_8000", x"0002_8FFF", "11", TbDirBoth);
                -- Write burst into the SLVERR range from its third beat (0x26010): the failed beats write nothing
                memWrite(x"0002_6000", countWords(4, 1), "write into the SLVERR range", INCR, C_EMPTY_SLV_ARRAY, SLVERR);
                checkBytes(x"0002_6000", 16, 1, "beats before the error range");
                checkZero(x"0002_6010", 16, "beats in the error range");
                -- Read error range: the beat that touches it responds with DECERR
                memCheck(x"0002_7000", Zero_v, "read of the DECERR range", INCR, (DECERR, OKAY));
                -- A read-only range does not affect writes, a write-only range does not affect reads
                memWrite(x"0002_7000", countWords(1, 5), "write to the read error range");
                memCheck(x"0002_6010", Zero_v, "read of the write error range", INCR, (OKAY, OKAY));
                -- Both directions
                memWrite(x"0002_8000", countWords(1, 5), "write to the DECERR range", INCR, C_EMPTY_SLV_ARRAY, DECERR);
                memCheck(x"0002_8000", Zero_v, "read of the DECERR range for both directions", INCR, (DECERR, DECERR));
                checkZero(x"0002_8000", 8, "write to the DECERR range");
                checkBytes(x"0002_7000", 8, 5, "write to the read error range");
                -- EXOKAY in both directions (interpretation I14 of the core)
                Mem_v.setError(0, 3, x"0002_9000", x"0002_9007", "01", TbDirBoth);
                memWrite(x"0002_9000", countWords(1, 6), "write to the EXOKAY range", INCR, C_EMPTY_SLV_ARRAY, EXOKAY);
                memCheck(x"0002_9000", Zero_v, "read of the EXOKAY range", INCR, (EXOKAY, OKAY));
                checkZero(x"0002_9000", 8, "write to the EXOKAY range");
                Mem_v.clearErrors(0);

            elsif run("test_mem_fifo") then
                log(ID_LOG_HDR, "TC-PKG-14 FIFO window");
                -- Window: the word 0x50000 (given by an address inside it), backing range from 0x51000
                Mem_v.setFifo(0, x"0005_0004", x"0005_1000");
                -- FIXED writes: every beat in the next backing word, the window word itself unchanged
                memWrite(x"0005_0000", countWords(16, 16#10#), "FIXED write of 16 beats at the window", FIXED);
                memWrite(x"0005_0000", countWords(3, 16#90#), "FIXED write of 3 beats, the last partial", FIXED,
                         (x"FF", x"FF", x"0F"));
                checkBytes(x"0005_1000", 128, 16#10#, "16 beats in consecutive backing words");
                checkBytes(x"0005_1080", 20, 16#90#, "3 beats, the last with 4 bytes");
                checkZero(x"0005_1094", 4, "the bytes without strobe of the last beat");
                checkZero(x"0005_0000", 8, "the window word itself");
                -- FIXED reads: the read counter starts at 0, consecutive bursts continue
                memCheck(x"0005_0000", countWords(1, 16#10#), "FIXED read of 1 beat", FIXED);
                memCheck(x"0005_0000", countWords(16, 16#18#), "FIXED read of 16 beats", FIXED);
                -- INCR next to the window: not affected
                memWrite(x"0005_0008", countWords(2, 16#A0#), "INCR next to the window");
                checkBytes(x"0005_0008", 16, 16#A0#, "INCR next to the window");
                checkBytes(x"0005_1000", 8, 16#10#, "backing range unchanged by the INCR burst");
                -- A new setting restarts both counters
                Mem_v.setFifo(0, x"0005_0000", x"0005_1000");
                memCheck(x"0005_0000", countWords(2, 16#10#), "FIXED read after a new setting", FIXED);

            elsif run("test_mem_checks") then
                log(ID_LOG_HDR, "TC-PKG-08 memory model protocol checks");
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                memWrite(x"0000_0FF8", countWords(4, 0), "INCR across 4 KB");
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                Mem_v.setMaxBeats(0, 16);
                memWrite(x"0003_0000", countWords(17, 0), "17 beats with a maximum of 16");
                Mem_v.setMaxBeats(0, 256);
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                memWrite(x"0003_1000", countWords(17, 0), "FIXED 17 beats", FIXED);
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                memWrite(x"0003_2000", countWords(4, 0), "WRAP burst", WRAP);
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                memWrite(x"0003_3000", countWords(1, 0), "narrow beat", INCR, (0 => x"0F"), OKAY, 4);
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                rawBurst(1);
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                rawBurst(2);
                -- Window 0x34000 to 0x3400F; a burst from 0x34008 over four beats leaves it with three beats
                increment_expected_alerts_and_stop_limit(ERROR, 3);
                Mem_v.setWindow(0, x"0003_4000", x"0003_400F");
                memWrite(x"0003_4008", countWords(4, 0), "write leaving the window");
                Mem_v.setWindow(0, a64(x"0000_0000_0000_0000"), a64(x"FFFF_FFFF_FFFF_FFFF"));

            elsif run("test_seq_player") then
                log(ID_LOG_HDR, "TC-PKG-09 sequence player");
                odmaSequence(tb_path(runner_cfg) & "sequences/player_ok.txt", AXILITE_VVCT, 0, AXISTREAM_VVCT, 0, 1,
                             Mm2sIrq, S2mmIrq, ClkPeriod_c);

            elsif run("test_seq_errors") then
                log(ID_LOG_HDR, "TC-PKG-10 sequence player failures");
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                odmaSequence(tb_path(runner_cfg) & "sequences/error_compare.txt", AXILITE_VVCT, 0, AXISTREAM_VVCT,
                             0, 1, Mm2sIrq, S2mmIrq, ClkPeriod_c);
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                odmaSequence(tb_path(runner_cfg) & "sequences/error_poll.txt", AXILITE_VVCT, 0, AXISTREAM_VVCT,
                             0, 1, Mm2sIrq, S2mmIrq, ClkPeriod_c);
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                odmaSequence(tb_path(runner_cfg) & "sequences/error_irq.txt", AXILITE_VVCT, 0, AXISTREAM_VVCT,
                             0, 1, Mm2sIrq, S2mmIrq, ClkPeriod_c);
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                odmaSequence(tb_path(runner_cfg) & "sequences/error_stream.txt", AXILITE_VVCT, 0, AXISTREAM_VVCT,
                             0, 1, Mm2sIrq, S2mmIrq, ClkPeriod_c);
                increment_expected_alerts_and_stop_limit(TB_ERROR, 1);
                odmaSequence(tb_path(runner_cfg) & "sequences/error_wait.txt", AXILITE_VVCT, 0, AXISTREAM_VVCT,
                             0, 1, Mm2sIrq, S2mmIrq, ClkPeriod_c);

            elsif run("test_mem_fill") then
                log(ID_LOG_HDR, "TC-PKG-12 address-dependent fill pattern");
                Base_v := x"0000_0000_0123_0000";
                Mem_v.fill(2, Base_v, 65536, 7);
                Bad_v  := 0;

                for i in 0 to 65535 loop
                    if Mem_v.read8(2, Base_v + i) /= odmaMemByte(Base_v + i, 7) then
                        Bad_v := Bad_v + 1;
                    end if;
                end loop;

                check_value(Bad_v, 0, ERROR, "filled bytes of odmaMemByte");

                -- Shifted windows differ: within the filled range through the backdoor, beyond it by the function
                for s in 0 to 11 loop
                    Exp_v  := 1 when s = 0 else
                              2 when s = 1 else
                              3 when s = 2 else
                              64 when s = 3 else
                              256 when s = 4 else
                              4096 when s = 5 else
                              8192 when s = 6 else
                              32768 when s = 7 else
                              0;
                    Sh_v   := 16 when s = 8 else
                              20 when s = 9 else
                              32 when s = 10 else
                              48;
                    Diff_v := 0;

                    for i in 0 to 255 loop
                        if s < 8 then
                            if Mem_v.read8(2, Base_v + i) /= Mem_v.read8(2, Base_v + Exp_v + i) then
                                Diff_v := Diff_v + 1;
                            end if;
                        elsif odmaMemByte(Base_v + i, 7) /= odmaMemByte(Base_v + shift_left(One_c, Sh_v) + i, 7) then
                            Diff_v := Diff_v + 1;
                        end if;
                    end loop;

                    check_value(Diff_v >= 200, ERROR, "window shifted by step " & to_string(s) & ": " &
                                to_string(Diff_v) & " of 256 bytes differ");
                end loop;

                -- Another seed gives other bytes
                Diff_v := 0;

                for i in 0 to 255 loop
                    if odmaMemByte(Base_v + i, 7) /= odmaMemByte(Base_v + i, 8) then
                        Diff_v := Diff_v + 1;
                    end if;
                end loop;

                check_value(Diff_v >= 200, ERROR, "another seed: " & to_string(Diff_v) & " of 256 bytes differ");

            elsif run("test_model_dr") then
                log(ID_LOG_HDR, "TC-PKG-11 model of the programming sequences");
                -- The pre_config of the test wrote the files of the reference scenario into the output path
                compareFiles(output_path(runner_cfg) & "sequence.txt",
                             tb_path(runner_cfg) & "golden/dr_reference/sequence.txt");
                compareFiles(output_path(runner_cfg) & "memory.txt",
                             tb_path(runner_cfg) & "golden/dr_reference/memory.txt");
                compareFiles(output_path(runner_cfg) & "expected_memory.txt",
                             tb_path(runner_cfg) & "golden/dr_reference/expected_memory.txt");
                -- The memory image round trip through the loader and the checker of the player package
                odmaLoadImage(1, output_path(runner_cfg) & "memory.txt");
                odmaCheckImage(1, tb_path(runner_cfg) & "golden/dr_reference/memory.txt");
            end if;

        end loop;

        odmaTestEnd(runner);
        wait;
    end process;

end architecture;
