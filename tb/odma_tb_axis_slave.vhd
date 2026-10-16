---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- UVVM AXI-Stream slave VVC with plain valid / ready stream ports, so that test harnesses connect
-- DUT streams without the t_axistream_if record boilerplate. Commands: axistream_expect and
-- axistream_receive with AXISTREAM_VVCT and InstanceIdx_g.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library bitvis_vip_axistream;
    use bitvis_vip_axistream.axistream_bfm_pkg.all;
    use bitvis_vip_axistream.vvc_methods_pkg.all;

library work;
    use work.odma_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_tb_axis_slave is
    generic (
        InstanceIdx_g              : natural;
        DataWidth_g                : positive;
        UserWidth_g                : positive      := 1;
        -- Alert when the DUT drives the stream while no command is active (UVVM unwanted activity)
        UnwantedActivitySeverity_g : t_alert_level := NO_ALERT
    );
    port (
        Clk      : in    std_logic;
        In_Data  : in    std_logic_vector(DataWidth_g-1 downto 0);
        In_User  : in    std_logic_vector(UserWidth_g-1 downto 0)   := (others => '0');
        In_Keep  : in    std_logic_vector(DataWidth_g/8-1 downto 0) := (others => '1');
        In_Last  : in    std_logic                                  := '0';
        In_Valid : in    std_logic;
        In_Ready : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_tb_axis_slave is

    signal AxisIf : t_axistream_if(
                                    tdata(DataWidth_g-1 downto 0),
                                    tkeep(DataWidth_g/8-1 downto 0),
                                    tuser(UserWidth_g-1 downto 0),
                                    tstrb(DataWidth_g/8-1 downto 0),
                                    tid(0 downto 0),
                                    tdest(0 downto 0));

begin

    -- Signals driven by the DUT side
    AxisIf.tdata  <= In_Data;
    AxisIf.tuser  <= In_User;
    AxisIf.tkeep  <= In_Keep;
    AxisIf.tlast  <= In_Last;
    AxisIf.tvalid <= In_Valid;
    AxisIf.tstrb  <= (others => '0');
    AxisIf.tid    <= (others => '0');
    AxisIf.tdest  <= (others => '0');

    In_Ready <= AxisIf.tready;

    p_config : process is
    begin
        wait for 1 ns; -- after the VVC constructor
        shared_axistream_vvc_config(InstanceIdx_g).unwanted_activity_severity := UnwantedActivitySeverity_g;
        wait;
    end process;

    i_vvc : entity bitvis_vip_axistream.axistream_vvc
        generic map (
            Gc_Vvc_Is_Master        => false,
            Gc_Data_Width           => DataWidth_g,
            Gc_User_Width           => UserWidth_g,
            Gc_Id_Width             => 1,
            Gc_Dest_Width           => 1,
            Gc_Instance_Idx         => InstanceIdx_g,
            Gc_Axistream_Bfm_Config => OdmaAxisBfmConfig_c
        )
        port map (
            Clk              => Clk,
            Axistream_Vvc_If => AxisIf
        );

end architecture;
