---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Chunk former of the S2MM channel (S2-1): takes the S2MM stream into the data buffer, cuts each
-- packet into chunks of one burst and writes a descriptor per chunk; discards the rest of a packet
-- that a halt interrupts.
--
-- Documentation: hdl/odma_s2mm/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.odma_pkg.all;
    use work.odma_s2mm_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_s2mm_chunker is
    generic (
        StreamWidth_g : positive;
        ChunkBeats_g  : positive
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
        -- Data buffer (write side)
        Data_Data    : out   std_logic_vector(StreamWidth_g - 1 downto 0);
        Data_Valid   : out   std_logic;
        Data_Ready   : in    std_logic;
        -- Chunk buffer (write side)
        Desc_Data    : out   std_logic_vector(DescWidth_c - 1 downto 0);
        Desc_Valid   : out   std_logic;
        Desc_Ready   : in    std_logic;
        -- A packet started and its TLast not yet taken
        PacketOpen   : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_s2mm_chunker is

    constant StreamBytes_c : positive := StreamWidth_g / 8;

    type ChunkerFsm_t is (Normal_s, Discard_s);

    type TwoProcess_r is record
        State    : ChunkerFsm_t;
        Beats    : natural range 0 to ChunkBeats_g - 1;     -- Beats of the chunk in progress in the data buffer
        InPacket : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal Take    : std_logic;
    signal Drop    : std_logic;
    signal Ready_i : std_logic;

begin

    -- *** Input ***
    -- Normal operation: the beat goes into the data buffer, a chunk end also writes its descriptor; the
    -- input waits while the channel is halted or drains, and while a buffer is full
    Take <= '1' when r.State = Normal_s and Run = '1' and Drain = '0' and Data_Ready = '1' and Desc_Ready = '1' else
            '0';
    -- Discard of the rest of an interrupted packet
    Drop <= '1' when r.State = Discard_s and Drain = '0' else '0';

    Ready_i      <= Take or Drop;
    S_S2mm_Ready <= Ready_i;

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable Desc_v : Desc_r;
    begin
        v := r;

        -- Defaults
        Data_Valid <= '0';
        Desc_Valid <= '0';
        Desc_v     := (Bytes => (others => '0'),
                       Beats => (others => '0'),
                       Pend => '0',
                       Discard => '0');

        case r.State is

            when Normal_s =>
                if Take = '1' and S_S2mm_Valid = '1' then
                    Data_Valid <= '1';
                    v.InPacket := not S_S2mm_Last;
                    -- End of a chunk: the chunk is full or the packet ends (the cut of olo_base_chunker, from the
                    -- beat count that the descriptor needs anyway)
                    if r.Beats = ChunkBeats_g - 1 or S_S2mm_Last = '1' then
                        -- Descriptor of the chunk: the full beats and the valid bytes of the last beat of a packet
                        Desc_v.Beats := to_unsigned(r.Beats + 1, 16);
                        Desc_v.Bytes := to_unsigned(r.Beats * StreamBytes_c, 16);
                        if S_S2mm_Last = '1' then
                            Desc_v.Bytes := Desc_v.Bytes + keepBytes(S_S2mm_Keep);
                        else
                            Desc_v.Bytes := Desc_v.Bytes + StreamBytes_c;
                        end if;
                        Desc_v.Pend := S_S2mm_Last;
                        Desc_Valid  <= '1';
                        v.Beats     := 0;
                    else
                        v.Beats := r.Beats + 1;
                    end if;
                elsif Run = '0' and Drain = '0' and r.InPacket = '1' and Desc_Ready = '1' then
                    -- A halt inside a packet: the stored part of the packet is not written, the rest is discarded
                    Desc_v.Beats   := to_unsigned(r.Beats, 16);
                    Desc_v.Pend    := '1';
                    Desc_v.Discard := '1';
                    Desc_Valid     <= '1';
                    v.Beats        := 0;
                    v.State        := Discard_s;
                end if;

            when Discard_s =>
                if Drop = '1' and S_S2mm_Valid = '1' and S_S2mm_Last = '1' then
                    v.InPacket := '0';
                    v.State    := Normal_s;
                end if;

            -- coverage off
            when others =>
                v.State := Normal_s; -- unreachable, safe recovery
            -- coverage on

        end case;

        Desc_Data <= toSlv(Desc_v);
        r_next    <= v;
    end process;

    -- Outputs
    Data_Data  <= S_S2mm_Data;
    PacketOpen <= r.InPacket;

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State    <= Normal_s;
                r.Beats    <= 0;
                r.InPacket <= '0';
            end if;
        end if;
    end process;

end architecture;
