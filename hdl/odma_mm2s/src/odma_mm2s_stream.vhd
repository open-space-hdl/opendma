---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stream output of the MM2S channel (MM-2): sends the read data of each transfer with TKeep and
-- TLast and returns one transfer result per command; discards the data during a drain.
--
-- Documentation: hdl/odma_mm2s/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.odma_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_mm2s_stream is
    generic (
        LengthWidth_g : positive;
        StreamWidth_g : positive
    );
    port (
        -- Control Signals
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        Drain        : in    std_logic;
        -- Transfer buffer (read side)
        Xfer_Valid   : in    std_logic;
        Xfer_Ready   : out   std_logic;
        Xfer_Length  : in    std_logic_vector(LengthWidth_g - 1 downto 0);
        Xfer_Eof     : in    std_logic;
        Xfer_Code    : in    XferErr_t;
        -- Response buffer (read side)
        Resp_Valid   : in    std_logic;
        Resp_Ready   : out   std_logic;
        Resp_Code    : in    XferErr_t;
        -- Read data of the read master
        Rd_Data      : in    std_logic_vector(StreamWidth_g - 1 downto 0);
        Rd_Last      : in    std_logic;
        Rd_Valid     : in    std_logic;
        Rd_Ready     : out   std_logic;
        -- Transfer result
        Res_Valid    : out   std_logic;
        Res_Ready    : in    std_logic;
        Res_Bytes    : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        Res_Eof      : out   std_logic;
        Res_Err      : out   XferErr_t;
        -- MM2S stream
        M_Mm2s_Data  : out   std_logic_vector(StreamWidth_g - 1 downto 0);
        M_Mm2s_Keep  : out   std_logic_vector(StreamWidth_g / 8 - 1 downto 0);
        M_Mm2s_Last  : out   std_logic;
        M_Mm2s_Valid : out   std_logic;
        M_Mm2s_Ready : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_mm2s_stream is

    constant KeepWidth_c  : positive := StreamWidth_g / 8;
    constant StageWidth_c : positive := StreamWidth_g + KeepWidth_c + 1;

    type StreamFsm_t is (Head_s, Data_s, Result_s);

    type TwoProcess_r is record
        State    : StreamFsm_t;
        LastKeep : std_logic_vector(KeepWidth_c - 1 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- Register stage of the stream output
    signal StgRst      : std_logic;
    signal Stg_InData  : std_logic_vector(StageWidth_c - 1 downto 0);
    signal Stg_InValid : std_logic;
    signal Stg_InReady : std_logic;
    signal Stg_OutData : std_logic_vector(StageWidth_c - 1 downto 0);
    signal Stg_OutVld  : std_logic;

    signal ResValid : std_logic;
    signal Pop      : std_logic;
    signal Keep     : std_logic_vector(KeepWidth_c - 1 downto 0);
    signal Read_i   : std_logic;

begin

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v : TwoProcess_r;
    begin
        v := r;

        case r.State is

            when Head_s =>
                if Xfer_Valid = '1' then
                    -- TKeep of the last beat of the transfer
                    v.LastKeep := lastKeep(unsigned(Xfer_Length), KeepWidth_c);
                    if Xfer_Code = ErrNone_c then
                        v.State := Data_s;
                    else
                        v.State := Result_s;
                    end if;
                end if;

            when Data_s =>
                if Rd_Valid = '1' and Read_i = '1' and Rd_Last = '1' then
                    v.State := Result_s;
                end if;

            when Result_s =>
                if Pop = '1' then
                    v.State := Head_s;
                end if;

            -- coverage off
            when others =>
                v.State := Head_s; -- unreachable, safe recovery
            -- coverage on

        end case;

        r_next <= v;
    end process;

    -- Read data: into the register stage, discarded during a drain
    Read_i      <= '1' when r.State = Data_s and (Stg_InReady = '1' or Drain = '1') else '0';
    Rd_Ready    <= Read_i;
    Stg_InValid <= '1' when r.State = Data_s and Rd_Valid = '1' and Drain = '0' else '0';
    Keep        <= r.LastKeep when Rd_Last = '1' else (others => '1');
    -- {TLast, TKeep, TData}: TLast on the last beat of a transfer with the end of packet
    Stg_InData <= (Rd_Last and Xfer_Eof) & Keep & Rd_Data;

    -- Result: after the stream peer took the last beat (stage empty) and with the response of a read entry; during
    -- a drain the entries are popped without a result
    ResValid <= '1' when r.State = Result_s and Drain = '0' and Stg_OutVld = '0' and
                         (Xfer_Code /= ErrNone_c or Resp_Valid = '1') else
                '0';
    Pop      <= '1' when (ResValid = '1' and Res_Ready = '1') or
                         (r.State = Result_s and Drain = '1' and (Xfer_Code /= ErrNone_c or Resp_Valid = '1')) else
                '0';

    Res_Valid  <= ResValid;
    Res_Bytes  <= Xfer_Length when Xfer_Code = ErrNone_c else (others => '0');
    Res_Eof    <= Xfer_Eof;
    Res_Err    <= Resp_Code when Xfer_Code = ErrNone_c else Xfer_Code;
    Xfer_Ready <= Pop;
    Resp_Ready <= Pop when Xfer_Code = ErrNone_c else '0';

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State <= Head_s;
            end if;
        end if;
    end process;

    -- *** Register stage of the stream output, cleared during a drain ***
    StgRst <= Rst or Drain;

    i_stage : entity olo.olo_base_pl_stage
        generic map (
            Width_g    => StageWidth_c,
            UseReady_g => true,
            Stages_g   => 1
        )
        port map (
            Clk       => Clk,
            Rst       => StgRst,
            In_Valid  => Stg_InValid,
            In_Ready  => Stg_InReady,
            In_Data   => Stg_InData,
            Out_Valid => Stg_OutVld,
            Out_Ready => M_Mm2s_Ready,
            Out_Data  => Stg_OutData
        );

    M_Mm2s_Data  <= Stg_OutData(StreamWidth_g - 1 downto 0);
    M_Mm2s_Keep  <= Stg_OutData(StreamWidth_g + KeepWidth_c - 1 downto StreamWidth_g);
    M_Mm2s_Last  <= Stg_OutData(StageWidth_c - 1);
    M_Mm2s_Valid <= Stg_OutVld;

end architecture;
