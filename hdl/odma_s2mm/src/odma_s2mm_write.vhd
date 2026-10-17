---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Write command block of the S2MM channel (S2-2): writes the chunks of the packet of each transfer
-- into its buffer through the AXI4 write master, handles overflow, write errors, halt, drain and the
-- flush of discarded data, and returns one transfer result per command.
--
-- Documentation: hdl/odma_s2mm/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.odma_pkg.all;
    use work.odma_s2mm_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_s2mm_write is
    generic (
        AddrWidth_g   : positive;
        LengthWidth_g : positive;
        StreamWidth_g : positive;
        Split_g       : boolean := false
    );
    port (
        -- Control Signals
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        Run          : in    std_logic;
        Drain        : in    std_logic;
        -- Transfer command and result
        Cmd_Valid    : in    std_logic;
        Cmd_Ready    : out   std_logic;
        Cmd_Addr     : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        Cmd_Length   : in    std_logic_vector(LengthWidth_g - 1 downto 0);
        Cmd_Keyhole  : in    std_logic;
        Res_Valid    : out   std_logic;
        Res_Ready    : in    std_logic;
        Res_Bytes    : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        Res_Eof      : out   std_logic;
        Res_Err      : out   XferErr_t;
        Res_Sof      : out   std_logic;
        -- Segment of the stream split (Split_g) and the flush of the rest of a packet
        Seg_Valid    : out   std_logic;
        Seg_Size     : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        Seg_Ready    : in    std_logic;
        FlushReq     : out   std_logic;
        -- Chunk buffer (read side) and the state of the chunk former
        Desc_Data    : in    std_logic_vector(DescWidth_c - 1 downto 0);
        Desc_Valid   : in    std_logic;
        Desc_Ready   : out   std_logic;
        Desc_Stored  : in    std_logic;                     -- A descriptor is written to the chunk buffer
        PacketOpen   : in    std_logic;
        -- Data buffer (read side)
        Buf_Data     : in    std_logic_vector(StreamWidth_g - 1 downto 0);
        Buf_Valid    : in    std_logic;
        Buf_Ready    : out   std_logic;
        -- Write master
        CmdWr_Addr   : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        CmdWr_Size   : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        CmdWr_Fixed  : out   std_logic;
        CmdWr_Valid  : out   std_logic;
        CmdWr_Ready  : in    std_logic;
        Wr_Data      : out   std_logic_vector(StreamWidth_g - 1 downto 0);
        Wr_Valid     : out   std_logic;
        Wr_Ready     : in    std_logic;
        Wr_Done      : in    std_logic;
        Wr_Error     : in    std_logic;
        Wr_ErrorResp : in    std_logic_vector(1 downto 0);
        -- No transfer in progress and no write outstanding
        Idle         : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_s2mm_write is

    constant StreamBytes_c    : positive := StreamWidth_g / 8;
    -- Write commands without response: at most the open transactions of the master
    constant MaxOutstanding_c : positive := 16;

    -- Feed job {beats to the master, beats to drop} from the command block to the feeder
    constant CntWidth_c : positive := 16;
    constant JobWidth_c : positive := 2 * CntWidth_c;

    type WriteFsm_t is (Idle_s, Take_s, Issue_s, Wait_s, Result_s, Flush_s, Drained_s);
    type FeedFsm_t is (Head_s, Feed_s, Drop_s);

    type TwoProcess_r is record
        State       : WriteFsm_t;
        Addr        : unsigned(AddrWidth_g - 1 downto 0);
        Length      : unsigned(LengthWidth_g downto 0);
        Written     : unsigned(LengthWidth_g downto 0);    -- Bytes given to write commands
        Err         : XferErr_t;
        Eof         : std_logic;
        FlushPend   : std_logic;                           -- The rest of the packet is flushed after the result
        Keyhole     : std_logic;                           -- Every write of the transfer at the command address
        Cont        : std_logic;                           -- The transfer ended with a full buffer, the packet goes on
        Disc        : std_logic;                           -- The transfer ended with a discarded packet
        SofNext     : std_logic;                           -- The next buffer is the first buffer of a packet
        SegValid    : std_logic;                           -- Split_g: segment of the transfer not yet taken
        SegSize     : std_logic_vector(LengthWidth_g - 1 downto 0);
        CmdAddr     : unsigned(AddrWidth_g - 1 downto 0);
        CmdSize     : unsigned(LengthWidth_g - 1 downto 0);
        CmdLast     : std_logic;                           -- The write command ends the transfer
        Outstanding : natural range 0 to MaxOutstanding_c;
        -- Feeder
        Feed        : FeedFsm_t;
        FeedCnt     : unsigned(CntWidth_c - 1 downto 0);
        DropCnt     : unsigned(CntWidth_c - 1 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- Feed jobs
    signal Job_InValid  : std_logic;
    signal Job_InReady  : std_logic;
    signal Job_InData   : std_logic_vector(JobWidth_c - 1 downto 0);
    signal Job_OutValid : std_logic;
    signal Job_OutReady : std_logic;
    signal Job_OutData  : std_logic_vector(JobWidth_c - 1 downto 0);

begin

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Desc_v  : Desc_r;
        variable Fit_v   : unsigned(LengthWidth_g downto 0);
        variable Feed_v  : unsigned(CntWidth_c - 1 downto 0);
        variable Job_v   : boolean;
        variable Issue_v : boolean;
    begin
        v := r;

        Desc_v := toDesc(Desc_Data);

        -- Defaults
        Cmd_Ready   <= '0';
        Desc_Ready  <= '0';
        Job_InValid <= '0';
        Job_InData  <= (others => '0');
        Res_Valid   <= '0';
        Job_v       := false;
        Issue_v     := false;
        Feed_v      := (others => '0');

        -- *** Command block ***
        case r.State is

            when Idle_s =>
                if Drain = '1' then
                    v.State := Drained_s;
                elsif Run = '1' then
                    Cmd_Ready <= '1';
                    if Cmd_Valid = '1' then
                        v.Addr      := unsigned(Cmd_Addr);
                        v.Length    := resize(unsigned(Cmd_Length), LengthWidth_g + 1);
                        v.Written   := (others => '0');
                        v.Err       := ErrNone_c;
                        v.Eof       := '0';
                        v.FlushPend := '0';
                        v.Keyhole   := Cmd_Keyhole;
                        v.Cont      := '0';
                        v.Disc      := '0';
                        if unsigned(Cmd_Length) = 0 then
                            -- No write and no stream data for a length of 0 (S2-WR-06)
                            v.Err   := ErrInt_c;
                            v.State := Result_s;
                        elsif Cmd_Keyhole = '0' and beyondTop(unsigned(Cmd_Addr), unsigned(Cmd_Length)) then
                            -- No write and no stream data for a buffer beyond the top of the address space (S2-WR-04);
                            -- a keyhole buffer is the memory word at the address (S2-SG-04)
                            v.Err   := ErrDec_c;
                            v.State := Result_s;
                        else
                            -- Split_g: the buffer length is the segment of the split (architecture section 4.2)
                            v.SegValid := '1' when Split_g else '0';
                            v.SegSize  := Cmd_Length;
                            v.State    := Take_s;
                        end if;
                    end if;
                elsif Desc_Valid = '1' then
                    -- Halted: data received for later transfers is discarded, a whole packet at a time
                    v.State := Flush_s;
                end if;

            when Take_s =>
                if Drain = '1' then
                    v.State := Drained_s;
                elsif r.Err /= ErrNone_c then
                    -- A write error: no further write; the rest of the packet is flushed after the result
                    v.FlushPend := '1';
                    v.State     := Wait_s;
                elsif Desc_Valid = '1' and Job_InReady = '1' then
                    Desc_Ready <= '1';
                    Job_v      := true;
                    if Desc_v.Discard = '1' then
                        -- Interrupted packet: its stored beats are dropped, the transfer ends without the end of packet
                        v.Disc  := '1';
                        v.State := Wait_s;
                    elsif Desc_v.Bytes = 0 then
                        -- A last beat without valid bytes (with Split_g a packet without bytes): dropped, no write
                        v.Eof   := Desc_v.PktEnd;
                        v.Cont  := Desc_v.Pend and not Desc_v.PktEnd;
                        v.State := Wait_s when Desc_v.Pend = '1' else Take_s;
                    elsif r.Written + Desc_v.Bytes <= r.Length then
                        -- The chunk fits into the buffer; a keyhole transfer writes every chunk at the command address
                        Feed_v    := resize((Desc_v.Bytes + StreamBytes_c - 1) / StreamBytes_c, CntWidth_c);
                        v.CmdAddr := r.Addr when r.Keyhole = '1' else r.Addr + r.Written;
                        v.CmdSize := resize(Desc_v.Bytes, LengthWidth_g);
                        v.CmdLast := Desc_v.Pend;
                        v.Written := resize(r.Written + Desc_v.Bytes, LengthWidth_g + 1);
                        v.Eof     := Desc_v.PktEnd;
                        v.Cont    := Desc_v.Pend and not Desc_v.PktEnd;
                        v.State   := Issue_s;
                    else
                        -- Overflow (without Split_g): the bytes that fit are written, the rest of the packet is
                        -- discarded (S2-RS-02)
                        Fit_v       := r.Length - r.Written;
                        v.Err       := ErrInt_c;
                        v.FlushPend := not Desc_v.PktEnd;
                        if Fit_v /= 0 then
                            Feed_v    := resize((Fit_v + StreamBytes_c - 1) / StreamBytes_c, CntWidth_c);
                            v.CmdAddr := r.Addr when r.Keyhole = '1' else r.Addr + r.Written;
                            v.CmdSize := resize(Fit_v, LengthWidth_g);
                            v.CmdLast := '1';
                            v.Written := r.Length;
                            v.State   := Issue_s;
                        else
                            v.State := Wait_s;
                        end if;
                    end if;
                elsif Run = '0' and Desc_Valid = '0' and Desc_Stored = '0' and PacketOpen = '0' then
                    -- Halted with no data of the packet left: the transfer ends without the end of packet
                    v.State := Wait_s;
                end if;

            when Issue_s =>
                if CmdWr_Ready = '1' then
                    Issue_v := true;
                    if r.CmdLast = '1' then
                        v.State := Wait_s;
                    else
                        v.State := Take_s;
                    end if;
                end if;

            when Wait_s =>
                -- The result once no write of the transfer is outstanding (S2-RS-01, S2-RS-04)
                if Drain = '1' then
                    v.State := Drained_s;
                elsif r.Outstanding = 0 then
                    -- An error before the end of the packet: the rest of the packet is flushed (S2-RS-03)
                    if r.Err /= ErrNone_c and r.Eof = '0' and r.Disc = '0' then
                        v.FlushPend := '1';
                    end if;
                    v.State := Result_s;
                end if;

            when Result_s =>
                if Drain = '1' then
                    v.State := Drained_s;
                else
                    Res_Valid <= '1';
                    if Res_Ready = '1' then
                        -- The next buffer continues the packet only after a full buffer without error (S2-SG-02)
                        if r.Cont = '1' and r.Disc = '0' and r.Err = ErrNone_c then
                            v.SofNext := '0';
                        else
                            v.SofNext := '1';
                        end if;
                        if r.FlushPend = '1' then
                            v.State := Flush_s;
                        else
                            v.State := Idle_s;
                        end if;
                    end if;
                end if;

            when Flush_s =>
                -- The descriptors of the packet are dropped up to the one that ends it
                if Drain = '1' then
                    v.State := Drained_s;
                elsif Desc_Valid = '1' and Job_InReady = '1' then
                    Desc_Ready <= '1';
                    Job_v      := true;
                    if Desc_v.PktEnd = '1' then
                        v.FlushPend := '0';
                        v.State     := Idle_s;
                    end if;
                end if;

            when Drained_s =>
                -- No descriptor and no command until the core reset that follows the drain
                null;

            -- coverage off
            when others =>
                v.State := Idle_s; -- unreachable, safe recovery
            -- coverage on

        end case;

        -- Feed job of a taken descriptor: the beats written, then the other beats of the chunk dropped
        if Job_v then
            Job_InValid <= '1';
            Job_InData  <= std_logic_vector(resize(Desc_v.Beats - Feed_v, CntWidth_c)) & std_logic_vector(Feed_v);
        end if;

        -- *** Write responses: the first error code of the transfer is kept ***
        if Issue_v and Wr_Done = '0' and Wr_Error = '0' then
            v.Outstanding := r.Outstanding + 1;
        elsif not Issue_v and (Wr_Done = '1' or Wr_Error = '1') and r.Outstanding > 0 then
            v.Outstanding := r.Outstanding - 1;
        end if;
        -- SLVERR and EXOKAY give the slave error, DECERR the decode error (S2-RS-05, interpretation I14)
        if Wr_Error = '1' and v.Err = ErrNone_c then
            v.Err := respErr(Wr_ErrorResp);
        end if;

        -- The split takes the segment of the transfer
        if r.SegValid = '1' and Seg_Ready = '1' then
            v.SegValid := '0';
        end if;

        -- *** Feeder ***
        Job_OutReady <= '0';
        Buf_Ready    <= '0';
        Wr_Valid     <= '0';

        case r.Feed is

            when Head_s =>
                if Job_OutValid = '1' then
                    Job_OutReady <= '1';
                    v.FeedCnt    := unsigned(Job_OutData(CntWidth_c - 1 downto 0));
                    v.DropCnt    := unsigned(Job_OutData(JobWidth_c - 1 downto CntWidth_c));
                    if v.FeedCnt /= 0 then
                        v.Feed := Feed_s;
                    elsif v.DropCnt /= 0 then
                        v.Feed := Drop_s;
                    end if;
                end if;

            when Feed_s =>
                Wr_Valid  <= Buf_Valid;
                Buf_Ready <= Wr_Ready;
                if Buf_Valid = '1' and Wr_Ready = '1' then
                    v.FeedCnt := r.FeedCnt - 1;
                    if r.FeedCnt = 1 then
                        if r.DropCnt /= 0 then
                            v.Feed := Drop_s;
                        else
                            v.Feed := Head_s;
                        end if;
                    end if;
                end if;

            when Drop_s =>
                Buf_Ready <= '1';
                if Buf_Valid = '1' then
                    v.DropCnt := r.DropCnt - 1;
                    if r.DropCnt = 1 then
                        v.Feed := Head_s;
                    end if;
                end if;

            -- coverage off
            when others =>
                v.Feed := Head_s; -- unreachable, safe recovery
            -- coverage on

        end case;

        r_next <= v;
    end process;

    -- Outputs
    CmdWr_Addr  <= std_logic_vector(r.CmdAddr);
    CmdWr_Size  <= std_logic_vector(r.CmdSize);
    CmdWr_Fixed <= r.Keyhole;
    CmdWr_Valid <= '1' when r.State = Issue_s else '0';
    Seg_Valid   <= r.SegValid;
    Seg_Size    <= r.SegSize;
    -- Split_g: S2-1 discards the rest of the packet that has not passed the split (architecture section 4.3)
    FlushReq  <= '1' when Split_g and (r.FlushPend = '1' or r.State = Flush_s) else '0';
    Res_Sof   <= r.SofNext;
    Wr_Data   <= Buf_Data;
    Res_Bytes <= std_logic_vector(r.Written(LengthWidth_g - 1 downto 0));
    -- A transfer with an error has no end of packet (S2-RS-02, S2-RS-03)
    Res_Eof <= r.Eof when r.Err = ErrNone_c else '0';
    Res_Err <= r.Err;
    Idle    <= '1' when (r.State = Idle_s or r.State = Drained_s) and r.Outstanding = 0 else '0';

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State       <= Idle_s;
                r.Outstanding <= 0;
                r.Feed        <= Head_s;
                r.FlushPend   <= '0';
                r.SofNext     <= '1';
                r.SegValid    <= '0';
            end if;
        end if;
    end process;

    -- *** Feed jobs: the command block runs up to two jobs ahead of the feeder ***
    i_jobs : entity olo.olo_base_pl_stage
        generic map (
            Width_g    => JobWidth_c,
            UseReady_g => true,
            Stages_g   => 1
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Valid  => Job_InValid,
            In_Ready  => Job_InReady,
            In_Data   => Job_InData,
            Out_Valid => Job_OutValid,
            Out_Ready => Job_OutReady,
            Out_Data  => Job_OutData
        );

end architecture;
