---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Descriptor engine of one channel (SG-1, SG-2): tail pointer handling, descriptor fetch one
-- descriptor ahead, the descriptor buffer, the checks of a descriptor, transfer commands, the
-- queue of the issued commands, the status update after each result, the current descriptor
-- pointer, idle, stopped and the events towards the register interface.
--
-- Documentation: hdl/odma_sg/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.odma_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_sg_channel is
    generic (
        Mm2s_g        : boolean;
        AddrWidth_g   : positive range 32 to 64;
        LengthWidth_g : positive range 8 to 26
    );
    port (
        -- Control Signals
        Clk             : in    std_logic;
        Rst             : in    std_logic;
        -- Register interface
        Run             : in    std_logic;
        Drain           : in    std_logic;
        CurDesc         : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        Tail            : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        TailWr          : in    std_logic;
        Cyclic          : in    std_logic;
        Keyhole         : in    std_logic;
        CurPtr          : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        Idle            : out   std_logic;
        Stopped         : out   std_logic;
        Pkt             : out   std_logic;
        ErrValid        : out   std_logic;
        ErrXfer         : out   XferErr_t;
        ErrSg           : out   XferErr_t;
        -- Transfer command and result of the channel
        Cmd_Valid       : out   std_logic;
        Cmd_Ready       : in    std_logic;
        Cmd_Addr        : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        Cmd_Length      : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        Cmd_Sof         : out   std_logic;
        Cmd_Eof         : out   std_logic;
        Cmd_Keyhole     : out   std_logic;
        Res_Valid       : in    std_logic;
        Res_Ready       : out   std_logic;
        Res_Bytes       : in    std_logic_vector(LengthWidth_g - 1 downto 0);
        Res_Sof         : in    std_logic;
        Res_Eof         : in    std_logic;
        Res_Err         : in    XferErr_t;
        -- Descriptor port: fetch (8 words in order, then the end pulse) and status write
        Fetch_Req       : out   std_logic;
        Fetch_Addr      : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        Fetch_Ack       : in    std_logic;
        Fetch_Word      : in    std_logic_vector(31 downto 0);
        Fetch_WordValid : in    std_logic;
        Fetch_End       : in    std_logic;
        Fetch_Err       : in    XferErr_t;
        Upd_Req         : out   std_logic;
        Upd_Addr        : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        Upd_Data        : out   std_logic_vector(31 downto 0);
        Upd_Ack         : in    std_logic;
        Upd_End         : in    std_logic;
        Upd_Err         : in    XferErr_t;
        -- FT descriptor buffer
        Ecc_Sec         : out   std_logic;
        Ecc_Ded         : out   std_logic;
        EccInj_Valid    : in    std_logic;
        EccInj_Double   : in    std_logic;
        EccInj_Data     : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_sg_channel is

    -- Descriptor pointers without bits 5 to 0
    constant PtrWidth_c : positive := AddrWidth_g - 6;

    subtype Ptr_t is std_logic_vector(PtrWidth_c - 1 downto 0);

    -- Entry of the descriptor buffer, fields from bit 0 upwards (architecture section 6)
    constant LengthLo_c   : natural  := 0;
    constant BufferLo_c   : natural  := LengthLo_c + LengthWidth_g;
    constant AddrLo_c     : natural  := BufferLo_c + AddrWidth_g;
    constant SofBit_c     : natural  := AddrLo_c + PtrWidth_c;
    constant EofBit_c     : natural  := SofBit_c + 1;
    constant StaleBit_c   : natural  := SofBit_c + 2;
    constant KeyholeBit_c : natural  := SofBit_c + 3;
    constant EntryWidth_c : positive := SofBit_c + 4;

    -- The window of two descriptors keeps the engine one descriptor ahead (SG-FE-04)
    constant Window_c : positive := 2;

    type FetchFsm_t is (Idle_s, Request_s, Words_s);
    type UpdateFsm_t is (Idle_s, Request_s, Wait_s);
    type Ptr_a is array (0 to Window_c - 1) of Ptr_t;

    type TwoProcess_r is record
        -- Tail pointer and fetch position (sections 4.2, 4.3)
        RunPrev      : std_logic;
        Started      : std_logic;
        AtTail       : std_logic;
        NextPtr      : Ptr_t;
        LastPtr      : Ptr_t;
        TailPtr      : Ptr_t;
        -- Fetch in progress
        Fetch        : FetchFsm_t;
        FetchPtr     : Ptr_t;
        FetchCyc     : std_logic;
        FetchKey     : std_logic;
        WordCnt      : natural range 0 to 7;
        NxtWord      : std_logic_vector(63 downto 0);
        BufWord      : std_logic_vector(63 downto 0);
        CtrlWord     : std_logic_vector(31 downto 0);
        Cmplt        : std_logic;
        -- Descriptors in the buffer, issued commands without result (oldest at index 0)
        BufCnt       : natural range 0 to Window_c;
        IssCnt       : natural range 0 to Window_c;
        IssPtr       : Ptr_a;
        -- Status update (section 4.5)
        Update       : UpdateFsm_t;
        UpdPtr       : Ptr_t;
        UpdStatus    : std_logic_vector(31 downto 0);
        UpdEof       : std_logic;
        UpdXfer      : XferErr_t;
        -- Errors, the not started descriptor of a halt, the halted state (section 4.7)
        ErrStop      : std_logic;
        ErrPtr       : Ptr_t;
        StaleHold    : std_logic;                                -- A stale descriptor was fetched: no further fetch
        NsValid      : std_logic;
        NsPtr        : Ptr_t;
        Halted       : std_logic;
        -- A fetch error waiting for an event slot
        FetchErrPend : std_logic;
        FetchErrCode : XferErr_t;
        -- Outputs
        CurPtr       : Ptr_t;
        Idle         : std_logic;
        Pkt          : std_logic;
        ErrValid     : std_logic;
        ErrXfer      : XferErr_t;
        ErrSg        : XferErr_t;
    end record;

    signal r, r_next : TwoProcess_r;

    -- Descriptor buffer
    signal Buf_InData   : std_logic_vector(EntryWidth_c - 1 downto 0);
    signal Buf_InValid  : std_logic;
    signal Buf_OutData  : std_logic_vector(EntryWidth_c - 1 downto 0);
    signal Buf_OutValid : std_logic;
    signal Buf_OutReady : std_logic;
    signal Buf_OutSec   : std_logic;
    signal Buf_OutDed   : std_logic;
    signal BufInjFlip   : std_logic_vector(eccCodewordWidth(EntryWidth_c) - 1 downto 0);

    -- Head entry of the descriptor buffer
    signal HeadPtr   : Ptr_t;
    signal HeadStale : std_logic;
    signal CmdValid  : std_logic;
    signal ResReady  : std_logic;
    signal PortIdle  : std_logic;
    signal NoWork    : std_logic;

    -- The pointer bits of an address word pair: bits AddrWidth_g - 1 to 6
    function pointer (word : std_logic_vector(63 downto 0)) return Ptr_t is
    begin
        return word(AddrWidth_g - 1 downto 6);
    end function;

    -- Status word of a result (architecture section 4.5)
    function statusWord (
        bytes : std_logic_vector(LengthWidth_g - 1 downto 0);
        sof   : std_logic;
        eof   : std_logic;
        err   : XferErr_t) return std_logic_vector is
        variable S_v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        S_v(LengthWidth_g - 1 downto 0) := bytes;
        if not Mm2s_g then
            S_v(26) := eof;                                    -- RXEOF
            S_v(27) := sof;                                    -- RXSOF
        end if;
        -- DMAIntErr; S2MM also with the slave and the decode error (interpretation I13)
        if err = ErrInt_c or (not Mm2s_g and err /= ErrNone_c) then
            S_v(28) := '1';
        end if;
        if err = ErrSlv_c then
            S_v(29) := '1';                                    -- DMASlvErr
        end if;
        if err = ErrDec_c then
            S_v(30) := '1';                                    -- DMADecErr
        end if;
        if err = ErrNone_c then
            S_v(31) := '1';                                    -- Cmplt (interpretation SGI-02)
        end if;
        return S_v;
    end function;

begin

    -- *** Head of the descriptor buffer ***
    HeadPtr   <= Buf_OutData(AddrLo_c + PtrWidth_c - 1 downto AddrLo_c);
    HeadStale <= Buf_OutData(StaleBit_c);

    -- A command is presented only while it can be accepted (section 4.4)
    CmdValid <= '1' when Buf_OutValid = '1' and HeadStale = '0' and Run = '1' and Drain = '0' and r.ErrStop = '0' else
                '0';
    -- One status update at a time
    ResReady <= '1' when r.Update = Idle_s else '0';

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Count_v : natural range 0 to 2 * Window_c + 1;
        variable Event_v : boolean;
        variable Ns_v    : boolean;
        variable Iss_v   : natural range 0 to Window_c;
    begin
        v := r;

        -- Defaults
        v.Pkt      := '0';
        v.ErrValid := '0';
        v.ErrXfer  := ErrNone_c;
        v.ErrSg    := ErrNone_c;
        Event_v    := false;
        v.RunPrev  := Run;

        -- Descriptors in the window: a fetch in progress, the buffer, the issued commands. The counters below
        -- saturate: the buffer output and the handshakes of other processes follow a clock edge one delta cycle
        -- after the registers, so a delta cycle of the simulation can combine an old handshake with a new count
        Count_v := r.BufCnt + r.IssCnt;
        if r.Fetch /= Idle_s then
            Count_v := Count_v + 1;
        end if;

        -- *** Start (section 4.2) ***
        if Run = '1' and r.RunPrev = '0' then
            v.NextPtr   := CurDesc(AddrWidth_g - 1 downto 6);
            v.Started   := '0';
            v.AtTail    := '0';
            v.ErrStop   := '0';
            v.StaleHold := '0';
            v.NsValid   := '0';
            v.Halted    := '0';
        end if;

        -- *** Tail pointer write ***
        if TailWr = '1' then
            v.TailPtr := Tail(AddrWidth_g - 1 downto 6);
            if r.Started = '0' then
                v.Started := '1';
            elsif r.Idle = '1' then
                v.AtTail := '0';
            elsif r.LastPtr /= Tail(AddrWidth_g - 1 downto 6) then
                v.AtTail := '0';
            end if;
        end if;

        -- *** Fetch (section 4.3) ***
        case r.Fetch is

            when Idle_s =>
                if Run = '1' and Drain = '0' and r.ErrStop = '0' and r.StaleHold = '0' and r.Started = '1' and
                   r.AtTail = '0' and Count_v < Window_c and r.Halted = '0' then
                    v.FetchPtr := r.NextPtr;
                    v.FetchCyc := Cyclic;
                    v.FetchKey := Keyhole;
                    v.Fetch    := Request_s;
                end if;

            when Request_s =>
                -- The request is withdrawn when it can no longer be granted
                if Fetch_Ack = '1' then
                    v.WordCnt := 0;
                    v.Fetch   := Words_s;
                elsif Run = '0' or Drain = '1' then
                    v.Fetch := Idle_s;
                end if;

            when Words_s =>
                if Fetch_WordValid = '1' then

                    -- NXTDESC, NXTDESC_MSB, BUFFER_ADDRESS, BUFFER_ADDRESS_MSB, two reserved words, CONTROL, STATUS;
                    -- the upper words only above 32 address bits (SG-IF-03)
                    case r.WordCnt is
                        when 0 => v.NxtWord(31 downto 0) := Fetch_Word;
                        when 1 =>
                            if AddrWidth_g > 32 then
                                v.NxtWord(63 downto 32) := Fetch_Word;
                            end if;
                        when 2 => v.BufWord(31 downto 0) := Fetch_Word;
                        when 3 =>
                            if AddrWidth_g > 32 then
                                v.BufWord(63 downto 32) := Fetch_Word;
                            end if;
                        when 6 => v.CtrlWord := Fetch_Word;
                        when 7 => v.Cmplt := Fetch_Word(31);
                        when others => null;
                    end case;

                    if r.WordCnt /= 7 then
                        v.WordCnt := r.WordCnt + 1;
                    end if;
                end if;
                if Fetch_End = '1' then
                    v.Fetch := Idle_s;
                    if Drain = '1' then
                        -- Read data of a drain is discarded
                        null;
                    elsif Fetch_Err /= ErrNone_c then
                        -- Engine error of the access (SG-ER-02); nothing enters the buffer
                        if r.ErrStop = '0' then
                            v.ErrPtr := r.FetchPtr;
                        end if;
                        v.ErrStop      := '1';
                        v.FetchErrPend := '1';
                        v.FetchErrCode := Fetch_Err;
                    else
                        -- The entry enters the buffer (Buf_InValid); the tail check uses a tail pointer written in
                        -- the same clock cycle (SG-FE-03, SG-CY-01)
                        if r.BufCnt < Window_c then
                            v.BufCnt := r.BufCnt + 1;
                        end if;
                        v.LastPtr := r.FetchPtr;
                        -- Nothing is fetched after a stale descriptor; its error follows at the head of the buffer
                        if r.Cmplt = '1' and r.FetchCyc = '0' then
                            v.StaleHold := '1';
                        end if;
                        v.NextPtr := pointer(r.NxtWord);
                        if r.FetchPtr = v.TailPtr and r.FetchCyc = '0' then
                            v.AtTail := '1';
                        else
                            v.AtTail := '0';
                        end if;
                    end if;
                end if;

            -- coverage off
            when others =>
                -- Unreachable, safe recovery
                v.Fetch := Idle_s;
            -- coverage on

        end case;

        -- *** Result (section 4.5): the oldest issued descriptor leaves the queue ***
        Iss_v := r.IssCnt;
        if Res_Valid = '1' and ResReady = '1' then
            v.IssPtr(0) := r.IssPtr(1);
            if Iss_v > 0 then
                Iss_v := Iss_v - 1;
            end if;
            Ns_v := unsigned(Res_Bytes) = 0 and Res_Eof = '0' and Res_Err = ErrNone_c and Run = '0';
            if Ns_v then
                -- Not started: no status write, CURDESC held at this descriptor
                if r.NsValid = '0' then
                    v.NsPtr := r.IssPtr(0);
                end if;
                v.NsValid := '1';
            else
                v.UpdPtr    := r.IssPtr(0);
                v.UpdStatus := statusWord(Res_Bytes, Res_Sof, Res_Eof, Res_Err);
                v.UpdEof    := Res_Eof;
                v.UpdXfer   := Res_Err;
                v.Update    := Request_s;
                if Res_Err /= ErrNone_c then
                    -- No further command; the first error names CURDESC
                    if r.ErrStop = '0' then
                        v.ErrPtr := r.IssPtr(0);
                    end if;
                    v.ErrStop := '1';
                end if;
            end if;
        end if;

        -- *** Issue (section 4.4): the accepted command joins the queue ***
        if CmdValid = '1' and Cmd_Ready = '1' and v.BufCnt > 0 and Iss_v < Window_c then
            v.BufCnt        := v.BufCnt - 1;
            v.IssPtr(Iss_v) := HeadPtr;
            Iss_v           := Iss_v + 1;
        end if;
        v.IssCnt := Iss_v;
        -- Emptying the buffer after a halt (section 4.7)
        if r.Halted = '1' and Buf_OutValid = '1' and v.BufCnt > 0 then
            v.BufCnt := v.BufCnt - 1;
        end if;

        -- *** Status update ***
        case r.Update is

            when Idle_s =>
                null;

            when Request_s =>
                if Upd_Ack = '1' then
                    v.Update := Wait_s;
                elsif Drain = '1' then
                    -- No status write is requested during a drain
                    v.Update := Idle_s;
                end if;

            when Wait_s =>
                if Upd_End = '1' then
                    v.Update := Idle_s;
                    if Drain = '0' then
                        if Upd_Err = ErrNone_c and r.UpdXfer = ErrNone_c then
                            -- The status of the packet is in memory (SG-UP-04, SG-UP-05)
                            v.Pkt := r.UpdEof;
                        else
                            -- Transfer error and engine error of the write (SG-ER-01, SG-ER-02)
                            v.ErrValid := '1';
                            v.ErrXfer  := r.UpdXfer;
                            v.ErrSg    := Upd_Err;
                            Event_v    := true;
                            if Upd_Err /= ErrNone_c then
                                if v.ErrStop = '0' then
                                    v.ErrPtr := r.UpdPtr;
                                end if;
                                v.ErrStop := '1';
                            end if;
                        end if;
                    end if;
                end if;

            -- coverage off
            when others =>
                -- Unreachable, safe recovery
                v.Update := Idle_s;
            -- coverage on

        end case;

        -- *** Events of the fetch: a fetch error, else a stale descriptor at the head (SG-FE-05) ***
        if not Event_v and r.FetchErrPend = '1' then
            v.ErrValid     := '1';
            v.ErrSg        := r.FetchErrCode;
            v.FetchErrPend := '0';
            Event_v        := true;
        end if;
        if not Event_v and r.FetchErrPend = '0' and Buf_OutValid = '1' and HeadStale = '1' and Run = '1' and
           Drain = '0' and r.ErrStop = '0' then
            v.ErrValid := '1';
            v.ErrSg    := ErrInt_c;
            v.ErrStop  := '1';
            v.ErrPtr   := HeadPtr;
        end if;
        if Drain = '1' then
            v.FetchErrPend := '0';
            v.ErrValid     := '0';
            v.Pkt          := '0';
        end if;

        -- *** Halt: nothing outstanding once Run is '0' (section 4.7) ***
        if Run = '0' and r.Fetch = Idle_s and r.IssCnt = 0 and r.Update = Idle_s then
            v.Halted := '1';
        end if;

        -- *** Current descriptor pointer (section 4.6) ***
        if r.Halted = '0' then
            if r.ErrStop = '1' then
                v.CurPtr := r.ErrPtr;
            elsif r.NsValid = '1' then
                v.CurPtr := r.NsPtr;
            elsif r.IssCnt /= 0 then
                v.CurPtr := r.IssPtr(0);
            elsif Buf_OutValid = '1' then
                v.CurPtr := HeadPtr;
            elsif r.AtTail = '1' then
                v.CurPtr := r.LastPtr;
            else
                v.CurPtr := r.NextPtr;
            end if;
        end if;

        -- Idle: the tail is completed and its status written (SG-FE-03)
        if r.Started = '1' and r.AtTail = '1' and Count_v = 0 and r.Update = Idle_s then
            v.Idle := '1';
        else
            v.Idle := '0';
        end if;

        r_next <= v;
    end process;

    -- *** Outputs ***
    CurPtr      <= r.CurPtr & "000000";
    Idle        <= r.Idle;
    Pkt         <= r.Pkt;
    ErrValid    <= r.ErrValid;
    ErrXfer     <= r.ErrXfer;
    ErrSg       <= r.ErrSg;
    Cmd_Valid   <= CmdValid;
    Cmd_Addr    <= Buf_OutData(BufferLo_c + AddrWidth_g - 1 downto BufferLo_c);
    Cmd_Length  <= Buf_OutData(LengthLo_c + LengthWidth_g - 1 downto LengthLo_c);
    Cmd_Sof     <= Buf_OutData(SofBit_c);
    Cmd_Eof     <= Buf_OutData(EofBit_c);
    Cmd_Keyhole <= Buf_OutData(KeyholeBit_c);
    Res_Ready   <= ResReady;
    Fetch_Req   <= '1' when r.Fetch = Request_s and Run = '1' and Drain = '0' else '0';
    Fetch_Addr  <= r.FetchPtr & "000000";
    Upd_Req     <= '1' when r.Update = Request_s and Drain = '0' else '0';
    Upd_Addr    <= r.UpdPtr & "011100";                       -- STATUS at offset 0x1C
    Upd_Data    <= r.UpdStatus;

    -- Stopped: nothing outstanding at the port, and either a drain or a halted channel with an empty buffer, or a
    -- running channel without work (section 8)
    PortIdle <= '1' when r.Fetch /= Words_s and r.Update /= Wait_s else '0';
    NoWork   <= '1' when r.Fetch = Idle_s and r.BufCnt = 0 and r.IssCnt = 0 and r.Update = Idle_s else '0';
    Stopped  <= PortIdle and (Drain or (r.Halted and not Buf_OutValid and NoWork) or (Run and NoWork));

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.RunPrev      <= '0';
                r.Started      <= '0';
                r.AtTail       <= '0';
                r.NextPtr      <= (others => '0');
                r.LastPtr      <= (others => '0');
                r.TailPtr      <= (others => '0');
                r.Fetch        <= Idle_s;
                r.FetchPtr     <= (others => '0');
                r.FetchCyc     <= '0';
                r.FetchKey     <= '0';
                r.WordCnt      <= 0;
                r.NxtWord      <= (others => '0');
                r.BufWord      <= (others => '0');
                r.CtrlWord     <= (others => '0');
                r.Cmplt        <= '0';
                r.BufCnt       <= 0;
                r.IssCnt       <= 0;
                r.IssPtr       <= (others => (others => '0'));
                r.Update       <= Idle_s;
                r.UpdPtr       <= (others => '0');
                r.UpdStatus    <= (others => '0');
                r.UpdEof       <= '0';
                r.UpdXfer      <= ErrNone_c;
                r.ErrStop      <= '0';
                r.ErrPtr       <= (others => '0');
                r.StaleHold    <= '0';
                r.NsValid      <= '0';
                r.NsPtr        <= (others => '0');
                r.Halted       <= '1';
                r.FetchErrPend <= '0';
                r.FetchErrCode <= ErrNone_c;
                r.CurPtr       <= (others => '0');
                r.Idle         <= '0';
                r.Pkt          <= '0';
                r.ErrValid     <= '0';
                r.ErrXfer      <= ErrNone_c;
                r.ErrSg        <= ErrNone_c;
            end if;
        end if;
    end process;

    -- *** Descriptor buffer (SG-1) ***
    Buf_InData(LengthLo_c + LengthWidth_g - 1 downto LengthLo_c) <= r.CtrlWord(LengthWidth_g - 1 downto 0);
    Buf_InData(BufferLo_c + AddrWidth_g - 1 downto BufferLo_c)   <= r.BufWord(AddrWidth_g - 1 downto 0);
    Buf_InData(AddrLo_c + PtrWidth_c - 1 downto AddrLo_c)        <= r.FetchPtr;
    Buf_InData(SofBit_c)                                         <= r.CtrlWord(27) when Mm2s_g else '0';
    Buf_InData(EofBit_c)                                         <= r.CtrlWord(26) when Mm2s_g else '0';
    Buf_InData(StaleBit_c)                                       <= r.Cmplt and not r.FetchCyc;
    Buf_InData(KeyholeBit_c)                                     <= r.FetchKey;

    Buf_InValid  <= '1' when r.Fetch = Words_s and Fetch_End = '1' and Fetch_Err = ErrNone_c and Drain = '0' else '0';
    Buf_OutReady <= '1' when (CmdValid = '1' and Cmd_Ready = '1') or r.Halted = '1' else '0';
    BufInjFlip   <= flipPattern(BufInjFlip'length, EccInj_Double, EccInj_Data);

    i_buf : entity olo.olo_ft_fifo_sync
        generic map (
            Width_g => EntryWidth_c,
            Depth_g => Window_c
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Data           => Buf_InData,
            In_Valid          => Buf_InValid,
            Out_Data          => Buf_OutData,
            Out_Valid         => Buf_OutValid,
            Out_Ready         => Buf_OutReady,
            Out_EccSec        => Buf_OutSec,
            Out_EccDed        => Buf_OutDed,
            In_ErrInj_BitFlip => BufInjFlip,
            In_ErrInj_Valid   => EccInj_Valid
        );

    -- One event per word read from the buffer
    Ecc_Sec <= Buf_OutSec and Buf_OutValid and Buf_OutReady;
    Ecc_Ded <= Buf_OutDed and Buf_OutValid and Buf_OutReady;

end architecture;
