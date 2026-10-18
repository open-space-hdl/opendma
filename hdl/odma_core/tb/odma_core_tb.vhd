---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VUnit testbench of odma_core: the test cases TC-CO-01 to TC-CO-08 of the verification plan. The
-- programming sequences come from the model tb/model/odma_model.py, which the pre_config of each
-- test writes into its output path (hdl/odma_core/tb/vunit_config.py). Register offsets and
-- expected values are taken from the specifications, not from the register package of the DUT.
--
-- Documentation: hdl/odma_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library vunit_lib;
    context vunit_lib.vunit_context;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axilite;
    context bitvis_vip_axilite.vvc_context;

library bitvis_vip_axistream;
    context bitvis_vip_axistream.vvc_context;

library work;
    use work.odma_tb_pkg.all;
    use work.odma_tb_mem_pkg.all;
    use work.odma_tb_memvar_pkg.all;
    use work.odma_tb_seq_pkg.all;
    use work.odma_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_core_tb is
    generic (
        runner_cfg        : string;
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
        ExtRegs_g         : boolean  := true;
        IncludeSg_g       : boolean  := false
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_core_tb is

    subtype Word_t is std_logic_vector(31 downto 0);

    constant ClkPeriod_c : time := 10 ns;

    -- Register offsets of PG021 Table 5 and of the extension window
    constant Mm2sDmacr_c  : natural := 16#000#;
    constant Mm2sDmasr_c  : natural := 16#004#;
    constant Mm2sSa_c     : natural := 16#018#;
    constant Mm2sSaMsb_c  : natural := 16#01C#;
    constant Mm2sLength_c : natural := 16#028#;
    constant S2mmDmacr_c  : natural := 16#030#;
    constant S2mmDmasr_c  : natural := 16#034#;
    constant S2mmDa_c     : natural := 16#048#;
    constant S2mmDaMsb_c  : natural := 16#04C#;
    constant S2mmLength_c : natural := 16#058#;
    constant ExtId_c      : natural := 16#100#;
    constant ExtConfig_c  : natural := 16#108#;
    constant ExtMm2sCfg_c : natural := 16#10C#;
    constant ExtS2mmCfg_c : natural := 16#110#;
    constant EccInfo_c    : natural := 16#120#;
    constant EccCtrl_c    : natural := 16#124#;
    constant EccStatus_c  : natural := 16#128#;
    constant EccEnable_c  : natural := 16#12C#;
    constant EccInject_c  : natural := 16#130#;
    constant EccCount_c   : natural := 16#140#;

    -- Fields and reset values
    constant Start_c      : Word_t := x"00015001"; -- DMACR: RS, IOC_IrqEn, Err_IrqEn, IRQThreshold 1
    constant Reset_c      : Word_t := x"00010004"; -- DMACR: Reset
    constant ResetBit_c   : Word_t := x"00000004";
    constant DmacrReset_c : Word_t := x"00010002";
    constant DmasrReset_c : Word_t := x"00010001";
    constant SgIncld_c    : Word_t := x"00000008"; -- DMASR.SGIncld

    -- Scatter/Gather Mode: pointer registers of PG021 Table 4
    constant Mm2sCur_c     : natural := 16#008#;
    constant Mm2sCurMsb_c  : natural := 16#00C#;
    constant Mm2sTail_c    : natural := 16#010#;
    constant Mm2sTailMsb_c : natural := 16#014#;
    constant S2mmCur_c     : natural := 16#038#;
    constant S2mmCurMsb_c  : natural := 16#03C#;
    constant S2mmTail_c    : natural := 16#040#;
    constant S2mmTailMsb_c : natural := 16#044#;

    -- Regions of the memory model of the descriptor port that answer SLVERR (tb/model/odma_model.py,
    -- ERR_DESC_READ_BASE, ERR_DESC_WRITE_BASE)
    constant ErrDescReadBase_c  : unsigned(63 downto 0) := x"0000_0000_0006_0000";
    constant ErrDescWriteBase_c : unsigned(63 downto 0) := x"0000_0000_0007_0000";
    -- DECERR ranges of the model (ERR_READ_DEC_BASE and the others)
    constant DecReadBase_c      : unsigned(63 downto 0) := x"0000_0000_0004_1000";
    constant DecWriteBase_c     : unsigned(63 downto 0) := x"0000_0000_0005_1000";
    constant DecDescReadBase_c  : unsigned(63 downto 0) := x"0000_0000_0006_1000";
    constant DecDescWriteBase_c : unsigned(63 downto 0) := x"0000_0000_0007_1000";
    -- FIFO windows of the model for keyhole transfers (KEYHOLE_WIN, KEYHOLE_BACK)
    constant KhWinRd_c          : unsigned(63 downto 0) := x"0000_0000_0070_0000";
    constant KhWinWr_c          : unsigned(63 downto 0) := x"0000_0000_0074_0000";
    constant KhBackRd_c         : unsigned(63 downto 0) := x"0000_0000_0078_0000";
    constant KhBackWr_c         : unsigned(63 downto 0) := x"0000_0000_007C_0000";
    constant Ones_c             : Word_t                := x"FFFFFFFF";
    constant Zero_c             : Word_t                := x"00000000";

    -- Regions of the memory model that answer SLVERR (tb/model/odma_model.py, ERR_READ_BASE, ERR_WRITE_BASE)
    constant ErrReadBase_c  : unsigned(63 downto 0) := x"0000_0000_0004_0000";
    constant ErrWriteBase_c : unsigned(63 downto 0) := x"0000_0000_0005_0000";
    constant ErrSize_c      : natural               := 4096;

    -- Buffers of the transfers that the soft reset interrupts (outside the regions of the model scenarios)
    constant LoadRdAddr_c : natural := 16#0040_0000#;
    constant LoadWrAddr_c : natural := 16#0050_0000#;

    -- Buffers of the injections in data mode (TC-CO-10): the MM2S transfer and the S2MM packets have a length of
    -- 2 modulo 4, so that the double error of a length (its bits 0 and 1) shortens it by one byte
    constant DataRdAddr_c : natural  := 16#0060_0000#;
    constant DataWrAddr_c : natural  := 16#0070_0000#;
    constant DataRdLen_c  : positive := 254;
    constant DataPktLen_c : positive := 62;
    constant DataBufLen_c : positive := 128;
    constant InjData_c    : natural  := 16#400#;
    constant InjDouble_c  : natural  := 16#100#;
    constant InjInject_c  : natural  := 16#200#;

    constant MaxLen_c : positive := 2**LengthWidth_g - 1;

    signal Mm2sIrq    : std_logic;
    signal S2mmIrq    : std_logic;
    signal EccIrq     : std_logic;
    signal Mm2sRstOut : std_logic;
    signal S2mmRstOut : std_logic;
    signal PeerBytes  : natural                       := 0;
    signal PeerEmpty  : std_logic                     := '0';
    signal FixedRd    : std_logic_vector(63 downto 0) := (others => '0');
    signal FixedWr    : std_logic_vector(63 downto 0) := (others => '0');
    signal ObsClear   : std_logic                     := '0';
    signal Obs        : CoreObs_r;

    -- n ones from bit 0
    function lowOnes (n : natural) return Word_t is
        variable W_v : Word_t := (others => '0');
    begin

        for i in 0 to 31 loop
            if i < n then
                W_v(i) := '1';
            end if;
        end loop;

        return W_v;
    end function;

    -- t when c, otherwise f
    function choose (
        c : boolean;
        t : Word_t;
        f : Word_t) return Word_t is
    begin
        if c then
            return t;
        end if;
        return f;
    end function;

    function choose (
        c : boolean;
        t : string;
        f : string) return string is
    begin
        if c then
            return t;
        end if;
        return f;
    end function;

    function choose (
        c : boolean;
        t : natural;
        f : natural) return natural is
    begin
        if c then
            return t;
        end if;
        return f;
    end function;

    -- EXT_CONFIG (odma_registers specification RG-EX-02, architecture section 7)
    function extConfig return Word_t is
        variable W_v : Word_t := (others => '0');
    begin
        W_v(0)            := '1' when IncludeSg_g else '0';
        W_v(1)            := '1' when IncludeMm2s_g else '0';
        W_v(2)            := '1' when IncludeS2mm_g else '0';
        W_v(12 downto 8)  := std_logic_vector(to_unsigned(LengthWidth_g, 5));
        W_v(22 downto 16) := std_logic_vector(to_unsigned(AddrWidth_g, 7));
        return W_v;
    end function;

    -- EXT_MM2S_CONFIG and EXT_S2MM_CONFIG
    function channelConfig (
        mem    : positive;
        stream : positive;
        burst  : positive;
        buf    : positive) return Word_t is
        variable W_v : Word_t;
    begin
        W_v(3 downto 0)   := std_logic_vector(to_unsigned(log2(mem / 8), 4));
        W_v(7 downto 4)   := std_logic_vector(to_unsigned(log2(stream / 8), 4));
        W_v(11 downto 8)  := std_logic_vector(to_unsigned(log2(burst), 4));
        W_v(31 downto 12) := std_logic_vector(to_unsigned(buf, 20));
        return W_v;
    end function;

begin

    -----------------------------------------------------------------------------------------------
    -- Harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.odma_core_th
        generic map (
            ClkPeriod_g       => ClkPeriod_c,
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
            ExtRegs_g         => ExtRegs_g,
            IncludeSg_g       => IncludeSg_g
        )
        port map (
            Mm2sIrq    => Mm2sIrq,
            S2mmIrq    => S2mmIrq,
            EccIrq     => EccIrq,
            Mm2sRstOut => Mm2sRstOut,
            S2mmRstOut => S2mmRstOut,
            PeerBytes  => PeerBytes,
            PeerEmpty  => PeerEmpty,
            FixedRd    => FixedRd,
            FixedWr    => FixedWr,
            ObsClear   => ObsClear,
            Obs        => Obs
        );

    -----------------------------------------------------------------------------------------------
    -- Test control
    -----------------------------------------------------------------------------------------------
    p_control : process is
        variable Data_v      : Word_t;
        variable CmdIdx_v    : natural;
        variable Result_v    : bitvis_vip_axilite.vvc_cmd_pkg.t_vvc_result;
        variable Ar_v        : natural;
        variable Aw_v        : natural;
        variable Len_v       : natural;
        variable Mm2s_v      : boolean;
        variable Counts_v    : boolean;
        variable Ded_v       : boolean;
        variable Exp_v       : t_slv_array(0 to 255)(7 downto 0);
        variable Base_v      : unsigned(63 downto 0);
        variable Cnt_v       : integer;
        variable RateBeats_v : natural;
        variable Cyc1k_v     : integer;
        variable Cyc4k_v     : integer;
        variable CycU_v      : integer;

        impure function hex (ofs : natural) return string is
        begin
            return "0x" & to_hstring(to_unsigned(ofs, 12));
        end function;

        -- Register write, complete before the next access
        procedure wr (
            ofs  : natural;
            data : Word_t) is
        begin
            axilite_write(AXILITE_VVCT, 0, to_unsigned(ofs, 10), data, "write " & hex(ofs));
            await_completion(AXILITE_VVCT, 0, 10 us, "write " & hex(ofs));
        end procedure;

        -- Register read (the VVC checks the response OKAY)
        procedure rd (
            ofs  : natural;
            data : out Word_t) is
        begin
            axilite_read(AXILITE_VVCT, 0, to_unsigned(ofs, 10), "read " & hex(ofs));
            CmdIdx_v := get_last_received_cmd_idx(AXILITE_VVCT, 0);
            await_completion(AXILITE_VVCT, 0, CmdIdx_v, 10 us, "read " & hex(ofs));
            fetch_result(AXILITE_VVCT, 0, CmdIdx_v, Result_v, "read " & hex(ofs));
            data     := Result_v(31 downto 0);
        end procedure;

        -- The bits of mask
        procedure chk (
            ofs  : natural;
            exp  : Word_t;
            msg  : string;
            mask : Word_t := Ones_c) is
            variable D_v : Word_t;
        begin
            rd(ofs, D_v);
            check_value(D_v and mask, exp and mask, ERROR, msg & ": " & hex(ofs), C_TB_SCOPE_DEFAULT, HEX);
        end procedure;

        -- Reads until the bits of mask have the expected value, for at most limit
        procedure poll (
            ofs   : natural;
            exp   : Word_t;
            mask  : Word_t;
            limit : time;
            msg   : string) is
            variable D_v        : Word_t;
            variable Deadline_v : time;
        begin
            Deadline_v := now + limit;

            loop
                rd(ofs, D_v);
                exit when (D_v and mask) = (exp and mask) or now > Deadline_v;
            end loop;

            check_value(D_v and mask, exp and mask, ERROR, msg & ": " & hex(ofs), C_TB_SCOPE_DEFAULT, HEX);
        end procedure;

        -- Memory image, sequence and expected memory of a model scenario in the directory dir of the
        -- output path
        procedure scenario (
            dir : string;
            msg : string) is
            constant Path_c : string := output_path(runner_cfg) & dir;
        begin
            log(ID_SEQUENCER, "scenario " & msg);
            odmaLoadImage(MemRd_c, Path_c & "memory.txt");
            if IncludeSg_g then
                odmaLoadImage(MemSg_c, Path_c & "desc_memory.txt");
            end if;
            odmaSequence(Path_c & "sequence.txt", AXILITE_VVCT, 0, AXISTREAM_VVCT, 0, 1, Mm2sIrq, S2mmIrq,
                         ClkPeriod_c);
            odmaCheckImage(MemWr_c, Path_c & "expected_memory.txt");
            if IncludeSg_g then
                odmaCheckImage(MemSg_c, Path_c & "expected_desc_memory.txt");
            end if;
        end procedure;

        -- Address registers of a channel: low word and, above 32 address bits, the MSB register
        procedure setAddr (
            lo   : natural;
            hi   : natural;
            addr : natural) is
        begin
            wr(lo, std_logic_vector(to_unsigned(addr, 32)));
            if AddrWidth_g > 32 then
                wr(hi, Zero_c);
            end if;
        end procedure;

        -- Soft reset through the first included channel
        procedure softReset is
            constant Dmacr_c : natural := choose(IncludeMm2s_g, Mm2sDmacr_c, S2mmDmacr_c);
        begin
            wr(Dmacr_c, Reset_c);
            poll(Dmacr_c, Zero_c, ResetBit_c, 10 us, "end of the soft reset");
        end procedure;

        -- Error injection in data mode into buffer k after cleared counters and flags
        procedure injectData (
            k      : natural;
            double : boolean) is
        begin
            wr(EccCtrl_c, x"00000001");
            wr(EccStatus_c, x"00000003");
            wr(EccInject_c, std_logic_vector(to_unsigned(InjData_c + InjInject_c + k +
                                                          choose(double, InjDouble_c, 0), 32)));
        end procedure;

        -- The counters of buffer k count one event of the kind, all other counters 0
        procedure checkCounts (
            k      : natural;
            double : boolean;
            msg    : string) is
            variable D_v : Word_t;
        begin

            for n in 0 to 15 loop
                rd(EccCount_c + 4 * n, D_v);
                if n = k and double then
                    check_value(D_v, x"00010000", ERROR, msg & ": counters of buffer " & to_string(n), C_TB_SCOPE_DEFAULT,
                                HEX);
                elsif n = k then
                    check_value(D_v, x"00000001", ERROR, msg & ": counters of buffer " & to_string(n), C_TB_SCOPE_DEFAULT,
                                HEX);
                else
                    check_value(D_v, Zero_c, ERROR, msg & ": counters of buffer " & to_string(n), C_TB_SCOPE_DEFAULT, HEX);
                end if;
            end loop;

        end procedure;

        -- S2MM packet of DataPktLen_c bytes (odmaMemByte of the byte index and seed) into the buffer at addr; the
        -- bytes from the packet start to the end of the buffer are checked: byte 0 inverted in bits 0 and 1 when
        -- flip, the packet shortened by one byte when short, unwritten bytes 0
        procedure checkPacket (
            addr  : natural;
            seed  : natural;
            flip  : boolean;
            short : boolean;
            msg   : string) is
            variable Exp8_v : std_logic_vector(7 downto 0);
            variable Bad_v  : natural := 0;
            variable Len_v  : natural;
        begin
            Len_v := DataPktLen_c - 1 when short else DataPktLen_c;

            for i in 0 to DataBufLen_c - 1 loop
                Exp8_v := odmaMemByte(to_unsigned(i, 64), seed) when i < Len_v else x"00";
                if i = 0 and flip then
                    Exp8_v := Exp8_v xor x"03";
                end if;
                if Mem_v.read8(MemWr_c, to_unsigned(addr + i, 64)) /= Exp8_v then
                    Bad_v := Bad_v + 1;
                end if;
            end loop;

            check_value(Bad_v, 0, ERROR, msg & ": bytes of the buffer that differ");
            chk(S2mmLength_c, std_logic_vector(to_unsigned(Len_v, 32)), msg & ": S2MM_LENGTH");
        end procedure;

        -- One S2MM transfer of a packet that is already in the data buffer (sent before) or is sent now
        procedure s2mmTransfer (
            addr : natural) is
        begin
            setAddr(S2mmDa_c, S2mmDaMsb_c, addr);
            wr(S2mmLength_c, std_logic_vector(to_unsigned(DataBufLen_c, 32)));
            await_value(S2mmIrq, '1', 0 ns, 100 us, ERROR, "S2MM interrupt");
            chk(S2mmDmasr_c, x"00001002", "S2MM transfer completed", x"00007773");
            wr(S2mmDmasr_c, x"00001000");
        end procedure;

        procedure sendPacket (
            seed : natural) is
            variable Pkt_v : t_slv_array(0 to DataPktLen_c - 1)(7 downto 0);
        begin

            for i in 0 to DataPktLen_c - 1 loop
                Pkt_v(i) := odmaMemByte(to_unsigned(i, 64), seed);
            end loop;

            axistream_transmit(AXISTREAM_VVCT, 0, Pkt_v, "S2MM packet");
            await_completion(AXISTREAM_VVCT, 0, 100 us, "S2MM packet sent");
        end procedure;

    -- Comment for the style checker: subprograms above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);
        -- Every burst is checked against the burst limit of its channel and 4 KB
        Mem_v.setMaxBeats(MemRd_c, Mm2sBurstBeats_g);
        Mem_v.setMaxBeats(MemWr_c, S2mmBurstBeats_g);
        Mem_v.setMaxBeats(MemSg_c, 16);
        await_uvvm_initialization(VOID);
        -- The sequences issue thousands of VVC commands: the log keeps the headers and the sequence steps
        disable_log_msg(AXILITE_VVCT, 0, ALL_MESSAGES);
        disable_log_msg(AXISTREAM_VVCT, 0, ALL_MESSAGES);
        disable_log_msg(AXISTREAM_VVCT, 1, ALL_MESSAGES);
        wait for 20 * ClkPeriod_c;

        while test_suite loop

            if run("test_dr_reference") then
                log(ID_LOG_HDR, "TC-CO-01 reference DR scenario of the model");
                scenario("", "dr_reference");

            elsif run("test_dr_random") then
                log(ID_LOG_HDR, "TC-CO-02 random DR transfers with memory backpressure");
                Mem_v.setStall(MemRd_c, 30);
                Mem_v.setStall(MemWr_c, 30);
                Mem_v.setLatency(MemRd_c, 8);
                Mem_v.setLatency(MemWr_c, 8);
                scenario("", "dr_random");

            elsif run("test_concurrent") then
                log(ID_LOG_HDR, "TC-CO-03 both channels at the same time");
                scenario("", "dr_concurrent");
                check_value(Obs.Overlap, ERROR, "a read beat and a write beat in the same clock cycle");

            elsif run("test_errors") then
                log(ID_LOG_HDR, "TC-CO-04 errors end to end and their recovery");
                Mem_v.setError(MemRd_c, 0, ErrReadBase_c, ErrReadBase_c + ErrSize_c - 1, "10", TbDirRead);
                Mem_v.setError(MemWr_c, 0, ErrWriteBase_c, ErrWriteBase_c + ErrSize_c - 1, "10", TbDirWrite);
                Mem_v.setError(MemRd_c, 1, DecReadBase_c, DecReadBase_c + ErrSize_c - 1, "11", TbDirRead);
                Mem_v.setError(MemWr_c, 1, DecWriteBase_c, DecWriteBase_c + ErrSize_c - 1, "11", TbDirWrite);
                scenario("", "dr_errors");

            elsif run("test_soft_reset_load") then
                log(ID_LOG_HDR, "TC-CO-05 soft reset with transfers in progress");
                Mem_v.setLatency(MemRd_c, 100);
                Mem_v.setLatency(MemWr_c, 100);
                Mem_v.setStall(MemRd_c, 50);
                Mem_v.setStall(MemWr_c, 50);
                wr(Mm2sDmacr_c, Start_c);
                wr(S2mmDmacr_c, Start_c);
                poll(Mm2sDmasr_c, Zero_c, x"00000001", 10 us, "MM2S running");
                poll(S2mmDmasr_c, Zero_c, x"00000001", 10 us, "S2MM running");
                -- MM2S: the stream peer takes nothing, the read data fills the buffer
                setAddr(Mm2sSa_c, Mm2sSaMsb_c, LoadRdAddr_c);
                wr(Mm2sLength_c, std_logic_vector(to_unsigned(minimum(MaxLen_c, 4000), 32)));
                -- S2MM: a packet of three data buffers from the stream peer of the harness, written slowly; the
                -- peer is still sending at the reset and abandons the packet when S2mm_RstOut rises
                Len_v     := minimum(minimum(MaxLen_c, 3 * S2mmBufferBeats_g * S2mmStreamWidth_g / 8), 16384);
                setAddr(S2mmDa_c, S2mmDaMsb_c, LoadWrAddr_c);
                wr(S2mmLength_c, std_logic_vector(to_unsigned(Len_v, 32)));
                PeerBytes <= Len_v;
                if Obs.AwBursts = 0 or Obs.ArBursts = 0 then
                    wait until Obs.AwBursts > 0 and Obs.ArBursts > 0 for 100 us;
                end if;
                check_value(Obs.ArBursts > Obs.RBursts, ERROR, "read bursts outstanding before the reset");
                check_value(Obs.AwBursts > Obs.BResps, ERROR, "write bursts outstanding before the reset");
                check_value(not Obs.PeerDone, ERROR, "S2MM stream peer in the middle of its packet at the reset");
                -- Soft reset: the reset outputs are high while it lasts, the S2MM stream takes no beat
                wr(Mm2sDmacr_c, Reset_c);
                check_value(Mm2sRstOut, '1', ERROR, "MM2S reset output during the soft reset");
                check_value(S2mmRstOut, '1', ERROR, "S2MM reset output during the soft reset");
                poll(Mm2sDmacr_c, Zero_c, ResetBit_c, 200 us, "end of the soft reset");
                check_value(Mm2sRstOut, '0', ERROR, "MM2S reset output after the soft reset");
                check_value(S2mmRstOut, '0', ERROR, "S2MM reset output after the soft reset");
                check_value(Obs.PeerDone, ERROR, "S2MM stream peer abandoned its packet");
                check_value(Obs.RstBeats, 0, ERROR, "S2MM stream beats taken during the soft reset");
                PeerBytes <= 0;
                -- Every accepted transaction completed, none started after the reset
                check_value(Obs.RBursts, Obs.ArBursts, ERROR, "every read burst completed");
                check_value(Obs.BResps, Obs.AwBursts, ERROR, "every write burst answered");
                Ar_v := Obs.ArBursts;
                Aw_v := Obs.AwBursts;
                wait for 2 us;
                check_value(Obs.ArBursts, Ar_v, ERROR, "no read burst after the soft reset");
                check_value(Obs.AwBursts, Aw_v, ERROR, "no write burst after the soft reset");
                chk(Mm2sDmacr_c, DmacrReset_c, "MM2S_DMACR after the soft reset");
                chk(Mm2sDmasr_c, DmasrReset_c, "MM2S_DMASR after the soft reset");
                chk(S2mmDmacr_c, DmacrReset_c, "S2MM_DMACR after the soft reset");
                chk(S2mmDmasr_c, DmasrReset_c, "S2MM_DMASR after the soft reset");
                -- The core works normally afterwards; no beat of the interrupted transfers appears
                Mem_v.setLatency(MemRd_c, 0);
                Mem_v.setLatency(MemWr_c, 0);
                Mem_v.setStall(MemRd_c, 0);
                Mem_v.setStall(MemWr_c, 0);
                scenario("", "after the soft reset");

            elsif run("test_ecc_index") then
                log(ID_LOG_HDR, "TC-CO-06 FT buffer indices of the extension window");

                for k in 0 to 6 loop
                    -- Channel of buffer k (architecture of odma_registers, section 8); index 6 has no buffer in DR mode
                    Mm2s_v   := k = 0 or k = 4 or k = 5 or (k = 6 and IncludeMm2s_g);
                    Counts_v := ExtRegs_g and k < 6 and ((Mm2s_v and IncludeMm2s_g) or (not Mm2s_v and IncludeS2mm_g));
                    Mm2s_v   := (Mm2s_v and IncludeMm2s_g) or not IncludeS2mm_g;
                    log(ID_SEQUENCER, "buffer index " & to_string(k) & ", " & (choose(Counts_v, "counts", "counts nothing")));
                    wr(EccCtrl_c, x"00000001");
                    wr(EccStatus_c, x"00000003");
                    wr(EccEnable_c, x"00000001");
                    check_value(EccIrq, '0', ERROR, "Ecc_Irq after the clear");
                    wr(EccInject_c, std_logic_vector(to_unsigned(16#200# + k, 32)));
                    if Mm2s_v then
                        scenario("ecc_mm2s/", "MM2S transfer through buffer " & to_string(k));
                    else
                        scenario("ecc_s2mm/", "S2MM transfer through buffer " & to_string(k));
                    end if;

                    for n in 0 to 15 loop
                        rd(EccCount_c + 4 * n, Data_v);
                        if n = k and Counts_v then
                            check_value(unsigned(Data_v(15 downto 0)) >= 1, ERROR,
                                        "SEC counter of buffer " & to_string(n));
                            check_value(Data_v(31 downto 16), x"0000", ERROR, "DED counter of buffer " & to_string(n));
                        else
                            check_value(Data_v, Zero_c, ERROR, "counters of buffer " & to_string(n), C_TB_SCOPE_DEFAULT,
                                        HEX);
                        end if;
                    end loop;

                    if Counts_v then
                        chk(EccStatus_c, x"00000001", "SEC flag");
                        await_value(EccIrq, '1', 0 ns, 10 * ClkPeriod_c, ERROR, "Ecc_Irq of the SEC flag");
                    else
                        chk(EccStatus_c, Zero_c, "no ECC flag");
                        check_value(EccIrq, '0', ERROR, "Ecc_Irq without an event");
                    end if;
                end loop;

                -- A soft reset resets the channels: it cancels an injection that is pending in a buffer
                for k in 0 to 5 loop
                    Mm2s_v := k = 0 or k = 4 or k = 5;
                    next when not ExtRegs_g or (Mm2s_v and not IncludeMm2s_g) or (not Mm2s_v and not IncludeS2mm_g);
                    log(ID_SEQUENCER, "buffer index " & to_string(k) & ": injection cancelled by a soft reset");
                    wr(EccInject_c, std_logic_vector(to_unsigned(16#200# + k, 32)));
                    wr(choose(IncludeMm2s_g, Mm2sDmacr_c, S2mmDmacr_c), Reset_c);
                    poll(choose(IncludeMm2s_g, Mm2sDmacr_c, S2mmDmacr_c), Zero_c, ResetBit_c, 10 us, "end of the soft reset");
                    wr(EccCtrl_c, x"00000001");
                    wr(EccStatus_c, x"00000003");
                    if Mm2s_v then
                        scenario("ecc_mm2s/", "MM2S transfer after the soft reset");
                    else
                        scenario("ecc_s2mm/", "S2MM transfer after the soft reset");
                    end if;

                    for n in 0 to 15 loop
                        chk(EccCount_c + 4 * n, Zero_c, "counters of buffer " & to_string(n) & " after the soft reset");
                    end loop;

                    chk(EccStatus_c, Zero_c, "no ECC flag after the soft reset");
                end loop;

            elsif run("test_ecc_data") then
                log(ID_LOG_HDR, "TC-CO-10 error injections in data mode: corrected single errors, the double error of " &
                    "each buffer with its own consequence");

                for d in 0 to 1 loop
                    Ded_v := d = 1;

                    -- MM2S: an injection before a transfer goes into its first read data word (index 0), its entry
                    -- {code, end of packet, length} (index 4) and its response code (index 5)
                    for k in 0 to 5 loop
                        next when not IncludeMm2s_g or (k /= 0 and k /= 4 and k /= 5);
                        log(ID_SEQUENCER, "MM2S buffer " & to_string(k) & choose(Ded_v, ", double error", ", single error"));
                        Base_v := to_unsigned(DataRdAddr_c + 4096 * k, 64);
                        Mem_v.fill(MemRd_c, Base_v, DataRdLen_c, 40 + k);
                        softReset;
                        injectData(k, Ded_v);
                        wr(Mm2sDmacr_c, Start_c);
                        poll(Mm2sDmasr_c, Zero_c, x"00000001", 10 us, "MM2S running");

                        for i in 0 to DataRdLen_c - 1 loop
                            Exp_v(i) := odmaMemByte(Base_v + i, 40 + k);
                        end loop;

                        Len_v := DataRdLen_c;
                        if Ded_v and k = 0 then
                            Exp_v(0) := Exp_v(0) xor x"03";            -- Data bits 0 and 1 of the first word
                        elsif Ded_v and k = 4 then
                            Len_v := DataRdLen_c - 1;                   -- Length bits 0 and 1: 254 becomes 253
                        end if;
                        axistream_expect(AXISTREAM_VVCT, 1, Exp_v(0 to Len_v - 1), "MM2S packet");
                        setAddr(Mm2sSa_c, Mm2sSaMsb_c, DataRdAddr_c + 4096 * k);
                        wr(Mm2sLength_c, std_logic_vector(to_unsigned(DataRdLen_c, 32)));
                        await_completion(AXISTREAM_VVCT, 1, 100 us, "MM2S packet received");
                        await_value(Mm2sIrq, '1', 0 ns, 100 us, ERROR, "MM2S interrupt");
                        if Ded_v and k = 5 then
                            -- Response code 00 becomes 11: the transfer ends with the decode error
                            poll(Mm2sDmasr_c, x"00000001", x"00000001", 10 us, "MM2S halted");
                            chk(Mm2sDmasr_c, x"00004041", "MM2S decode error of the response", x"00007773");
                        else
                            chk(Mm2sDmasr_c, x"00001002", "MM2S transfer completed", x"00007773");
                        end if;
                        checkCounts(k, Ded_v, "MM2S buffer " & to_string(k));
                    end loop;

                    -- S2MM: packet A waits in the data buffer (its words and its chunk entry written) before the
                    -- injection, packet B arrives after it. The injection goes into the write data of A (index 3),
                    -- the first data word of B (index 1) or the chunk entry of B (index 2)
                    for k in 1 to 3 loop
                        next when not IncludeS2mm_g;
                        log(ID_SEQUENCER, "S2MM buffer " & to_string(k) & choose(Ded_v, ", double error", ", single error"));
                        softReset;
                        wr(S2mmDmacr_c, Start_c);
                        poll(S2mmDmasr_c, Zero_c, x"00000001", 10 us, "S2MM running");
                        sendPacket(50 + k);
                        wait for 100 * ClkPeriod_c;
                        injectData(k, Ded_v);
                        s2mmTransfer(DataWrAddr_c + 32768 * d + 4096 * k);
                        checkPacket(DataWrAddr_c + 32768 * d + 4096 * k, 50 + k, Ded_v and k = 3, false,
                                    "packet A, buffer " & to_string(k));
                        sendPacket(60 + k);
                        s2mmTransfer(DataWrAddr_c + 32768 * d + 4096 * k + 2048);
                        checkPacket(DataWrAddr_c + 32768 * d + 4096 * k + 2048, 60 + k, Ded_v and k = 1, Ded_v and k = 2,
                                    "packet B, buffer " & to_string(k));
                        checkCounts(k, Ded_v, "S2MM buffer " & to_string(k));
                    end loop;

                end loop;

            elsif run("test_configuration") then
                log(ID_LOG_HDR, "TC-CO-07 configuration readback and register widths");
                chk(Mm2sDmacr_c, choose(IncludeMm2s_g, DmacrReset_c, Zero_c), "MM2S_DMACR reset value");
                chk(Mm2sDmasr_c, choose(IncludeMm2s_g, DmasrReset_c or choose(IncludeSg_g, SgIncld_c, Zero_c), Zero_c),
                    "MM2S_DMASR reset value");
                chk(S2mmDmacr_c, choose(IncludeS2mm_g, DmacrReset_c, Zero_c), "S2MM_DMACR reset value");
                chk(S2mmDmasr_c, choose(IncludeS2mm_g, DmasrReset_c or choose(IncludeSg_g, SgIncld_c, Zero_c), Zero_c),
                    "S2MM_DMASR reset value");
                if ExtRegs_g then
                    chk(ExtId_c, x"4F444D41", "EXT_ID");
                    chk(ExtConfig_c, extConfig, "EXT_CONFIG");
                    chk(ExtMm2sCfg_c, channelConfig(Mm2sMemWidth_g, Mm2sStreamWidth_g, Mm2sBurstBeats_g,
                                                    Mm2sBufferBeats_g), "EXT_MM2S_CONFIG");
                    chk(ExtS2mmCfg_c, channelConfig(S2mmMemWidth_g, S2mmStreamWidth_g, S2mmBurstBeats_g,
                                                    S2mmBufferBeats_g), "EXT_S2MM_CONFIG");
                    chk(EccInfo_c, x"00001010", "ECC_INFO");
                else
                    chk(ExtId_c, Zero_c, "EXT_ID without the extension window");
                    chk(ExtConfig_c, Zero_c, "EXT_CONFIG without the extension window");
                end if;
                -- Scatter/Gather Mode: the pointer registers hold AddrWidth_g bits without bits 5 to 0; the registers
                -- of Direct Register Mode do not exist (CO-SG-01)
                if IncludeSg_g then

                    for i in 0 to 1 loop
                        if (i = 0 and IncludeMm2s_g) or (i = 1 and IncludeS2mm_g) then
                            wr(choose(i = 0, Mm2sCur_c, S2mmCur_c), Ones_c);
                            wr(choose(i = 0, Mm2sCurMsb_c, S2mmCurMsb_c), Ones_c);
                            wr(choose(i = 0, Mm2sTail_c, S2mmTail_c), Ones_c);
                            wr(choose(i = 0, Mm2sTailMsb_c, S2mmTailMsb_c), Ones_c);
                            chk(choose(i = 0, Mm2sCur_c, S2mmCur_c), x"FFFFFFC0", "CURDESC width");
                            chk(choose(i = 0, Mm2sCurMsb_c, S2mmCurMsb_c), lowOnes(AddrWidth_g - 32), "CURDESC_MSB width");
                            chk(choose(i = 0, Mm2sTail_c, S2mmTail_c), x"FFFFFFC0", "TAILDESC width");
                            chk(choose(i = 0, Mm2sTailMsb_c, S2mmTailMsb_c), lowOnes(AddrWidth_g - 32), "TAILDESC_MSB width");
                        end if;
                    end loop;

                    wr(Mm2sLength_c, Ones_c);
                    wr(S2mmLength_c, Ones_c);
                    chk(Mm2sLength_c, Zero_c, "no MM2S_LENGTH in Scatter/Gather Mode");
                    chk(S2mmLength_c, Zero_c, "no S2MM_LENGTH in Scatter/Gather Mode");
                    wait for 1 us;
                    check_value(Obs.ArBursts + Obs.AwBursts + Obs.SgFetch + Obs.SgUpdate, 0, ERROR,
                                "no memory access while the channels are halted");
                else
                    -- Address and length registers hold AddrWidth_g and LengthWidth_g bits; a length written while
                    -- the channel is halted starts nothing (interpretation I7 of odma_registers)
                    wr(Mm2sSa_c, Ones_c);
                    wr(Mm2sSaMsb_c, Ones_c);
                    wr(Mm2sLength_c, Ones_c);
                    wr(S2mmDa_c, Ones_c);
                    wr(S2mmDaMsb_c, Ones_c);
                    wr(S2mmLength_c, Ones_c);
                    chk(Mm2sSa_c, choose(IncludeMm2s_g, Ones_c, Zero_c), "MM2S_SA width");
                    chk(Mm2sSaMsb_c, choose(IncludeMm2s_g and AddrWidth_g > 32, lowOnes(AddrWidth_g - 32), Zero_c),
                        "MM2S_SA_MSB width");
                    chk(Mm2sLength_c, choose(IncludeMm2s_g, lowOnes(LengthWidth_g), Zero_c), "MM2S_LENGTH width");
                    chk(S2mmDa_c, choose(IncludeS2mm_g, Ones_c, Zero_c), "S2MM_DA width");
                    chk(S2mmDaMsb_c, choose(IncludeS2mm_g and AddrWidth_g > 32, lowOnes(AddrWidth_g - 32), Zero_c),
                        "S2MM_DA_MSB width");
                    chk(S2mmLength_c, choose(IncludeS2mm_g, lowOnes(LengthWidth_g), Zero_c), "S2MM_LENGTH width");
                    wait for 1 us;
                    check_value(Obs.ArBursts + Obs.AwBursts, 0, ERROR, "no memory access while the channels are halted");
                end if;

            elsif run("test_excluded_channel") then
                log(ID_LOG_HDR, "TC-CO-08 configuration with one channel");
                if IncludeMm2s_g then
                    -- The S2MM registers read 0 and ignore writes; the S2MM ports stay idle (harness)
                    wr(S2mmDmacr_c, Start_c);
                    wr(S2mmDa_c, x"00001000");
                    wr(S2mmLength_c, x"00000100");
                    chk(S2mmDmacr_c, Zero_c, "S2MM_DMACR of the excluded channel");
                    chk(S2mmDmasr_c, Zero_c, "S2MM_DMASR of the excluded channel");
                    chk(S2mmDa_c, Zero_c, "S2MM_DA of the excluded channel");
                    chk(S2mmLength_c, Zero_c, "S2MM_LENGTH of the excluded channel");
                    scenario("", "MM2S only");
                else
                    wr(Mm2sDmacr_c, Start_c);
                    wr(Mm2sSa_c, x"00001000");
                    wr(Mm2sLength_c, x"00000100");
                    chk(Mm2sDmacr_c, Zero_c, "MM2S_DMACR of the excluded channel");
                    chk(Mm2sDmasr_c, Zero_c, "MM2S_DMASR of the excluded channel");
                    chk(Mm2sSa_c, Zero_c, "MM2S_SA of the excluded channel");
                    chk(Mm2sLength_c, Zero_c, "MM2S_LENGTH of the excluded channel");
                    scenario("", "S2MM only");
                end if;
                check_value(choose(IncludeMm2s_g, Obs.AwBursts, Obs.ArBursts), 0, ERROR,
                            "no access of the excluded channel");

            elsif run("test_sg_reference") then
                log(ID_LOG_HDR, "TC-CO-11 programming sequence of Scatter/Gather Mode");
                scenario("", "sg_reference");

            elsif run("test_sg_tail_moves") then
                log(ID_LOG_HDR, "TC-CO-12 tail pointer moved while the channels run, with memory backpressure");
                Mem_v.setStall(MemRd_c, 20);
                Mem_v.setStall(MemWr_c, 20);
                Mem_v.setStall(MemSg_c, 30);
                Mem_v.setLatency(MemSg_c, 6);
                scenario("", "sg_tail_moves");

            elsif run("test_sg_cyclic") then
                log(ID_LOG_HDR, "TC-CO-13 cyclic mode");
                scenario("", "sg_cyclic");

            elsif run("test_sg_errors") then
                log(ID_LOG_HDR, "TC-CO-14 errors of Scatter/Gather Mode and their recovery");
                Mem_v.setError(MemSg_c, 0, ErrDescReadBase_c, ErrDescReadBase_c + ErrSize_c - 1, "10", TbDirRead);
                Mem_v.setError(MemSg_c, 1, ErrDescWriteBase_c, ErrDescWriteBase_c + ErrSize_c - 1, "10", TbDirWrite);
                Mem_v.setError(MemSg_c, 2, DecDescReadBase_c, DecDescReadBase_c + ErrSize_c - 1, "11", TbDirRead);
                Mem_v.setError(MemSg_c, 3, DecDescWriteBase_c, DecDescWriteBase_c + ErrSize_c - 1, "11", TbDirWrite);
                scenario("", "sg_errors");

            elsif run("test_sg_delay") then
                log(ID_LOG_HDR, "TC-CO-16 interrupt delay and the start of a packet");
                -- Every packet pauses after its first beat: for 1500 clock cycles, longer than the delay of the
                -- scenarios, then for 400 clock cycles, shorter than the delay
                shared_axistream_vvc_config(0).bfm_config.valid_low_at_word_num := 1;
                shared_axistream_vvc_config(0).bfm_config.valid_low_duration    := 1500;
                shared_axistream_vvc_config(1).bfm_config.ready_low_at_word_num := 1;
                shared_axistream_vvc_config(1).bfm_config.ready_low_duration    := 1500;
                scenario("hold/", "sg_delay");
                shared_axistream_vvc_config(0).bfm_config.valid_low_duration    := 400;
                shared_axistream_vvc_config(1).bfm_config.ready_low_duration    := 400;
                scenario("overlap/", "sg_delay_overlap");

            elsif run("test_sg_soft_reset") then
                log(ID_LOG_HDR, "TC-CO-17 soft reset in Scatter/Gather Mode under load");
                Mem_v.setLatency(MemSg_c, 100);
                Mem_v.setStall(MemSg_c, 50);
                Mem_v.setLatency(MemRd_c, 100);
                Mem_v.setLatency(MemWr_c, 100);
                Mem_v.setStall(MemRd_c, 50);
                Mem_v.setStall(MemWr_c, 50);

                -- Phase 0: the soft reset comes while a descriptor access is outstanding; phase 1: while data bursts
                -- of the channels are outstanding (S2MM writes, without S2MM MM2S reads) and no descriptor access
                for phase in 0 to 1 loop
                    -- The chains of both channels started; the MM2S stream peer takes nothing, the S2MM peer of the
                    -- harness sends one packet into the first buffer of the chain and abandons it at the reset
                    scenario("start/", "chains started under load");
                    if IncludeS2mm_g then
                        PeerBytes <= minimum(minimum(MaxLen_c, 3 * S2mmBufferBeats_g * S2mmStreamWidth_g / 8), 16384);
                    end if;

                    loop
                        Mm2s_v := Obs.SgFetch > Obs.SgRDone or Obs.SgUpdate > Obs.SgBDone;
                        if phase = 1 then
                            Mm2s_v := not Mm2s_v and
                                      ((IncludeS2mm_g and Obs.AwBursts > Obs.BResps) or
                                         (not IncludeS2mm_g and Obs.ArBursts > Obs.RBursts));
                        end if;
                        exit when Mm2s_v or now > 1 ms;
                        wait for ClkPeriod_c;
                    end loop;

                    check_value(Mm2s_v, ERROR, "accesses outstanding before the reset of phase " & to_string(phase));
                    wr(choose(IncludeMm2s_g, Mm2sDmacr_c, S2mmDmacr_c), Reset_c);
                    poll(choose(IncludeMm2s_g, Mm2sDmacr_c, S2mmDmacr_c), Zero_c, ResetBit_c, 200 us,
                         "end of the soft reset");
                    -- Every accepted transaction completed, none started after the reset
                    check_value(Obs.SgRDone, Obs.SgFetch, ERROR, "every descriptor read completed");
                    check_value(Obs.SgBDone, Obs.SgUpdate, ERROR, "every descriptor write answered");
                    check_value(Obs.RBursts, Obs.ArBursts, ERROR, "every read burst completed");
                    check_value(Obs.BResps, Obs.AwBursts, ERROR, "every write burst answered");
                    check_value(Obs.RstBeats, 0, ERROR, "S2MM stream beats taken during the soft reset");
                    check_value(Obs.PeerDone or not IncludeS2mm_g, ERROR, "S2MM stream peer abandoned its packet");
                    PeerBytes <= 0;
                    Ar_v      := Obs.SgFetch + Obs.ArBursts;
                    Aw_v      := Obs.SgUpdate + Obs.AwBursts;
                    wait for 2 us;
                    check_value(Obs.SgFetch + Obs.ArBursts, Ar_v, ERROR, "no read burst after the soft reset");
                    check_value(Obs.SgUpdate + Obs.AwBursts, Aw_v, ERROR, "no write burst after the soft reset");
                    chk(Mm2sDmacr_c, choose(IncludeMm2s_g, DmacrReset_c, Zero_c), "MM2S_DMACR after the soft reset");
                    chk(Mm2sDmasr_c, choose(IncludeMm2s_g, DmasrReset_c or SgIncld_c, Zero_c),
                        "MM2S_DMASR after the soft reset");
                    chk(S2mmDmacr_c, choose(IncludeS2mm_g, DmacrReset_c, Zero_c), "S2MM_DMACR after the soft reset");
                    chk(S2mmDmasr_c, choose(IncludeS2mm_g, DmasrReset_c or SgIncld_c, Zero_c),
                        "S2MM_DMASR after the soft reset");
                end loop;

                -- The core works normally afterwards
                Mem_v.setLatency(MemSg_c, 0);
                Mem_v.setStall(MemSg_c, 0);
                Mem_v.setLatency(MemRd_c, 0);
                Mem_v.setLatency(MemWr_c, 0);
                Mem_v.setStall(MemRd_c, 0);
                Mem_v.setStall(MemWr_c, 0);
                scenario("after/", "sg_reference after the soft reset");

            elsif run("test_sg_multi_buffer") then
                log(ID_LOG_HDR, "TC-CO-18 packets of several buffers");
                scenario("multi/", "sg_multi_buffer");
                if IncludeS2mm_g then
                    -- A packet without bytes from the stream peer (odma_sg interpretation SGI-13)
                    PeerEmpty <= '1';
                    scenario("empty/", "sg_empty");
                    check_value(Obs.PeerDone, ERROR, "the packet without bytes was taken");
                    PeerEmpty <= '0';
                end if;

            elsif run("test_keyhole") then
                log(ID_LOG_HDR, "TC-CO-19 keyhole transfers with FIXED bursts");
                Mem_v.setFifo(MemRd_c, KhWinRd_c, KhBackRd_c);
                Mem_v.setFifo(MemWr_c, KhWinWr_c, KhBackWr_c);
                FixedRd <= std_logic_vector(KhWinRd_c);
                FixedWr <= std_logic_vector(KhWinWr_c);
                scenario("", "keyhole");
                -- MM2S: FIXED bursts in SG mode only (interpretation I1); S2MM in both modes
                if IncludeMm2s_g and IncludeSg_g then
                    check_value(Obs.ArFixed > 0, ERROR, "FIXED read bursts of the MM2S keyhole descriptors");
                else
                    check_value(Obs.ArFixed, 0, ERROR, "no FIXED read burst: MM2S keyhole without function in DR mode");
                end if;
                if IncludeS2mm_g then
                    check_value(Obs.AwFixed > 0, ERROR, "FIXED write bursts of the S2MM keyhole transfers");
                end if;
                check_value(Obs.FixBad, 0, ERROR, "every FIXED burst at most 16 beats at the window word");

            elsif run("test_sg_boundary_rate") then
                log(ID_LOG_HDR, "TC-CO-20 S2MM packets over buffers of 1 KB and 4 KB");

                for lat in 0 to 1 loop
                    Mem_v.setLatency(MemWr_c, 50 * lat);

                    -- Buffers of 1 KB and of 4 KB at multiples of 64 bytes, buffers of 4 KB 1 byte above
                    for b in 0 to 2 loop
                        ObsClear <= not ObsClear;
                        wait for 2 * ClkPeriod_c;
                        if b = 0 then
                            scenario("r1k/", "buffers of 1 KB");
                            Cyc1k_v := Obs.S2Last - Obs.S2First + 1;
                        elsif b = 1 then
                            scenario("r4k/", "buffers of 4 KB");
                            Cyc4k_v := Obs.S2Last - Obs.S2First + 1;
                        else
                            scenario("u4k/", "buffers of 4 KB at unaligned addresses");
                            CycU_v := Obs.S2Last - Obs.S2First + 1;
                        end if;
                        log(ID_SEQUENCER, "TC-CO-20 buffers of " & to_string(4 ** minimum(b, 1)) & " KB" &
                            choose(b = 2, " (unaligned)", "") & ", write response latency " & to_string(50 * lat) &
                            ": " & to_string(Obs.S2Beats) & " beats in " & to_string(Obs.S2Last - Obs.S2First + 1) &
                            " clock cycles");
                        RateBeats_v := Obs.S2Beats;
                    end loop;

                    -- The pause per buffer boundary: the difference of the two runs over the difference of the
                    -- numbers of boundaries inside the packets (2 packets of 16 KB)
                    Len_v := minimum(1024, MaxLen_c);
                    Cnt_v := 2 * ((16384 + Len_v - 1) / Len_v - 1);
                    Len_v := minimum(4096, MaxLen_c);
                    Cnt_v := Cnt_v - 2 * ((16384 + Len_v - 1) / Len_v - 1);
                    if Cnt_v > 0 then
                        log(ID_SEQUENCER, "TC-CO-20 write response latency " & to_string(50 * lat) & ": " &
                            to_string((Cyc1k_v - Cyc4k_v) / Cnt_v) & " clock cycles per buffer boundary, " &
                            to_string(RateBeats_v * 100 / Cyc4k_v) & " beats per 100 clock cycles with 4 KB");
                    end if;
                    log(ID_SEQUENCER, "TC-CO-20 write response latency " & to_string(50 * lat) &
                        ": unaligned buffers of 4 KB take " & to_string((CycU_v - Cyc4k_v) / 32) &
                        " clock cycles more per KB");
                end loop;

                Mem_v.setLatency(MemWr_c, 0);

            elsif run("test_sg_write_overlap") then
                log(ID_LOG_HDR, "TC-CO-21 S2MM write error while the next buffer of the packet is written");
                Mem_v.setError(MemWr_c, 0, ErrWriteBase_c, ErrWriteBase_c + ErrSize_c - 1, "10", TbDirWrite);
                -- The write responses 400 clock cycles late: the second buffer is written before the error arrives
                Mem_v.setLatency(MemWr_c, 400);
                scenario("", "sg_write_overlap");
                Mem_v.setLatency(MemWr_c, 0);
                Mem_v.clearErrors(MemWr_c);

            elsif run("test_sg_ecc_index") then
                log(ID_LOG_HDR, "TC-CO-15 FT buffers 6 to 9 of the Scatter/Gather engine");

                -- One index at a time: the event is counted at the index of the injection only
                for k in 6 to 9 loop
                    softReset;
                    wr(EccCtrl_c, x"00000001");
                    wr(EccStatus_c, x"00000003");
                    wr(EccInject_c, std_logic_vector(to_unsigned(InjInject_c + k, 32)));
                    scenario("", "SG chains through buffer " & to_string(k));

                    for n in 0 to 15 loop
                        rd(EccCount_c + 4 * n, Data_v);
                        Counts_v := n = k and ((n = 6 and IncludeMm2s_g) or (n = 7 and IncludeS2mm_g) or n >= 8);
                        if Counts_v then
                            check_value(Data_v, x"00000001", ERROR, "one SEC event of buffer " & to_string(n),
                                        C_TB_SCOPE_DEFAULT, HEX);
                        else
                            check_value(Data_v, Zero_c, ERROR, "counters of buffer " & to_string(n) &
                                        " after an injection at " & to_string(k), C_TB_SCOPE_DEFAULT, HEX);
                        end if;
                    end loop;

                end loop;

            end if;

        end loop;

        odmaTestEnd(runner);
        wait;
    end process;

end architecture;
