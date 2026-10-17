---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Read command block of the MM2S channel (MM-1): accepts transfer commands, checks them, issues the
-- read commands to the AXI4 read master and records the transfer entries and the response codes.
--
-- Documentation: hdl/odma_mm2s/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.odma_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_mm2s_command is
    generic (
        AddrWidth_g   : positive;
        LengthWidth_g : positive
    );
    port (
        -- Control Signals
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        -- Transfer command
        Cmd_Valid    : in    std_logic;
        Cmd_Ready    : out   std_logic;
        Cmd_Addr     : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        Cmd_Length   : in    std_logic_vector(LengthWidth_g - 1 downto 0);
        Cmd_Eof      : in    std_logic;
        Cmd_Keyhole  : in    std_logic;
        -- Channel control
        Run          : in    std_logic;
        Drain        : in    std_logic;
        -- Read command and responses of the read master
        CmdRd_Addr   : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        CmdRd_Size   : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        CmdRd_Fixed  : out   std_logic;
        CmdRd_Valid  : out   std_logic;
        CmdRd_Ready  : in    std_logic;
        Rd_Done      : in    std_logic;
        Rd_Error     : in    std_logic;
        Rd_ErrorResp : in    std_logic_vector(1 downto 0);
        -- Transfer buffer (write side)
        Xfer_Valid   : out   std_logic;
        Xfer_Ready   : in    std_logic;
        Xfer_Length  : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        Xfer_Eof     : out   std_logic;
        Xfer_Code    : out   XferErr_t;
        -- Response buffer (write side)
        Resp_Valid   : out   std_logic;
        Resp_Code    : out   XferErr_t;
        -- No command in progress
        Idle         : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_mm2s_command is

    type CommandFsm_t is (Idle_s, Entry_s, Issue_s);

    type TwoProcess_r is record
        State  : CommandFsm_t;
        Addr   : std_logic_vector(AddrWidth_g - 1 downto 0);
        Length : std_logic_vector(LengthWidth_g - 1 downto 0);
        Eof    : std_logic;
        Fixed  : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal Code     : XferErr_t;
    signal CmdReady : std_logic;

begin

    -- A command is accepted while the channel runs, does not drain and the transfer buffer has a free entry
    CmdReady <= '1' when r.State = Idle_s and Run = '1' and Drain = '0' and Xfer_Ready = '1' else '0';

    -- Code of the transfer entry: no read for a length of 0 or a buffer beyond the top of the address space; a
    -- keyhole read accesses only the memory word at the address, which lies in the address space (MM-SG-03)
    Code <= ErrInt_c when unsigned(r.Length) = 0 else
            ErrDec_c when r.Fixed = '0' and beyondTop(unsigned(r.Addr), unsigned(r.Length)) else
            ErrNone_c;

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v : TwoProcess_r;
    begin
        v := r;

        case r.State is

            when Idle_s =>
                if Cmd_Valid = '1' and CmdReady = '1' then
                    v.Addr   := Cmd_Addr;
                    v.Length := Cmd_Length;
                    v.Eof    := Cmd_Eof;
                    v.Fixed  := Cmd_Keyhole;
                    v.State  := Entry_s;
                end if;

            when Entry_s =>
                -- The transfer entry is written in this clock cycle; the read follows for a read entry
                if Code = ErrNone_c then
                    v.State := Issue_s;
                else
                    v.State := Idle_s;
                end if;

            when Issue_s =>
                if CmdRd_Ready = '1' then
                    v.State := Idle_s;
                end if;

            -- coverage off
            when others =>
                v.State := Idle_s; -- unreachable, safe recovery
            -- coverage on

        end case;

        r_next <= v;
    end process;

    -- Outputs
    Cmd_Ready   <= CmdReady;
    CmdRd_Addr  <= r.Addr;
    CmdRd_Size  <= r.Length;
    CmdRd_Fixed <= r.Fixed;
    CmdRd_Valid <= '1' when r.State = Issue_s else '0';
    Xfer_Valid  <= '1' when r.State = Entry_s else '0';
    Xfer_Length <= r.Length;
    Xfer_Eof    <= r.Eof;
    Xfer_Code   <= Code;
    Resp_Valid  <= Rd_Done or Rd_Error;
    -- SLVERR and EXOKAY give the slave error, DECERR the decode error (MM-ER-03, interpretation I14)
    Resp_Code <= respErr(Rd_ErrorResp) when Rd_Error = '1' else ErrNone_c;
    Idle      <= '1' when r.State = Idle_s else '0';

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State <= Idle_s;
            end if;
        end if;
    end process;

end architecture;
