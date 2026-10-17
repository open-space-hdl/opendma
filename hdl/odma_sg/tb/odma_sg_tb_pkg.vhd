---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types shared by the harness and the testbench of odma_sg: the register side the testbench
-- drives, the behaviour of the channel models and the observations of the harness.
--
-- Documentation: hdl/odma_sg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_sg_tb_pkg is

    constant ClkPeriod_c : time := 10 ns;

    -- Channel indices
    constant Mm2s_c : natural := 0;
    constant S2mm_c : natural := 1;

    -- Instance of the AXI memory model on the descriptor port
    constant MemSg_c : natural := 0;

    -- Entries of the logs of the harness
    constant LogDepth_c : positive := 128;

    subtype Addr_t is std_logic_vector(63 downto 0);
    subtype Word_t is std_logic_vector(31 downto 0);

    type Nat_a is array (0 to 1) of natural;
    type Addr_a is array (0 to 1) of Addr_t;
    type Sl_a is array (0 to 1) of std_logic;

    -- Register side of a channel, driven by the testbench; TailWr is a pulse of one clock cycle
    type RegDrive_r is record
        Run     : std_logic;
        Drain   : std_logic;
        CurDesc : Addr_t;
        Tail    : Addr_t;
        TailWr  : std_logic;
        Cyclic  : std_logic;
        Keyhole : std_logic;
    end record;

    type RegDrive_a is array (0 to 1) of RegDrive_r;

    constant RegDriveIdle_c : RegDrive_r := (
        Run     => '0',
        Drain   => '0',
        CurDesc => (others => '0'),
        Tail    => (others => '0'),
        TailWr  => '0',
        Cyclic  => '0',
        Keyhole => '0'
    );

    -- Result of a command, queued by the testbench for the command with the same number
    type Result_r is record
        Valid : boolean; -- false: the default result of the model
        Bytes : integer; -- -1: the buffer length of the command
        Sof   : std_logic;
        Eof   : std_logic;
        Err   : std_logic_vector(1 downto 0);
    end record;

    type Results_t is array (0 to LogDepth_c - 1) of Result_r;

    constant ResultDefault_c : Result_r := (
        Valid => false,
        Bytes => -1,
        Sof   => '1',
        Eof   => '1',
        Err   => "00"
    );

    -- Behaviour of a channel model. The MM2S model accepts up to MaxCmds commands, like the transfer buffer of
    -- odma_mm2s, the S2MM model one command at a time. The default result: MM2S the buffer length, the end of
    -- packet of the command, no error; S2MM the buffer length with start and end of packet; both return the internal
    -- error with 0 bytes for a buffer length of 0. When Run falls, the S2MM model ends its command with HaltBytes
    -- bytes, the start of packet when HaltBytes is not 0, and no end of packet.
    type ChanCfg_r is record
        CmdDelay  : natural;   -- Clock cycles a command waits for Cmd_Ready
        ResDelay  : natural;   -- Clock cycles from the command handshake to Res_Valid
        Hold      : std_logic; -- '1': no result is returned
        HaltBytes : natural;
        MaxCmds   : positive;
        Results   : Results_t;
    end record;

    type ChanCfg_a is array (0 to 1) of ChanCfg_r;

    constant ChanCfgDefault_c : ChanCfg_r := (
        CmdDelay  => 0,
        ResDelay  => 4,
        Hold      => '0',
        HaltBytes => 0,
        MaxCmds   => 8,
        Results   => (others => ResultDefault_c)
    );

    -- Logs of the harness
    type Cmd_r is record
        Addr    : Addr_t;
        Length  : natural;
        Sof     : std_logic;
        Eof     : std_logic;
        Keyhole : std_logic;
        Cycle   : natural;
    end record;

    type CmdLog_t is array (0 to LogDepth_c - 1) of Cmd_r;
    type CmdLog_a is array (0 to 1) of CmdLog_t;

    type Burst_r is record
        Addr  : Addr_t;
        Len   : natural; -- AxLen + 1
        Size  : std_logic_vector(2 downto 0);
        Burst : std_logic_vector(1 downto 0);
        Lock  : std_logic;
        Cache : std_logic_vector(3 downto 0);
        Prot  : std_logic_vector(2 downto 0);
        Cycle : natural;
    end record;

    type BurstLog_t is array (0 to LogDepth_c - 1) of Burst_r;

    type Write_r is record
        Data : Word_t;
        Strb : std_logic_vector(3 downto 0);
        Last : std_logic;
        Addr : Addr_t; -- Address of its burst
    end record;

    type WriteLog_t is array (0 to LogDepth_c - 1) of Write_r;
    type NatLog_t is array (0 to LogDepth_c - 1) of natural;

    type Event_r is record
        Cycle : natural;
        Xfer  : std_logic_vector(1 downto 0);
        Sg    : std_logic_vector(1 downto 0);
    end record;

    type EventLog_t is array (0 to LogDepth_c - 1) of Event_r;
    type EventLog_a is array (0 to 1) of EventLog_t;
    type Count16_t is array (0 to 3) of natural;

    -- Observations of the harness; a cycle number is the count of rising clock edges before that cycle
    type Obs_r is record
        Cycle     : natural;
        CmdCount  : Nat_a;     -- Accepted commands and their log
        Cmds      : CmdLog_a;
        ResCount  : Nat_a;     -- Results taken by the DUT
        ArCount   : natural;   -- Read and write bursts of the descriptor port
        Ars       : BurstLog_t;
        AwCount   : natural;
        Aws       : BurstLog_t;
        WCount    : natural;   -- Write beats
        Ws        : WriteLog_t;
        BCount    : natural;   -- Write responses and their clock cycles
        Bs        : NatLog_t;
        PktCount  : Nat_a;     -- Packet events and their clock cycles
        PktCycles : EventLog_a;
        ErrCount  : Nat_a;     -- Error events with their codes
        Errs      : EventLog_a;
        EccSec    : Count16_t; -- ECC events of the four buffers
        EccDed    : Count16_t;
        MaxCmds   : Nat_a;     -- Most commands accepted and without result at a time
        Idle      : Sl_a;      -- Levels of the DUT
        Stopped   : Sl_a;
        CurPtr    : Addr_a;
    end record;

end package;
