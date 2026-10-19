---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VUnit testbench of odma_sg: the test cases TC-SG-01 to TC-SG-17 of the verification plan.
-- Descriptor layout, status bits and expected values are taken from the specification, never from
-- the RTL: the testbench builds the chains in the memory model and walks them itself.
--
-- Documentation: hdl/odma_sg/docs/verification_plan.md

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
    use work.odma_sg_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_sg_tb is
    generic (
        runner_cfg    : string;
        AddrWidth_g   : positive := 32;
        LengthWidth_g : positive := 14;
        IncludeMm2s_g : boolean  := true;
        IncludeS2mm_g : boolean  := true
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_sg_tb is

    type Bool_a is array (0 to 1) of boolean;

    constant Incl_c : Bool_a := (IncludeMm2s_g, IncludeS2mm_g);

    -- Error codes of a result and of the engine (odma_pkg XferErr_t)
    constant ErrNone_c : std_logic_vector(1 downto 0) := "00";
    constant ErrInt_c  : std_logic_vector(1 downto 0) := "01";
    constant ErrSlv_c  : std_logic_vector(1 downto 0) := "10";
    constant ErrDec_c  : std_logic_vector(1 downto 0) := "11";

    -- Descriptors per chain at most, descriptors of the random test
    constant MaxDesc_c : positive := 16;
    constant Total_c   : positive := 40;

    -- Harness
    signal Clk          : std_logic;
    signal Rst          : std_logic                    := '1';
    signal Reg          : RegDrive_a                   := (others => RegDriveIdle_c);
    signal Cfg          : ChanCfg_a                    := (others => ChanCfgDefault_c);
    signal EccInjValid  : std_logic_vector(3 downto 0) := (others => '0');
    signal EccInjDouble : std_logic                    := '0';
    signal EccInjData   : std_logic                    := '0';
    signal Obs          : Obs_r;

    -- An address limited to AddrWidth_g bits
    function mask (a : Addr_t) return Addr_t is
        variable A_v : Addr_t := a;
    begin

        for i in 0 to 63 loop
            if i >= AddrWidth_g then
                A_v(i) := '0';
            end if;
        end loop;

        return A_v;
    end function;

    -- Descriptor i of a chain: aligned to 64 bytes, every address bit used, apart by 7 x 64 bytes (crossing 4 KB)
    function descAddr (
        ch : natural;
        i  : natural) return Addr_t is
        variable Base_v : Addr_t;
    begin
        if ch = Mm2s_c then
            Base_v := x"5AC396E12B74D800";
        else
            Base_v := x"A53C691ED48B2400";
        end if;
        return mask(std_logic_vector(unsigned(Base_v) + to_unsigned(i * 16#1C0#, 64)));
    end function;

    -- Buffer of descriptor i (never accessed on the descriptor port)
    function bufAddr (
        ch : natural;
        i  : natural) return Addr_t is
        variable Base_v : Addr_t;
    begin
        if ch = Mm2s_c then
            Base_v := x"13579BDF2468ACE1";
        else
            Base_v := x"ECA8642FDB975313";
        end if;
        return mask(std_logic_vector(unsigned(Base_v) + to_unsigned(i * 16#10F1#, 64)));
    end function;

    -- Buffer length of descriptor i: 1 to 2**LengthWidth_g - 1, never 0
    function lenOf (i : natural) return natural is
        variable L_v : natural;
    begin
        L_v := (37 + 211 * i) mod (2 ** LengthWidth_g);
        if L_v = 0 then
            L_v := 1;
        end if;
        return L_v;
    end function;

    -- One of two strings
    function sel (
        c : boolean;
        a : string;
        b : string) return string is
    begin
        if c then
            return a;
        end if;
        return b;
    end function;

    -- Status word expected after a result (PG021 Tables 31 and 38, interpretations SGI-02 and I13)
    function statusExp (
        ch    : natural;
        bytes : natural;
        sof   : std_logic;
        eof   : std_logic;
        err   : std_logic_vector(1 downto 0)) return Word_t is
        variable S_v : Word_t := (others => '0');
    begin
        S_v(25 downto 0) := std_logic_vector(to_unsigned(bytes, 26));
        if ch = S2mm_c then
            S_v(27) := sof;
            S_v(26) := eof;
        end if;
        if err = ErrInt_c or (ch = S2mm_c and err /= ErrNone_c) then
            S_v(28) := '1';
        end if;
        if err = ErrSlv_c then
            S_v(29) := '1';
        end if;
        if err = ErrDec_c then
            S_v(30) := '1';
        end if;
        if err = ErrNone_c then
            S_v(31) := '1';
        end if;
        return S_v;
    end function;

begin

    test_runner_watchdog(runner, 100 ms);

    i_th : entity work.odma_sg_th
        generic map (
            AddrWidth_g   => AddrWidth_g,
            LengthWidth_g => LengthWidth_g,
            IncludeMm2s_g => IncludeMm2s_g,
            IncludeS2mm_g => IncludeS2mm_g
        )
        port map (
            Clk          => Clk,
            Rst          => Rst,
            Reg          => Reg,
            Cfg          => Cfg,
            EccInjValid  => EccInjValid,
            EccInjDouble => EccInjDouble,
            EccInjData   => EccInjData,
            Obs          => Obs
        );

    p_control : process is
        -- Descriptors of the chains of both channels, and the words written to memory
        type Desc_r is record
            Nxt   : natural;
            Len   : natural;
            Sof   : std_logic;
            Eof   : std_logic;
            Cmplt : std_logic;
        end record;

        type DescChain_t is array (0 to MaxDesc_c - 1) of Desc_r;
        type DescChain_a is array (0 to 1) of DescChain_t;
        type Image_t is array (0 to 15) of Word_t;
        type Images_t is array (0 to MaxDesc_c - 1) of Image_t;
        type Images_a is array (0 to 1) of Images_t;

        variable D_v       : DescChain_a;
        variable Img_v     : Images_a;
        variable ArBase_v  : natural;
        variable AwBase_v  : natural;
        variable WBase_v   : natural;
        variable BBase_v   : natural;
        variable CmdBase_v : Nat_a;
        variable ResBase_v : Nat_a;
        variable PktBase_v : Nat_a;
        variable ErrBase_v : Nat_a;
        variable N_v       : natural;
        variable K_v       : natural;
        variable Word_v    : Word_t;
        variable Exp_v     : Word_t;
        variable Ok_v      : boolean;
        variable Seed1_v   : positive;
        variable Seed2_v   : positive;
        variable Rand_v    : real;
        variable SecBase_v : natural;
        variable DedBase_v : natural;
        variable ExpErr_v  : std_logic_vector(1 downto 0);

        -- Random test: descriptors prepared and checked, packets, expected status words
        type Status_a is array (0 to Total_c - 1) of Word_t;

        variable ExpSt_v    : Status_a;
        variable Prepared_v : natural;
        variable Checked_v  : natural;
        variable Pkts_v     : natural;
        variable PktOpen_v  : boolean;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- Backdoor access to the memory of the descriptors
        procedure wrWord (
            addr : Addr_t;
            w    : Word_t) is
        begin

            for b in 0 to 3 loop
                Mem_v.write8(MemSg_c, unsigned(addr) + b, w(8 * b + 7 downto 8 * b));
            end loop;

        end procedure;

        impure function rdWord (addr : Addr_t) return Word_t is
            variable W_v : Word_t;
        begin

            for b in 0 to 3 loop
                W_v(8 * b + 7 downto 8 * b) := Mem_v.read8(MemSg_c, unsigned(addr) + b);
            end loop;

            return W_v;
        end function;

        -- A word that depends on its address: the content of every descriptor bit the engine ignores
        impure function junk (addr : Addr_t) return Word_t is
            variable W_v : Word_t;
        begin

            for b in 0 to 3 loop
                W_v(8 * b + 7 downto 8 * b) := odmaMemByte(unsigned(addr) + b, 7);
            end loop;

            return W_v;
        end function;

        -- Writes descriptor i of channel ch from D_v (all 16 words of its block); with ign the ignored bits are set
        procedure writeDesc (
            ch  : natural;
            i   : natural;
            ign : boolean) is
            variable A_v : Addr_t;
            variable N_v : Addr_t;
            variable B_v : Addr_t;
            variable W_v : Image_t;
            variable J_v : Word_t;
        begin
            A_v := descAddr(ch, i);
            N_v := descAddr(ch, D_v(ch)(i).Nxt);
            B_v := bufAddr(ch, i);

            for w in 0 to 15 loop
                W_v(w) := junk(std_logic_vector(unsigned(A_v) + 4 * w));
            end loop;

            -- NXTDESC, NXTDESC_MSB: bits 5 to 0 and bits at or above AddrWidth_g are ignored (SG-FE-01, SG-IF-03)
            J_v := W_v(0);
            if not ign then
                J_v := (others => '0');
            end if;
            W_v(0) := N_v(31 downto 6) & J_v(5 downto 0);
            W_v(1) := N_v(63 downto 32);
            W_v(2) := B_v(31 downto 0);
            W_v(3) := B_v(63 downto 32);

            for b in 32 to 63 loop
                if b >= AddrWidth_g then
                    W_v(1)(b - 32) := J_v(b - 32) when ign else '0';
                    W_v(3)(b - 32) := J_v((b - 30) mod 32) when ign else '0';
                end if;
            end loop;

            -- CONTROL: the buffer length, bits above LengthWidth_g ignored; MM2S TXSOF (27) and TXEOF (26), S2MM bits
            -- 27 and 26 ignored (SG-TR-02)
            J_v := W_v(6);
            if not ign then
                J_v := (others => '0');
            end if;
            W_v(6)                             := J_v;
            W_v(6)(LengthWidth_g - 1 downto 0) := std_logic_vector(to_unsigned(D_v(ch)(i).Len, LengthWidth_g));
            if ch = Mm2s_c then
                W_v(6)(27) := D_v(ch)(i).Sof;
                W_v(6)(26) := D_v(ch)(i).Eof;
            end if;
            -- STATUS: only Cmplt is taken
            W_v(7)(31) := D_v(ch)(i).Cmplt;

            for w in 0 to 15 loop
                wrWord(std_logic_vector(unsigned(A_v) + 4 * w), W_v(w));
            end loop;

            Img_v(ch)(i) := W_v;
        end procedure;

        -- A chain of n descriptors in a ring; MM2S packets of pkt descriptors; lengths from lenOf
        procedure chain (
            ch  : natural;
            n   : natural;
            pkt : positive := 1;
            ign : boolean  := true) is
        begin

            for i in 0 to n - 1 loop
                D_v(ch)(i).Nxt   := (i + 1) mod n;
                D_v(ch)(i).Len   := lenOf(i + 3 * ch);
                D_v(ch)(i).Sof   := '1' when i mod pkt = 0 else '0';
                D_v(ch)(i).Eof   := '1' when i mod pkt = pkt - 1 or i = n - 1 else '0';
                D_v(ch)(i).Cmplt := '0';
                writeDesc(ch, i, ign);
            end loop;

        end procedure;

        -- Random test: descriptor k of the chain (ring position k mod MaxDesc_c) with a random length and packet
        -- structure; S2MM: the result of its command (a packet continues only in a full buffer)
        procedure prepareRandom (
            ch : natural;
            k  : natural) is
            variable I_v     : natural;
            variable Sof_v   : std_logic;
            variable Eof_v   : std_logic;
            variable Bytes_v : natural;
        begin
            I_v                := k mod MaxDesc_c;
            uniform(Seed1_v, Seed2_v, Rand_v);
            D_v(ch)(I_v).Nxt   := (I_v + 1) mod MaxDesc_c;
            D_v(ch)(I_v).Len   := 1 + integer(Rand_v * real(minimum(2 ** LengthWidth_g - 2, 3000)));
            uniform(Seed1_v, Seed2_v, Rand_v);
            Eof_v              := '1' when Rand_v < 0.5 or k = Total_c - 1 else '0';
            Sof_v              := '0' when PktOpen_v else '1';
            D_v(ch)(I_v).Sof   := Sof_v;
            D_v(ch)(I_v).Eof   := Eof_v;
            D_v(ch)(I_v).Cmplt := '0';
            writeDesc(ch, I_v, true);
            Bytes_v            := D_v(ch)(I_v).Len;
            if ch = S2mm_c then
                if Eof_v = '1' then
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    Bytes_v := 1 + integer(Rand_v * real(D_v(ch)(I_v).Len - 1));
                end if;
                Cfg(ch).Results(CmdBase_v(ch) + k) <= (true, Bytes_v, Sof_v, Eof_v, ErrNone_c);
            end if;
            ExpSt_v(k) := statusExp(ch, Bytes_v, Sof_v, Eof_v, ErrNone_c);
            PktOpen_v  := Eof_v = '0';
            if Eof_v = '1' then
                Pkts_v := Pkts_v + 1;
            end if;
        end procedure;

        -- Clears the status of descriptor i (the software of the drivers before it moves the tail pointer)
        procedure rearm (
            ch : natural;
            i  : natural) is
        begin
            D_v(ch)(i).Cmplt := '0';
            Img_v(ch)(i)(7)  := (others => '0');
            wrWord(std_logic_vector(unsigned(descAddr(ch, i)) + 16#1C#), (others => '0'));
        end procedure;

        -- Every word of descriptor i: STATUS as expected (exp, or unchanged when not written), the others unchanged
        procedure checkDesc (
            ch      : natural;
            i       : natural;
            written : boolean;
            exp     : Word_t;
            msg     : string) is
            variable A_v : Addr_t;
        begin
            A_v := descAddr(ch, i);

            for w in 0 to 15 loop
                if w = 7 and written then
                    check_value(rdWord(std_logic_vector(unsigned(A_v) + 28)), exp, ERROR,
                                msg & ": status of descriptor " & to_string(i), C_TB_SCOPE_DEFAULT, HEX);
                else
                    check_value(rdWord(std_logic_vector(unsigned(A_v) + 4 * w)), Img_v(ch)(i)(w), ERROR,
                                msg & ": word " & to_string(w) & " of descriptor " & to_string(i) & " unchanged",
                                C_TB_SCOPE_DEFAULT, HEX);
                end if;
            end loop;

        end procedure;

        -- Command k of channel ch carries descriptor i
        procedure checkCmd (
            ch  : natural;
            k   : natural;
            i   : natural;
            msg : string) is
        begin
            check_value(Obs.Cmds(ch)(CmdBase_v(ch) + k).Addr, bufAddr(ch, i), ERROR,
                        msg & ": address of command " & to_string(k), C_TB_SCOPE_DEFAULT, HEX);
            check_value(Obs.Cmds(ch)(CmdBase_v(ch) + k).Length, D_v(ch)(i).Len, ERROR,
                        msg & ": length of command " & to_string(k));
            if ch = Mm2s_c then
                check_value(Obs.Cmds(ch)(CmdBase_v(ch) + k).Sof, D_v(ch)(i).Sof, ERROR,
                            msg & ": TXSOF of command " & to_string(k));
                check_value(Obs.Cmds(ch)(CmdBase_v(ch) + k).Eof, D_v(ch)(i).Eof, ERROR,
                            msg & ": TXEOF of command " & to_string(k));
            end if;
        end procedure;

        -- Read burst k of the descriptor port: the fetch of descriptor i of channel ch
        procedure checkFetch (
            k   : natural;
            ch  : natural;
            i   : natural;
            msg : string) is
        begin
            check_value(Obs.Ars(ArBase_v + k).Addr, descAddr(ch, i), ERROR, msg & ": address of fetch " & to_string(k),
                        C_TB_SCOPE_DEFAULT, HEX);
            check_value(Obs.Ars(ArBase_v + k).Len, 8, ERROR, msg & ": one burst of 8 beats");
            check_value(Obs.Ars(ArBase_v + k).Size, std_logic_vector'("010"), ERROR, msg & ": 4 bytes per beat");
            check_value(Obs.Ars(ArBase_v + k).Burst, std_logic_vector'("01"), ERROR, msg & ": INCR burst");
            check_value(Obs.Ars(ArBase_v + k).Lock, '0', ERROR, msg & ": ArLock");
            check_value(Obs.Ars(ArBase_v + k).Cache, std_logic_vector'("0011"), ERROR, msg & ": ArCache");
            check_value(Obs.Ars(ArBase_v + k).Prot, std_logic_vector'("000"), ERROR, msg & ": ArProt");
        end procedure;

        -- Register side
        procedure start (
            ch  : natural;
            cur : Addr_t) is
        begin
            wait until rising_edge(Clk);
            Reg(ch).CurDesc <= cur;
            Reg(ch).Run     <= '1';
            wait until rising_edge(Clk);
        end procedure;

        procedure tail (
            ch : natural;
            t  : Addr_t) is
        begin
            wait until rising_edge(Clk);
            Reg(ch).Tail   <= t;
            Reg(ch).TailWr <= '1';
            wait until rising_edge(Clk);
            Reg(ch).TailWr <= '0';
        end procedure;

        procedure waitCmds (
            ch  : natural;
            n   : natural;
            msg : string) is
        begin
            if Obs.CmdCount(ch) - CmdBase_v(ch) < n then
                wait until Obs.CmdCount(ch) - CmdBase_v(ch) >= n for 500 us;
            end if;
            check_value(Obs.CmdCount(ch) - CmdBase_v(ch), n, ERROR, msg & ": commands");
        end procedure;

        procedure waitRes (
            ch  : natural;
            n   : natural;
            msg : string) is
        begin
            if Obs.ResCount(ch) - ResBase_v(ch) < n then
                wait until Obs.ResCount(ch) - ResBase_v(ch) >= n for 500 us;
            end if;
            check_value(Obs.ResCount(ch) - ResBase_v(ch), n, ERROR, msg & ": results");
        end procedure;

        procedure waitIdle (
            ch  : natural;
            msg : string) is
        begin
            if Obs.Idle(ch) /= '1' then
                wait until Obs.Idle(ch) = '1' for 500 us;
            end if;
            check_value(Obs.Idle(ch), '1', ERROR, msg & ": idle");
        end procedure;

        procedure waitStopped (
            ch  : natural;
            msg : string) is
        begin
            wait until rising_edge(Clk);
            wait until rising_edge(Clk);
            if Obs.Stopped(ch) /= '1' then
                wait until Obs.Stopped(ch) = '1' for 500 us;
            end if;
            check_value(Obs.Stopped(ch), '1', ERROR, msg & ": stopped");
        end procedure;

        procedure waitErrs (
            ch  : natural;
            n   : natural;
            msg : string) is
        begin
            if Obs.ErrCount(ch) - ErrBase_v(ch) < n then
                wait until Obs.ErrCount(ch) - ErrBase_v(ch) >= n for 500 us;
            end if;
            check_value(Obs.ErrCount(ch) - ErrBase_v(ch), n, ERROR, msg & ": error events");
        end procedure;

        -- Fetches of the descriptor port since the last reset
        procedure waitFetches (
            n   : natural;
            msg : string) is
        begin
            if Obs.ArCount - ArBase_v < n then
                wait until Obs.ArCount - ArBase_v >= n for 500 us;
            end if;
            check_value(Obs.ArCount - ArBase_v, n, ERROR, msg & ": fetches");
        end procedure;

        -- Write responses of status writes since the last reset
        procedure waitWrites (
            n   : natural;
            msg : string) is
        begin
            if Obs.BCount - BBase_v < n then
                wait until Obs.BCount - BBase_v >= n for 500 us;
            end if;
            check_value(Obs.BCount - BBase_v, n, ERROR, msg & ": status writes");
        end procedure;

        procedure halt (
            ch  : natural;
            msg : string) is
        begin
            wait until rising_edge(Clk);
            Reg(ch).Run <= '0';
            waitStopped(ch, msg);
        end procedure;

        -- Reset of the DUT and of the models between the parts of a test
        procedure resetAll is
        begin
            wait until rising_edge(Clk);
            Reg       <= (others => RegDriveIdle_c);
            Cfg       <= (others => ChanCfgDefault_c);
            Rst       <= '1';
            cycles(5);
            Rst       <= '0';
            Mem_v.clearErrors(MemSg_c);
            Mem_v.setLatency(MemSg_c, 0);
            Mem_v.setStall(MemSg_c, 0);
            cycles(5);
            ArBase_v  := Obs.ArCount;
            AwBase_v  := Obs.AwCount;
            WBase_v   := Obs.WCount;
            BBase_v   := Obs.BCount;
            CmdBase_v := Obs.CmdCount;
            ResBase_v := Obs.ResCount;
            PktBase_v := Obs.PktCount;
            ErrBase_v := Obs.ErrCount;
        end procedure;

        -- Pulse of the error injection into buffer idx
        procedure inject (
            idx    : natural;
            double : std_logic;
            data   : std_logic) is
        begin
            wait until rising_edge(Clk);
            EccInjDouble     <= double;
            EccInjData       <= data;
            EccInjValid(idx) <= '1';
            wait until rising_edge(Clk);
            EccInjValid      <= (others => '0');
        end procedure;

    -- Comment for the style checker: subprograms above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);
        Mem_v.setMaxBeats(MemSg_c, 16);
        Seed1_v := 17;
        Seed2_v := 4711;
        resetAll;

        while test_suite loop

            if run("test_fetch") then
                log(ID_LOG_HDR, "TC-SG-01 descriptor fetch and transfer commands");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        chain(ch, 3, 3);
                        -- The longest buffer length in the second descriptor
                        D_v(ch)(1).Len := 2 ** LengthWidth_g - 1;
                        writeDesc(ch, 1, true);
                        -- Pointer bits 5 to 0 set in CURDESC and in the tail pointer
                        start(ch, descAddr(ch, 0) or x"0000000000000015");
                        tail(ch, descAddr(ch, 2) or x"000000000000002A");
                        waitIdle(ch, "chain of three");
                        waitCmds(ch, 3, "chain of three");
                        cycles(20);
                        check_value(Obs.ArCount - ArBase_v, 3, ERROR, "three fetches, none beyond the tail");

                        for i in 0 to 2 loop
                            checkFetch(i, ch, i, "chain of three");
                            checkCmd(ch, i, i, "chain of three");
                            checkDesc(ch, i, true, statusExp(ch, D_v(ch)(i).Len, '1', '1', ErrNone_c), "chain of three");
                        end loop;

                    end if;
                end loop;

            elsif run("test_status") then
                log(ID_LOG_HDR, "TC-SG-02 status update");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        chain(ch, 4, 2);
                        if ch = S2mm_c then
                            -- Every combination of RXSOF and RXEOF; a buffer that received no byte while running
                            Cfg(ch).Results(CmdBase_v(ch) + 0) <= (true, 10, '1', '0', ErrNone_c);
                            Cfg(ch).Results(CmdBase_v(ch) + 1) <= (true, D_v(ch)(1).Len, '0', '0', ErrNone_c);
                            Cfg(ch).Results(CmdBase_v(ch) + 2) <= (true, 5, '0', '1', ErrNone_c);
                            Cfg(ch).Results(CmdBase_v(ch) + 3) <= (true, 0, '0', '0', ErrNone_c);
                        end if;
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 3));
                        waitIdle(ch, "status update");
                        check_value(Obs.AwCount - AwBase_v, 4, ERROR, "one status write per descriptor");
                        check_value(Obs.WCount - WBase_v, 4, ERROR, "one beat per status write");

                        for i in 0 to 3 loop
                            K_v := AwBase_v + i;
                            check_value(Obs.Aws(K_v).Addr, std_logic_vector(unsigned(descAddr(ch, i)) + 16#1C#), ERROR,
                                        "status write at offset 0x1C", C_TB_SCOPE_DEFAULT, HEX);
                            check_value(Obs.Aws(K_v).Len, 1, ERROR, "one beat");
                            check_value(Obs.Aws(K_v).Size, std_logic_vector'("010"), ERROR, "4 bytes");
                            check_value(Obs.Aws(K_v).Burst, std_logic_vector'("01"), ERROR, "INCR burst");
                            check_value(Obs.Aws(K_v).Lock, '0', ERROR, "AwLock");
                            check_value(Obs.Aws(K_v).Cache, std_logic_vector'("0011"), ERROR, "AwCache");
                            check_value(Obs.Aws(K_v).Prot, std_logic_vector'("000"), ERROR, "AwProt");
                            check_value(Obs.Ws(WBase_v + i).Strb, std_logic_vector'("1111"), ERROR, "all strobes");
                            check_value(Obs.Ws(WBase_v + i).Last, '1', ERROR, "WLast");
                        end loop;

                        if ch = Mm2s_c then

                            for i in 0 to 3 loop
                                checkDesc(ch, i, true, statusExp(ch, D_v(ch)(i).Len, '0', '0', ErrNone_c), "MM2S status");
                            end loop;

                        else
                            checkDesc(ch, 0, true, statusExp(ch, 10, '1', '0', ErrNone_c), "S2MM status, RXSOF");
                            checkDesc(ch, 1, true, statusExp(ch, D_v(ch)(1).Len, '0', '0', ErrNone_c), "S2MM status, full");
                            checkDesc(ch, 2, true, statusExp(ch, 5, '0', '1', ErrNone_c), "S2MM status, RXEOF");
                            checkDesc(ch, 3, true, statusExp(ch, 0, '0', '0', ErrNone_c), "S2MM status, no byte");
                        end if;
                    end if;
                end loop;

            elsif run("test_tail") then
                log(ID_LOG_HDR, "TC-SG-03 tail pointer");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        chain(ch, 10);
                        Cfg(ch).ResDelay <= 30;
                        -- No fetch before the first tail pointer write after the start
                        start(ch, descAddr(ch, 0));
                        cycles(50);
                        check_value(Obs.ArCount - ArBase_v, 0, ERROR, "no fetch before the first tail pointer write");
                        check_value(Obs.Idle(ch), '0', ERROR, "not idle before the first tail pointer write");
                        -- Up to the tail, then idle once its status is written
                        tail(ch, descAddr(ch, 2));
                        waitIdle(ch, "tail D2");
                        check_value(Obs.BCount - BBase_v, 3, ERROR, "idle after the status write of the tail");
                        cycles(30);
                        check_value(Obs.ArCount - ArBase_v, 3, ERROR, "no fetch beyond the tail");
                        check_value(Obs.CurPtr(ch), descAddr(ch, 2), ERROR, "CURDESC at the tail", C_TB_SCOPE_DEFAULT, HEX);
                        -- The tail fetched but not completed: a new tail continues the chain
                        Cfg(ch).Hold <= '1';
                        tail(ch, descAddr(ch, 3));
                        waitCmds(ch, 4, "tail D3");
                        cycles(20);
                        tail(ch, descAddr(ch, 4));
                        cycles(5);
                        Cfg(ch).Hold <= '0';
                        waitIdle(ch, "tail D4");
                        waitFetches(5, "tail D4");
                        check_value(Obs.CurPtr(ch), descAddr(ch, 4), ERROR, "CURDESC at D4", C_TB_SCOPE_DEFAULT, HEX);
                        -- A tail pointer write before the tail is reached only moves the pause point
                        Cfg(ch).Hold <= '1';
                        tail(ch, descAddr(ch, 7));
                        waitFetches(7, "D5 and D6 fetched, D7 not yet");
                        cycles(30);
                        check_value(Obs.ArCount - ArBase_v, 7, ERROR, "the window holds two descriptors");
                        tail(ch, descAddr(ch, 9));
                        Cfg(ch).Hold <= '0';
                        waitFetches(10, "tail D9");
                        waitIdle(ch, "tail D9");
                        cycles(30);
                        check_value(Obs.ArCount - ArBase_v, 10, ERROR, "paused at D9, not at D7");
                        check_value(Obs.CurPtr(ch), descAddr(ch, 9), ERROR, "CURDESC at D9", C_TB_SCOPE_DEFAULT, HEX);

                        -- A tail pointer write at idle, also with the same value, restarts at the NXTDESC of the tail
                        for i in 0 to 9 loop
                            rearm(ch, i);
                        end loop;

                        tail(ch, descAddr(ch, 9));
                        waitFetches(11, "restart");
                        check_value(Obs.Ars(ArBase_v + 10).Addr, descAddr(ch, 0), ERROR, "restart at the NXTDESC of the tail",
                                    C_TB_SCOPE_DEFAULT, HEX);
                        cycles(10);
                        waitIdle(ch, "second lap");
                        waitFetches(20, "second lap");
                        waitCmds(ch, 20, "second lap");

                        for k in 0 to 19 loop
                            checkCmd(ch, k, k mod 10, "chain in order");
                        end loop;

                    end if;
                end loop;

            elsif run("test_prefetch") then
                log(ID_LOG_HDR, "TC-SG-04 one descriptor ahead");

                if IncludeMm2s_g then
                    resetAll;
                    chain(Mm2s_c, 5);
                    Cfg(Mm2s_c).Hold     <= '1';
                    Cfg(Mm2s_c).ResDelay <= 200;
                    start(Mm2s_c, descAddr(Mm2s_c, 0));
                    tail(Mm2s_c, descAddr(Mm2s_c, 4));
                    -- D1 is fetched and issued while D0 is in progress, D2 not before the result of D0
                    waitCmds(Mm2s_c, 2, "MM2S D0 and D1 issued");
                    cycles(100);
                    check_value(Obs.ArCount - ArBase_v, 2, ERROR, "MM2S: no fetch of D2 while D0 and D1 are in progress");
                    check_value(Obs.CmdCount(Mm2s_c) - CmdBase_v(Mm2s_c), 2, ERROR, "MM2S: two commands");
                    Cfg(Mm2s_c).Hold <= '0';
                    waitRes(Mm2s_c, 1, "MM2S result of D0");
                    Cfg(Mm2s_c).Hold <= '1';
                    waitCmds(Mm2s_c, 3, "MM2S D2 issued after the result of D0");
                    cycles(100);
                    check_value(Obs.ArCount - ArBase_v, 3, ERROR, "MM2S: D2 fetched after the result of D0, D3 not");
                    Cfg(Mm2s_c).Hold <= '0';
                    waitIdle(Mm2s_c, "MM2S chain");
                    cycles(20);
                    check_value(Obs.ArCount - ArBase_v, 5, ERROR, "MM2S: no fetch beyond the tail");
                end if;

                if IncludeS2mm_g then
                    resetAll;
                    chain(S2mm_c, 4);
                    Cfg(S2mm_c).Hold <= '1';
                    start(S2mm_c, descAddr(S2mm_c, 0));
                    tail(S2mm_c, descAddr(S2mm_c, 3));
                    -- D1 is fetched while D0 is in progress and waits for the channel
                    waitFetches(2, "S2MM D0 and D1 fetched");
                    cycles(100);
                    check_value(Obs.ArCount - ArBase_v, 2, ERROR, "S2MM: two descriptors in the window");
                    check_value(Obs.CmdCount(S2mm_c) - CmdBase_v(S2mm_c), 1, ERROR, "S2MM: one command");
                    Cfg(S2mm_c).Hold <= '0';
                    waitIdle(S2mm_c, "S2MM chain");
                    cycles(20);
                    check_value(Obs.ArCount - ArBase_v, 4, ERROR, "S2MM: no fetch beyond the tail");
                end if;

            elsif run("test_curdesc") then
                log(ID_LOG_HDR, "TC-SG-05 current descriptor pointer");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        chain(ch, 4);
                        Cfg(ch).Hold     <= '1';
                        Cfg(ch).ResDelay <= 100;
                        start(ch, descAddr(ch, 0) or x"000000000000003F");
                        cycles(5);
                        check_value(Obs.CurPtr(ch), descAddr(ch, 0), ERROR, "CURDESC after the start, bits 5 to 0 zero",
                                    C_TB_SCOPE_DEFAULT, HEX);
                        tail(ch, descAddr(ch, 3));
                        waitCmds(ch, 1, "D0 in progress");
                        cycles(10);
                        check_value(Obs.CurPtr(ch), descAddr(ch, 0), ERROR, "CURDESC: the transfer in progress",
                                    C_TB_SCOPE_DEFAULT, HEX);
                        -- MM2S has issued D1 already; D2 shall wait for the channel after it is fetched
                        if ch = Mm2s_c then
                            waitCmds(ch, 2, "MM2S D1 issued");
                            Cfg(ch).CmdDelay <= 100000;
                        end if;
                        Cfg(ch).Hold <= '0';
                        waitRes(ch, 1, "result of D0");
                        Cfg(ch).Hold <= '1';
                        waitCmds(ch, 2, "D1 in progress");
                        cycles(10);
                        check_value(Obs.CurPtr(ch), descAddr(ch, 1), ERROR, "CURDESC: the oldest transfer in progress",
                                    C_TB_SCOPE_DEFAULT, HEX);
                        -- Between transfers: the next descriptor to be processed
                        Cfg(ch).CmdDelay <= 100000;
                        Cfg(ch).Hold     <= '0';
                        waitRes(ch, 2, "result of D1");
                        waitFetches(3, "D2 fetched");
                        cycles(40);
                        check_value(Obs.CmdCount(ch) - CmdBase_v(ch), 2, ERROR, "D2 waits for the channel");
                        check_value(Obs.CurPtr(ch), descAddr(ch, 2), ERROR, "CURDESC: the next descriptor",
                                    C_TB_SCOPE_DEFAULT, HEX);
                        Cfg(ch).CmdDelay <= 0;
                        waitIdle(ch, "chain");
                        check_value(Obs.CurPtr(ch), descAddr(ch, 3), ERROR, "CURDESC: the tail after it is completed",
                                    C_TB_SCOPE_DEFAULT, HEX);
                    end if;
                end loop;

            elsif run("test_packet_events") then
                log(ID_LOG_HDR, "TC-SG-06 packet events after the status write");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        Mem_v.setLatency(MemSg_c, 50);
                        chain(ch, 6);

                        -- Packets of one, two and three descriptors: the ends at D0, D2 and D5
                        for i in 0 to 5 loop
                            D_v(ch)(i).Sof := '1' when i = 0 or i = 1 or i = 3 else '0';
                            D_v(ch)(i).Eof := '1' when i = 0 or i = 2 or i = 5 else '0';
                            writeDesc(ch, i, true);
                            if ch = S2mm_c then
                                Cfg(ch).Results(CmdBase_v(ch) + i) <= (true, -1, D_v(ch)(i).Sof, D_v(ch)(i).Eof, ErrNone_c);
                            end if;
                        end loop;

                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 5));
                        waitIdle(ch, "three packets");
                        check_value(Obs.PktCount(ch) - PktBase_v(ch), 3, ERROR, "one event per packet");
                        -- Each event follows the write response of the status of the descriptor with the end of packet
                        check_value(Obs.PktCycles(ch)(PktBase_v(ch) + 0).Cycle > Obs.Bs(BBase_v + 0), ERROR,
                                    "packet 1 after the status write of D0");
                        check_value(Obs.PktCycles(ch)(PktBase_v(ch) + 1).Cycle > Obs.Bs(BBase_v + 2), ERROR,
                                    "packet 2 after the status write of D2");
                        check_value(Obs.PktCycles(ch)(PktBase_v(ch) + 2).Cycle > Obs.Bs(BBase_v + 5), ERROR,
                                    "packet 3 after the status write of D5");
                        check_value(Obs.PktCycles(ch)(PktBase_v(ch) + 1).Cycle < Obs.Bs(BBase_v + 3), ERROR,
                                    "packet 2 before the status write of D3");
                    end if;
                end loop;

                -- No event for a packet whose transfer failed
                if IncludeS2mm_g then
                    resetAll;
                    chain(S2mm_c, 2);
                    Cfg(S2mm_c).Results(CmdBase_v(S2mm_c) + 0) <= (true, 4, '1', '1', ErrSlv_c);
                    start(S2mm_c, descAddr(S2mm_c, 0));
                    tail(S2mm_c, descAddr(S2mm_c, 1));
                    waitErrs(S2mm_c, 1, "transfer error");
                    halt(S2mm_c, "transfer error");
                    check_value(Obs.PktCount(S2mm_c) - PktBase_v(S2mm_c), 0, ERROR, "no packet event for a failed packet");
                end if;

            elsif run("test_stale") then
                log(ID_LOG_HDR, "TC-SG-07 stale descriptor");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        chain(ch, 5);
                        D_v(ch)(2).Cmplt := '1';
                        writeDesc(ch, 2, true);
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 4));
                        waitErrs(ch, 1, "stale D2");
                        -- The register interface lowers Run after an error
                        halt(ch, "stale D2");
                        check_value(Obs.Errs(ch)(ErrBase_v(ch)).Sg, ErrInt_c, ERROR, "SGIntErr");
                        check_value(Obs.Errs(ch)(ErrBase_v(ch)).Xfer, ErrNone_c, ERROR, "no transfer error");
                        check_value(Obs.CmdCount(ch) - CmdBase_v(ch), 2, ERROR, "D2 not issued");
                        check_value(Obs.ArCount - ArBase_v, 3, ERROR, "no fetch after the stale descriptor");
                        checkDesc(ch, 0, true, statusExp(ch, D_v(ch)(0).Len, '1', '1', ErrNone_c), "stale D2");
                        checkDesc(ch, 1, true, statusExp(ch, D_v(ch)(1).Len, '1', '1', ErrNone_c), "stale D2");
                        checkDesc(ch, 2, false, Img_v(ch)(2)(7), "stale D2 not written");
                        check_value(Obs.CurPtr(ch), descAddr(ch, 2), ERROR, "CURDESC at the stale descriptor",
                                    C_TB_SCOPE_DEFAULT, HEX);
                        -- Cyclic mode ignores the completed bit
                        resetAll;
                        chain(ch, 5);
                        D_v(ch)(2).Cmplt := '1';
                        writeDesc(ch, 2, true);
                        Reg(ch).Cyclic   <= '1';
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 4));
                        waitCmds(ch, 7, "cyclic mode");
                        halt(ch, "cyclic mode");
                        check_value(Obs.ErrCount(ch) - ErrBase_v(ch), 0, ERROR, "no error in cyclic mode");
                    end if;
                end loop;

            elsif run("test_transfer_errors") then
                log(ID_LOG_HDR, "TC-SG-08 transfer errors");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then

                        for e in 1 to 3 loop
                            -- D1 fails: a buffer length of 0 (internal error), the slave error, the decode error
                            resetAll;
                            chain(ch, 4);
                            if e = 1 then
                                D_v(ch)(1).Len := 0;
                                writeDesc(ch, 1, true);
                                Exp_v          := statusExp(ch, 0, '0', '0', ErrInt_c);
                            else
                                Cfg(ch).Results(CmdBase_v(ch) + 1) <= (true, 33, '1', '0', std_logic_vector(to_unsigned(e, 2)));
                                Exp_v                              := statusExp(ch, 33, '1', '0', std_logic_vector(to_unsigned(e, 2)));
                            end if;
                            start(ch, descAddr(ch, 0));
                            tail(ch, descAddr(ch, 3));
                            waitErrs(ch, 1, "error of D1");
                            halt(ch, "error of D1");
                            check_value(Obs.Errs(ch)(ErrBase_v(ch)).Xfer, std_logic_vector(to_unsigned(e, 2)), ERROR,
                                        "transfer error code");
                            check_value(Obs.Errs(ch)(ErrBase_v(ch)).Sg, ErrNone_c, ERROR, "no engine error");
                            check_value(Obs.Errs(ch)(ErrBase_v(ch)).Cycle > Obs.Bs(BBase_v + 1), ERROR,
                                        "error event after the status write of D1");
                            checkDesc(ch, 0, true, statusExp(ch, D_v(ch)(0).Len, '1', '1', ErrNone_c), "error of D1");
                            checkDesc(ch, 1, true, Exp_v, "status of the failed descriptor");
                            check_value(Obs.CmdCount(ch) - CmdBase_v(ch), 2, ERROR, "no command after the error");
                            checkDesc(ch, 2, false, Img_v(ch)(2)(7), "D2 not started");
                            check_value(Obs.CurPtr(ch), descAddr(ch, 1), ERROR, "CURDESC at the failed descriptor",
                                        C_TB_SCOPE_DEFAULT, HEX);
                        end loop;

                    end if;
                end loop;

                -- MM2S: a command issued before the error result completes and is written (interpretation SGI-08)
                if IncludeMm2s_g then
                    resetAll;
                    chain(Mm2s_c, 4);
                    Cfg(Mm2s_c).ResDelay                       <= 80;
                    Cfg(Mm2s_c).Results(CmdBase_v(Mm2s_c) + 1) <= (true, 33, '1', '1', ErrSlv_c);
                    start(Mm2s_c, descAddr(Mm2s_c, 0));
                    tail(Mm2s_c, descAddr(Mm2s_c, 3));
                    waitErrs(Mm2s_c, 1, "error of D1, D2 in progress");
                    halt(Mm2s_c, "error of D1, D2 in progress");
                    check_value(Obs.CmdCount(Mm2s_c) - CmdBase_v(Mm2s_c), 3, ERROR, "D2 issued before the error");
                    checkDesc(Mm2s_c, 1, true, statusExp(Mm2s_c, 33, '1', '1', ErrSlv_c), "status of D1");
                    checkDesc(Mm2s_c, 2, true, statusExp(Mm2s_c, D_v(Mm2s_c)(2).Len, '1', '1', ErrNone_c),
                              "D2 completed after the error");
                    check_value(Obs.CurPtr(Mm2s_c), descAddr(Mm2s_c, 1), ERROR, "CURDESC at the first error",
                                C_TB_SCOPE_DEFAULT, HEX);
                end if;

                -- A fetched descriptor waits for the channel when the result of D1 fails (one command at a time, results
                -- 80 clock cycles after the command): it is not issued and keeps its status, CURDESC at D1
                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        chain(ch, 4);
                        Cfg(ch).ResDelay                   <= 80;
                        Cfg(ch).MaxCmds                    <= 1;
                        Cfg(ch).Results(CmdBase_v(ch) + 1) <= (true, 33, '1', '0', ErrSlv_c);
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 3));
                        waitErrs(ch, 1, "error of D1 with D2 fetched");
                        halt(ch, "error of D1 with D2 fetched");
                        check_value(Obs.ArCount - ArBase_v >= 3, ERROR, "D2 fetched before the error");
                        check_value(Obs.CmdCount(ch) - CmdBase_v(ch), 2, ERROR, "the fetched D2 not issued after the error");
                        checkDesc(ch, 1, true, statusExp(ch, 33, '1', '0', ErrSlv_c), "status of D1");
                        checkDesc(ch, 2, false, Img_v(ch)(2)(7), "the fetched D2 keeps its status");
                        check_value(Obs.CurPtr(ch), descAddr(ch, 1), ERROR, "CURDESC at D1 with D2 fetched",
                                    C_TB_SCOPE_DEFAULT, HEX);
                    end if;
                end loop;

            elsif run("test_error_codes") then
                log(ID_LOG_HDR, "TC-SG-18 error codes of descriptor accesses");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then

                        -- EXOKAY ("01", not the internal error code; interpretation I14), SLVERR, DECERR
                        for e in 1 to 3 loop
                            ExpErr_v := ErrSlv_c;
                            if e = 3 then
                                ExpErr_v := ErrDec_c;
                            end if;
                            -- The fetch of D1
                            resetAll;
                            chain(ch, 4);
                            Mem_v.setError(MemSg_c, 0, unsigned(descAddr(ch, 1)), unsigned(descAddr(ch, 1)) + 31,
                                           std_logic_vector(to_unsigned(e, 2)), TbDirRead);
                            start(ch, descAddr(ch, 0));
                            tail(ch, descAddr(ch, 3));
                            waitErrs(ch, 1, "fetch error");
                            halt(ch, "fetch error");
                            check_value(Obs.Errs(ch)(ErrBase_v(ch)).Sg, ExpErr_v, ERROR, "engine error of the fetch");
                            check_value(Obs.Errs(ch)(ErrBase_v(ch)).Xfer, ErrNone_c, ERROR, "no transfer error");
                            -- The status write of D0
                            resetAll;
                            chain(ch, 4);
                            Mem_v.setError(MemSg_c, 0, unsigned(descAddr(ch, 0)) + 28, unsigned(descAddr(ch, 0)) + 31,
                                           std_logic_vector(to_unsigned(e, 2)), TbDirWrite);
                            start(ch, descAddr(ch, 0));
                            tail(ch, descAddr(ch, 3));
                            waitErrs(ch, 1, "status write error");
                            halt(ch, "status write error");
                            check_value(Obs.Errs(ch)(ErrBase_v(ch)).Sg, ExpErr_v, ERROR,
                                        "engine error of the status write");
                            check_value(Obs.Errs(ch)(ErrBase_v(ch)).Xfer, ErrNone_c, ERROR, "no transfer error");
                        end loop;

                    end if;
                end loop;

            elsif run("test_descriptor_errors") then
                log(ID_LOG_HDR, "TC-SG-09 errors of descriptor accesses");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then

                        for e in 2 to 3 loop
                            -- Fetch of D1 with SLVERR, then DECERR
                            resetAll;
                            chain(ch, 4);
                            Mem_v.setError(MemSg_c, 0, unsigned(descAddr(ch, 1)), unsigned(descAddr(ch, 1)) + 31,
                                           std_logic_vector(to_unsigned(e, 2)), TbDirRead);
                            start(ch, descAddr(ch, 0));
                            tail(ch, descAddr(ch, 3));
                            waitErrs(ch, 1, "fetch error");
                            halt(ch, "fetch error");
                            -- SLVERR gives the slave, DECERR the decode error (SG-ER-04)
                            check_value(Obs.Errs(ch)(ErrBase_v(ch)).Sg, std_logic_vector(to_unsigned(e, 2)), ERROR,
                                        "engine error of the fetch");
                            check_value(Obs.Errs(ch)(ErrBase_v(ch)).Xfer, ErrNone_c, ERROR, "no transfer error");
                            check_value(Obs.CmdCount(ch) - CmdBase_v(ch), 1, ERROR, "nothing issued from the failed fetch");
                            checkDesc(ch, 0, true, statusExp(ch, D_v(ch)(0).Len, '1', '1', ErrNone_c), "fetch error");
                            checkDesc(ch, 1, false, Img_v(ch)(1)(7), "fetch error");
                            check_value(Obs.CurPtr(ch), descAddr(ch, 1), ERROR, "CURDESC at the failed fetch",
                                        C_TB_SCOPE_DEFAULT, HEX);
                        end loop;

                        -- Status write of D0 with SLVERR
                        resetAll;
                        chain(ch, 4);
                        Mem_v.setError(MemSg_c, 0, unsigned(descAddr(ch, 0)) + 28, unsigned(descAddr(ch, 0)) + 31, "10",
                                       TbDirWrite);
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 3));
                        waitErrs(ch, 1, "status write error");
                        halt(ch, "status write error");
                        check_value(Obs.Errs(ch)(ErrBase_v(ch)).Sg, ErrSlv_c, ERROR, "engine error of the status write");
                        check_value(Obs.Errs(ch)(ErrBase_v(ch)).Xfer, ErrNone_c, ERROR, "no transfer error");
                        check_value(Obs.CmdCount(ch) - CmdBase_v(ch) <= 2, ERROR, "no command after the error");
                        check_value(Obs.PktCount(ch) - PktBase_v(ch) <= 1, ERROR, "no packet event for D0");
                        check_value(Obs.CurPtr(ch), descAddr(ch, 0), ERROR, "CURDESC at the failed status write",
                                    C_TB_SCOPE_DEFAULT, HEX);
                        -- A transfer error whose status write fails: one event with both codes
                        resetAll;
                        chain(ch, 4);
                        Mem_v.setError(MemSg_c, 0, unsigned(descAddr(ch, 0)) + 28, unsigned(descAddr(ch, 0)) + 31, "10",
                                       TbDirWrite);
                        Cfg(ch).Results(CmdBase_v(ch) + 0) <= (true, 12, '1', '1', ErrDec_c);
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 3));
                        waitErrs(ch, 1, "transfer and status write error");
                        halt(ch, "transfer and status write error");
                        check_value(Obs.Errs(ch)(ErrBase_v(ch)).Xfer, ErrDec_c, ERROR, "transfer error in the event");
                        check_value(Obs.Errs(ch)(ErrBase_v(ch)).Sg, ErrSlv_c, ERROR, "engine error in the same event");
                        -- A fetch error while the channel stops at a transfer error: the fetch of D2 is in flight
                        -- (memory latency 100 clock cycles) when the result of D1 fails, then it gets DECERR. Both
                        -- events, nothing issued after D1, CURDESC at D1, the descriptor of the first error (SG-FE-07)
                        resetAll;
                        chain(ch, 4);
                        Mem_v.setLatency(MemSg_c, 100);
                        Mem_v.setError(MemSg_c, 0, unsigned(descAddr(ch, 2)), unsigned(descAddr(ch, 2)) + 31, ErrDec_c,
                                       TbDirRead);
                        Cfg(ch).Results(CmdBase_v(ch) + 1) <= (true, 33, '1', '0', ErrSlv_c);
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 3));
                        waitErrs(ch, 2, "transfer error of D1, fetch error of D2");
                        halt(ch, "transfer error of D1, fetch error of D2");
                        check_value(Obs.ArCount - ArBase_v, 3, ERROR, "D2 fetched");
                        check_value(Obs.CmdCount(ch) - CmdBase_v(ch), 2, ERROR, "no command after the error of D1");
                        check_value((Obs.Errs(ch)(ErrBase_v(ch)).Xfer = ErrSlv_c and Obs.Errs(ch)(ErrBase_v(ch)).Sg = ErrNone_c and
                                     Obs.Errs(ch)(ErrBase_v(ch) + 1).Xfer = ErrNone_c and
                                     Obs.Errs(ch)(ErrBase_v(ch) + 1).Sg = ErrDec_c) or
                                    (Obs.Errs(ch)(ErrBase_v(ch)).Xfer = ErrNone_c and Obs.Errs(ch)(ErrBase_v(ch)).Sg = ErrDec_c and
                                     Obs.Errs(ch)(ErrBase_v(ch) + 1).Xfer = ErrSlv_c and
                                     Obs.Errs(ch)(ErrBase_v(ch) + 1).Sg = ErrNone_c), ERROR,
                                    "one event with the transfer error of D1, one with the engine error of the fetch of D2");
                        checkDesc(ch, 1, true, statusExp(ch, 33, '1', '0', ErrSlv_c), "status of D1");
                        checkDesc(ch, 2, false, Img_v(ch)(2)(7), "D2 not processed");
                        check_value(Obs.CurPtr(ch), descAddr(ch, 1), ERROR, "CURDESC at D1, the first error",
                                    C_TB_SCOPE_DEFAULT, HEX);
                    end if;
                end loop;

            elsif run("test_channels") then
                log(ID_LOG_HDR, "TC-SG-10 both channels");
                -- The fetches and the status writes alternate while both channels request
                resetAll;
                chain(Mm2s_c, 6);
                chain(S2mm_c, 6);
                Cfg(Mm2s_c).Hold   <= '1';
                Cfg(S2mm_c).Hold   <= '1';
                start(Mm2s_c, descAddr(Mm2s_c, 0));
                start(S2mm_c, descAddr(S2mm_c, 0));
                wait until rising_edge(Clk);
                Reg(Mm2s_c).Tail   <= descAddr(Mm2s_c, 5);
                Reg(S2mm_c).Tail   <= descAddr(S2mm_c, 5);
                Reg(Mm2s_c).TailWr <= '1';
                Reg(S2mm_c).TailWr <= '1';
                wait until rising_edge(Clk);
                Reg(Mm2s_c).TailWr <= '0';
                Reg(S2mm_c).TailWr <= '0';
                waitFetches(4, "first fetches of both channels");
                checkFetch(0, Mm2s_c, 0, "round robin");
                checkFetch(1, S2mm_c, 0, "round robin");
                checkFetch(2, Mm2s_c, 1, "round robin");
                checkFetch(3, S2mm_c, 1, "round robin");
                Cfg(Mm2s_c).Hold   <= '0';
                Cfg(S2mm_c).Hold   <= '0';
                waitIdle(Mm2s_c, "both channels");
                waitIdle(S2mm_c, "both channels");
                check_value(Obs.Aws(AwBase_v).Addr, std_logic_vector(unsigned(descAddr(Mm2s_c, 0)) + 16#1C#), ERROR,
                            "round robin: first status write MM2S", C_TB_SCOPE_DEFAULT, HEX);
                check_value(Obs.Aws(AwBase_v + 1).Addr, std_logic_vector(unsigned(descAddr(S2mm_c, 0)) + 16#1C#), ERROR,
                            "round robin: second status write S2MM", C_TB_SCOPE_DEFAULT, HEX);

                for i in 0 to 5 loop
                    checkDesc(Mm2s_c, i, true, statusExp(Mm2s_c, D_v(Mm2s_c)(i).Len, '1', '1', ErrNone_c), "MM2S");
                    checkDesc(S2mm_c, i, true, statusExp(S2mm_c, D_v(S2mm_c)(i).Len, '1', '1', ErrNone_c), "S2MM");
                end loop;

                -- An error of one channel does not stop the other
                resetAll;
                chain(Mm2s_c, 6);
                chain(S2mm_c, 6);
                D_v(Mm2s_c)(3).Cmplt := '1';
                writeDesc(Mm2s_c, 3, true);
                start(Mm2s_c, descAddr(Mm2s_c, 0));
                start(S2mm_c, descAddr(S2mm_c, 0));
                tail(Mm2s_c, descAddr(Mm2s_c, 5));
                tail(S2mm_c, descAddr(S2mm_c, 5));
                waitErrs(Mm2s_c, 1, "stale MM2S descriptor");
                halt(Mm2s_c, "stale MM2S descriptor");
                waitIdle(S2mm_c, "S2MM continues");
                check_value(Obs.CmdCount(S2mm_c) - CmdBase_v(S2mm_c), 6, ERROR, "S2MM chain complete");
                check_value(Obs.CmdCount(Mm2s_c) - CmdBase_v(Mm2s_c), 3, ERROR, "MM2S stopped at the stale descriptor");
                check_value(Obs.ErrCount(S2mm_c) - ErrBase_v(S2mm_c), 0, ERROR, "no S2MM error");

            elsif run("test_halt") then
                log(ID_LOG_HDR, "TC-SG-11 halt");

                if IncludeMm2s_g then
                    -- Two commands issued: both complete and are written, nothing further is fetched or issued
                    resetAll;
                    chain(Mm2s_c, 6);
                    Cfg(Mm2s_c).Hold <= '1';
                    start(Mm2s_c, descAddr(Mm2s_c, 0));
                    tail(Mm2s_c, descAddr(Mm2s_c, 5));
                    waitCmds(Mm2s_c, 2, "MM2S D0 and D1 issued");
                    cycles(20);
                    wait until rising_edge(Clk);
                    Reg(Mm2s_c).Run  <= '0';
                    cycles(50);
                    check_value(Obs.Stopped(Mm2s_c), '0', ERROR, "MM2S not stopped while commands are outstanding");
                    Cfg(Mm2s_c).Hold <= '0';
                    waitStopped(Mm2s_c, "MM2S halt");
                    check_value(Obs.CmdCount(Mm2s_c) - CmdBase_v(Mm2s_c), 2, ERROR, "no command after the halt");
                    check_value(Obs.ArCount - ArBase_v, 2, ERROR, "no fetch after the halt");
                    checkDesc(Mm2s_c, 0, true, statusExp(Mm2s_c, D_v(Mm2s_c)(0).Len, '1', '1', ErrNone_c), "MM2S halt");
                    checkDesc(Mm2s_c, 1, true, statusExp(Mm2s_c, D_v(Mm2s_c)(1).Len, '1', '1', ErrNone_c), "MM2S halt");
                    check_value(Obs.CurPtr(Mm2s_c), descAddr(Mm2s_c, 2), ERROR, "CURDESC at the first descriptor not started",
                                C_TB_SCOPE_DEFAULT, HEX);
                    -- A fetched descriptor that was not issued keeps its status; the restart continues there
                    resetAll;
                    chain(Mm2s_c, 6);
                    Cfg(Mm2s_c).Hold    <= '1';
                    Cfg(Mm2s_c).MaxCmds <= 1;
                    start(Mm2s_c, descAddr(Mm2s_c, 0));
                    tail(Mm2s_c, descAddr(Mm2s_c, 5));
                    waitCmds(Mm2s_c, 1, "MM2S D0 issued");
                    waitFetches(2, "MM2S D1 fetched");
                    wait until rising_edge(Clk);
                    Reg(Mm2s_c).Run     <= '0';
                    Cfg(Mm2s_c).Hold    <= '0';
                    waitStopped(Mm2s_c, "MM2S halt with a fetched descriptor");
                    checkDesc(Mm2s_c, 1, false, Img_v(Mm2s_c)(1)(7), "fetched descriptor keeps its status");
                    check_value(Obs.CurPtr(Mm2s_c), descAddr(Mm2s_c, 1), ERROR, "CURDESC at the fetched descriptor",
                                C_TB_SCOPE_DEFAULT, HEX);
                    Cfg(Mm2s_c).MaxCmds <= 8;
                    start(Mm2s_c, Obs.CurPtr(Mm2s_c));
                    tail(Mm2s_c, descAddr(Mm2s_c, 5));
                    waitIdle(Mm2s_c, "MM2S restart");
                    waitCmds(Mm2s_c, 6, "MM2S restart");

                    for k in 0 to 5 loop
                        checkCmd(Mm2s_c, k, k, "MM2S restart");
                    end loop;

                end if;

                if IncludeS2mm_g then
                    -- Halt before any byte arrived: the descriptor is not started
                    resetAll;
                    chain(S2mm_c, 3);
                    Cfg(S2mm_c).Hold <= '1';
                    start(S2mm_c, descAddr(S2mm_c, 0));
                    tail(S2mm_c, descAddr(S2mm_c, 2));
                    waitCmds(S2mm_c, 1, "S2MM D0 issued");
                    halt(S2mm_c, "S2MM halt before any byte");
                    check_value(Obs.AwCount - AwBase_v, 0, ERROR, "no status write for a descriptor not started");
                    checkDesc(S2mm_c, 0, false, Img_v(S2mm_c)(0)(7), "not started");
                    check_value(Obs.CurPtr(S2mm_c), descAddr(S2mm_c, 0), ERROR, "CURDESC at the descriptor not started",
                                C_TB_SCOPE_DEFAULT, HEX);
                    -- Halt inside a packet: the bytes written, RXSOF, no RXEOF, Cmplt (interpretation SGI-11)
                    resetAll;
                    chain(S2mm_c, 3);
                    Cfg(S2mm_c).Hold      <= '1';
                    Cfg(S2mm_c).HaltBytes <= 20;
                    start(S2mm_c, descAddr(S2mm_c, 0));
                    tail(S2mm_c, descAddr(S2mm_c, 2));
                    waitCmds(S2mm_c, 1, "S2MM D0 issued");
                    waitFetches(2, "S2MM D1 fetched");
                    halt(S2mm_c, "S2MM halt inside a packet");
                    checkDesc(S2mm_c, 0, true, statusExp(S2mm_c, 20, '1', '0', ErrNone_c), "halt inside a packet");
                    checkDesc(S2mm_c, 1, false, Img_v(S2mm_c)(1)(7), "fetched descriptor keeps its status");
                    check_value(Obs.CurPtr(S2mm_c), descAddr(S2mm_c, 1), ERROR, "CURDESC at the next descriptor",
                                C_TB_SCOPE_DEFAULT, HEX);
                end if;

                -- A fetch outstanding at the halt completes without a command
                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        chain(ch, 4);
                        Mem_v.setLatency(MemSg_c, 60);
                        Cfg(ch).Hold    <= '1';
                        Cfg(ch).MaxCmds <= 1;
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 3));
                        waitFetches(2, "fetch of D1 started");
                        wait until rising_edge(Clk);
                        Reg(ch).Run     <= '0';
                        Cfg(ch).Hold    <= '0';
                        waitStopped(ch, "halt with a fetch outstanding");
                        check_value(Obs.CmdCount(ch) - CmdBase_v(ch), 1, ERROR, "the fetched descriptor is not issued");
                        check_value(Obs.ArCount - ArBase_v, 2, ERROR, "no further fetch");
                        check_value(Obs.CurPtr(ch), descAddr(ch, 1), ERROR, "CURDESC at the fetched descriptor",
                                    C_TB_SCOPE_DEFAULT, HEX);
                    end if;
                end loop;

                -- Both channels: Run of S2MM falls while its fetch waits for the descriptor port, which serves the fetch
                -- of MM2S (memory latency 200 clock cycles): the request is withdrawn, nothing is fetched or issued for
                -- S2MM, and MM2S completes its chain
                if IncludeMm2s_g and IncludeS2mm_g then
                    resetAll;
                    chain(Mm2s_c, 4);
                    chain(S2mm_c, 4);
                    Mem_v.setLatency(MemSg_c, 200);
                    start(Mm2s_c, descAddr(Mm2s_c, 0));
                    tail(Mm2s_c, descAddr(Mm2s_c, 3));
                    odmaWaitAtLeast(Obs.ArCount, ArBase_v + 1, 10 us, "fetch of MM2S D0");
                    start(S2mm_c, descAddr(S2mm_c, 0));
                    tail(S2mm_c, descAddr(S2mm_c, 3));
                    cycles(20);
                    halt(S2mm_c, "halt of S2MM with its fetch waiting for the port");
                    waitIdle(Mm2s_c, "MM2S chain after the halt of S2MM");
                    check_value(Obs.CmdCount(S2mm_c) - CmdBase_v(S2mm_c), 0, ERROR, "nothing issued for S2MM");

                    for k in 0 to Obs.ArCount - ArBase_v - 1 loop
                        check_value(Obs.Ars(ArBase_v + k).Addr /= descAddr(S2mm_c, 0), ERROR,
                                    "no fetch for S2MM: fetch " & to_string(k));
                    end loop;

                    check_value(Obs.CurPtr(S2mm_c), descAddr(S2mm_c, 0), ERROR, "CURDESC of S2MM at D0",
                                C_TB_SCOPE_DEFAULT, HEX);
                    checkDesc(S2mm_c, 0, false, Img_v(S2mm_c)(0)(7), "S2MM D0 not started");
                end if;

            elsif run("test_drain") then
                log(ID_LOG_HDR, "TC-SG-12 drain");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        chain(ch, 6);
                        Mem_v.setLatency(MemSg_c, 40);
                        Cfg(ch).Hold     <= '1';
                        Cfg(ch).ResDelay <= 300;
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 5));
                        waitCmds(ch, 1, "D0 issued");
                        waitFetches(2, "D1 fetched");
                        -- One result: its status write and the next fetch start, then the drain
                        Cfg(ch).Hold  <= '0';
                        waitRes(ch, 1, "result of D0");
                        Cfg(ch).Hold  <= '1';
                        cycles(3);
                        wait until rising_edge(Clk);
                        Reg(ch).Drain <= '1';
                        K_v           := Obs.CmdCount(ch);
                        waitStopped(ch, "drain");
                        N_v           := Obs.ArCount;
                        cycles(300);
                        check_value(Obs.CmdCount(ch), K_v, ERROR, "no command during the drain");
                        check_value(Obs.ArCount, N_v, ERROR, "no fetch after the drain completed");
                        check_value(Obs.BCount - BBase_v, Obs.AwCount - AwBase_v, ERROR, "every status write answered");
                        check_value(Obs.PktCount(ch) - PktBase_v(ch), 0, ERROR, "no event during the drain");
                    end if;
                end loop;

                -- Both channels: Drain while the status write of one channel waits for the descriptor port, which
                -- writes the status of the other (memory latency 200 clock cycles): the waiting status write is not
                -- requested, the granted one completes
                if IncludeMm2s_g and IncludeS2mm_g then
                    resetAll;
                    chain(Mm2s_c, 4);
                    chain(S2mm_c, 4);
                    Mem_v.setLatency(MemSg_c, 200);
                    Cfg(Mm2s_c).Hold    <= '1';
                    Cfg(S2mm_c).Hold    <= '1';
                    Cfg(Mm2s_c).MaxCmds <= 1;
                    start(Mm2s_c, descAddr(Mm2s_c, 0));
                    start(S2mm_c, descAddr(S2mm_c, 0));
                    tail(Mm2s_c, descAddr(Mm2s_c, 3));
                    tail(S2mm_c, descAddr(S2mm_c, 3));
                    waitCmds(Mm2s_c, 1, "MM2S D0 issued");
                    waitCmds(S2mm_c, 1, "S2MM D0 issued");
                    -- Both results at once: one status write gets the port, the other waits for it
                    wait until rising_edge(Clk);
                    Cfg(Mm2s_c).Hold  <= '0';
                    Cfg(S2mm_c).Hold  <= '0';
                    odmaWaitAtLeast(Obs.AwCount, AwBase_v + 1, 10 us, "first status write");
                    cycles(20);
                    check_value(Obs.AwCount - AwBase_v, 1, ERROR, "the second status write waits for the port");
                    wait until rising_edge(Clk);
                    Reg(Mm2s_c).Drain <= '1';
                    Reg(S2mm_c).Drain <= '1';
                    waitStopped(Mm2s_c, "drain with a status write waiting");
                    waitStopped(S2mm_c, "drain with a status write waiting");
                    cycles(300);
                    check_value(Obs.AwCount - AwBase_v, 1, ERROR, "the waiting status write is not requested");
                    check_value(Obs.BCount - BBase_v, 1, ERROR, "the granted status write answered");
                    check_value(Obs.PktCount(Mm2s_c) - PktBase_v(Mm2s_c) + Obs.PktCount(S2mm_c) - PktBase_v(S2mm_c), 0,
                                ERROR, "no event during the drain");
                end if;

            elsif run("test_cyclic") then
                log(ID_LOG_HDR, "TC-SG-13 cyclic mode");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        chain(ch, 4);
                        Reg(ch).Cyclic <= '1';
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 1));
                        K_v            := 0;

                        -- Three laps; the tail is no pause point and the engine is never idle
                        while Obs.CmdCount(ch) - CmdBase_v(ch) < 12 loop
                            wait until rising_edge(Clk);
                            if Obs.Idle(ch) = '1' then
                                K_v := K_v + 1;
                            end if;
                            exit when Obs.Cycle > 200000;
                        end loop;

                        check_value(Obs.CmdCount(ch) - CmdBase_v(ch) >= 12, ERROR, "three laps");
                        check_value(K_v, 0, ERROR, "never idle in cyclic mode");
                        halt(ch, "end of the ring");
                        check_value(Obs.ErrCount(ch) - ErrBase_v(ch), 0, ERROR, "no stale error in cyclic mode");
                        -- Every completed descriptor is written; the S2MM model ends the last transfer without data
                        -- at the halt, which leaves that descriptor not started (interpretation SGI-10)
                        check_value(Obs.AwCount - AwBase_v >= Obs.CmdCount(ch) - CmdBase_v(ch) - 1, ERROR,
                                    "the status written in every lap");

                        for k in 0 to 11 loop
                            checkCmd(ch, k, k mod 4, "ring order");
                        end loop;

                    end if;
                end loop;

            elsif run("test_keyhole") then
                log(ID_LOG_HDR, "TC-SG-14 keyhole");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        chain(ch, 4);
                        Reg(ch).Keyhole <= '1';
                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 1));
                        waitIdle(ch, "keyhole");
                        Reg(ch).Keyhole <= '0';
                        tail(ch, descAddr(ch, 3));
                        cycles(5);
                        waitIdle(ch, "incrementing");
                        waitCmds(ch, 4, "keyhole");

                        for k in 0 to 3 loop
                            Ok_v := Obs.Cmds(ch)(CmdBase_v(ch) + k).Keyhole = '1';
                            check_value(Ok_v, k < 2, ERROR, "keyhole taken at the fetch, command " & to_string(k));
                        end loop;

                    end if;
                end loop;

            elsif run("test_ecc") then
                log(ID_LOG_HDR, "TC-SG-15 ECC of the FT buffers");

                for idx in 0 to 3 loop
                    -- The channel of a descriptor buffer, or an included channel for the buffers of the port
                    if idx = 0 then
                        K_v := Mm2s_c;
                    elsif idx = 1 then
                        K_v := S2mm_c;
                    elsif IncludeMm2s_g then
                        K_v := Mm2s_c;
                    else
                        K_v := S2mm_c;
                    end if;
                    if Incl_c(K_v) then

                        for m in 0 to 3 loop
                            -- 0 parity single, 1 parity double, 2 data single, 3 data double error
                            resetAll;
                            chain(K_v, 2);
                            SecBase_v := Obs.EccSec(idx);
                            DedBase_v := Obs.EccDed(idx);
                            if m = 0 then
                                inject(idx, '0', '0');
                            elsif m = 1 then
                                inject(idx, '1', '0');
                            elsif m = 2 then
                                inject(idx, '0', '1');
                            else
                                inject(idx, '1', '1');
                            end if;
                            start(K_v, descAddr(K_v, 0));
                            tail(K_v, descAddr(K_v, 1));
                            waitIdle(K_v, "ECC buffer " & to_string(idx) & " mode " & to_string(m));
                            cycles(5);
                            if m = 0 or m = 2 then
                                check_value(Obs.EccSec(idx) - SecBase_v, 1, ERROR, "one SEC event, buffer " & to_string(idx));
                                check_value(Obs.EccDed(idx) - DedBase_v, 0, ERROR, "no DED event, buffer " & to_string(idx));
                            else
                                check_value(Obs.EccSec(idx) - SecBase_v, 0, ERROR, "no SEC event, buffer " & to_string(idx));
                                check_value(Obs.EccDed(idx) - DedBase_v, 1, ERROR, "one DED event, buffer " & to_string(idx));
                            end if;
                            -- Consequences: a double error in data mode corrupts bits 0 and 1 of the word it hits
                            N_v := D_v(K_v)(0).Len;
                            if m = 3 and idx <= 1 then
                                N_v := to_integer(unsigned(std_logic_vector(to_unsigned(N_v, LengthWidth_g)) xor
                                                           std_logic_vector(to_unsigned(3, LengthWidth_g))));
                                check_value(Obs.Cmds(K_v)(CmdBase_v(K_v)).Length, N_v, ERROR,
                                            "descriptor buffer: buffer length with bits 0 and 1 flipped");
                            else
                                checkCmd(K_v, 0, 0, "ECC buffer " & to_string(idx));
                            end if;
                            checkCmd(K_v, 1, 1, "ECC buffer " & to_string(idx));
                            Exp_v := statusExp(K_v, N_v, '1', '1', ErrNone_c);
                            if m = 3 and idx = 3 then
                                Exp_v := Exp_v xor x"00000003";
                            end if;
                            checkDesc(K_v, 0, true, Exp_v, "ECC buffer " & to_string(idx) & " mode " & to_string(m));
                            checkDesc(K_v, 1, true, statusExp(K_v, D_v(K_v)(1).Len, '1', '1', ErrNone_c),
                                      "ECC buffer " & to_string(idx) & " mode " & to_string(m));
                        end loop;

                    end if;
                end loop;

            elsif run("test_random") then
                log(ID_LOG_HDR, "TC-SG-16 random chains");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then
                        resetAll;
                        -- Random timing of the memory and of the channel model
                        uniform(Seed1_v, Seed2_v, Rand_v);
                        Mem_v.setLatency(MemSg_c, integer(Rand_v * 20.0));
                        uniform(Seed1_v, Seed2_v, Rand_v);
                        Mem_v.setStall(MemSg_c, integer(Rand_v * 40.0));
                        uniform(Seed1_v, Seed2_v, Rand_v);
                        Cfg(ch).CmdDelay <= integer(Rand_v * 6.0);
                        uniform(Seed1_v, Seed2_v, Rand_v);
                        Cfg(ch).ResDelay <= integer(Rand_v * 30.0);
                        Prepared_v       := 0;
                        Checked_v        := 0;
                        Pkts_v           := 0;
                        PktOpen_v        := false;

                        -- Software model: the ring of 16 descriptors is prepared ahead of the tail, every completed
                        -- descriptor is checked and prepared again with new values before the tail moves over it
                        while Prepared_v < 6 loop
                            prepareRandom(ch, Prepared_v);
                            Prepared_v := Prepared_v + 1;
                        end loop;

                        start(ch, descAddr(ch, 0));
                        tail(ch, descAddr(ch, 5));

                        while Checked_v < Total_c loop
                            if Obs.BCount - BBase_v <= Checked_v then
                                wait until Obs.BCount - BBase_v > Checked_v for 500 us;
                            end if;
                            check_value(Obs.BCount - BBase_v > Checked_v, ERROR, "status write " & to_string(Checked_v));
                            exit when Obs.BCount - BBase_v <= Checked_v;
                            wait until rising_edge(Clk);
                            checkCmd(ch, Checked_v, Checked_v mod MaxDesc_c, "random command " & to_string(Checked_v));
                            checkDesc(ch, Checked_v mod MaxDesc_c, true, ExpSt_v(Checked_v),
                                      "random descriptor " & to_string(Checked_v));
                            Checked_v := Checked_v + 1;
                            if Prepared_v < Total_c and Prepared_v - Checked_v < 6 then
                                uniform(Seed1_v, Seed2_v, Rand_v);

                                for j in 0 to integer(Rand_v * 2.0) loop
                                    exit when Prepared_v = Total_c;
                                    prepareRandom(ch, Prepared_v);
                                    Prepared_v := Prepared_v + 1;
                                end loop;

                                tail(ch, descAddr(ch, (Prepared_v - 1) mod MaxDesc_c));
                            end if;
                        end loop;

                        waitIdle(ch, "random chain");
                        check_value(Obs.CmdCount(ch) - CmdBase_v(ch), Total_c, ERROR, "every descriptor issued once");
                        check_value(Obs.PktCount(ch) - PktBase_v(ch), Pkts_v, ERROR, "one event per packet");
                        check_value(Obs.CurPtr(ch), descAddr(ch, (Total_c - 1) mod MaxDesc_c), ERROR, "CURDESC at the tail",
                                    C_TB_SCOPE_DEFAULT, HEX);
                    end if;
                end loop;

            elsif run("test_rate") then
                log(ID_LOG_HDR, "TC-SG-17 descriptor rate");

                for lat in 0 to 1 loop

                    for ch in 0 to 2 loop
                        -- 0 MM2S alone, 1 S2MM alone, 2 both channels
                        if (ch < 2 and Incl_c(ch mod 2)) or (ch = 2 and IncludeMm2s_g and IncludeS2mm_g) then
                            resetAll;
                            Mem_v.setLatency(MemSg_c, 20 * lat);

                            for c in 0 to 1 loop
                                if (ch = c or ch = 2) then
                                    chain(c, 16);
                                    Cfg(c).ResDelay <= 0;
                                    start(c, descAddr(c, 0));
                                end if;
                            end loop;

                            for c in 0 to 1 loop
                                if (ch = c or ch = 2) then
                                    tail(c, descAddr(c, 15));
                                end if;
                            end loop;

                            for c in 0 to 1 loop
                                if (ch = c or ch = 2) then
                                    waitIdle(c, "rate");
                                    waitCmds(c, 16, "rate");
                                    N_v := Obs.Cmds(c)(CmdBase_v(c) + 15).Cycle - Obs.Cmds(c)(CmdBase_v(c)).Cycle;
                                    log(ID_LOG_HDR, "Descriptor rate, " & sel(c = Mm2s_c, "MM2S", "S2MM") &
                                        sel(ch = 2, " with both channels", " alone") & ", memory latency " &
                                        to_string(20 * lat) & ": " & to_string(N_v * 10 / 15) & " / 10 clock cycles per descriptor");
                                end if;
                            end loop;

                        end if;
                    end loop;

                end loop;

            elsif run("test_hard_reset") then
                log(ID_LOG_HDR, "TC-SG-19 Rst at every clock cycle around a status write");

                for ch in 0 to 1 loop
                    if Incl_c(ch) then

                        -- Rst d clock cycles after the DUT takes the result of D0: its status write not yet requested,
                        -- waiting for the port, given to the master, issued or answered. After Rst the chain runs from
                        -- its start as after the first reset
                        for d in 0 to 12 loop
                            resetAll;
                            chain(ch, 3);
                            Cfg(ch).Hold <= '1';
                            start(ch, descAddr(ch, 0));
                            tail(ch, descAddr(ch, 2));
                            waitCmds(ch, 1, "D0 issued");
                            wait until rising_edge(Clk);
                            Cfg(ch).Hold <= '0';
                            waitRes(ch, 1, "result of D0");
                            cycles(d);
                            resetAll;
                            chain(ch, 3);
                            start(ch, descAddr(ch, 0));
                            tail(ch, descAddr(ch, 2));
                            waitCmds(ch, 3, "chain after Rst " & to_string(d) & " clock cycles after the result");
                            waitIdle(ch, "chain after Rst " & to_string(d) & " clock cycles after the result");
                            check_value(Obs.ErrCount(ch) - ErrBase_v(ch), 0, ERROR, "no error after Rst");

                            for i in 0 to 2 loop
                                checkCmd(ch, i, i, "chain after Rst " & to_string(d));
                                checkDesc(ch, i, true, statusExp(ch, D_v(ch)(i).Len, '1', '1', ErrNone_c),
                                          "chain after Rst " & to_string(d));
                            end loop;

                        end loop;

                    end if;
                end loop;

            end if;

        end loop;

        odmaTestEnd(runner);
        wait;
    end process;

end architecture;
