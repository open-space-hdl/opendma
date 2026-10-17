---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types shared by the harness and the testbench of odma_s2mm: the queue of the packets the stream
-- generator sends, the behaviour of the generator and the observations of the harness.
--
-- Documentation: hdl/odma_s2mm/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_s2mm_tb_pkg is

    constant ClkPeriod_c : time := 10 ns;

    -- Seed of the packet data: byte n of a packet from the source address a is odmaMemByte(a + n, SrcSeed_c)
    constant SrcSeed_c : natural := 101;
    -- Seed of the pre-fill of the destination
    constant DstSeed_c : natural := 202;

    -- TKeep of a packet
    type KeepMode_t is (
        KeepNormal,   -- All lanes of the beats before the last one, the valid bytes of the last beat
        KeepZeroLast, -- An additional last beat without valid bytes after the bytes (a multiple of the beat)
        KeepHoles,    -- Beats before the last one with random lanes deasserted (the bytes still count)
        KeepGapLast   -- The last beat has the valid bytes, a deasserted lane, then asserted lanes (not counted)
    );

    constant MaxPackets_c : positive := 16;

    type PktQueue_t is protected

        procedure push (
            src   : unsigned(63 downto 0);
            bytes : natural;
            mode  : KeepMode_t := KeepNormal);

        impure function count return natural;

        impure function headSrc return unsigned;

        impure function headBytes return natural;

        impure function headMode return KeepMode_t;

        procedure pop;

    end protected;

    shared variable Pkts_v : PktQueue_t;

    -- TValid of the stream generator
    type GenCfg_r is record
        Percent : natural;   -- Percentage of clock cycles with TValid high while a packet is sent
        Hold    : std_logic; -- '1': no beat
    end record;

    constant GenAlways_c : GenCfg_r := (Percent => 100, Hold => '0');

    constant MaxResults_c : positive := 64;

    type Result_r is record
        Bytes : natural;
        Sof   : std_logic;
        Eof   : std_logic;
        Err   : std_logic_vector(1 downto 0);
        Cycle : natural;
    end record;

    type Results_a is array (0 to MaxResults_c - 1) of Result_r;
    type Nat3_a is array (0 to 2) of natural;

    -- Observations of the harness; a cycle number is the count of rising clock edges before that cycle. The
    -- stream counters restart when StreamClear toggles.
    type Obs_r is record
        Cycle     : natural;
        ResCount  : natural;
        Results   : Results_a;
        Beats     : natural; -- Stream handshakes
        FirstBeat : natural; -- Clock cycles of the first and of the last stream handshake
        LastBeat  : natural;
        Packets   : natural; -- Packets sent completely (not restarted)
        LastSent  : natural; -- Clock cycle of the handshake of the last TLast
        RunBeats  : natural; -- Stream handshakes in clock cycles with Run '1' (taken before a halt)
        RunPkts   : natural; -- Handshakes with TLast in clock cycles with Run '1'
        AwCount   : natural; -- AW handshakes
        BCount    : natural; -- B handshakes
        AwBadAttr : natural; -- AW handshakes with AwSize, AwBurst, AwLock, AwCache or AwProt not as specified
        AwFixed   : natural; -- AW handshakes of FIXED bursts
        AwFixLong : natural; -- FIXED bursts of more than 16 beats
        AwFixAddr : natural; -- FIXED bursts at another address than FixedAddr of the harness
        WGaps     : natural; -- Clock cycles between two data beats of a burst with WReady high and WValid low
        EccSec    : Nat3_a;  -- Pulses per buffer
        EccDed    : Nat3_a;
    end record;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body odma_s2mm_tb_pkg is

    type PktQueue_t is protected body

        type Pkt_r is record
            Src   : unsigned(63 downto 0);
            Bytes : natural;
            Mode  : KeepMode_t;
        end record;

        type Pkts_t is array (0 to MaxPackets_c - 1) of Pkt_r;

        variable Pkts_v  : Pkts_t  := (others => (Src => (others => '0'), Bytes => 0, Mode => KeepNormal));
        variable Head_v  : natural := 0;
        variable Count_v : natural := 0;

        procedure push (
            src   : unsigned(63 downto 0);
            bytes : natural;
            mode  : KeepMode_t := KeepNormal) is
        begin
            assert Count_v < MaxPackets_c
                report "odma_s2mm_tb_pkg: packet queue full"
                severity failure;
            Pkts_v((Head_v + Count_v) mod MaxPackets_c) := (Src => src,
                                                            Bytes => bytes,
                                                            Mode => mode);
            Count_v                                     := Count_v + 1;
        end procedure;

        impure function count return natural is
        begin
            return Count_v;
        end function;

        impure function headSrc return unsigned is
        begin
            return Pkts_v(Head_v).Src;
        end function;

        impure function headBytes return natural is
        begin
            return Pkts_v(Head_v).Bytes;
        end function;

        impure function headMode return KeepMode_t is
        begin
            return Pkts_v(Head_v).Mode;
        end function;

        procedure pop is
        begin
            if Count_v > 0 then
                Head_v  := (Head_v + 1) mod MaxPackets_c;
                Count_v := Count_v - 1;
            end if;
        end procedure;

    end protected body;

end package body;
