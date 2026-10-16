---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types shared by the harness and the testbench of odma_mm2s: the queue of the packets that the
-- stream checker expects, the TReady behaviour of the checker and the observations of the harness.
--
-- Documentation: hdl/odma_mm2s/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_mm2s_tb_pkg is

    constant ClkPeriod_c : time := 10 ns;

    -- Results kept by the harness: result n is element n mod MaxResults_c
    constant MaxResults_c : positive := 64;

    -- Packets the stream checker expects, in order: the bytes of the memory model from the address of the
    -- packet; the packet ends with TLast on the beat of its last byte.
    constant MaxPackets_c : positive := 16;

    type PktQueue_t is protected

        procedure push (
            addr  : unsigned(63 downto 0);
            bytes : positive);

        impure function count return natural;

        -- Address and length of the oldest packet
        impure function headAddr return unsigned;

        impure function headBytes return natural;

        procedure pop;

    end protected;

    shared variable Pkts_v : PktQueue_t;

    -- TReady of the stream checker
    type ReadyCfg_r is record
        Percent     : natural;   -- Percentage of clock cycles with TReady high
        Hold        : std_logic; -- '1': TReady low
        StallBeat   : integer;   -- >= 0: TReady low for StallCycles cycles before the beat with this index
        StallCycles : natural;
    end record;

    constant ReadyAlways_c : ReadyCfg_r := (Percent => 100, Hold => '0', StallBeat => -1, StallCycles => 0);

    type Result_r is record
        Bytes : natural;
        Eof   : std_logic;
        Err   : std_logic_vector(1 downto 0);
        Cycle : natural; -- Clock cycle of the result handshake
    end record;

    type Results_a is array (0 to MaxResults_c - 1) of Result_r;
    type Nat3_a is array (0 to 2) of natural;

    -- Observations of the harness; a cycle number is the count of rising clock edges before that cycle. The
    -- stream counters restart when StreamClear toggles.
    type Obs_r is record
        Cycle      : natural;
        ResCount   : natural;
        Results    : Results_a;
        Beats      : natural; -- Stream handshakes
        Bytes      : natural; -- Stream bytes
        FirstBeat  : natural; -- Clock cycle of the first stream handshake
        LastBeat   : natural; -- Clock cycle of the last stream handshake with TLast
        Packets    : natural; -- Packets completed with TLast (not restarted)
        StreamErr  : natural; -- Wrong bytes, TKeep or TLast, beats without an expected packet (not restarted)
        RHeld      : natural; -- Clock cycles with RValid high and RReady low
        ArCount    : natural; -- AR handshakes
        RLastCount : natural; -- R handshakes with RLast
        ArBadAttr  : natural; -- AR handshakes with ArSize, ArBurst, ArLock, ArCache or ArProt not as specified
        EccSec     : Nat3_a;  -- Pulses per buffer
        EccDed     : Nat3_a;
    end record;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body odma_mm2s_tb_pkg is

    type PktQueue_t is protected body

        type Pkt_r is record
            Addr  : unsigned(63 downto 0);
            Bytes : natural;
        end record;

        type Pkts_t is array (0 to MaxPackets_c - 1) of Pkt_r;

        variable Pkts_v  : Pkts_t  := (others => (Addr => (others => '0'), Bytes => 0));
        variable Head_v  : natural := 0;
        variable Count_v : natural := 0;

        procedure push (
            addr  : unsigned(63 downto 0);
            bytes : positive) is
        begin
            assert Count_v < MaxPackets_c
                report "odma_mm2s_tb_pkg: packet queue full"
                severity failure;
            Pkts_v((Head_v + Count_v) mod MaxPackets_c) := (Addr => addr,
                                                            Bytes => bytes);
            Count_v                                     := Count_v + 1;
        end procedure;

        impure function count return natural is
        begin
            return Count_v;
        end function;

        impure function headAddr return unsigned is
        begin
            return Pkts_v(Head_v).Addr;
        end function;

        impure function headBytes return natural is
        begin
            return Pkts_v(Head_v).Bytes;
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
