---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stream output of the MM2S channel (MM-2): sends the read data of each transfer with TKeep and
-- TLast and returns one transfer result per command; discards the data during a drain. With
-- Join_g the buffers of a packet are joined into one packet, and a packet left open by a halt is
-- closed with TLast on its last byte.
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
        StreamWidth_g : positive;
        Join_g        : boolean := false
    );
    port (
        -- Control Signals
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        Run          : in    std_logic := '1';
        Drain        : in    std_logic;
        -- MM-1 idle and the transfer buffer empty: no further entry can arrive while Run is '0'
        NoEntry      : in    std_logic := '0';
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
        -- No packet open in the stream join and no closing beat pending (always '1' without Join_g)
        Closed       : out   std_logic;
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

    type StreamFsm_t is (Head_s, Data_s, Result_s, Close_s);

    type TwoProcess_r is record
        State    : StreamFsm_t;
        LastKeep : std_logic_vector(KeepWidth_c - 1 downto 0);
        InPkt    : std_logic; -- Join_g: a beat without the end of packet has entered the join
        LastOut  : std_logic; -- Join_g: the beat with TLast of the entry has been accepted by the peer
        Sent     : std_logic; -- Close_s: the closing beat has entered the join
    end record;

    signal r, r_next : TwoProcess_r;

    -- Input of the output element (register stage or stream join)
    signal OutRst   : std_logic;
    signal OutData  : std_logic_vector(StreamWidth_g - 1 downto 0);
    signal OutKeep  : std_logic_vector(KeepWidth_c - 1 downto 0);
    signal OutLast  : std_logic;
    signal OutValid : std_logic;
    signal OutReady : std_logic;

    -- Stream output
    signal Mm2sValid : std_logic;
    signal Mm2sLast  : std_logic;
    signal LastTaken : std_logic;

    signal ResValid : std_logic;
    signal Pop      : std_logic;
    signal Keep     : std_logic_vector(KeepWidth_c - 1 downto 0);
    signal Read_i   : std_logic;
    signal ResOk    : std_logic;

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
                elsif Join_g and r.InPkt = '1' and Run = '0' and Drain = '0' and NoEntry = '1' then
                    -- A halt or an error left a packet open: close it (MM-SG-04, interpretation M4)
                    v.Sent  := '0';
                    v.State := Close_s;
                end if;

            when Data_s =>
                if OutValid = '1' and OutReady = '1' then
                    v.InPkt := not OutLast;
                end if;
                if Rd_Valid = '1' and Read_i = '1' and Rd_Last = '1' then
                    v.LastOut := '0';
                    v.State   := Result_s;
                end if;

            when Result_s =>
                if LastTaken = '1' then
                    v.LastOut := '1';
                end if;
                if Pop = '1' then
                    v.State := Head_s;
                end if;

            when Close_s =>
                if OutValid = '1' and OutReady = '1' then
                    v.Sent  := '1';
                    v.InPkt := '0';
                end if;
                if (r.Sent = '1' and LastTaken = '1') or Drain = '1' then
                    v.State := Head_s;
                end if;

            -- coverage off
            when others =>
                v.State := Head_s; -- unreachable, safe recovery
            -- coverage on

        end case;

        if Drain = '1' then
            v.InPkt := '0';
        end if;

        r_next <= v;
    end process;

    -- Read data: to the output element, discarded during a drain; Close_s sends the closing beat
    Read_i   <= '1' when r.State = Data_s and (OutReady = '1' or Drain = '1') else '0';
    Rd_Ready <= Read_i;
    Keep     <= r.LastKeep when Rd_Last = '1' else (others => '1');
    OutValid <= '1' when (r.State = Data_s and Rd_Valid = '1' and Drain = '0') or
                         (r.State = Close_s and r.Sent = '0' and Drain = '0') else
                '0';
    OutData  <= Rd_Data when r.State = Data_s else (others => '0');
    OutKeep  <= Keep when r.State = Data_s else (others => '0');
    -- TLast on the last beat of a transfer with the end of packet, and with the closing beat
    OutLast <= (Rd_Last and Xfer_Eof) when r.State = Data_s else '1';

    LastTaken <= Mm2sValid and M_Mm2s_Ready and Mm2sLast;

    -- Result: with the response of a read entry, and after the stream peer took the last beat (without Join_g
    -- the register stage is empty; with Join_g for an entry with the end of packet the beat with TLast has been
    -- accepted, for one without it the last beat has entered the join); during a drain the entries are popped
    -- without a result
    ResValid <= '1' when r.State = Result_s and Drain = '0' and (Xfer_Code /= ErrNone_c or Resp_Valid = '1') and
                         ResOk = '1' else
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

    Closed <= '1' when not Join_g or (r.InPkt = '0' and r.State /= Close_s) else '0';

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State   <= Head_s;
                r.InPkt   <= '0';
                r.LastOut <= '0';
                r.Sent    <= '0';
            end if;
        end if;
    end process;

    -- The output element is cleared during a drain
    OutRst <= Rst or Drain;

    -- *** Register stage of the stream output (DR mode) ***
    g_stage : if not Join_g generate
        signal Stg_InData  : std_logic_vector(StageWidth_c - 1 downto 0);
        signal Stg_OutData : std_logic_vector(StageWidth_c - 1 downto 0);
    begin
        -- {TLast, TKeep, TData}
        Stg_InData <= OutLast & OutKeep & OutData;

        i_stage : entity olo.olo_base_pl_stage
            generic map (
                Width_g    => StageWidth_c,
                UseReady_g => true,
                Stages_g   => 1
            )
            port map (
                Clk       => Clk,
                Rst       => OutRst,
                In_Valid  => OutValid,
                In_Ready  => OutReady,
                In_Data   => Stg_InData,
                Out_Valid => Mm2sValid,
                Out_Ready => M_Mm2s_Ready,
                Out_Data  => Stg_OutData
            );

        M_Mm2s_Data <= Stg_OutData(StreamWidth_g - 1 downto 0);
        M_Mm2s_Keep <= Stg_OutData(StreamWidth_g + KeepWidth_c - 1 downto StreamWidth_g);
        Mm2sLast    <= Stg_OutData(StageWidth_c - 1);
        -- The result waits until the stream peer took the last beat of the transfer
        ResOk <= not Mm2sValid;
    end generate;

    -- *** Stream join of the buffers of a packet (Scatter/Gather Mode) ***
    g_join : if Join_g generate

        i_join : entity olo.olo_base_stream_join
            generic map (
                Width_g => StreamWidth_g
            )
            port map (
                Clk       => Clk,
                Rst       => OutRst,
                In_Data   => OutData,
                In_Be     => OutKeep,
                In_Valid  => OutValid,
                In_Ready  => OutReady,
                In_Last   => OutLast,
                Out_Data  => M_Mm2s_Data,
                Out_Be    => M_Mm2s_Keep,
                Out_Valid => Mm2sValid,
                Out_Ready => M_Mm2s_Ready,
                Out_Last  => Mm2sLast
            );

        -- An entry without the end of packet has passed its bytes to the join; one with it waits for TLast
        ResOk <= '1' when Xfer_Eof = '0' or Xfer_Code /= ErrNone_c or r.LastOut = '1' else '0';
    end generate;

    M_Mm2s_Last  <= Mm2sLast;
    M_Mm2s_Valid <= Mm2sValid;

end architecture;
