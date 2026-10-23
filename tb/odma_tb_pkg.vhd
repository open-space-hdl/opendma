---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Verification helpers shared by all OpenDMA testbenches (VUnit runner plus UVVM): test end check,
-- timed waits that check their condition, AXI4-Stream BFM configuration and byte array helpers.
--
-- Documentation: hdl/odma_pkg/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library bitvis_vip_axistream;
    use bitvis_vip_axistream.axistream_bfm_pkg.all;

library vunit_lib;
    context vunit_lib.vunit_run_context;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_tb_pkg is

    -- AXI4-Stream BFM configuration of the OpenDMA testbenches: byte elements map to TData with the
    -- first byte in lane 0 (LOWER_BYTE_RIGHT), the timeouts suit long transfers
    constant OdmaAxisBfmConfig_c : t_axistream_bfm_config := (
        max_wait_cycles                => 1000000,
        max_wait_cycles_severity       => error,
        clock_period                   => C_UNDEFINED_TIME,
        clock_period_margin            => 0 ns,
        clock_margin_severity          => TB_ERROR,
        setup_time                     => C_UNDEFINED_TIME,
        hold_time                      => C_UNDEFINED_TIME,
        bfm_sync                       => SYNC_ON_CLOCK_ONLY,
        match_strictness               => MATCH_EXACT,
        byte_endianness                => LOWER_BYTE_RIGHT,
        valid_low_at_word_num          => 0,
        valid_low_multiple_random_prob => 0.5,
        valid_low_duration             => 0,
        valid_low_max_random_duration  => 5,
        check_packet_length            => false,
        protocol_error_severity        => error,
        ready_low_at_word_num          => 0,
        ready_low_multiple_random_prob => 0.5,
        ready_low_duration             => 0,
        ready_low_max_random_duration  => 5,
        ready_default_value            => '0',
        id_for_bfm                     => ID_BFM
    );

    -- Ends a test: prints the UVVM alert summary, compares the alert counters of every level from WARNING to
    -- TB_FAILURE with the expected alerts, ends the simulation with a failure on a difference, whatever the stop
    -- limits of the test, and hands over to the VUnit runner.
    procedure odmaTestEnd (signal runner : inout runner_sync_t);

    -- Timed waits that must end with their condition: each waits as "wait until <condition> for timeout" does
    -- (for an event, also when the condition already holds) and then raises an ERROR unless the condition ended
    -- the wait before the timeout, so that a missing handshake or event is not a silent timeout, also when the
    -- condition held already and nothing moved. A caller that accepts a condition that holds already does not
    -- enter the wait
    -- Until sig is '1'
    procedure odmaWaitHigh (
        signal sig : in std_logic;
        timeout    : in time;
        msg        : in string);

    -- Until a rising edge of clk with sig '1'
    procedure odmaWaitHighAtEdge (
        signal clk : in std_logic;
        signal sig : in std_logic;
        timeout    : in time;
        msg        : in string);

    -- Until the counter cnt reaches at least n
    procedure odmaWaitAtLeast (
        signal cnt : in natural;
        n          : in natural;
        timeout    : in time;
        msg        : in string);

    -- n bytes with the values (first + i) mod 256
    function odmaCountBytes (
        n     : in natural;
        first : in natural := 0) return t_slv_array;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body odma_tb_pkg is

    procedure odmaTestEnd (signal runner : inout runner_sync_t) is
        variable Mismatch_v : boolean := false;
    begin
        report_alert_counters(FINAL);

        -- The counters are compared here: an alert of the test end would not stop a test that raised the stop
        -- limit of its level, so a difference would pass
        for L in WARNING to TB_FAILURE loop

            if L /= MANUAL_CHECK and get_alert_counter(L, REGARD) /= get_alert_counter(L, EXPECT) then
                Mismatch_v := true;
                log(ID_SEQUENCER, t_alert_level'image(L) & ": " & integer'image(get_alert_counter(L, REGARD))
                                  & " alerts, " & integer'image(get_alert_counter(L, EXPECT)) & " expected",
                    "odmaTestEnd");
            end if;

        end loop;

        -- A failure ends the simulation, whatever the stop limits of the test
        assert not Mismatch_v
            report "odmaTestEnd: the alerts of the test differ from the expected alerts (summary above)"
            severity failure;
        test_runner_cleanup(runner);
    end procedure;

    procedure odmaWaitHigh (
        signal sig : in std_logic;
        timeout    : in time;
        msg        : in string) is
        variable T0_v : time;
    begin
        T0_v := now;
        wait until sig = '1' for timeout;
        check_value(sig = '1' and now - T0_v < timeout, ERROR,
                    msg & ": '1' within " & to_string(timeout / 1 ns) & " ns");
    end procedure;

    procedure odmaWaitHighAtEdge (
        signal clk : in std_logic;
        signal sig : in std_logic;
        timeout    : in time;
        msg        : in string) is
        variable T0_v : time;
    begin
        T0_v := now;
        wait until rising_edge(clk) and sig = '1' for timeout;
        check_value(sig = '1' and now - T0_v < timeout, ERROR,
                    msg & ": '1' at a rising edge within " & to_string(timeout / 1 ns) & " ns");
    end procedure;

    procedure odmaWaitAtLeast (
        signal cnt : in natural;
        n          : in natural;
        timeout    : in time;
        msg        : in string) is
        variable T0_v : time;
    begin
        T0_v := now;
        wait until cnt >= n for timeout;
        check_value(cnt >= n and now - T0_v < timeout, ERROR,
                    msg & ": " & to_string(cnt) & ", at least " & to_string(n) & " within " &
                    to_string(timeout / 1 ns) & " ns");
    end procedure;

    function odmaCountBytes (
        n     : in natural;
        first : in natural := 0) return t_slv_array is
        variable Arr_v : t_slv_array(0 to maximum(n, 1) - 1)(7 downto 0) := (others => x"00");
    begin

        for i in 0 to n - 1 loop
            Arr_v(i) := std_logic_vector(to_unsigned((first + i) mod 256, 8));
        end loop;

        return Arr_v;
    end function;

end package body;
