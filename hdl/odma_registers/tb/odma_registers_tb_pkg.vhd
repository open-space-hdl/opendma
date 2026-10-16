---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types shared by the harness and the testbench of odma_registers: configuration of the channel
-- models and the observations of the harness.
--
-- Documentation: hdl/odma_registers/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_registers_tb_pkg is

    constant ClkPeriod_c : time := 10 ns;

    -- Channel indices
    constant Mm2s_c : natural := 0;
    constant S2mm_c : natural := 1;

    -- Generics of the channels that only the configuration readback uses
    constant Mm2sMemWidth_c    : positive := 64;
    constant Mm2sStreamWidth_c : positive := 32;
    constant Mm2sBurstBeats_c  : positive := 16;
    constant Mm2sBufferBeats_c : positive := 64;
    constant S2mmMemWidth_c    : positive := 128;
    constant S2mmStreamWidth_c : positive := 64;
    constant S2mmBurstBeats_c  : positive := 32;
    constant S2mmBufferBeats_c : positive := 256;
    constant StsCntrlStrm_c    : boolean  := true;
    constant UseRxLength_c     : boolean  := false;
    constant MicroDma_c        : boolean  := true;

    -- Behaviour of a channel model
    type ChanCfg_r is record
        CmdDelay   : natural;  -- Clock cycles a command waits for Cmd_Ready
        ResDelay   : integer;  -- >= 0: the result follows the command handshake after
        -- ResDelay + 2 clock cycles; -1: the result follows the next AW handshake of the register port
        ResAfterAw : positive; -- ResDelay = -1: Res_Valid rises ResAfterAw cycles after
        -- the clock cycle of the AW handshake
        ResBytes   : integer;  -- Bytes of the result; -1: the length of the command
        ResEof     : std_logic;
        ResErr     : std_logic_vector(1 downto 0);
        DrainTime  : natural;  -- Clock cycles Stopped stays low after Run falls or Drain rises
    end record;

    type ChanCfg_a is array (0 to 1) of ChanCfg_r;

    constant ChanCfgDefault_c : ChanCfg_r := (
        CmdDelay   => 0,
        ResDelay   => 5,
        ResAfterAw => 1,
        ResBytes   => -1,
        ResEof     => '1',
        ResErr     => "00",
        DrainTime  => 0
    );

    type Nat_a is array (0 to 1) of natural;
    type Addr_a is array (0 to 1) of std_logic_vector(63 downto 0);

    -- Observations of the harness; a cycle number is the count of rising clock edges before that cycle
    type Obs_r is record
        CmdCount     : Nat_a;     -- Accepted commands
        CmdAddr      : Addr_a;    -- Fields of the last accepted command
        CmdLength    : Nat_a;
        CmdSof       : std_logic; -- MM2S only
        CmdEof       : std_logic;
        CmdKeyhole   : std_logic_vector(0 to 1);
        ResCount     : Nat_a;     -- Results taken by the DUT
        ResCycle     : Nat_a;     -- Clock cycle of the last result handshake
        Cycle        : natural;
        AwCycle      : natural;   -- Clock cycle of the last write address handshake
        BValidCycle  : natural;   -- Clock cycle in which BValid rose last
        ArCycle      : natural;   -- Clock cycle of the last read address handshake
        RValidCycle  : natural;   -- Clock cycle in which RValid rose last
        DrainCycle   : natural;   -- Clock cycle in which a drain request rose last
        CoreRstCycle : natural;   -- Clock cycle in which CoreRst rose last
        CoreRstEarly : natural;   -- Soft resets that started before both channels were stopped
        RstOutLen    : natural;   -- Clock cycles of the last completed reset output pulse
        RstOutDiffer : natural;   -- Clock cycles with different reset outputs
        InjCount     : natural;   -- Error injection strobes
        InjIdx       : natural;   -- Buffer index and EccInj_Double of the last strobe
        InjDouble    : std_logic;
        InjMulti     : natural;   -- Clock cycles with more than one strobe
    end record;

end package;
