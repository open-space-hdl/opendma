---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Verification helpers shared by all OpenDMA testbenches (VUnit runner plus UVVM): test end check,
-- AXI4-Stream BFM configuration and byte array helpers.
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

    -- Ends a test: prints the UVVM alert summary, raises a TB_ERROR when an unexpected alert occurred
    -- or an expected alert did not occur (this stops the simulation and fails the VUnit test) and
    -- hands over to the VUnit runner.
    procedure odmaTestEnd (signal runner : inout runner_sync_t);

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
    begin
        report_alert_counters(FINAL);
        if shared_uvvm_status.mismatch_on_expected_simulation_warnings_or_worse /= 0 then
            alert(TB_ERROR, "UVVM alert counters do not match the expected alerts", "odmaTestEnd");
        end if;
        test_runner_cleanup(runner);
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
