---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- UVVM AXI4 master VVC with plain AXI4 ports without ID and user signals, the port set of the AXI
-- memory model odma_tb_axi_ram. Commands: axi_write, axi_read and axi_check with AXI_VVCT and
-- InstanceIdx_g.
--
-- Documentation: hdl/odma_pkg/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library bitvis_vip_axi;
    use bitvis_vip_axi.axi_bfm_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_tb_axi_master is
    generic (
        InstanceIdx_g : natural;
        AddrWidth_g   : positive;
        DataWidth_g   : positive
    );
    port (
        Clk     : in    std_logic;
        AwAddr  : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        AwLen   : out   std_logic_vector(7 downto 0);
        AwSize  : out   std_logic_vector(2 downto 0);
        AwBurst : out   std_logic_vector(1 downto 0);
        AwValid : out   std_logic;
        AwReady : in    std_logic;
        WData   : out   std_logic_vector(DataWidth_g - 1 downto 0);
        WStrb   : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        WLast   : out   std_logic;
        WValid  : out   std_logic;
        WReady  : in    std_logic;
        BResp   : in    std_logic_vector(1 downto 0);
        BValid  : in    std_logic;
        BReady  : out   std_logic;
        ArAddr  : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        ArLen   : out   std_logic_vector(7 downto 0);
        ArSize  : out   std_logic_vector(2 downto 0);
        ArBurst : out   std_logic_vector(1 downto 0);
        ArValid : out   std_logic;
        ArReady : in    std_logic;
        RData   : in    std_logic_vector(DataWidth_g - 1 downto 0);
        RResp   : in    std_logic_vector(1 downto 0);
        RLast   : in    std_logic;
        RValid  : in    std_logic;
        RReady  : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_tb_axi_master is

    -- Long bursts with backpressure of the memory model take more than the default 1000 cycles
    function axiConfig return t_axi_bfm_config is
        variable Config_v : t_axi_bfm_config := C_AXI_BFM_CONFIG_DEFAULT;
    begin
        Config_v.max_wait_cycles := 100000;
        return Config_v;
    end function;

    constant AxiConfig_c : t_axi_bfm_config := axiConfig;

    signal AxiIf : t_axi_if(
                             write_address_channel(
                                                      awid(-1 downto 0),
                                                      AwAddr(AddrWidth_g - 1 downto 0),
                                                      awuser(-1 downto 0)),
                             write_data_channel(
                                                   WData(DataWidth_g - 1 downto 0),
                                                   WStrb(DataWidth_g / 8 - 1 downto 0),
                                                   wuser(-1 downto 0)),
                             write_response_channel(
                                                       bid(-1 downto 0),
                                                       buser(-1 downto 0)),
                             read_address_channel(
                                                     arid(-1 downto 0),
                                                     ArAddr(AddrWidth_g - 1 downto 0),
                                                     aruser(-1 downto 0)),
                             read_data_channel(
                                                  rid(-1 downto 0),
                                                  RData(DataWidth_g - 1 downto 0),
                                                  ruser(-1 downto 0))) := init_axi_if_signals(AddrWidth_g, DataWidth_g, 0, 0);

begin

    -- Signals driven by the slave side
    AxiIf.write_address_channel.awready <= AwReady;
    AxiIf.write_data_channel.wready     <= WReady;
    AxiIf.write_response_channel.bresp  <= BResp;
    AxiIf.write_response_channel.bvalid <= BValid;
    AxiIf.read_address_channel.arready  <= ArReady;
    AxiIf.read_data_channel.rdata       <= RData;
    AxiIf.read_data_channel.rresp       <= RResp;
    AxiIf.read_data_channel.rlast       <= RLast;
    AxiIf.read_data_channel.rvalid      <= RValid;

    AwAddr  <= AxiIf.write_address_channel.awaddr;
    AwLen   <= AxiIf.write_address_channel.awlen;
    AwSize  <= AxiIf.write_address_channel.awsize;
    AwBurst <= AxiIf.write_address_channel.awburst;
    AwValid <= AxiIf.write_address_channel.awvalid;
    WData   <= AxiIf.write_data_channel.wdata;
    WStrb   <= AxiIf.write_data_channel.wstrb;
    WLast   <= AxiIf.write_data_channel.wlast;
    WValid  <= AxiIf.write_data_channel.wvalid;
    BReady  <= AxiIf.write_response_channel.bready;
    ArAddr  <= AxiIf.read_address_channel.araddr;
    ArLen   <= AxiIf.read_address_channel.arlen;
    ArSize  <= AxiIf.read_address_channel.arsize;
    ArBurst <= AxiIf.read_address_channel.arburst;
    ArValid <= AxiIf.read_address_channel.arvalid;
    RReady  <= AxiIf.read_data_channel.rready;

    i_vvc : entity bitvis_vip_axi.axi_vvc
        generic map (
            Gc_Addr_Width   => AddrWidth_g,
            Gc_Data_Width   => DataWidth_g,
            Gc_Id_Width     => 0,
            Gc_User_Width   => 0,
            Gc_Instance_Idx => InstanceIdx_g,
            Gc_Axi_Config   => AxiConfig_c
        )
        port map (
            Clk               => Clk,
            Axi_Vvc_Master_If => AxiIf
        );

end architecture;
