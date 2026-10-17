---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VUnit testbench of odma_registers: the test cases TC-RG-01 to TC-RG-23 of the verification plan.
-- Register offsets and expected values are taken from the specification, not from the register
-- package of the DUT.
--
-- Documentation: hdl/odma_registers/docs/verification_plan.md

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

library work;
    use work.odma_tb_pkg.all;
    use work.odma_registers_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_registers_tb is
    generic (
        runner_cfg    : string;
        AddrWidth_g   : positive := 40;
        LengthWidth_g : positive := 26;
        IncludeMm2s_g : boolean  := true;
        IncludeS2mm_g : boolean  := true;
        ExtRegs_g     : boolean  := true;
        IncludeSg_g   : boolean  := false
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_registers_tb is

    subtype Word_t is std_logic_vector(31 downto 0);

    -- Register offsets of PG021 Table 5 (index: channel) and of the extension window
    constant Dmacr_c         : Nat_a   := (16#000#, 16#030#);
    constant Dmasr_c         : Nat_a   := (16#004#, 16#034#);
    constant AddrLo_c        : Nat_a   := (16#018#, 16#048#);
    constant AddrHi_c        : Nat_a   := (16#01C#, 16#04C#);
    constant Length_c        : Nat_a   := (16#028#, 16#058#);
    constant ExtId_c         : natural := 16#100#;
    constant ExtVersion_c    : natural := 16#104#;
    constant ExtConfig_c     : natural := 16#108#;
    constant ExtMm2sConfig_c : natural := 16#10C#;
    constant ExtS2mmConfig_c : natural := 16#110#;
    constant EccInfo_c       : natural := 16#120#;
    constant EccCtrl_c       : natural := 16#124#;
    constant EccStatus_c     : natural := 16#128#;
    constant EccEnable_c     : natural := 16#12C#;
    constant EccInject_c     : natural := 16#130#;
    constant EccCount_c      : natural := 16#140#;

    -- Fields
    constant Rs_c       : Word_t := x"00000001"; -- DMACR
    constant Reset_c    : Word_t := x"00000004";
    constant IocIrqEn_c : Word_t := x"00001000";
    constant ErrIrqEn_c : Word_t := x"00004000";
    constant Halted_c   : Word_t := x"00000001"; -- DMASR
    constant Idle_c     : Word_t := x"00000002";
    constant IntErr_c   : Word_t := x"00000010";
    constant SlvErr_c   : Word_t := x"00000020";
    constant DecErr_c   : Word_t := x"00000040";
    constant IocIrq_c   : Word_t := x"00001000";
    constant ErrIrq_c   : Word_t := x"00004000";
    constant Ones_c     : Word_t := x"FFFFFFFF";
    constant Zero_c     : Word_t := x"00000000";

    -- Reset values
    constant DmacrReset_c : Word_t := x"00010002";
    constant DmasrReset_c : Word_t := x"00010001";

    -- Error codes of a result
    constant ErrInt_c : std_logic_vector(1 downto 0) := "01";
    constant ErrSlv_c : std_logic_vector(1 downto 0) := "10";
    constant ErrDec_c : std_logic_vector(1 downto 0) := "11";

    type Bool_a is array (0 to 1) of boolean;

    constant Incl_c : Bool_a := (IncludeMm2s_g, IncludeS2mm_g);

    -- Offsets without a register: reserved offsets of Table 5 and a sample of the others
    type Offsets_t is array (natural range <>) of natural;

    constant Reserved_c : Offsets_t := (16#008#, 16#00C#, 16#010#, 16#014#, 16#02C#, 16#038#, 16#03C#, 16#040#,
                                        16#044#);
    constant Unmapped_c : Offsets_t := (16#020#, 16#024#, 16#05C#, 16#060#, 16#0FC#, 16#114#, 16#11C#, 16#134#,
                                        16#13C#, 16#180#, 16#1FC#, 16#200#, 16#3FC#);

    -- Scatter/Gather Mode: register offsets of PG021 Table 4, the offsets of Table 5 without a register
    constant CurLo_c  : Nat_a     := (16#008#, 16#038#);
    constant CurHi_c  : Nat_a     := (16#00C#, 16#03C#);
    constant TailLo_c : Nat_a     := (16#010#, 16#040#);
    constant TailHi_c : Nat_a     := (16#014#, 16#044#);
    constant DrOnly_c : Offsets_t := (16#018#, 16#01C#, 16#020#, 16#024#, 16#028#, 16#02C#, 16#048#, 16#04C#,
                                      16#050#, 16#054#, 16#058#, 16#05C#);

    -- Scatter/Gather Mode: fields and the reset value of DMASR (Halted, SGIncld, IRQThresholdSts 1)
    constant Keyhole_c      : Word_t := x"00000008";
    -- Keyhole of the DR command per channel: MM2S never (interpretation I1), S2MM from DMACR (RG-SG-11)
    constant DrKeyhole_c    : std_logic_vector(0 to 1) := (Mm2s_c => '0', S2mm_c => '1');
    constant CyclicBd_c     : Word_t                   := x"00000010";
    constant DlyIrqEn_c     : Word_t                   := x"00002000";
    constant SgIncld_c      : Word_t                   := x"00000008";
    constant SgIntErr_c     : Word_t                   := x"00000100";
    constant SgSlvErr_c     : Word_t                   := x"00000200";
    constant SgDecErr_c     : Word_t                   := x"00000400";
    constant DlyIrq_c       : Word_t                   := x"00002000";
    constant ThrMask_c      : Word_t                   := x"00FF0000";
    constant DlyMask_c      : Word_t                   := x"FF000000";
    constant DmasrSgReset_c : Word_t                   := x"00010009";
    constant PtrMask_c      : Word_t                   := x"FFFFFFC0";

    -- The tail pointer write that starts the engine (interpretation SGI-01)
    function tailTrigger return Nat_a is
    begin
        if AddrWidth_g > 32 then
            return TailHi_c;
        end if;
        return TailLo_c;
    end function;

    constant TailTrig_c : Nat_a := tailTrigger;

    -- DMACR.IRQThreshold, DMACR.IRQDelay and the status fields at the same positions
    function threshold (n : natural) return Word_t is
        variable W_v : Word_t := (others => '0');
    begin
        W_v(23 downto 16) := std_logic_vector(to_unsigned(n, 8));
        return W_v;
    end function;

    function delay (n : natural) return Word_t is
        variable W_v : Word_t := (others => '0');
    begin
        W_v(31 downto 24) := std_logic_vector(to_unsigned(n, 8));
        return W_v;
    end function;

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

    -- The address of a command: bits at or above AddrWidth_g are 0
    function cmdAddr (
        hi : Word_t;
        lo : Word_t) return std_logic_vector is
        variable A_v : std_logic_vector(63 downto 0) := hi & lo;
    begin

        for i in 0 to 63 loop
            if i >= AddrWidth_g then
                A_v(i) := '0';
            end if;
        end loop;

        return A_v;
    end function;

    -- EXT_CONFIG of the configuration (specification RG-EX-02, architecture section 7)
    function extConfig return Word_t is
        variable W_v : Word_t := (others => '0');
    begin
        W_v(1)            := '1' when IncludeMm2s_g else '0';
        W_v(2)            := '1' when IncludeS2mm_g else '0';
        W_v(3)            := '1' when StsCntrlStrm_c else '0';
        W_v(4)            := '1' when UseRxLength_c else '0';
        W_v(5)            := '1' when MicroDma_c else '0';
        W_v(12 downto 8)  := std_logic_vector(to_unsigned(LengthWidth_g, 5));
        W_v(22 downto 16) := std_logic_vector(to_unsigned(AddrWidth_g, 7));
        return W_v;
    end function;

    -- EXT_MM2S_CONFIG and EXT_S2MM_CONFIG of the harness generics: memory 64 bits, stream 32 bits,
    -- bursts of 16 beats, 64 beats; memory 128 bits, stream 64 bits, bursts of 32 beats, 256 beats
    constant ExtMm2sConfigExp_c : Word_t := x"00040423";
    constant ExtS2mmConfigExp_c : Word_t := x"00100534";

    -- Harness
    signal Clk         : std_logic;
    signal HardRst     : std_logic                     := '0';
    signal Cfg         : ChanCfg_a                     := (others => ChanCfgDefault_c);
    signal Sg          : SgDrive_a                     := (others => SgDriveIdle_c);
    signal EccSec      : std_logic_vector(15 downto 0) := (others => '0');
    signal EccDed      : std_logic_vector(15 downto 0) := (others => '0');
    signal EccSecOnB   : std_logic_vector(15 downto 0) := (others => '0');
    signal EccDedOnB   : std_logic_vector(15 downto 0) := (others => '0');
    signal Obs         : Obs_r;
    signal ChRun       : std_logic_vector(0 to 1);
    signal ChDrain     : std_logic_vector(0 to 1);
    signal ChStopped   : std_logic_vector(0 to 1);
    signal ChIrq       : std_logic_vector(0 to 1);
    signal ChRstOut    : std_logic_vector(0 to 1);
    signal CoreRst     : std_logic;
    signal EccIrq      : std_logic;
    signal EccInjValid : std_logic_vector(15 downto 0);

begin

    test_runner_watchdog(runner, 50 ms);

    i_th : entity work.odma_registers_th
        generic map (
            AddrWidth_g   => AddrWidth_g,
            LengthWidth_g => LengthWidth_g,
            IncludeMm2s_g => IncludeMm2s_g,
            IncludeS2mm_g => IncludeS2mm_g,
            ExtRegs_g     => ExtRegs_g,
            IncludeSg_g   => IncludeSg_g
        )
        port map (
            Clk         => Clk,
            HardRst     => HardRst,
            Cfg         => Cfg,
            Sg          => Sg,
            EccSec      => EccSec,
            EccDed      => EccDed,
            EccSecOnB   => EccSecOnB,
            EccDedOnB   => EccDedOnB,
            Obs         => Obs,
            Run         => ChRun,
            Drain       => ChDrain,
            Stopped     => ChStopped,
            Irq         => ChIrq,
            RstOut      => ChRstOut,
            CoreRst     => CoreRst,
            EccIrq      => EccIrq,
            EccInjValid => EccInjValid
        );

    p_control : process is
        variable Data_v   : Word_t;
        variable Exp_v    : Word_t;
        variable Flag_v   : Word_t;
        variable Cnt_v    : natural;
        variable Set_v    : natural;
        variable Clear_v  : natural;
        variable Other_v  : natural;
        variable Excl_v   : natural;
        variable First_v  : natural;
        variable CmdIdx_v : natural;
        variable Result_v : bitvis_vip_axilite.vvc_cmd_pkg.t_vvc_result;
        variable Sl_v     : std_logic;
        variable Pair_v   : std_logic_vector(0 to 1);

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

        procedure wrStrb (
            ofs  : natural;
            data : Word_t;
            strb : std_logic_vector(3 downto 0)) is
        begin
            axilite_write(AXILITE_VVCT, 0, to_unsigned(ofs, 10), data, strb, "write with strobes " & hex(ofs));
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

        procedure chk (
            ofs : natural;
            exp : Word_t;
            msg : string) is
        begin
            axilite_check(AXILITE_VVCT, 0, to_unsigned(ofs, 10), exp, msg & ": " & hex(ofs));
            await_completion(AXILITE_VVCT, 0, 10 us, "check " & hex(ofs));
        end procedure;

        -- The bits of mask
        procedure chkMask (
            ofs  : natural;
            exp  : Word_t;
            mask : Word_t;
            msg  : string) is
            variable D_v : Word_t;
        begin
            rd(ofs, D_v);
            check_value(D_v and mask, exp and mask, ERROR, msg & ": " & hex(ofs), C_TB_SCOPE_DEFAULT, HEX);
        end procedure;

        -- Reads until the bits of mask have the expected value
        procedure poll (
            ofs  : natural;
            exp  : Word_t;
            mask : Word_t;
            msg  : string) is
            variable D_v : Word_t;
        begin

            for i in 1 to 500 loop
                rd(ofs, D_v);
                exit when (D_v and mask) = (exp and mask);
            end loop;

            check_value(D_v and mask, exp and mask, ERROR, msg & ": " & hex(ofs), C_TB_SCOPE_DEFAULT, HEX);
        end procedure;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        procedure waitCmd (
            ch : natural;
            n  : natural) is
        begin
            if Obs.CmdCount(ch) < n then
                wait until Obs.CmdCount(ch) >= n for 100 us;
            end if;
            check_value(Obs.CmdCount(ch), n, ERROR, "commands of channel " & to_string(ch));
        end procedure;

        procedure waitRes (
            ch : natural;
            n  : natural) is
        begin
            if Obs.ResCount(ch) < n then
                wait until Obs.ResCount(ch) >= n for 100 us;
            end if;
            check_value(Obs.ResCount(ch), n, ERROR, "results of channel " & to_string(ch));
            wait until rising_edge(Clk);
        end procedure;

        -- One SEC (sec true) or DED event on buffer idx in each of n clock cycles
        procedure pulseEcc (
            sec : boolean;
            idx : natural;
            n   : natural) is
        begin
            wait until rising_edge(Clk);
            if sec then
                EccSec(idx) <= '1';
            else
                EccDed(idx) <= '1';
            end if;
            cycles(n);
            EccSec <= (others => '0');
            EccDed <= (others => '0');
            cycles(2);
        end procedure;

        -- Pulses of the Scatter/Gather engine model, one clock cycle each
        procedure sgPkt (ch : natural) is
        begin
            wait until rising_edge(Clk);
            Sg(ch).Pkt <= '1';
            wait until rising_edge(Clk);
            Sg(ch).Pkt <= '0';
        end procedure;

        procedure sgPktStart (ch : natural) is
        begin
            wait until rising_edge(Clk);
            Sg(ch).PktStart <= '1';
            wait until rising_edge(Clk);
            Sg(ch).PktStart <= '0';
        end procedure;

        procedure sgErr (
            ch   : natural;
            xfer : std_logic_vector(1 downto 0);
            eng  : std_logic_vector(1 downto 0)) is
        begin
            wait until rising_edge(Clk);
            Sg(ch).ErrValid <= '1';
            Sg(ch).ErrXfer  <= xfer;
            Sg(ch).ErrSg    <= eng;
            wait until rising_edge(Clk);
            Sg(ch).ErrValid <= '0';
            Sg(ch).ErrXfer  <= "00";
            Sg(ch).ErrSg    <= "00";
        end procedure;

        -- Halt and wait for DMASR.Halted
        procedure sgHalt (ch : natural) is
        begin
            wr(Dmacr_c(ch), Zero_c);
            poll(Dmasr_c(ch), Halted_c, Halted_c, "halted");
        end procedure;

        -- Every register at its reset value
        procedure checkResetValues (msg : string) is
        begin

            for ch in 0 to 1 loop
                if Incl_c(ch) then
                    chk(Dmacr_c(ch), DmacrReset_c, msg);
                    chk(Dmasr_c(ch), DmasrReset_c, msg);
                else
                    chk(Dmacr_c(ch), Zero_c, msg);
                    chk(Dmasr_c(ch), Zero_c, msg);
                end if;
                chk(AddrLo_c(ch), Zero_c, msg);
                chk(AddrHi_c(ch), Zero_c, msg);
                chk(Length_c(ch), Zero_c, msg);
            end loop;

            if ExtRegs_g then
                chk(ExtId_c, x"4F444D41", msg);
                chk(ExtVersion_c, x"00000100", msg);
                chk(ExtConfig_c, extConfig, msg);
                chk(ExtMm2sConfig_c, ExtMm2sConfigExp_c, msg);
                chk(ExtS2mmConfig_c, ExtS2mmConfigExp_c, msg);
                chk(EccInfo_c, x"00001010", msg);
                chk(EccCtrl_c, Zero_c, msg);
                chk(EccStatus_c, Zero_c, msg);
                chk(EccEnable_c, Zero_c, msg);
                chk(EccInject_c, Zero_c, msg);

                for n in 0 to 15 loop
                    chk(EccCount_c + 4 * n, Zero_c, msg);
                end loop;

            end if;
        end procedure;

        -- Soft reset through DMACR.Reset of channel ch, until DMACR.Reset reads 0
        procedure softReset (ch : natural) is
        begin
            wr(Dmacr_c(ch), Reset_c);
            poll(Dmacr_c(ch), Zero_c, Reset_c, "end of the soft reset");
        end procedure;

        -- Registers away from their reset values, a transfer in progress on each channel
        procedure prepareReset is
        begin

            for ch in 0 to 1 loop
                if Incl_c(ch) then
                    Cfg(ch).ResDelay  <= 2000;
                    Cfg(ch).DrainTime <= 100;
                    wr(Dmacr_c(ch), Rs_c or IocIrqEn_c or x"03000000");
                    wr(AddrLo_c(ch), x"12345678");
                    wr(AddrHi_c(ch), x"00000001");
                    wr(Length_c(ch), x"00000040");
                    waitCmd(ch, Obs.CmdCount(ch) + 1);
                end if;
            end loop;

            if ExtRegs_g then
                wr(EccEnable_c, x"00000003");
            end if;
        end procedure;

    -- Comment for the style checker: subprograms above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);
        wait for 20 * ClkPeriod_c;
        wait until rising_edge(Clk);

        -- The first included channel and, in a configuration with one channel, the excluded one
        First_v := Mm2s_c when IncludeMm2s_g else S2mm_c;
        Excl_v  := S2mm_c when IncludeMm2s_g else Mm2s_c;

        while test_suite loop

            if run("test_reset_values") then
                log(ID_LOG_HDR, "TC-RG-01 reset values, reserved and unmapped offsets, bit order");
                checkResetValues("reset value");

                for i in Reserved_c'range loop
                    chk(Reserved_c(i), Zero_c, "reserved offset");
                end loop;

                for i in Unmapped_c'range loop
                    chk(Unmapped_c(i), Zero_c, "unmapped offset");
                end loop;

                -- Address bits 1 and 0 are ignored, bit n of a register is bit n of the data word
                wr(AddrLo_c(First_v) + 3, x"A5C30F01");
                chk(AddrLo_c(First_v), x"A5C30F01", "bit order");
                chk(AddrLo_c(First_v) + 1, x"A5C30F01", "address bits 1 and 0");
                chk(AddrLo_c(First_v) + 2, x"A5C30F01", "address bits 1 and 0");
                -- Read latency (architecture section 9)
                check_value(Obs.RValidCycle - Obs.ArCycle, 3, ERROR, "RValid 3 clock cycles after the AR handshake");

            elsif run("test_access") then
                log(ID_LOG_HDR, "TC-RG-02 access types, strobes, unmapped offsets, stored DR-mode fields");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        -- DMACR: read/write fields, reserved bits, IRQThreshold ignores 0
                        wr(Dmacr_c(ch), x"FFFFFFF8");
                        chk(Dmacr_c(ch), x"FFFF701A", "DMACR read/write fields");
                        chk(Dmasr_c(ch), x"00FF0001", "DMASR.IRQThresholdSts follows DMACR.IRQThreshold");
                        wr(Dmacr_c(ch), Zero_c);
                        chk(Dmacr_c(ch), x"00FF0002", "DMACR.IRQThreshold ignores 0");
                        wr(Dmacr_c(ch), x"00050000");
                        chk(Dmacr_c(ch), x"00050002", "DMACR.IRQThreshold");
                        -- DMASR: read-only fields and reserved bits ignore writes
                        wr(Dmasr_c(ch), Ones_c);
                        chk(Dmasr_c(ch), x"00050001", "DMASR ignores writes");
                        -- Address and length registers
                        wr(AddrLo_c(ch), Ones_c);
                        chk(AddrLo_c(ch), Ones_c, "address bits 31 to 0");
                        wr(AddrHi_c(ch), Ones_c);
                        chk(AddrHi_c(ch), lowOnes(AddrWidth_g - 32), "address bits 63 to 32");
                        wr(Length_c(ch), Ones_c);
                        chk(Length_c(ch), lowOnes(LengthWidth_g), "length");
                        -- All 32 bits of a write are taken, independent of the strobes
                        wrStrb(AddrLo_c(ch), x"12345678", "0001");
                        chk(AddrLo_c(ch), x"12345678", "write with one strobe");
                        wrStrb(AddrLo_c(ch), x"9ABCDEF0", "0000");
                        chk(AddrLo_c(ch), x"9ABCDEF0", "write without strobes");
                    end if;
                end loop;

                -- Writes to offsets without a register have no effect
                for i in Reserved_c'range loop
                    wr(Reserved_c(i), Ones_c);
                    chk(Reserved_c(i), Zero_c, "reserved offset after a write");
                end loop;

                for i in Unmapped_c'range loop
                    wr(Unmapped_c(i), Ones_c);
                    chk(Unmapped_c(i), Zero_c, "unmapped offset after a write");
                end loop;

                chk(AddrLo_c(First_v), x"9ABCDEF0", "register after writes to unmapped offsets");
                chk(Dmacr_c(First_v), x"00050002", "register after writes to unmapped offsets");

                -- Extension window: read-only registers ignore writes, ECC_ENABLE is read/write
                if ExtRegs_g then
                    wr(ExtId_c, Zero_c);
                    wr(ExtVersion_c, Ones_c);
                    wr(ExtConfig_c, Ones_c);
                    wr(ExtMm2sConfig_c, Ones_c);
                    wr(ExtS2mmConfig_c, Zero_c);
                    wr(EccInfo_c, Ones_c);
                    chk(ExtId_c, x"4F444D41", "EXT_ID ignores writes");
                    chk(ExtVersion_c, x"00000100", "EXT_VERSION ignores writes");
                    chk(ExtConfig_c, extConfig, "EXT_CONFIG ignores writes");
                    chk(ExtMm2sConfig_c, ExtMm2sConfigExp_c, "EXT_MM2S_CONFIG ignores writes");
                    chk(ExtS2mmConfig_c, ExtS2mmConfigExp_c, "EXT_S2MM_CONFIG ignores writes");
                    chk(EccInfo_c, x"00001010", "ECC_INFO ignores writes");
                    wr(EccEnable_c, Ones_c);
                    chk(EccEnable_c, x"00000003", "ECC_ENABLE");
                    wr(EccEnable_c, x"FFFFFFFC");
                    chk(EccEnable_c, Zero_c, "ECC_ENABLE");
                    wr(EccCtrl_c, Ones_c);
                    chk(EccCtrl_c, Zero_c, "ECC_CTRL reads 0");
                    wr(EccInject_c, x"0000010F");
                    chk(EccInject_c, Zero_c, "ECC_INJECT reads 0");
                end if;

                -- The stored DR-mode fields have no function: CyclicBD, Dly_IrqEn, IRQDelay and the MM2S
                -- keyhole (interpretation I1); the S2MM keyhole goes with the command (RG-SG-11, TC-RG-24)
                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        wr(Dmacr_c(ch), x"FF002019");
                        chk(Dmacr_c(ch), x"FF05201B", "DMACR with the stored fields");
                        wr(Length_c(ch), x"00000010");
                        waitRes(ch, 1);
                        check_value(Obs.CmdKeyhole(ch), DrKeyhole_c(ch), ERROR,
                                    "command keyhole (MM2S without function in DR mode)");
                        chkMask(Dmasr_c(ch), IocIrq_c, x"00003000", "IOC_Irq set, Dly_Irq 0");
                        cycles(4);
                        check_value(ChIrq(ch), '0', ERROR, "no interrupt from Dly_IrqEn");
                    end if;
                end loop;

            elsif run("test_dr_keyhole") then
                log(ID_LOG_HDR, "TC-RG-24 keyhole in Direct Register Mode");
                -- The command waits 100 clock cycles for Cmd_Ready, so that a DMACR write after the length
                -- write meets the pending command
                Cfg(Mm2s_c).CmdDelay <= 100;
                Cfg(S2mm_c).CmdDelay <= 100;

                for ch in 0 to 1 loop
                    -- Keyhole set at the length write, cleared while the command waits: the command keeps it
                    wr(Dmacr_c(ch), Rs_c or Keyhole_c);
                    wr(Length_c(ch), x"00000020");
                    wr(Dmacr_c(ch), Rs_c);
                    waitCmd(ch, 1);
                    check_value(Obs.CmdKeyhole(ch), DrKeyhole_c(ch), ERROR,
                                "keyhole at the length write (MM2S never, interpretation I1)");
                    waitRes(ch, 1);
                    -- Keyhole cleared at the length write, set while the command waits: the command has none
                    wr(Length_c(ch), x"00000020");
                    wr(Dmacr_c(ch), Rs_c or Keyhole_c);
                    waitCmd(ch, 2);
                    check_value(Obs.CmdKeyhole(ch), '0', ERROR, "no keyhole at the length write");
                    waitRes(ch, 2);
                    -- The next transfer takes the keyhole again
                    wr(Length_c(ch), x"00000020");
                    waitCmd(ch, 3);
                    check_value(Obs.CmdKeyhole(ch), DrKeyhole_c(ch), ERROR,
                                "keyhole of the next transfer");
                    waitRes(ch, 3);
                end loop;

            elsif run("test_start_halt") then
                log(ID_LOG_HDR, "TC-RG-03 start and halt");

                for ch in 0 to 1 loop
                    Other_v := 1 - ch;
                    -- Start
                    wr(Dmacr_c(ch), Rs_c);
                    chkMask(Dmasr_c(ch), Zero_c, Halted_c or Idle_c, "started: Halted 0, Idle 0");
                    chkMask(Dmacr_c(ch), Rs_c, Rs_c, "DMACR.RS after the start");
                    check_value(ChRun(ch), '1', ERROR, "Run after the start");
                    check_value(ChRun(Other_v), '0', ERROR, "the other channel stays halted");
                    chkMask(Dmasr_c(Other_v), Halted_c, Halted_c, "the other channel stays halted");
                    -- Halt without drain time
                    wr(Dmacr_c(ch), Zero_c);
                    check_value(ChRun(ch), '0', ERROR, "Run after the halt");
                    chkMask(Dmasr_c(ch), Halted_c, Halted_c or Idle_c, "halted");
                    -- Halt with 50 clock cycles until Stopped; RS = 1 while stopping has no effect
                    Cfg(ch).DrainTime <= 50;
                    wr(Dmacr_c(ch), Rs_c);
                    wr(Dmacr_c(ch), Zero_c);
                    wr(Dmacr_c(ch), Rs_c);
                    chkMask(Dmacr_c(ch), Zero_c, Rs_c, "RS = 1 while stopping");
                    chkMask(Dmasr_c(ch), Zero_c, Halted_c or Idle_c, "Halted waits for Stopped");
                    check_value(ChStopped(ch), '0', ERROR, "the channel model is still stopping");
                    cycles(60);
                    chkMask(Dmasr_c(ch), Halted_c, Halted_c or Idle_c, "halted after Stopped");
                    check_value(ChRun(ch), '0', ERROR, "no restart after stopping");
                    check_value(Obs.CmdCount(ch), 0, ERROR, "no command");
                    Cfg(ch).DrainTime <= 0;
                end loop;

                -- Both channels running, one halts
                wr(Dmacr_c(Mm2s_c), Rs_c);
                wr(Dmacr_c(S2mm_c), Rs_c);
                wr(Dmacr_c(Mm2s_c), Zero_c);
                chkMask(Dmasr_c(Mm2s_c), Halted_c, Halted_c, "MM2S halted");
                chkMask(Dmasr_c(S2mm_c), Zero_c, Halted_c, "S2MM still running");
                check_value(ChRun, "01", ERROR, "Run of both channels");
                wr(Dmacr_c(S2mm_c), Zero_c);
                chkMask(Dmasr_c(S2mm_c), Halted_c, Halted_c, "S2MM halted");

            elsif run("test_mm2s_transfer") then
                log(ID_LOG_HDR, "TC-RG-04 MM2S transfer");
                wr(Dmacr_c(Mm2s_c), Rs_c);
                -- The command waits 100 clock cycles; an address written meanwhile does not change it
                Cfg(Mm2s_c).CmdDelay <= 100;
                Cfg(Mm2s_c).ResDelay <= 50;
                wr(AddrLo_c(Mm2s_c), x"89ABCDEF");
                wr(AddrHi_c(Mm2s_c), x"00000012");
                wr(Length_c(Mm2s_c), x"000003E8");
                wr(AddrLo_c(Mm2s_c), x"00000000");
                wr(AddrHi_c(Mm2s_c), x"00000000");
                chkMask(Dmasr_c(Mm2s_c), Zero_c, Halted_c or Idle_c, "busy");
                waitCmd(Mm2s_c, 1);
                check_value(Obs.CmdAddr(Mm2s_c), cmdAddr(x"00000012", x"89ABCDEF"), ERROR, "command address");
                check_value(Obs.CmdLength(Mm2s_c), 1000, ERROR, "command length");
                check_value(std_logic_vector'(Obs.CmdSof & Obs.CmdEof & Obs.CmdKeyhole(Mm2s_c)), "110", ERROR, "Sof, Eof, Keyhole");
                chkMask(Dmasr_c(Mm2s_c), Zero_c, Halted_c or Idle_c or IocIrq_c, "busy until the result");
                waitRes(Mm2s_c, 1);
                chkMask(Dmasr_c(Mm2s_c), Idle_c or IocIrq_c, Halted_c or Idle_c or IocIrq_c, "completed");
                cycles(4);
                check_value(ChIrq(Mm2s_c), '0', ERROR, "no interrupt without IOC_IrqEn");
                wr(Dmacr_c(Mm2s_c), Rs_c or IocIrqEn_c);
                cycles(2);
                check_value(ChIrq(Mm2s_c), '1', ERROR, "interrupt with IOC_IrqEn");
                wr(Dmasr_c(Mm2s_c), IocIrq_c);
                chkMask(Dmasr_c(Mm2s_c), Zero_c, IocIrq_c, "IOC_Irq cleared");
                check_value(ChIrq(Mm2s_c), '0', ERROR, "interrupt cleared");

                -- Three transfers in a row with the address registers of their length write
                Cfg(Mm2s_c).CmdDelay <= 0;
                Cfg(Mm2s_c).ResDelay <= 5;

                for i in 1 to 3 loop
                    Data_v := x"00000001" when i = 1 else
                              x"00001000" when i = 2 else
                              lowOnes(LengthWidth_g);
                    Exp_v  := std_logic_vector(to_unsigned(i * 16#10000# + i, 32));
                    wr(AddrLo_c(Mm2s_c), Exp_v);
                    wr(Length_c(Mm2s_c), Data_v);
                    waitRes(Mm2s_c, 1 + i);
                    check_value(Obs.CmdAddr(Mm2s_c), cmdAddr(Zero_c, Exp_v), ERROR, "command address");
                    check_value(Obs.CmdLength(Mm2s_c), to_integer(unsigned(Data_v)), ERROR, "command length");
                    chkMask(Dmasr_c(Mm2s_c), Idle_c or IocIrq_c, Halted_c or Idle_c or IocIrq_c, "completed");
                    check_value(ChIrq(Mm2s_c), '1', ERROR, "interrupt");
                    wr(Dmasr_c(Mm2s_c), IocIrq_c);
                    chkMask(Dmasr_c(Mm2s_c), Idle_c, Idle_c or IocIrq_c, "IOC_Irq cleared, still idle");
                end loop;

                check_value(Obs.CmdCount(Mm2s_c), 4, ERROR, "one command per transfer");

            elsif run("test_s2mm_transfer") then
                log(ID_LOG_HDR, "TC-RG-05 S2MM transfer");
                wr(Dmacr_c(S2mm_c), Rs_c or IocIrqEn_c);
                Cfg(S2mm_c).ResDelay <= 30;
                Cfg(S2mm_c).ResBytes <= 29;
                wr(AddrLo_c(S2mm_c), x"00001000");
                wr(AddrHi_c(S2mm_c), x"000000AB");
                wr(Length_c(S2mm_c), x"00001000");
                waitCmd(S2mm_c, 1);
                check_value(Obs.CmdAddr(S2mm_c), cmdAddr(x"000000AB", x"00001000"), ERROR, "command address");
                check_value(Obs.CmdLength(S2mm_c), 4096, ERROR, "buffer length");
                check_value(Obs.CmdKeyhole(S2mm_c), '0', ERROR, "command without keyhole");
                chkMask(Dmasr_c(S2mm_c), Zero_c, Halted_c or Idle_c, "busy");
                chk(Length_c(S2mm_c), x"00001000", "buffer length while busy");
                waitRes(S2mm_c, 1);
                chk(Length_c(S2mm_c), x"0000001D", "bytes received");
                chkMask(Dmasr_c(S2mm_c), Idle_c or IocIrq_c, Halted_c or Idle_c or IocIrq_c, "completed");
                check_value(ChIrq(S2mm_c), '1', ERROR, "interrupt");
                wr(Dmasr_c(S2mm_c), IocIrq_c);
                cycles(2);
                check_value(ChIrq(S2mm_c), '0', ERROR, "interrupt cleared");

            elsif run("test_length_rules") then
                log(ID_LOG_HDR, "TC-RG-06 length writes: zero, busy, halted");

                for ch in 0 to 1 loop
                    -- Halted: stored and read back, no command, also not after the start
                    wr(Length_c(ch), x"00000064");
                    chk(Length_c(ch), x"00000064", "length written while halted");
                    wr(Dmacr_c(ch), Rs_c);
                    cycles(20);
                    check_value(Obs.CmdCount(ch), 0, ERROR, "no command for the length written while halted");
                    chkMask(Dmasr_c(ch), Zero_c, Halted_c or Idle_c, "started, no transfer");
                    -- A length of 0 has no effect
                    wr(Length_c(ch), Zero_c);
                    chk(Length_c(ch), x"00000064", "a length of 0 is not stored");
                    cycles(20);
                    check_value(Obs.CmdCount(ch), 0, ERROR, "no command for a length of 0");
                    -- A length written while busy has no effect
                    Cfg(ch).ResDelay <= 100;
                    wr(Length_c(ch), x"000000C8");
                    waitCmd(ch, 1);
                    wr(Length_c(ch), x"0000012C");
                    chk(Length_c(ch), x"000000C8", "length written while busy");
                    waitRes(ch, 1);
                    cycles(20);
                    check_value(Obs.CmdCount(ch), 1, ERROR, "no command for the length written while busy");
                    chk(Length_c(ch), x"000000C8", "length after the transfer");
                    wr(Dmacr_c(ch), Zero_c);
                end loop;

            elsif run("test_halt_during_transfer") then
                log(ID_LOG_HDR, "TC-RG-07 halt during a transfer");
                -- MM2S: the transfer in progress completes with the end of packet
                wr(Dmacr_c(Mm2s_c), Rs_c or IocIrqEn_c);
                Cfg(Mm2s_c).ResDelay <= 100;
                wr(Length_c(Mm2s_c), x"00000040");
                waitCmd(Mm2s_c, 1);
                wr(Dmacr_c(Mm2s_c), IocIrqEn_c);
                check_value(ChRun(Mm2s_c), '0', ERROR, "Run falls with the halt request");
                chkMask(Dmasr_c(Mm2s_c), Zero_c, Halted_c, "not halted before the result");
                waitRes(Mm2s_c, 1);
                poll(Dmasr_c(Mm2s_c), Halted_c, Halted_c, "halted after the result");
                chkMask(Dmasr_c(Mm2s_c), Halted_c or IocIrq_c, Halted_c or Idle_c or IocIrq_c, "IOC_Irq");
                check_value(ChIrq(Mm2s_c), '1', ERROR, "interrupt");
                wr(Length_c(Mm2s_c), x"00000040");
                cycles(20);
                check_value(Obs.CmdCount(Mm2s_c), 1, ERROR, "no command after the halt");
                wr(Dmasr_c(Mm2s_c), IocIrq_c);

                -- MM2S: a halt request before the command is accepted; Run stays high until the handshake
                Cfg(Mm2s_c).CmdDelay <= 40;
                Cfg(Mm2s_c).ResDelay <= 10;
                wr(Dmacr_c(Mm2s_c), Rs_c or IocIrqEn_c);
                wr(Length_c(Mm2s_c), x"00000040");
                wr(Dmacr_c(Mm2s_c), IocIrqEn_c);
                check_value(Obs.CmdCount(Mm2s_c), 1, ERROR, "command not yet accepted");
                check_value(ChRun(Mm2s_c), '1', ERROR, "Run until the command is accepted");
                waitCmd(Mm2s_c, 2);
                cycles(2);
                check_value(ChRun(Mm2s_c), '0', ERROR, "Run after the command handshake");
                waitRes(Mm2s_c, 2);
                poll(Dmasr_c(Mm2s_c), Halted_c, Halted_c, "halted");

                -- S2MM: the result without the end of packet raises no IOC_Irq and keeps the length
                wr(Dmacr_c(S2mm_c), Rs_c or IocIrqEn_c);
                Cfg(S2mm_c).ResDelay <= 100;
                Cfg(S2mm_c).ResBytes <= 128;
                Cfg(S2mm_c).ResEof   <= '0';
                wr(Length_c(S2mm_c), x"00001000");
                waitCmd(S2mm_c, 1);
                wr(Dmacr_c(S2mm_c), IocIrqEn_c);
                waitRes(S2mm_c, 1);
                poll(Dmasr_c(S2mm_c), Halted_c, Halted_c, "halted after the result");
                chkMask(Dmasr_c(S2mm_c), Halted_c, Halted_c or Idle_c or IocIrq_c, "no IOC_Irq");
                chk(Length_c(S2mm_c), x"00001000", "length kept");
                check_value(ChIrq(S2mm_c), '0', ERROR, "no interrupt");

            elsif run("test_errors") then
                log(ID_LOG_HDR, "TC-RG-08 error results");

                for ch in 0 to 1 loop

                    for e in 1 to 3 loop
                        -- MM2S: slave and decode error; S2MM: internal, slave and decode error
                        next when ch = Mm2s_c and e = 1;
                        Cnt_v          := Obs.ResCount(ch);
                        Cfg(ch).ResErr <= std_logic_vector(to_unsigned(e, 2));
                        Flag_v         := IntErr_c when e = 1 else
                                          SlvErr_c when e = 2 else
                                          DecErr_c;
                        if ch = S2mm_c then
                            Flag_v := Flag_v or IntErr_c;
                        end if;
                        -- The S2MM internal error runs without Err_IrqEn
                        Exp_v := Zero_c when ch = S2mm_c and e = 1 else ErrIrqEn_c;
                        wr(Dmacr_c(ch), Rs_c or Exp_v);
                        wr(Length_c(ch), x"00000020");
                        waitRes(ch, Cnt_v + 1);
                        poll(Dmasr_c(ch), Halted_c, Halted_c, "halted after the error");
                        chkMask(Dmasr_c(ch), Flag_v or ErrIrq_c or Halted_c, x"00005071", "error flags, Err_Irq");
                        chkMask(Dmacr_c(ch), Zero_c, Rs_c, "RS cleared by the error");
                        cycles(2);
                        Sl_v  := '1' when Exp_v = ErrIrqEn_c else '0';
                        check_value(ChIrq(ch), Sl_v, ERROR, "interrupt");
                        -- The start is refused while an error flag is set
                        wr(Dmacr_c(ch), Rs_c or Exp_v);
                        chkMask(Dmacr_c(ch), Zero_c, Rs_c, "start refused");
                        chkMask(Dmasr_c(ch), Halted_c, Halted_c, "still halted");
                        check_value(ChRun(ch), '0', ERROR, "no Run after the refused start");
                        -- Ones written to the error flags do not clear them, Err_Irq is write-one-to-clear
                        wr(Dmasr_c(ch), x"00000070");
                        chkMask(Dmasr_c(ch), Flag_v, x"00000070", "error flags are read-only");
                        wr(Dmasr_c(ch), ErrIrq_c);
                        chkMask(Dmasr_c(ch), Flag_v, Flag_v or ErrIrq_c, "Err_Irq cleared, flags kept");
                        cycles(2);
                        check_value(ChIrq(ch), '0', ERROR, "interrupt cleared");
                        -- A soft reset clears the flags
                        Cfg(ch).ResErr <= "00";
                        softReset(ch);
                        chk(Dmasr_c(ch), DmasrReset_c, "error flags after the soft reset");
                    end loop;

                end loop;

            elsif run("test_irq_clear_race") then
                log(ID_LOG_HDR, "TC-RG-09 IOC_Irq cleared in the clock cycles around a result");

                for ch in 0 to 1 loop
                    Set_v   := 0;
                    Clear_v := 0;
                    wr(Dmacr_c(ch), Rs_c or IocIrqEn_c);

                    for j in 1 to 9 loop
                        -- A completed transfer sets IOC_Irq
                        Cfg(ch).ResDelay <= 2;
                        wr(Length_c(ch), x"00000010");
                        waitRes(ch, 2 * j - 1);
                        chkMask(Dmasr_c(ch), IocIrq_c, IocIrq_c, "IOC_Irq set");
                        -- The next result follows the AW handshake of the clearing write by j clock cycles
                        Cfg(ch).ResDelay   <= -1;
                        Cfg(ch).ResAfterAw <= j;
                        wr(Length_c(ch), x"00000010");
                        waitCmd(ch, 2 * j);
                        wr(Dmasr_c(ch), IocIrq_c);
                        check_value(Obs.BValidCycle - Obs.AwCycle, 2, ERROR, "BValid 2 clock cycles after the AW handshake");
                        waitRes(ch, 2 * j);
                        -- The write takes effect at the end of the clock cycle in which BValid rises: a result
                        -- in that clock cycle or later sets the flag again
                        if Obs.ResCycle(ch) >= Obs.BValidCycle then
                            Exp_v := IocIrq_c;
                            Set_v := Set_v + 1;
                        else
                            Exp_v   := Zero_c;
                            Clear_v := Clear_v + 1;
                        end if;
                        chkMask(Dmasr_c(ch), Exp_v, IocIrq_c, "IOC_Irq after result " & to_string(j));
                        wr(Dmasr_c(ch), IocIrq_c);
                    end loop;

                    check_value(Set_v > 0 and Clear_v > 0, ERROR, "results before and after the clear");
                    Cfg(ch).ResDelay <= ChanCfgDefault_c.ResDelay;
                    wr(Dmacr_c(ch), Zero_c);
                end loop;

            elsif run("test_soft_reset") then
                log(ID_LOG_HDR, "TC-RG-10 soft reset");

                for c in 0 to 1 loop
                    prepareReset;
                    Cnt_v := Obs.ResCount(0) + Obs.ResCount(1);
                    if c = S2mm_c then
                        Cfg(Mm2s_c).DrainTime <= 0;
                        Cfg(S2mm_c).DrainTime <= 0;
                    end if;
                    -- DMACR.Reset of channel c: the other bits are not taken; both Reset bits, drain, reset outputs
                    wr(Dmacr_c(c), Reset_c or ErrIrqEn_c);
                    if c = Mm2s_c then
                        chkMask(Dmacr_c(Mm2s_c), Reset_c or Rs_c or IocIrqEn_c, Reset_c or Rs_c or IocIrqEn_c or ErrIrqEn_c,
                                "MM2S_DMACR.Reset, the other bits of the write not taken");
                        chkMask(Dmacr_c(S2mm_c), Reset_c, Reset_c, "S2MM_DMACR.Reset");
                        check_value(ChDrain, "11", ERROR, "drain request");
                        check_value(ChRstOut, "11", ERROR, "reset outputs");
                        check_value(CoreRst, '0', ERROR, "no core reset before the channels stopped");
                        -- Writes during the soft reset have no effect
                        wr(AddrLo_c(Mm2s_c), Ones_c);
                        wr(EccEnable_c, Zero_c);
                        chk(AddrLo_c(Mm2s_c), x"12345678", "write during the soft reset");
                        chk(EccEnable_c, x"00000003", "write during the soft reset");
                    end if;
                    poll(Dmacr_c(c), Zero_c, Reset_c, "end of the soft reset");
                    check_value(Obs.CoreRstEarly, 0, ERROR, "core reset only after both channels stopped");
                    check_value(Obs.CoreRstCycle - Obs.DrainCycle >= Cfg(Mm2s_c).DrainTime, ERROR,
                                "core reset after the drain time");
                    check_value(Obs.RstOutLen >= Obs.CoreRstCycle - Obs.DrainCycle + 16, ERROR,
                                "reset outputs for the drain and at least 16 clock cycles of reset");
                    check_value(std_logic_vector'(ChDrain & ChRstOut & CoreRst), "00000", ERROR, "outputs after the soft reset");
                    check_value(Obs.ResCount(0) + Obs.ResCount(1), Cnt_v, ERROR, "no result of the drained transfers");
                    checkResetValues("after the soft reset");
                end loop;

            elsif run("test_hard_reset") then
                log(ID_LOG_HDR, "TC-RG-11 hard reset during transfers");
                prepareReset;
                wait until rising_edge(Clk);
                HardRst <= '1';

                for i in 1 to 5 loop
                    wait until rising_edge(Clk);
                    check_value(std_logic_vector'(ChRstOut & CoreRst), "111", ERROR, "reset outputs and core reset during Rst");
                end loop;

                HardRst <= '0';
                cycles(2);
                check_value(std_logic_vector'(ChRstOut & CoreRst & ChRun & ChDrain), "0000000", ERROR, "outputs after Rst");
                checkResetValues("after Rst");

            elsif run("test_excluded_channel") then
                log(ID_LOG_HDR, "TC-RG-12 channel not included");
                Other_v := 1 - Excl_v;
                -- The registers of the excluded channel read 0 and ignore writes
                wr(Dmacr_c(Excl_v), Rs_c or IocIrqEn_c);
                wr(AddrLo_c(Excl_v), Ones_c);
                wr(AddrHi_c(Excl_v), Ones_c);
                wr(Length_c(Excl_v), Ones_c);
                wr(Dmasr_c(Excl_v), Ones_c);
                chk(Dmacr_c(Excl_v), Zero_c, "DMACR of the excluded channel");
                chk(Dmasr_c(Excl_v), Zero_c, "DMASR of the excluded channel");
                chk(AddrLo_c(Excl_v), Zero_c, "address of the excluded channel");
                chk(AddrHi_c(Excl_v), Zero_c, "address of the excluded channel");
                chk(Length_c(Excl_v), Zero_c, "length of the excluded channel");
                cycles(20);
                check_value(std_logic_vector'(ChRun(Excl_v) & ChDrain(Excl_v) & ChIrq(Excl_v)), "000", ERROR, "outputs of the excluded channel");
                check_value(Obs.CmdCount(Excl_v), 0, ERROR, "no command of the excluded channel");
                -- DMACR.Reset of the excluded channel starts no soft reset
                wr(Dmacr_c(Excl_v), Reset_c);
                chkMask(Dmacr_c(Other_v), Zero_c, Reset_c, "no soft reset");
                check_value(ChDrain(Other_v), '0', ERROR, "no drain");
                -- The included channel works
                wr(Dmacr_c(Other_v), Rs_c or IocIrqEn_c);
                wr(Length_c(Other_v), x"00000040");
                waitRes(Other_v, 1);
                chkMask(Dmasr_c(Other_v), Idle_c or IocIrq_c, Halted_c or Idle_c or IocIrq_c, "completed");
                Pair_v := "10" when Other_v = Mm2s_c else "01";
                check_value(ChIrq, Pair_v, ERROR, "interrupts");
                -- A soft reset drains the included channel only
                wr(Dmacr_c(Other_v), Reset_c);
                check_value(ChDrain, Pair_v, ERROR, "drain requests");
                poll(Dmacr_c(Other_v), Zero_c, Reset_c, "end of the soft reset");
                -- The FT buffers of the excluded channel count nothing and take no injection
                if ExtRegs_g then

                    for i in 0 to 5 loop
                        pulseEcc(true, i, 1);
                    end loop;

                    Exp_v := x"00000001" when IncludeMm2s_g else Zero_c;
                    chk(EccCount_c, Exp_v, "buffer 0");
                    chk(EccCount_c + 20, Exp_v, "buffer 5");
                    Exp_v := x"00000001" when IncludeS2mm_g else Zero_c;
                    chk(EccCount_c + 12, Exp_v, "buffer 3");
                    -- Buffer 0 of MM2S or buffer 3 of S2MM
                    Exp_v := x"00000200" when Excl_v = Mm2s_c else x"00000203";
                    wr(EccInject_c, Exp_v);
                    cycles(4);
                    check_value(Obs.InjCount, 0, ERROR, "no injection into a buffer of the excluded channel");
                end if;

            elsif run("test_ecc") then
                log(ID_LOG_HDR, "TC-RG-13 ECC counters, flags, Ecc_Irq and error injection");
                check_value(Obs.InjMode, '0', ERROR, "injection mode after the reset");
                -- Events of the buffers of the configuration are counted, the other indices count nothing
                pulseEcc(true, 0, 3);
                pulseEcc(false, 0, 1);
                pulseEcc(true, 3, 2);
                pulseEcc(false, 3, 2);
                pulseEcc(true, 1, 1);
                pulseEcc(false, 2, 1);
                pulseEcc(true, 4, 2);
                pulseEcc(false, 5, 3);
                pulseEcc(true, 15, 4);
                pulseEcc(false, 15, 4);
                pulseEcc(true, 6, 1);
                chk(EccCount_c, x"00010003", "buffer 0");
                chk(EccCount_c + 4, x"00000001", "buffer 1");
                chk(EccCount_c + 8, x"00010000", "buffer 2");
                chk(EccCount_c + 12, x"00020002", "buffer 3");
                chk(EccCount_c + 16, x"00000002", "buffer 4");
                chk(EccCount_c + 20, x"00030000", "buffer 5");
                chk(EccCount_c + 24, Zero_c, "index 6 without a buffer");
                chk(EccCount_c + 60, Zero_c, "index 15 without a buffer");
                -- ECC_STATUS and Ecc_Irq with and without the enables
                chk(EccStatus_c, x"00000003", "ECC_STATUS");
                check_value(EccIrq, '0', ERROR, "no Ecc_Irq without enable");
                wr(EccEnable_c, x"00000001");
                cycles(2);
                check_value(EccIrq, '1', ERROR, "Ecc_Irq from Sec");
                wr(EccStatus_c, x"00000001");
                chk(EccStatus_c, x"00000002", "ECC_STATUS.Sec cleared");
                cycles(2);
                check_value(EccIrq, '0', ERROR, "Ecc_Irq with Ded not enabled");
                wr(EccEnable_c, x"00000002");
                cycles(2);
                check_value(EccIrq, '1', ERROR, "Ecc_Irq from Ded");
                wr(EccStatus_c, x"00000002");
                chk(EccStatus_c, Zero_c, "ECC_STATUS.Ded cleared");
                cycles(2);
                check_value(EccIrq, '0', ERROR, "Ecc_Irq cleared");
                -- A write to a counter word clears the counters of its buffer, ECC_CTRL.ClrAll all counters
                wr(EccCount_c + 12, Zero_c);
                chk(EccCount_c + 12, Zero_c, "buffer 3 cleared");
                chk(EccCount_c, x"00010003", "buffer 0 kept");
                wr(EccCtrl_c, x"00000001");

                for n in 0 to 5 loop
                    chk(EccCount_c + 4 * n, Zero_c, "all counters cleared");
                end loop;

                -- An event in the clock cycle of a clear is counted
                EccSecOnB(1) <= '1';
                wr(EccCtrl_c, x"00000001");
                EccSecOnB    <= (others => '0');
                chk(EccCount_c + 4, x"00000001", "event in the clock cycle of ECC_CTRL.ClrAll");
                EccDedOnB(0) <= '1';
                wr(EccCount_c, Zero_c);
                EccDedOnB    <= (others => '0');
                chk(EccCount_c, x"00010000", "event in the clock cycle of the counter clear");
                -- The counters saturate
                wait until rising_edge(Clk);
                EccSec(2) <= '1';
                EccDed(2) <= '1';
                cycles(65540);
                EccSec    <= (others => '0');
                EccDed    <= (others => '0');
                chk(EccCount_c + 8, Ones_c, "saturated counters");
                -- Error injection: one strobe on the selected buffer with the requested error
                wr(EccInject_c, x"00000303");
                cycles(2);
                check_value(Obs.InjCount, 1, ERROR, "one injection strobe");
                check_value(Obs.InjIdx, 3, ERROR, "buffer of the injection");
                check_value(Obs.InjDouble, '1', ERROR, "double error");
                wr(EccInject_c, x"00000200");
                cycles(2);
                check_value(Obs.InjCount, 2, ERROR, "one injection strobe");
                check_value(Obs.InjIdx, 0, ERROR, "buffer of the injection");
                check_value(Obs.InjDouble, '0', ERROR, "single error");
                wr(EccInject_c, x"00000102");
                wr(EccInject_c, x"0000020F");
                cycles(2);
                check_value(Obs.InjCount, 2, ERROR, "no strobe without Inject or without a buffer");
                check_value(Obs.InjMulti, 0, ERROR, "never more than one strobe");
                -- Injection mode: ECC_INJECT.Data is taken with a strobe and held, a reset returns it to 0
                check_value(Obs.InjMode, '0', ERROR, "parity mode after strobes without Data");
                wr(EccInject_c, x"00000601");
                cycles(2);
                check_value(Obs.InjCount, 3, ERROR, "one injection strobe");
                check_value(Obs.InjData, '1', ERROR, "data mode of the strobe");
                check_value(Obs.InjMode, '1', ERROR, "data mode held after the strobe");
                wr(EccInject_c, x"00000400");
                cycles(2);
                check_value(Obs.InjCount, 3, ERROR, "no strobe without Inject");
                check_value(Obs.InjMode, '1', ERROR, "mode unchanged by a write without Inject");
                Excl_v := Mm2s_c when Incl_c(Mm2s_c) else S2mm_c;
                wr(Dmacr_c(Excl_v), Reset_c);
                poll(Dmacr_c(Excl_v), Zero_c, Reset_c, "end of the soft reset");
                check_value(Obs.InjMode, '0', ERROR, "parity mode after a soft reset");

            elsif run("test_no_extension") then
                log(ID_LOG_HDR, "TC-RG-14 configuration without the extension window");

                for n in 0 to 63 loop
                    chk(16#100# + 4 * n, Zero_c, "extension window");
                end loop;

                wr(EccEnable_c, x"00000003");
                chk(EccEnable_c, Zero_c, "write to the extension window");
                pulseEcc(true, 0, 2);
                pulseEcc(false, 1, 2);
                cycles(4);
                check_value(EccIrq, '0', ERROR, "no Ecc_Irq");
                wr(EccInject_c, x"00000300");
                cycles(4);
                check_value(Obs.InjCount, 0, ERROR, "no injection strobe");

            elsif run("test_widths") then
                log(ID_LOG_HDR, "TC-RG-15 address and length widths");

                for ch in 0 to 1 loop
                    -- Bits above the widths read 0
                    wr(AddrHi_c(ch), Ones_c);
                    chk(AddrHi_c(ch), lowOnes(AddrWidth_g - 32), "address bits 63 to 32");
                    wr(Length_c(ch), Ones_c);
                    chk(Length_c(ch), lowOnes(LengthWidth_g), "length");
                    -- Commands carry the full address and length
                    wr(AddrLo_c(ch), Ones_c);
                    wr(Dmacr_c(ch), Rs_c);
                    wr(Length_c(ch), Ones_c);
                    waitRes(ch, 1);
                    check_value(Obs.CmdAddr(ch), cmdAddr(Ones_c, Ones_c), ERROR, "command address");
                    check_value(Obs.CmdLength(ch), 2**LengthWidth_g - 1, ERROR, "command length");
                    wr(AddrLo_c(ch), x"A5A5A5A5");
                    wr(AddrHi_c(ch), x"5A5A5A5A");
                    wr(Length_c(ch), x"00000081");
                    waitRes(ch, 2);
                    check_value(Obs.CmdAddr(ch), cmdAddr(x"5A5A5A5A", x"A5A5A5A5"), ERROR, "command address");
                    check_value(Obs.CmdLength(ch), 129, ERROR, "command length");
                end loop;

            elsif run("test_sg_map") then
                log(ID_LOG_HDR, "TC-RG-16 register map of Scatter/Gather Mode");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        chk(Dmacr_c(ch), DmacrReset_c, "DMACR after the reset");
                        chk(Dmasr_c(ch), DmasrSgReset_c, "DMASR after the reset: Halted, SGIncld");
                        chk(CurLo_c(ch), Zero_c, "CURDESC after the reset");
                        chk(CurHi_c(ch), Zero_c, "CURDESC_MSB after the reset");
                        chk(TailLo_c(ch), Zero_c, "TAILDESC after the reset");
                        chk(TailHi_c(ch), Zero_c, "TAILDESC_MSB after the reset");
                        -- Bits 5 to 0 and the bits at or above AddrWidth_g read 0
                        wr(CurLo_c(ch), Ones_c);
                        chk(CurLo_c(ch), PtrMask_c, "CURDESC bits 5 to 0");
                        wr(CurHi_c(ch), Ones_c);
                        chk(CurHi_c(ch), lowOnes(AddrWidth_g - 32), "CURDESC_MSB above AddrWidth_g");
                        wr(TailLo_c(ch), Ones_c);
                        chk(TailLo_c(ch), PtrMask_c, "TAILDESC bits 5 to 0");
                        wr(TailHi_c(ch), Ones_c);
                        chk(TailHi_c(ch), lowOnes(AddrWidth_g - 32), "TAILDESC_MSB above AddrWidth_g");
                        check_value(Obs.SgCurDesc(ch), cmdAddr(Ones_c, PtrMask_c), ERROR, "CURDESC output to the engine");
                        wr(Dmacr_c(ch), Rs_c);
                    end if;
                end loop;

                -- The registers of Direct Register Mode do not exist; a length write issues no command
                for i in DrOnly_c'range loop
                    wr(DrOnly_c(i), Ones_c);
                    chk(DrOnly_c(i), Zero_c, "no register of Direct Register Mode");
                end loop;

                cycles(20);
                check_value(Obs.CmdCount(Mm2s_c) + Obs.CmdCount(S2mm_c), 0, ERROR, "no transfer command");

                -- FT buffers of the engine at the indices 6 to 9: 6 and 7 only with their channel
                for n in 6 to 9 loop
                    pulseEcc(true, n, 1);
                    pulseEcc(false, n, 2);
                    Cnt_v := Obs.InjCount;
                    wr(EccInject_c, std_logic_vector(to_unsigned(n, 32)) or x"00000200");
                    cycles(3);
                    if (n = 6 and not Incl_c(Mm2s_c)) or (n = 7 and not Incl_c(S2mm_c)) then
                        chk(EccCount_c + 4 * n, Zero_c, "no ECC counter without the channel, index " & to_string(n));
                        check_value(Obs.InjCount, Cnt_v, ERROR, "no injection without the channel, index " & to_string(n));
                    else
                        chk(EccCount_c + 4 * n, x"00020001", "ECC counters, index " & to_string(n));
                        check_value(Obs.InjCount, Cnt_v + 1, ERROR, "injection strobe, index " & to_string(n));
                        check_value(Obs.InjIdx, n, ERROR, "injection index");
                    end if;
                end loop;

                -- The registers of a channel that is not included read 0 and ignore writes
                for ch in 0 to 1 loop
                    if not Incl_c(ch) then
                        wr(Dmacr_c(ch), Ones_c and not Reset_c);
                        chk(Dmacr_c(ch), Zero_c, "DMACR of the channel that is not included");
                        chk(Dmasr_c(ch), Zero_c, "DMASR of the channel that is not included");
                        wr(CurLo_c(ch), Ones_c);
                        wr(CurHi_c(ch), Ones_c);
                        wr(TailLo_c(ch), Ones_c);
                        wr(TailHi_c(ch), Ones_c);
                        chk(CurLo_c(ch), Zero_c, "CURDESC of the channel that is not included");
                        chk(CurHi_c(ch), Zero_c, "CURDESC_MSB of the channel that is not included");
                        chk(TailLo_c(ch), Zero_c, "TAILDESC of the channel that is not included");
                        chk(TailHi_c(ch), Zero_c, "TAILDESC_MSB of the channel that is not included");
                        check_value(Obs.SgTailWr(ch), 0, ERROR, "no tail pointer write of the channel that is not included");
                    end if;
                end loop;

            elsif run("test_sg_curdesc") then
                log(ID_LOG_HDR, "TC-RG-17 CURDESC");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        -- Written while halted; the engine starts from the written pointer
                        Sg(ch).CurPtr <= x"0000003C89ABCD40";
                        wr(CurLo_c(ch), x"12345678");
                        wr(CurHi_c(ch), x"A5A5A5A5");
                        chk(CurLo_c(ch), x"12345640", "CURDESC written while halted");
                        chk(CurHi_c(ch), x"A5A5A5A5" and lowOnes(AddrWidth_g - 32), "CURDESC_MSB written while halted");
                        wr(Dmacr_c(ch), Rs_c);
                        cycles(3);
                        check_value(Obs.SgStartPtr(ch), cmdAddr(x"A5A5A5A5", x"12345640"), ERROR, "pointer at the start");
                        -- Running: the pointer of the engine, writes ignored
                        chk(CurLo_c(ch), x"89ABCD40", "CURDESC reads the pointer of the engine");
                        chk(CurHi_c(ch), x"0000003C" and lowOnes(AddrWidth_g - 32), "CURDESC_MSB reads the pointer of the engine");
                        wr(CurLo_c(ch), Ones_c);
                        wr(CurHi_c(ch), Ones_c);
                        chk(CurLo_c(ch), x"89ABCD40", "CURDESC write ignored while running");
                        chk(CurHi_c(ch), x"0000003C" and lowOnes(AddrWidth_g - 32), "CURDESC_MSB write ignored while running");
                        Sg(ch).CurPtr <= x"0000000100000F80";
                        cycles(2);
                        chk(CurLo_c(ch), x"00000F80", "CURDESC follows the engine");
                        chk(CurHi_c(ch), x"00000001" and lowOnes(AddrWidth_g - 32), "CURDESC_MSB follows the engine");
                        check_value(Obs.SgCurDiffer(ch), 0, ERROR, "CURDESC output equals the engine pointer while running");
                        -- After the halt the last pointer of the engine
                        Sg(ch).Stopped <= '0';
                        wr(Dmacr_c(ch), Zero_c);
                        cycles(30);
                        Sg(ch).Stopped <= '1';
                        poll(Dmasr_c(ch), Halted_c, Halted_c, "halted");
                        chk(CurLo_c(ch), x"00000F80", "CURDESC after the halt");
                        -- The first write after a run starts from the pointer of the engine
                        if AddrWidth_g > 32 then
                            wr(CurHi_c(ch), x"00000022");
                            Sg(ch).CurPtr <= x"0000000000000000";
                            cycles(2);
                            chk(CurLo_c(ch), x"00000F80", "CURDESC keeps the low word of the engine pointer");
                            chk(CurHi_c(ch), x"00000022", "CURDESC_MSB written after the halt");
                            Exp_v         := x"00000022";
                            Data_v        := x"00000F80";
                        else
                            wr(CurLo_c(ch), x"00002000");
                            Sg(ch).CurPtr <= x"0000000000000000";
                            cycles(2);
                            chk(CurLo_c(ch), x"00002000", "CURDESC written after the halt");
                            Exp_v         := Zero_c;
                            Data_v        := x"00002000";
                        end if;
                        wr(Dmacr_c(ch), Rs_c);
                        cycles(3);
                        check_value(Obs.SgStartPtr(ch), cmdAddr(Exp_v, Data_v), ERROR, "pointer at the restart");
                        chk(CurLo_c(ch), Zero_c, "CURDESC reads the engine again");
                        sgHalt(ch);
                        -- A restart without a CURDESC write starts from the last pointer of the engine
                        Sg(ch).CurPtr <= x"0000000700003FC0";
                        cycles(2);
                        chk(CurLo_c(ch), x"00003FC0", "CURDESC after the halt, no write");
                        wr(Dmacr_c(ch), Rs_c);
                        cycles(3);
                        check_value(Obs.SgStartPtr(ch), cmdAddr(x"00000007", x"00003FC0"), ERROR,
                                    "restart without a CURDESC write: the pointer of the engine");
                        sgHalt(ch);
                    end if;
                end loop;

            elsif run("test_sg_tail") then
                log(ID_LOG_HDR, "TC-RG-18 TAILDESC");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        -- While halted the pointer is only stored
                        wr(TailLo_c(ch), x"00001240");
                        wr(TailHi_c(ch), x"00000003");
                        chk(TailLo_c(ch), x"00001240", "TAILDESC written while halted");
                        chk(TailHi_c(ch), x"00000003" and lowOnes(AddrWidth_g - 32), "TAILDESC_MSB written while halted");
                        check_value(Obs.SgTailWr(ch), 0, ERROR, "no tail pointer write while halted");
                        -- Running: the triggering write passes the pointer (interpretation SGI-01)
                        wr(Dmacr_c(ch), Rs_c);
                        wr(TailLo_c(ch), x"ABCDEF7F");
                        cycles(2);
                        if AddrWidth_g > 32 then
                            check_value(Obs.SgTailWr(ch), 0, ERROR, "TAILDESC alone does not start the engine");
                            wr(TailHi_c(ch), x"00000044");
                            cycles(2);
                            check_value(Obs.SgTailWr(ch), 1, ERROR, "TAILDESC_MSB starts the engine");
                            check_value(Obs.SgTail(ch), cmdAddr(x"00000044", x"ABCDEF40"), ERROR, "tail pointer of both words");
                            -- The other word never starts it
                            wr(TailLo_c(ch), x"00000100");
                            cycles(2);
                            check_value(Obs.SgTailWr(ch), 1, ERROR, "no start by TAILDESC");
                            wr(TailHi_c(ch), x"00000001");
                            cycles(2);
                            check_value(Obs.SgTail(ch), cmdAddr(x"00000001", x"00000100"), ERROR, "second tail pointer");
                        else
                            check_value(Obs.SgTailWr(ch), 1, ERROR, "TAILDESC starts the engine");
                            check_value(Obs.SgTail(ch), cmdAddr(Zero_c, x"ABCDEF40"), ERROR, "tail pointer");
                            wr(TailHi_c(ch), Ones_c);
                            cycles(2);
                            check_value(Obs.SgTailWr(ch), 1, ERROR, "no start by TAILDESC_MSB");
                            chk(TailHi_c(ch), Zero_c, "TAILDESC_MSB with 32 address bits");
                            wr(TailLo_c(ch), x"00000100");
                            cycles(2);
                            check_value(Obs.SgTail(ch), cmdAddr(Zero_c, x"00000100"), ERROR, "second tail pointer");
                        end if;
                        check_value(Obs.SgTailWr(ch), 2, ERROR, "two tail pointer writes");
                        -- Stopping and halted: stored only
                        Sg(ch).Stopped <= '0';
                        wr(Dmacr_c(ch), Zero_c);
                        wr(TailTrig_c(ch), x"00000040");
                        cycles(2);
                        Sg(ch).Stopped <= '1';
                        poll(Dmasr_c(ch), Halted_c, Halted_c, "halted");
                        wr(TailTrig_c(ch), x"00000080");
                        cycles(2);
                        check_value(Obs.SgTailWr(ch), 2, ERROR, "no tail pointer write while stopping or halted");
                        if AddrWidth_g > 32 then
                            chk(TailHi_c(ch), x"00000080" and lowOnes(AddrWidth_g - 32), "stored while halted");
                        else
                            chk(TailLo_c(ch), x"00000080", "stored while halted");
                        end if;
                    end if;
                end loop;

            elsif run("test_sg_state") then
                log(ID_LOG_HDR, "TC-RG-19 Halted and Idle in Scatter/Gather Mode");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        Sg(ch).Idle <= '1';
                        cycles(2);
                        chk(Dmasr_c(ch), DmasrSgReset_c, "halted: Idle 0 whatever the engine reports");
                        wr(Dmacr_c(ch), Rs_c);
                        chkMask(Dmasr_c(ch), Idle_c, Halted_c or Idle_c, "running, the engine at the tail");
                        Sg(ch).Idle <= '0';
                        cycles(2);
                        chkMask(Dmasr_c(ch), Zero_c, Halted_c or Idle_c, "running, the engine working");
                        -- Halted only when the engine and the channel have stopped
                        Sg(ch).Stopped    <= '0';
                        wr(Dmacr_c(ch), Zero_c);
                        cycles(50);
                        chkMask(Dmasr_c(ch), Zero_c, Halted_c, "not halted while the engine works");
                        Sg(ch).Stopped    <= '1';
                        poll(Dmasr_c(ch), Halted_c, Halted_c, "halted once the engine stopped");
                        Cfg(ch).DrainTime <= 200;
                        wr(Dmacr_c(ch), Rs_c);
                        wr(Dmacr_c(ch), Zero_c);
                        cycles(50);
                        chkMask(Dmasr_c(ch), Zero_c, Halted_c, "not halted while the channel works");
                        poll(Dmasr_c(ch), Halted_c, Halted_c, "halted once the channel stopped");
                        Cfg(ch).DrainTime <= 0;
                    end if;
                end loop;

                check_value(Obs.CmdCount(Mm2s_c) + Obs.CmdCount(S2mm_c), 0, ERROR, "no transfer command");

            elsif run("test_sg_errors") then
                log(ID_LOG_HDR, "TC-RG-20 error flags of the Scatter/Gather engine");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then

                        for e in 0 to 6 loop
                            -- The other channel runs and is not affected
                            if Incl_c(1 - ch) then
                                wr(Dmacr_c(1 - ch), Rs_c);
                            end if;
                            wr(Dmacr_c(ch), Rs_c or ErrIrqEn_c);
                            Flag_v := Zero_c;

                            case e is
                                when 0 =>
                                    sgErr(ch, "00", ErrInt_c);
                                    Exp_v := SgIntErr_c;
                                when 1 =>
                                    sgErr(ch, "00", ErrSlv_c);
                                    Exp_v := SgSlvErr_c;
                                when 2 =>
                                    sgErr(ch, "00", ErrDec_c);
                                    Exp_v := SgDecErr_c;
                                when 3 =>
                                    sgErr(ch, ErrInt_c, "00");
                                    Exp_v := IntErr_c;
                                when 4 =>
                                    sgErr(ch, ErrSlv_c, "00");
                                    Exp_v  := SlvErr_c;
                                    Flag_v := IntErr_c;
                                when 5 =>
                                    sgErr(ch, ErrDec_c, "00");
                                    Exp_v  := DecErr_c;
                                    Flag_v := IntErr_c;
                                when others =>
                                    sgErr(ch, ErrSlv_c, ErrSlv_c);
                                    Exp_v  := SlvErr_c or SgSlvErr_c;
                                    Flag_v := IntErr_c;
                            end case;

                            -- S2MM: DMAIntErr also with the slave and the decode error of a transfer
                            if ch = S2mm_c then
                                Exp_v := Exp_v or Flag_v;
                            end if;
                            poll(Dmasr_c(ch), Halted_c, Halted_c, "halted after the error");
                            chk(Dmasr_c(ch), Exp_v or Halted_c or SgIncld_c or ErrIrq_c or threshold(1), "error flags, Err_Irq");
                            chkMask(Dmacr_c(ch), Zero_c, Rs_c, "RS cleared by the error");
                            check_value(ChIrq(ch), '1', ERROR, "interrupt output");
                            if Incl_c(1 - ch) then
                                chkMask(Dmasr_c(1 - ch), Zero_c, Halted_c, "the other channel still runs");
                            end if;
                            -- No restart while the flag is set; the flags are read-only
                            wr(Dmacr_c(ch), Rs_c or ErrIrqEn_c);
                            cycles(5);
                            chkMask(Dmasr_c(ch), Halted_c, Halted_c, "no restart with an error flag");
                            wr(Dmasr_c(ch), Ones_c);
                            chk(Dmasr_c(ch), Exp_v or Halted_c or SgIncld_c or threshold(1), "flags kept, Err_Irq cleared");
                            softReset(ch);
                            chk(Dmasr_c(ch), DmasrSgReset_c, "flags cleared by the soft reset");
                        end loop;

                    end if;
                end loop;

            elsif run("test_sg_threshold") then
                log(ID_LOG_HDR, "TC-RG-21 interrupt threshold");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        wr(Dmacr_c(ch), Rs_c or IocIrqEn_c or threshold(3));
                        chkMask(Dmasr_c(ch), threshold(3), ThrMask_c, "IRQThresholdSts after the start");
                        sgPkt(ch);
                        sgPkt(ch);
                        chkMask(Dmasr_c(ch), threshold(1), ThrMask_c or IocIrq_c, "two packets: one left, no IOC_Irq");
                        sgPkt(ch);
                        chkMask(Dmasr_c(ch), threshold(3) or IocIrq_c, ThrMask_c or IocIrq_c, "third packet: IOC_Irq, reloaded");
                        cycles(2);
                        check_value(ChIrq(ch), '1', ERROR, "interrupt output");
                        wr(Dmasr_c(ch), IocIrq_c);
                        sgPkt(ch);
                        chkMask(Dmasr_c(ch), threshold(2), ThrMask_c or IocIrq_c, "one packet after the clear");
                        -- A write of the field reloads the counter, a write of 0 leaves both unchanged
                        wr(Dmacr_c(ch), Rs_c or IocIrqEn_c or threshold(5));
                        chkMask(Dmasr_c(ch), threshold(5), ThrMask_c, "reloaded by the write of the field");
                        sgPkt(ch);
                        chkMask(Dmasr_c(ch), threshold(4), ThrMask_c, "one packet");
                        wr(Dmacr_c(ch), Rs_c or IocIrqEn_c);
                        chkMask(Dmacr_c(ch), threshold(5), ThrMask_c, "IRQThreshold unchanged by a write of 0");
                        chkMask(Dmasr_c(ch), threshold(4), ThrMask_c, "counter unchanged by a write of 0");
                        -- The start of the channel reloads the counter
                        wr(Dmacr_c(ch), IocIrqEn_c);
                        poll(Dmasr_c(ch), Halted_c, Halted_c, "halted");
                        wr(Dmacr_c(ch), Rs_c or IocIrqEn_c);
                        chkMask(Dmasr_c(ch), threshold(5), ThrMask_c or IocIrq_c, "reloaded at the start");

                        for i in 1 to 5 loop
                            sgPkt(ch);
                        end loop;

                        chkMask(Dmasr_c(ch), threshold(5) or IocIrq_c, ThrMask_c or IocIrq_c, "IOC_Irq after five packets");
                        softReset(ch);
                    end if;
                end loop;

            elsif run("test_sg_delay") then
                log(ID_LOG_HDR, "TC-RG-22 delay timer");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        wr(Dmacr_c(ch), Rs_c or DlyIrqEn_c or threshold(4) or delay(2));
                        sgPkt(ch);
                        cycles(140);
                        First_v := Obs.PktCycle(ch);
                        chkMask(Dmasr_c(ch), delay(1) or threshold(3), DlyMask_c or ThrMask_c or DlyIrq_c, "IRQDelaySts after one unit");
                        if ChIrq(ch) = '0' then
                            wait until ChIrq(ch) = '1' for 5 us;
                        end if;
                        check_value(ChIrq(ch), '1', ERROR, "Dly_Irq drives the interrupt output");
                        cycles(2);
                        -- The timeout after 2 x 125 clock cycles: flag after the clock cycle 250, output one later, seen by
                        -- the harness one later (a unit of 124 or 126 clock cycles falls outside)
                        check_value_in_range(Obs.IrqRiseCycle(ch) - First_v, 251, 253, ERROR, "timeout after 2 x 125 clock cycles");
                        chkMask(Dmasr_c(ch), DlyIrq_c or threshold(4), DlyIrq_c or DlyMask_c or ThrMask_c, "Dly_Irq, timer cleared, threshold reloaded");
                        wr(Dmasr_c(ch), DlyIrq_c);
                        chkMask(Dmasr_c(ch), Zero_c, DlyIrq_c, "Dly_Irq cleared by writing 1");
                        cycles(2);
                        check_value(ChIrq(ch), '0', ERROR, "interrupt output after the clear");
                        -- The start of a packet stops and clears the timer
                        sgPkt(ch);
                        cycles(100);
                        sgPktStart(ch);
                        chkMask(Dmasr_c(ch), Zero_c, DlyMask_c, "timer cleared by the start of a packet");
                        cycles(300);
                        chkMask(Dmasr_c(ch), Zero_c, DlyIrq_c or DlyMask_c, "no timeout after the start of a packet");
                        -- A packet that sets IOC_Irq stops the timer
                        sgPkt(ch);
                        sgPkt(ch);
                        sgPkt(ch);
                        cycles(300);
                        chkMask(Dmasr_c(ch), IocIrq_c, IocIrq_c or DlyIrq_c or DlyMask_c, "IOC_Irq, no timeout");
                        -- IRQDelay = 0 disables the timer
                        wr(Dmasr_c(ch), IocIrq_c);
                        wr(Dmacr_c(ch), Rs_c or DlyIrqEn_c or threshold(4));
                        sgPkt(ch);
                        cycles(300);
                        chkMask(Dmasr_c(ch), Zero_c, DlyIrq_c or DlyMask_c, "no timer with IRQDelay 0");
                        softReset(ch);
                    end if;
                end loop;

            elsif run("test_sg_modes") then
                log(ID_LOG_HDR, "TC-RG-23 keyhole and cyclic mode");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        check_value(std_logic_vector'(Obs.SgKeyhole(ch) & Obs.SgCyclic(ch)), std_logic_vector'("00"), ERROR,
                                    "keyhole and cyclic after the reset");
                        wr(Dmacr_c(ch), Keyhole_c);
                        cycles(2);
                        check_value(std_logic_vector'(Obs.SgKeyhole(ch) & Obs.SgCyclic(ch)), std_logic_vector'("10"), ERROR, "keyhole");
                        wr(Dmacr_c(ch), CyclicBd_c);
                        cycles(2);
                        check_value(std_logic_vector'(Obs.SgKeyhole(ch) & Obs.SgCyclic(ch)), std_logic_vector'("01"), ERROR, "cyclic mode");
                        wr(Dmacr_c(ch), Rs_c or Keyhole_c or CyclicBd_c);
                        cycles(2);
                        check_value(std_logic_vector'(Obs.SgKeyhole(ch) & Obs.SgCyclic(ch)), std_logic_vector'("11"), ERROR, "both while running");
                        sgHalt(ch);
                    end if;
                end loop;

            end if;

        end loop;

        odmaTestEnd(runner);
        wait;
    end process;

end architecture;
