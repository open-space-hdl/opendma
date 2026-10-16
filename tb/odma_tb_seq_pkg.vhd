---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Sequence player of the OpenDMA testbenches: executes a sequence file of register accesses,
-- interrupt waits and stream packets through the AXI4-Lite and AXI4-Stream VVCs, and loads and
-- checks memory image files through the backdoor of the AXI memory model.
--
-- Documentation: hdl/odma_pkg/docs/architecture.md (section 3.3)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library std;
    use std.textio.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library bitvis_vip_axilite;
    context bitvis_vip_axilite.vvc_context;

library bitvis_vip_axistream;
    context bitvis_vip_axistream.vvc_context;

library work;
    use work.odma_tb_memvar_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_tb_seq_pkg is

    -- Largest packet of an S or E command (the limit of the AXI4-Stream VVC)
    constant SeqMaxBytes_c : positive := 16384;

    -- Executes the sequence file fileName (commands in hdl/odma_pkg/docs/architecture.md, section 3.3).
    -- Register accesses go to AXI4-Lite VVC axiliteIdx, S packets to AXI4-Stream VVC txIdx, E packets
    -- to AXI4-Stream VVC rxIdx; timeouts count periods of clkPeriod.
    procedure odmaSequence (
        constant fileName   : in    string;
        signal AxiliteVvct  : inout bitvis_vip_axilite.td_target_support_pkg.t_vvc_target_record;
        constant axiliteIdx : in    natural;
        signal AxisVvct     : inout bitvis_vip_axistream.td_target_support_pkg.t_vvc_target_record;
        constant txIdx      : in    natural;
        constant rxIdx      : in    natural;
        signal Mm2sIrq      : in    std_logic;
        signal S2mmIrq      : in    std_logic;
        constant clkPeriod  : in    time);

    -- Writes the ranges of a memory image file into instance idx of the memory models
    procedure odmaLoadImage (
        constant idx      : in natural;
        constant fileName : in string);

    -- Compares instance idx of the memory models with a memory image file; one error alert with the
    -- number of mismatches and the first one
    procedure odmaCheckImage (
        constant idx      : in natural;
        constant fileName : in string);

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body odma_tb_seq_pkg is

    constant Scope_c : string := "odmaSequence";

    -- Next token of a line, separated by spaces or tabs; null at the end of the line
    procedure getToken (
        variable lin : inout line;
        variable tok : out line) is
        variable C_v   : character;
        variable Buf_v : line;
    begin

        while lin /= null and lin'length > 0 loop
            exit when lin(lin'left) /= ' ' and lin(lin'left) /= HT;
            read(lin, C_v);
        end loop;

        while lin /= null and lin'length > 0 loop
            exit when lin(lin'left) = ' ' or lin(lin'left) = HT;
            read(lin, C_v);
            write(Buf_v, C_v);
        end loop;

        tok := Buf_v;
    end procedure;

    function hexDigit (c : character) return integer is
    begin

        case c is
            when '0' to '9' => return character'pos(c) - character'pos('0');
            when 'a' to 'f' => return character'pos(c) - character'pos('a') + 10;
            when 'A' to 'F' => return character'pos(c) - character'pos('A') + 10;
            when others => return -1;
        end case;

    end function;

    -- Number with the prefix 0x (hexadecimal) or without (decimal); hex forces hexadecimal digits
    -- without prefix. ok is false for an invalid digit.
    procedure toNumber (
        constant s   : in  string;
        constant hex : in  boolean;
        variable val : out unsigned(63 downto 0);
        variable ok  : out boolean) is
        variable V_v     : unsigned(63 downto 0) := (others => '0');
        variable First_v : natural               := s'low;
        variable Base_v  : natural               := 10;
        variable D_v     : integer;
    begin
        ok := s'length > 0;
        if s'length > 2 and s(s'low to s'low + 1) = "0x" then
            First_v := s'low + 2;
            Base_v  := 16;
        elsif hex then
            Base_v := 16;
        end if;

        for i in First_v to s'high loop
            D_v := hexDigit(s(i));
            if D_v < 0 or D_v >= Base_v then
                ok := false;
            else
                V_v := resize(V_v * to_unsigned(Base_v, 8), 64) + to_unsigned(D_v, 64);
            end if;
        end loop;

        val := V_v;
    end procedure;

    procedure odmaSequence (
        constant fileName   : in    string;
        signal AxiliteVvct  : inout bitvis_vip_axilite.td_target_support_pkg.t_vvc_target_record;
        constant axiliteIdx : in    natural;
        signal AxisVvct     : inout bitvis_vip_axistream.td_target_support_pkg.t_vvc_target_record;
        constant txIdx      : in    natural;
        constant rxIdx      : in    natural;
        signal Mm2sIrq      : in    std_logic;
        signal S2mmIrq      : in    std_logic;
        constant clkPeriod  : in    time) is
        file F_v : text;

        variable Status_v   : file_open_status;
        variable Lin_v      : line;
        variable Orig_v     : line;
        variable Tok_v      : line;
        variable LineNo_v   : natural := 0;
        variable Arg_v      : unsigned(63 downto 0);
        variable Ok_v       : boolean;
        variable Nums_v     : t_slv_array(0 to 3)(31 downto 0);
        variable NumCnt_v   : natural;
        variable Bytes_v    : t_slv_array(0 to SeqMaxBytes_c - 1)(7 downto 0);
        variable ByteCnt_v  : natural;
        variable Cmd_v      : character;
        variable CmdIdx_v   : natural;
        variable Result_v   : bitvis_vip_axilite.vvc_cmd_pkg.t_vvc_result;
        variable Data_v     : std_logic_vector(31 downto 0);
        variable Mask_v     : std_logic_vector(31 downto 0);
        variable Deadline_v : time;
        variable Level_v    : std_logic;
        variable IsMm2s_v   : boolean;
        variable Match_v    : boolean;

        impure function ctx return string is
        begin
            return fileName & ":" & integer'image(LineNo_v) & ": " & Orig_v.all;
        end function;

        -- Reads a register through the VVC and waits for the result
        procedure readReg (
            signal Vvct     : inout bitvis_vip_axilite.td_target_support_pkg.t_vvc_target_record;
            constant offset : in    std_logic_vector(31 downto 0);
            variable data   : out   std_logic_vector(31 downto 0)) is
        begin
            axilite_read(Vvct, axiliteIdx, unsigned(offset), ctx);
            CmdIdx_v := get_last_received_cmd_idx(Vvct, axiliteIdx);
            await_completion(Vvct, axiliteIdx, CmdIdx_v, 1 ms, ctx);
            fetch_result(Vvct, axiliteIdx, CmdIdx_v, Result_v, ctx);
            data     := Result_v(31 downto 0);
        end procedure;

    -- Comment for the style checker: subprograms above, statements below
    begin
        file_open(Status_v, F_v, fileName, read_mode);
        if Status_v /= open_ok then
            alert(TB_ERROR, "cannot open the sequence file " & fileName, Scope_c);
            return;
        end if;

        while not endfile(F_v) loop
            readline(F_v, Lin_v);
            LineNo_v := LineNo_v + 1;
            Orig_v   := new string'(Lin_v.all);
            getToken(Lin_v, Tok_v);
            next when Tok_v = null;
            next when Tok_v.all(Tok_v.all'low) = '#';
            Cmd_v    := Tok_v.all(Tok_v.all'low);

            -- Numeric arguments of the register, interrupt and delay commands
            NumCnt_v := 0;
            IsMm2s_v := false;
            if Cmd_v = 'W' or Cmd_v = 'R' or Cmd_v = 'P' or Cmd_v = 'I' or Cmd_v = 'D' or Cmd_v = 'A' then

                loop
                    getToken(Lin_v, Tok_v);
                    exit when Tok_v = null or NumCnt_v > 3;
                    if Cmd_v = 'I' and NumCnt_v = 0 then
                        IsMm2s_v := Tok_v.all = "MM2S";
                        if not IsMm2s_v and Tok_v.all /= "S2MM" then
                            alert(TB_ERROR, ctx & ": channel must be MM2S or S2MM", Scope_c);
                        end if;
                        Nums_v(0) := (others => '0');
                    else
                        toNumber(Tok_v.all, false, Arg_v, Ok_v);
                        if not Ok_v then
                            alert(TB_ERROR, ctx & ": invalid number " & Tok_v.all, Scope_c);
                        end if;
                        Nums_v(NumCnt_v) := std_logic_vector(Arg_v(31 downto 0));
                    end if;
                    NumCnt_v := NumCnt_v + 1;
                end loop;

            end if;

            case Cmd_v is

                when 'W' =>
                    -- The VVC executes reads and writes on independent channels: wait, so that the next command
                    -- sees the effect of the write
                    axilite_write(AxiliteVvct, axiliteIdx, unsigned(Nums_v(0)), Nums_v(1), ctx);
                    await_completion(AxiliteVvct, axiliteIdx, 1 ms, ctx);

                when 'R' =>
                    Mask_v := (others => '1');
                    if NumCnt_v > 2 then
                        Mask_v := Nums_v(2);
                    end if;
                    readReg(AxiliteVvct, Nums_v(0), Data_v);
                    check_value(Data_v and Mask_v, Nums_v(1) and Mask_v, ERROR, ctx, Scope_c);

                when 'P' =>
                    Deadline_v := now + to_integer(unsigned(Nums_v(3))) * clkPeriod;

                    loop
                        readReg(AxiliteVvct, Nums_v(0), Data_v);
                        Match_v := (Data_v and Nums_v(2)) = (Nums_v(1) and Nums_v(2));
                        exit when Match_v;
                        if now >= Deadline_v then
                            alert(ERROR, ctx & ": timeout, last value " & to_string(Data_v, HEX, AS_IS, INCL_RADIX),
                                  Scope_c);
                            exit;
                        end if;
                    end loop;

                when 'I' =>
                    await_completion(AxiliteVvct, axiliteIdx, 1 ms, ctx);
                    Level_v := '1' when Nums_v(1)(0) = '1' else '0';
                    if IsMm2s_v then
                        await_value(Mm2sIrq, Level_v, 0 ns, to_integer(unsigned(Nums_v(2))) * clkPeriod, ERROR, ctx,
                                    Scope_c);
                    else
                        await_value(S2mmIrq, Level_v, 0 ns, to_integer(unsigned(Nums_v(2))) * clkPeriod, ERROR, ctx,
                                    Scope_c);
                    end if;

                when 'S' | 'E' =>
                    ByteCnt_v := 0;

                    loop
                        getToken(Lin_v, Tok_v);
                        exit when Tok_v = null;
                        toNumber(Tok_v.all, true, Arg_v, Ok_v);
                        if not Ok_v or ByteCnt_v = SeqMaxBytes_c then
                            alert(TB_ERROR, ctx & ": invalid byte or packet longer than SeqMaxBytes_c", Scope_c);
                            exit;
                        end if;
                        Bytes_v(ByteCnt_v) := std_logic_vector(Arg_v(7 downto 0));
                        ByteCnt_v          := ByteCnt_v + 1;
                    end loop;

                    if ByteCnt_v = 0 then
                        alert(TB_ERROR, ctx & ": packet without bytes", Scope_c);
                    elsif Cmd_v = 'S' then
                        axistream_transmit(AxisVvct, txIdx, Bytes_v(0 to ByteCnt_v - 1), ctx);
                    else
                        axistream_expect(AxisVvct, rxIdx, Bytes_v(0 to ByteCnt_v - 1), ctx);
                    end if;

                when 'A' =>
                    if NumCnt_v = 0 then
                        Nums_v(0) := std_logic_vector(to_unsigned(1000000, 32));
                    end if;
                    await_completion(AxiliteVvct, axiliteIdx, 1 ms, ctx);
                    await_completion(AxisVvct, txIdx, to_integer(unsigned(Nums_v(0))) * clkPeriod, ctx);
                    await_completion(AxisVvct, rxIdx, to_integer(unsigned(Nums_v(0))) * clkPeriod, ctx);

                when 'D' =>
                    await_completion(AxiliteVvct, axiliteIdx, 1 ms, ctx);
                    wait for to_integer(unsigned(Nums_v(0))) * clkPeriod;

                when 'L' =>
                    log(ID_SEQUENCER, Lin_v.all, Scope_c);

                when others =>
                    alert(TB_ERROR, ctx & ": unknown command", Scope_c);

            end case;

            deallocate(Orig_v);
        end loop;

        await_completion(AxiliteVvct, axiliteIdx, 1 ms, fileName & ": end of the sequence");
        file_close(F_v);
    end procedure;

    procedure odmaLoadImage (
        constant idx      : in natural;
        constant fileName : in string) is
        file F_v : text;

        variable Status_v : file_open_status;
        variable Lin_v    : line;
        variable Tok_v    : line;
        variable Addr_v   : unsigned(63 downto 0);
        variable Byte_v   : unsigned(63 downto 0);
        variable Ok_v     : boolean;
    begin
        file_open(Status_v, F_v, fileName, read_mode);
        if Status_v /= open_ok then
            alert(TB_ERROR, "cannot open the memory image " & fileName, "odmaLoadImage");
            return;
        end if;

        while not endfile(F_v) loop
            readline(F_v, Lin_v);
            getToken(Lin_v, Tok_v);
            next when Tok_v = null;
            next when Tok_v.all(Tok_v.all'low) = '#';
            toNumber(Tok_v.all, false, Addr_v, Ok_v);

            loop
                getToken(Lin_v, Tok_v);
                exit when Tok_v = null;
                toNumber(Tok_v.all, true, Byte_v, Ok_v);
                Mem_v.write8(idx, Addr_v, std_logic_vector(Byte_v(7 downto 0)));
                Addr_v := Addr_v + 1;
            end loop;

        end loop;

        file_close(F_v);
    end procedure;

    procedure odmaCheckImage (
        constant idx      : in natural;
        constant fileName : in string) is
        file F_v : text;

        variable Status_v : file_open_status;
        variable Lin_v    : line;
        variable Tok_v    : line;
        variable Addr_v   : unsigned(63 downto 0);
        variable Byte_v   : unsigned(63 downto 0);
        variable Ok_v     : boolean;
        variable Bad_v    : natural := 0;
        variable Total_v  : natural := 0;
        variable First_v  : line;
    begin
        file_open(Status_v, F_v, fileName, read_mode);
        if Status_v /= open_ok then
            alert(TB_ERROR, "cannot open the memory image " & fileName, "odmaCheckImage");
            return;
        end if;

        while not endfile(F_v) loop
            readline(F_v, Lin_v);
            getToken(Lin_v, Tok_v);
            next when Tok_v = null;
            next when Tok_v.all(Tok_v.all'low) = '#';
            toNumber(Tok_v.all, false, Addr_v, Ok_v);

            loop
                getToken(Lin_v, Tok_v);
                exit when Tok_v = null;
                toNumber(Tok_v.all, true, Byte_v, Ok_v);
                Total_v := Total_v + 1;
                if Mem_v.read8(idx, Addr_v) /= std_logic_vector(Byte_v(7 downto 0)) then
                    if Bad_v = 0 then
                        write(First_v, to_string(std_logic_vector(Addr_v), HEX, AS_IS, INCL_RADIX) & " holds " &
                                       to_string(Mem_v.read8(idx, Addr_v), HEX, AS_IS, INCL_RADIX) & ", expected " &
                                       to_string(std_logic_vector(Byte_v(7 downto 0)), HEX, AS_IS, INCL_RADIX));
                    end if;
                    Bad_v := Bad_v + 1;
                end if;
                Addr_v := Addr_v + 1;
            end loop;

        end loop;

        file_close(F_v);
        if Bad_v > 0 then
            alert(ERROR, fileName & ": " & integer'image(Bad_v) & " of " & integer'image(Total_v) &
                         " bytes differ, the first at " & First_v.all, "odmaCheckImage");
        else
            log(ID_SEQUENCER, fileName & ": " & integer'image(Total_v) & " bytes as expected", "odmaCheckImage");
        end if;
    end procedure;

end package body;
