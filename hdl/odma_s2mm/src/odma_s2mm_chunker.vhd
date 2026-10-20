---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Chunk former of the S2MM channel (S2-1): takes the S2MM stream into the data buffer, cuts each
-- packet into chunks of one burst and writes a descriptor per chunk; discards the rest of a packet
-- that a halt interrupts. With Split_g the stream passes a stream split that cuts every packet at
-- the end of the buffer of each command, so that each buffer starts in lane 0, and the chunks
-- follow the bursts of the buffer address.
--
-- Documentation: hdl/odma_s2mm/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;

library work;
    use work.odma_pkg.all;
    use work.odma_s2mm_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_s2mm_chunker is
    generic (
        StreamWidth_g : positive;
        MemWidth_g    : positive;
        ChunkBeats_g  : positive;
        LengthWidth_g : positive := 14;
        Split_g       : boolean  := false;
        -- Split_g: beats by which every chunk of a buffer that starts inside a stream word is shorter (shortBeats)
        ShortBeats_g  : natural  := 0
    );
    port (
        -- Control Signals
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        Run          : in    std_logic;
        Drain        : in    std_logic;
        -- S2MM stream
        S_S2mm_Data  : in    std_logic_vector(StreamWidth_g - 1 downto 0);
        S_S2mm_Keep  : in    std_logic_vector(StreamWidth_g / 8 - 1 downto 0);
        S_S2mm_Last  : in    std_logic;
        S_S2mm_Valid : in    std_logic;
        S_S2mm_Ready : out   std_logic;
        -- Segment of the stream split (Split_g): the buffer length of the accepted command, the address bits of its
        -- buffer below the burst size (a chunk of ChunkBeats_g beats) and its keyhole
        Seg_Valid    : in    std_logic                                                             := '0';
        Seg_Size     : in    std_logic_vector(LengthWidth_g - 1 downto 0)                          := (others => '0');
        Seg_Ready    : out   std_logic;
        Seg_Offset   : in    std_logic_vector(log2(ChunkBeats_g * StreamWidth_g / 8) - 1 downto 0) := (others => '0');
        Seg_Keyhole  : in    std_logic                                                             := '0';
        -- Split_g: S2-2 flushes the rest of a packet after a write error
        FlushReq     : in    std_logic                                                             := '0';
        -- Data buffer (write side)
        Data_Data    : out   std_logic_vector(StreamWidth_g - 1 downto 0);
        Data_Valid   : out   std_logic;
        Data_Ready   : in    std_logic;
        -- Chunk buffer (write side)
        Desc_Data    : out   std_logic_vector(DescWidth_c - 1 downto 0);
        Desc_Valid   : out   std_logic;
        Desc_Ready   : in    std_logic;
        -- A descriptor of the open packet is still to come: the packet is open and its rest is not discarded
        DescPend     : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_s2mm_chunker is

    constant StreamBytes_c : positive := StreamWidth_g / 8;
    constant MemBytes_c    : positive := MemWidth_g / 8;
    -- Discard segments: the largest segment of the split
    constant MaxSeg_c      : positive := 2**LengthWidth_g - 1;
    -- Last beat of a full chunk and of a short chunk (Split_g, a buffer that starts inside a stream word)
    constant FullLast_c    : natural := ChunkBeats_g - 1;
    constant ShortLast_c   : natural := ChunkBeats_g - 1 - ShortBeats_g;

    -- Lanes 0 to n - 1 set
    function thermo (
        n : natural;
        w : positive) return std_logic_vector is
        variable K_v : std_logic_vector(w - 1 downto 0) := (others => '0');
    begin

        for i in 0 to w - 1 loop
            if i < n then
                K_v(i) := '1';
            end if;
        end loop;

        return K_v;
    end function;

    type ChunkerFsm_t is (Normal_s, Discard_s);

    type TwoProcess_r is record
        State    : ChunkerFsm_t;
        Beats    : natural range 0 to ChunkBeats_g - 1;     -- Beats of the chunk in progress in the data buffer
        Limit    : natural range 0 to ChunkBeats_g - 1;     -- Index of the last beat of the chunk in progress
        Rest     : natural range 0 to ChunkBeats_g - 1;     -- Split_g: Limit of the later chunks of the buffer
        InPacket : std_logic;                               -- A packet passed the chunk logic without its end
        StrmOpen : std_logic;                               -- Split_g: a packet entered the split without its end
        EndPend  : std_logic;                               -- Split_g: the end of a packet is in the split
        NeedSeg  : std_logic;                               -- Split_g: a segment ended inside the packet, none active
    end record;

    signal r, r_next : TwoProcess_r;

    signal Take      : std_logic;
    signal Drop      : std_logic;
    signal Ready_i   : std_logic;
    signal S2mmReady : std_logic;
    signal Open_i    : std_logic;
    signal Complete  : std_logic; -- Split_g: the rest of the packet in the split belongs to the active segment
    signal Cut       : std_logic; -- A halt cuts the open packet
    signal SegTaken  : std_logic; -- Split_g: the split takes a segment

    -- Input of the chunk logic: the stream, or the output of the split
    signal In_Data   : std_logic_vector(StreamWidth_g - 1 downto 0);
    signal In_Keep   : std_logic_vector(StreamBytes_c - 1 downto 0);
    signal In_Last   : std_logic; -- The beat ends the transfer: the packet ends, or with Split_g the buffer
    signal In_PktEnd : std_logic; -- The beat ends the packet
    signal In_Valid  : std_logic;

begin

    -- *** Input ***
    -- Split_g: the end of the packet has entered the split and no segment ended inside the packet since, so the rest
    -- of the packet in the split belongs to the active segment: the packet is complete at the stream port and is
    -- taken in whole, also when Run falls (S2-HA-01). A segment that ends inside the packet sets NeedSeg; the rest then
    -- waits for the next buffer, and a halt cuts the packet
    Complete <= r.EndPend and not r.NeedSeg;
    -- Normal operation: the beat goes into the data buffer, a chunk end also writes its descriptor; the
    -- input waits while the channel is halted (except for a complete packet) or drains, and while a buffer is full
    Take <= '1' when r.State = Normal_s and (Run = '1' or Complete = '1') and Drain = '0' and Data_Ready = '1' and
                     Desc_Ready = '1' else
            '0';
    -- Discard of the rest of an interrupted packet
    Drop <= '1' when r.State = Discard_s and Drain = '0' else '0';

    Ready_i <= Take or Drop;

    -- A packet is open: it passed the chunk logic, or with Split_g its beats or its end are still in the split
    Open_i <= r.InPacket or r.StrmOpen or r.EndPend;
    -- A halt cuts an open packet that is not complete
    Cut <= Open_i and not Complete;

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable Desc_v : Desc_r;
        variable Off_v  : natural;
    begin
        v := r;

        -- Defaults
        Data_Valid <= '0';
        Desc_Valid <= '0';
        Desc_v     := (Bytes => (others => '0'),
                       Beats => (others => '0'),
                       Pend => '0',
                       Discard => '0',
                       PktEnd => '0');

        -- Split_g: a beat with the end of a segment but not of the packet leaves the split without a segment; the
        -- next segment (of a command, or of the discard) ends that state. Only registers decide the discard segment,
        -- since the split takes a segment in the clock cycle in which its previous one has just ended
        if Ready_i = '1' and In_Valid = '1' and In_Last = '1' then
            v.NeedSeg := not In_PktEnd;
        end if;
        if SegTaken = '1' then
            v.NeedSeg := '0';
        end if;

        -- Split_g: the end of a packet is in the split from the beat with TLast at the stream port to the beat with
        -- Out_InLast at the output; the split takes no beat of the next packet before that end has left its carry,
        -- so at most one packet end is in the split, and a new end in the same clock cycle wins
        if Split_g and Ready_i = '1' and In_Valid = '1' and In_PktEnd = '1' then
            v.EndPend := '0';
        end if;
        -- Split_g: a packet is open at the stream port from its first beat to the beat with TLast
        if Split_g and S_S2mm_Valid = '1' and S2mmReady = '1' then
            v.StrmOpen := not S_S2mm_Last;
            if S_S2mm_Last = '1' then
                v.EndPend := '1';
            end if;
        end if;

        case r.State is

            when Normal_s =>
                if Take = '1' and In_Valid = '1' then
                    Data_Valid <= '1';
                    v.InPacket := not In_PktEnd;
                    -- End of a chunk: the chunk is full or the transfer ends (the cut of olo_base_chunker, from the
                    -- beat count that the descriptor needs anyway)
                    if r.Beats >= r.Limit or In_Last = '1' then
                        -- Descriptor of the chunk: the full beats and the valid bytes of the last beat of a transfer
                        Desc_v.Beats := to_unsigned(r.Beats + 1, 16);
                        Desc_v.Bytes := to_unsigned(r.Beats * StreamBytes_c, 16);
                        if In_Last = '1' then
                            Desc_v.Bytes := Desc_v.Bytes + keepBytes(In_Keep);
                        else
                            Desc_v.Bytes := Desc_v.Bytes + StreamBytes_c;
                        end if;
                        Desc_v.Pend   := In_Last;
                        Desc_v.PktEnd := In_PktEnd;
                        Desc_Valid    <= '1';
                        v.Beats       := 0;
                        v.Limit       := r.Rest;
                    else
                        v.Beats := r.Beats + 1;
                    end if;
                elsif ((Run = '0' and Cut = '1') or (Split_g and FlushReq = '1' and Open_i = '1')) and Drain = '0' and
                      Desc_Ready = '1' then
                    -- A halt inside a packet that is not complete, or with Split_g the flush after a write error: the
                    -- stored part of the packet is not written, the rest is discarded
                    Desc_v.Beats   := to_unsigned(r.Beats, 16);
                    Desc_v.Pend    := '1';
                    Desc_v.Discard := '1';
                    Desc_v.PktEnd  := '1';
                    Desc_Valid     <= '1';
                    v.Beats        := 0;
                    v.State        := Discard_s;
                end if;

            when Discard_s =>
                if Drop = '1' and In_Valid = '1' and In_PktEnd = '1' then
                    v.InPacket := '0';
                    v.State    := Normal_s;
                end if;

            -- coverage off
            when others =>
                v.State := Normal_s; -- unreachable, safe recovery
            -- coverage on

        end case;

        -- Split_g: the chunk plan of the buffer whose segment the split takes (architecture section 4.2). Every beat of
        -- the buffers before has left the split then, since S2-2 offers a segment only after the descriptor with the
        -- last beat of the buffer before. A keyhole buffer and a buffer at a multiple of the memory word (a full chunk
        -- covers B memory words) have full chunks; at another multiple of the stream width the first chunk ends at the
        -- burst boundary above the address and the later chunks are aligned; inside a stream word every chunk is
        -- ShortBeats_g beats shorter
        Off_v := to_integer(unsigned(Seg_Offset));
        if Split_g and SegTaken = '1' and r.State = Normal_s then
            if Seg_Keyhole = '1' or Off_v mod MemBytes_c = 0 then
                v.Limit := FullLast_c;
                v.Rest  := FullLast_c;
            elsif Off_v mod StreamBytes_c = 0 then
                v.Limit := FullLast_c - Off_v / StreamBytes_c;
                v.Rest  := FullLast_c;
            else
                v.Limit := ShortLast_c;
                v.Rest  := ShortLast_c;
            end if;
        end if;

        Desc_Data <= toSlv(Desc_v);
        r_next    <= v;
    end process;

    -- Outputs
    Data_Data    <= In_Data;
    DescPend     <= Open_i when r.State = Normal_s else '0';
    S_S2mm_Ready <= S2mmReady;

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State    <= Normal_s;
                r.Beats    <= 0;
                r.Limit    <= FullLast_c;
                r.Rest     <= FullLast_c;
                r.InPacket <= '0';
                r.StrmOpen <= '0';
                r.EndPend  <= '0';
                r.NeedSeg  <= '0';
            end if;
        end if;
    end process;

    -- *** The stream directly (DR mode) ***
    g_direct : if not Split_g generate
        In_Data   <= S_S2mm_Data;
        In_Keep   <= S_S2mm_Keep;
        In_Last   <= S_S2mm_Last;
        In_PktEnd <= S_S2mm_Last;
        In_Valid  <= S_S2mm_Valid;
        S2mmReady <= Ready_i;
        Seg_Ready <= '0';
        SegTaken  <= '0';
    end generate;

    -- *** Stream split at the end of every buffer (Scatter/Gather Mode) ***
    g_split : if Split_g generate
        signal InEn       : std_logic;
        signal SplitRst   : std_logic;
        signal SplitBe    : std_logic_vector(StreamBytes_c - 1 downto 0);
        signal SplitValid : std_logic;
        signal SplitReady : std_logic;
        signal SegValid   : std_logic;
        signal SegSize    : std_logic_vector(LengthWidth_g - 1 downto 0);
        signal SegReady   : std_logic;
    begin
        -- The stream enters the split only while the channel runs (S2-ST-01) or, while halted, S2-1 discards the rest
        -- of a packet; the next packet waits at the port, since the split gets no segment for it (S2-HA-01)
        InEn       <= '1' when (Run = '1' or r.State = Discard_s) and Drain = '0' else '0';
        SplitValid <= S_S2mm_Valid and InEn;
        S2mmReady  <= SplitReady and InEn;
        -- Valid bytes: all bytes of a beat without TLast, the bytes up to the first lane with TKeep '0' of the beat
        -- with TLast (I10), contiguous from lane 0 as the split requires
        SplitBe <= thermo(keepBytes(S_S2mm_Keep), StreamBytes_c) when S_S2mm_Last = '1' else (others => '1');

        -- Reset: with Rst, during a drain, and while halted without a packet open, which clears the segment of a
        -- transfer that ended before its packet arrived
        SplitRst <= '1' when Rst = '1' or Drain = '1' or (Run = '0' and Open_i = '0' and r.State = Normal_s) else
                    '0';

        -- Segments: the buffer length of the command, or MaxSeg_c while the rest of a packet is discarded and the
        -- split has no segment for it; both come from registers (olo_base_stream_split, Integration)
        SegValid  <= r.NeedSeg when r.State = Discard_s else Seg_Valid;
        SegTaken  <= SegValid and SegReady;
        SegSize   <= std_logic_vector(to_unsigned(MaxSeg_c, LengthWidth_g)) when r.State = Discard_s else Seg_Size;
        Seg_Ready <= SegReady when r.State = Normal_s else '0';

        i_split : entity olo.olo_base_stream_split
            generic map (
                Width_g      => StreamWidth_g,
                MaxSegSize_g => MaxSeg_c
            )
            port map (
                Clk        => Clk,
                Rst        => SplitRst,
                In_Data    => S_S2mm_Data,
                In_Be      => SplitBe,
                In_Valid   => SplitValid,
                In_Ready   => SplitReady,
                In_Last    => S_S2mm_Last,
                Seg_Size   => SegSize,
                Seg_Valid  => SegValid,
                Seg_Ready  => SegReady,
                Out_Data   => In_Data,
                Out_Be     => In_Keep,
                Out_Valid  => In_Valid,
                Out_Ready  => Ready_i,
                Out_Last   => In_Last,
                Out_InLast => In_PktEnd
            );

    end generate;

end architecture;
