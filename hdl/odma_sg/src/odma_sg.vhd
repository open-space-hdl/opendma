---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Scatter/Gather engine of OpenDMA (SG-1 to SG-3): one descriptor engine per included channel and
-- the descriptor port shared by both, with the ECC signals of the four FT buffers.
--
-- Documentation: hdl/odma_sg/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.odma_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_sg is
    generic (
        IncludeMm2s_g : boolean                 := true;
        IncludeS2mm_g : boolean                 := true;
        AddrWidth_g   : positive range 32 to 64 := 32;
        LengthWidth_g : positive range 8 to 26  := 14
    );
    port (
        -- Control Signals
        Clk             : in    std_logic;
        Rst             : in    std_logic;
        -- Register interface of the MM2S channel
        Mm2s_Run        : in    std_logic;
        Mm2s_Drain      : in    std_logic;
        Mm2s_CurDesc    : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        Mm2s_Tail       : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        Mm2s_TailWr     : in    std_logic;
        Mm2s_Cyclic     : in    std_logic;
        Mm2s_Keyhole    : in    std_logic;
        Mm2s_CurPtr     : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        Mm2s_Idle       : out   std_logic;
        Mm2s_Stopped    : out   std_logic;
        Mm2s_Pkt        : out   std_logic;
        Mm2s_ErrValid   : out   std_logic;
        Mm2s_ErrXfer    : out   XferErr_t;
        Mm2s_ErrSg      : out   XferErr_t;
        -- MM2S transfer command and result
        Mm2sCmd_Valid   : out   std_logic;
        Mm2sCmd_Ready   : in    std_logic                                    := '0';
        Mm2sCmd_Addr    : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        Mm2sCmd_Length  : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        Mm2sCmd_Sof     : out   std_logic;
        Mm2sCmd_Eof     : out   std_logic;
        Mm2sCmd_Keyhole : out   std_logic;
        Mm2sRes_Valid   : in    std_logic                                    := '0';
        Mm2sRes_Ready   : out   std_logic;
        Mm2sRes_Bytes   : in    std_logic_vector(LengthWidth_g - 1 downto 0) := (others => '0');
        Mm2sRes_Eof     : in    std_logic                                    := '0';
        Mm2sRes_Err     : in    XferErr_t                                    := ErrNone_c;
        -- Register interface of the S2MM channel
        S2mm_Run        : in    std_logic;
        S2mm_Drain      : in    std_logic;
        S2mm_CurDesc    : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        S2mm_Tail       : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        S2mm_TailWr     : in    std_logic;
        S2mm_Cyclic     : in    std_logic;
        S2mm_Keyhole    : in    std_logic;
        S2mm_CurPtr     : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        S2mm_Idle       : out   std_logic;
        S2mm_Stopped    : out   std_logic;
        S2mm_Pkt        : out   std_logic;
        S2mm_ErrValid   : out   std_logic;
        S2mm_ErrXfer    : out   XferErr_t;
        S2mm_ErrSg      : out   XferErr_t;
        -- S2MM transfer command and result
        S2mmCmd_Valid   : out   std_logic;
        S2mmCmd_Ready   : in    std_logic                                    := '0';
        S2mmCmd_Addr    : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        S2mmCmd_Length  : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        S2mmCmd_Keyhole : out   std_logic;
        S2mmRes_Valid   : in    std_logic                                    := '0';
        S2mmRes_Ready   : out   std_logic;
        S2mmRes_Bytes   : in    std_logic_vector(LengthWidth_g - 1 downto 0) := (others => '0');
        S2mmRes_Sof     : in    std_logic                                    := '0';
        S2mmRes_Eof     : in    std_logic                                    := '0';
        S2mmRes_Err     : in    XferErr_t                                    := ErrNone_c;
        -- Descriptor port: AXI4 master, 32 data bits
        M_Axi_AwAddr    : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        M_Axi_AwLen     : out   std_logic_vector(7 downto 0);
        M_Axi_AwSize    : out   std_logic_vector(2 downto 0);
        M_Axi_AwBurst   : out   std_logic_vector(1 downto 0);
        M_Axi_AwLock    : out   std_logic;
        M_Axi_AwCache   : out   std_logic_vector(3 downto 0);
        M_Axi_AwProt    : out   std_logic_vector(2 downto 0);
        M_Axi_AwValid   : out   std_logic;
        M_Axi_AwReady   : in    std_logic;
        M_Axi_WData     : out   std_logic_vector(31 downto 0);
        M_Axi_WStrb     : out   std_logic_vector(3 downto 0);
        M_Axi_WLast     : out   std_logic;
        M_Axi_WValid    : out   std_logic;
        M_Axi_WReady    : in    std_logic;
        M_Axi_BResp     : in    std_logic_vector(1 downto 0);
        M_Axi_BValid    : in    std_logic;
        M_Axi_BReady    : out   std_logic;
        M_Axi_ArAddr    : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        M_Axi_ArLen     : out   std_logic_vector(7 downto 0);
        M_Axi_ArSize    : out   std_logic_vector(2 downto 0);
        M_Axi_ArBurst   : out   std_logic_vector(1 downto 0);
        M_Axi_ArLock    : out   std_logic;
        M_Axi_ArCache   : out   std_logic_vector(3 downto 0);
        M_Axi_ArProt    : out   std_logic_vector(2 downto 0);
        M_Axi_ArValid   : out   std_logic;
        M_Axi_ArReady   : in    std_logic;
        M_Axi_RData     : in    std_logic_vector(31 downto 0);
        M_Axi_RResp     : in    std_logic_vector(1 downto 0);
        M_Axi_RLast     : in    std_logic;
        M_Axi_RValid    : in    std_logic;
        M_Axi_RReady    : out   std_logic;
        -- FT buffers: 0 MM2S descriptor buffer, 1 S2MM descriptor buffer, 2 read data buffer, 3 write data buffer
        -- of the descriptor port (indices 6 to 9 of the extension window)
        Ecc_Sec         : out   std_logic_vector(3 downto 0);
        Ecc_Ded         : out   std_logic_vector(3 downto 0);
        EccInj_Valid    : in    std_logic_vector(3 downto 0)                 := (others => '0');
        EccInj_Double   : in    std_logic                                    := '0';
        EccInj_Data     : in    std_logic                                    := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_sg is

    -- Channel engines to the descriptor port
    signal Mm2sFetch_Req       : std_logic;
    signal Mm2sFetch_Addr      : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal Mm2sFetch_Ack       : std_logic;
    signal Mm2sFetch_WordValid : std_logic;
    signal Mm2sFetch_End       : std_logic;
    signal Mm2sUpd_Req         : std_logic;
    signal Mm2sUpd_Addr        : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal Mm2sUpd_Data        : std_logic_vector(31 downto 0);
    signal Mm2sUpd_Ack         : std_logic;
    signal Mm2sUpd_End         : std_logic;
    signal S2mmFetch_Req       : std_logic;
    signal S2mmFetch_Addr      : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal S2mmFetch_Ack       : std_logic;
    signal S2mmFetch_WordValid : std_logic;
    signal S2mmFetch_End       : std_logic;
    signal S2mmUpd_Req         : std_logic;
    signal S2mmUpd_Addr        : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal S2mmUpd_Data        : std_logic_vector(31 downto 0);
    signal S2mmUpd_Ack         : std_logic;
    signal S2mmUpd_End         : std_logic;
    signal Fetch_Word          : std_logic_vector(31 downto 0);
    signal Fetch_Err           : XferErr_t;
    signal Upd_Err             : XferErr_t;
    signal PortDrain           : std_logic;

begin

    -- A soft reset drains both channels; the port withdraws the accesses the master has not taken
    PortDrain <= Mm2s_Drain or S2mm_Drain;

    -- *** MM2S engine (SG-1, SG-2) ***
    g_mm2s : if IncludeMm2s_g generate

        i_mm2s : entity work.odma_sg_channel
            generic map (
                Mm2s_g        => true,
                AddrWidth_g   => AddrWidth_g,
                LengthWidth_g => LengthWidth_g
            )
            port map (
                Clk             => Clk,
                Rst             => Rst,
                Run             => Mm2s_Run,
                Drain           => Mm2s_Drain,
                CurDesc         => Mm2s_CurDesc,
                Tail            => Mm2s_Tail,
                TailWr          => Mm2s_TailWr,
                Cyclic          => Mm2s_Cyclic,
                Keyhole         => Mm2s_Keyhole,
                CurPtr          => Mm2s_CurPtr,
                Idle            => Mm2s_Idle,
                Stopped         => Mm2s_Stopped,
                Pkt             => Mm2s_Pkt,
                ErrValid        => Mm2s_ErrValid,
                ErrXfer         => Mm2s_ErrXfer,
                ErrSg           => Mm2s_ErrSg,
                Cmd_Valid       => Mm2sCmd_Valid,
                Cmd_Ready       => Mm2sCmd_Ready,
                Cmd_Addr        => Mm2sCmd_Addr,
                Cmd_Length      => Mm2sCmd_Length,
                Cmd_Sof         => Mm2sCmd_Sof,
                Cmd_Eof         => Mm2sCmd_Eof,
                Cmd_Keyhole     => Mm2sCmd_Keyhole,
                Res_Valid       => Mm2sRes_Valid,
                Res_Ready       => Mm2sRes_Ready,
                Res_Bytes       => Mm2sRes_Bytes,
                Res_Sof         => '1',
                Res_Eof         => Mm2sRes_Eof,
                Res_Err         => Mm2sRes_Err,
                Fetch_Req       => Mm2sFetch_Req,
                Fetch_Addr      => Mm2sFetch_Addr,
                Fetch_Ack       => Mm2sFetch_Ack,
                Fetch_Word      => Fetch_Word,
                Fetch_WordValid => Mm2sFetch_WordValid,
                Fetch_End       => Mm2sFetch_End,
                Fetch_Err       => Fetch_Err,
                Upd_Req         => Mm2sUpd_Req,
                Upd_Addr        => Mm2sUpd_Addr,
                Upd_Data        => Mm2sUpd_Data,
                Upd_Ack         => Mm2sUpd_Ack,
                Upd_End         => Mm2sUpd_End,
                Upd_Err         => Upd_Err,
                Ecc_Sec         => Ecc_Sec(0),
                Ecc_Ded         => Ecc_Ded(0),
                EccInj_Valid    => EccInj_Valid(0),
                EccInj_Double   => EccInj_Double,
                EccInj_Data     => EccInj_Data
            );

    end generate;

    -- An engine that is not included keeps its idle values (architecture section 3)
    g_no_mm2s : if not IncludeMm2s_g generate
        Mm2s_CurPtr     <= (others => '0');
        Mm2s_Idle       <= '0';
        Mm2s_Stopped    <= '1';
        Mm2s_Pkt        <= '0';
        Mm2s_ErrValid   <= '0';
        Mm2s_ErrXfer    <= ErrNone_c;
        Mm2s_ErrSg      <= ErrNone_c;
        Mm2sCmd_Valid   <= '0';
        Mm2sCmd_Addr    <= (others => '0');
        Mm2sCmd_Length  <= (others => '0');
        Mm2sCmd_Sof     <= '0';
        Mm2sCmd_Eof     <= '0';
        Mm2sCmd_Keyhole <= '0';
        Mm2sRes_Ready   <= '0';
        Mm2sFetch_Req   <= '0';
        Mm2sFetch_Addr  <= (others => '0');
        Mm2sUpd_Req     <= '0';
        Mm2sUpd_Addr    <= (others => '0');
        Mm2sUpd_Data    <= (others => '0');
        Ecc_Sec(0)      <= '0';
        Ecc_Ded(0)      <= '0';
    end generate;

    -- *** S2MM engine (SG-1, SG-2) ***
    g_s2mm : if IncludeS2mm_g generate

        i_s2mm : entity work.odma_sg_channel
            generic map (
                Mm2s_g        => false,
                AddrWidth_g   => AddrWidth_g,
                LengthWidth_g => LengthWidth_g
            )
            port map (
                Clk             => Clk,
                Rst             => Rst,
                Run             => S2mm_Run,
                Drain           => S2mm_Drain,
                CurDesc         => S2mm_CurDesc,
                Tail            => S2mm_Tail,
                TailWr          => S2mm_TailWr,
                Cyclic          => S2mm_Cyclic,
                Keyhole         => S2mm_Keyhole,
                CurPtr          => S2mm_CurPtr,
                Idle            => S2mm_Idle,
                Stopped         => S2mm_Stopped,
                Pkt             => S2mm_Pkt,
                ErrValid        => S2mm_ErrValid,
                ErrXfer         => S2mm_ErrXfer,
                ErrSg           => S2mm_ErrSg,
                Cmd_Valid       => S2mmCmd_Valid,
                Cmd_Ready       => S2mmCmd_Ready,
                Cmd_Addr        => S2mmCmd_Addr,
                Cmd_Length      => S2mmCmd_Length,
                Cmd_Sof         => open,
                Cmd_Eof         => open,
                Cmd_Keyhole     => S2mmCmd_Keyhole,
                Res_Valid       => S2mmRes_Valid,
                Res_Ready       => S2mmRes_Ready,
                Res_Bytes       => S2mmRes_Bytes,
                Res_Sof         => S2mmRes_Sof,
                Res_Eof         => S2mmRes_Eof,
                Res_Err         => S2mmRes_Err,
                Fetch_Req       => S2mmFetch_Req,
                Fetch_Addr      => S2mmFetch_Addr,
                Fetch_Ack       => S2mmFetch_Ack,
                Fetch_Word      => Fetch_Word,
                Fetch_WordValid => S2mmFetch_WordValid,
                Fetch_End       => S2mmFetch_End,
                Fetch_Err       => Fetch_Err,
                Upd_Req         => S2mmUpd_Req,
                Upd_Addr        => S2mmUpd_Addr,
                Upd_Data        => S2mmUpd_Data,
                Upd_Ack         => S2mmUpd_Ack,
                Upd_End         => S2mmUpd_End,
                Upd_Err         => Upd_Err,
                Ecc_Sec         => Ecc_Sec(1),
                Ecc_Ded         => Ecc_Ded(1),
                EccInj_Valid    => EccInj_Valid(1),
                EccInj_Double   => EccInj_Double,
                EccInj_Data     => EccInj_Data
            );

    end generate;

    g_no_s2mm : if not IncludeS2mm_g generate
        S2mm_CurPtr     <= (others => '0');
        S2mm_Idle       <= '0';
        S2mm_Stopped    <= '1';
        S2mm_Pkt        <= '0';
        S2mm_ErrValid   <= '0';
        S2mm_ErrXfer    <= ErrNone_c;
        S2mm_ErrSg      <= ErrNone_c;
        S2mmCmd_Valid   <= '0';
        S2mmCmd_Addr    <= (others => '0');
        S2mmCmd_Length  <= (others => '0');
        S2mmCmd_Keyhole <= '0';
        S2mmRes_Ready   <= '0';
        S2mmFetch_Req   <= '0';
        S2mmFetch_Addr  <= (others => '0');
        S2mmUpd_Req     <= '0';
        S2mmUpd_Addr    <= (others => '0');
        S2mmUpd_Data    <= (others => '0');
        Ecc_Sec(1)      <= '0';
        Ecc_Ded(1)      <= '0';
    end generate;

    -- *** Descriptor port (SG-3) ***
    i_port : entity work.odma_sg_port
        generic map (
            AddrWidth_g => AddrWidth_g
        )
        port map (
            Clk                 => Clk,
            Rst                 => Rst,
            Drain               => PortDrain,
            Mm2sFetch_Req       => Mm2sFetch_Req,
            Mm2sFetch_Addr      => Mm2sFetch_Addr,
            Mm2sFetch_Ack       => Mm2sFetch_Ack,
            Mm2sFetch_WordValid => Mm2sFetch_WordValid,
            Mm2sFetch_End       => Mm2sFetch_End,
            S2mmFetch_Req       => S2mmFetch_Req,
            S2mmFetch_Addr      => S2mmFetch_Addr,
            S2mmFetch_Ack       => S2mmFetch_Ack,
            S2mmFetch_WordValid => S2mmFetch_WordValid,
            S2mmFetch_End       => S2mmFetch_End,
            Fetch_Word          => Fetch_Word,
            Fetch_Err           => Fetch_Err,
            Mm2sUpd_Req         => Mm2sUpd_Req,
            Mm2sUpd_Addr        => Mm2sUpd_Addr,
            Mm2sUpd_Data        => Mm2sUpd_Data,
            Mm2sUpd_Ack         => Mm2sUpd_Ack,
            Mm2sUpd_End         => Mm2sUpd_End,
            S2mmUpd_Req         => S2mmUpd_Req,
            S2mmUpd_Addr        => S2mmUpd_Addr,
            S2mmUpd_Data        => S2mmUpd_Data,
            S2mmUpd_Ack         => S2mmUpd_Ack,
            S2mmUpd_End         => S2mmUpd_End,
            Upd_Err             => Upd_Err,
            M_Axi_AwAddr        => M_Axi_AwAddr,
            M_Axi_AwLen         => M_Axi_AwLen,
            M_Axi_AwSize        => M_Axi_AwSize,
            M_Axi_AwBurst       => M_Axi_AwBurst,
            M_Axi_AwLock        => M_Axi_AwLock,
            M_Axi_AwCache       => M_Axi_AwCache,
            M_Axi_AwProt        => M_Axi_AwProt,
            M_Axi_AwValid       => M_Axi_AwValid,
            M_Axi_AwReady       => M_Axi_AwReady,
            M_Axi_WData         => M_Axi_WData,
            M_Axi_WStrb         => M_Axi_WStrb,
            M_Axi_WLast         => M_Axi_WLast,
            M_Axi_WValid        => M_Axi_WValid,
            M_Axi_WReady        => M_Axi_WReady,
            M_Axi_BResp         => M_Axi_BResp,
            M_Axi_BValid        => M_Axi_BValid,
            M_Axi_BReady        => M_Axi_BReady,
            M_Axi_ArAddr        => M_Axi_ArAddr,
            M_Axi_ArLen         => M_Axi_ArLen,
            M_Axi_ArSize        => M_Axi_ArSize,
            M_Axi_ArBurst       => M_Axi_ArBurst,
            M_Axi_ArLock        => M_Axi_ArLock,
            M_Axi_ArCache       => M_Axi_ArCache,
            M_Axi_ArProt        => M_Axi_ArProt,
            M_Axi_ArValid       => M_Axi_ArValid,
            M_Axi_ArReady       => M_Axi_ArReady,
            M_Axi_RData         => M_Axi_RData,
            M_Axi_RResp         => M_Axi_RResp,
            M_Axi_RLast         => M_Axi_RLast,
            M_Axi_RValid        => M_Axi_RValid,
            M_Axi_RReady        => M_Axi_RReady,
            Ecc_Sec             => Ecc_Sec(3 downto 2),
            Ecc_Ded             => Ecc_Ded(3 downto 2),
            EccInj_Valid        => EccInj_Valid(3 downto 2),
            EccInj_Double       => EccInj_Double,
            EccInj_Data         => EccInj_Data
        );

end architecture;
