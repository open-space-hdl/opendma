---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Memory to stream channel of OpenDMA (MM-1, MM-2): reads the buffer of each transfer command
-- through an AXI4 read master and sends it on the MM2S stream.
--
-- Documentation: hdl/odma_mm2s/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.odma_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_mm2s is
    generic (
        AddrWidth_g   : positive range 32 to 64 := 32;
        LengthWidth_g : positive range 8 to 26  := 14;
        MemWidth_g    : positive                := 32;
        StreamWidth_g : positive                := 32;
        BurstBeats_g  : positive                := 16;
        BufferBeats_g : positive                := 64;
        ReadBursts_g  : positive                := 6;
        Join_g        : boolean                 := false
    );
    port (
        -- Control Signals
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- Transfer command
        Cmd_Valid     : in    std_logic;
        Cmd_Ready     : out   std_logic;
        Cmd_Addr      : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        Cmd_Length    : in    std_logic_vector(LengthWidth_g - 1 downto 0);
        Cmd_Sof       : in    std_logic                    := '1';
        Cmd_Eof       : in    std_logic                    := '1';
        Cmd_Keyhole   : in    std_logic                    := '0';
        -- Transfer result
        Res_Valid     : out   std_logic;
        Res_Ready     : in    std_logic;
        Res_Bytes     : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        Res_Eof       : out   std_logic;
        Res_Err       : out   XferErr_t;
        -- Channel control
        Run           : in    std_logic;
        Drain         : in    std_logic;
        Stopped       : out   std_logic;
        -- AXI4 read master
        M_Axi_ArAddr  : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        M_Axi_ArLen   : out   std_logic_vector(7 downto 0);
        M_Axi_ArSize  : out   std_logic_vector(2 downto 0);
        M_Axi_ArBurst : out   std_logic_vector(1 downto 0);
        M_Axi_ArLock  : out   std_logic;
        M_Axi_ArCache : out   std_logic_vector(3 downto 0);
        M_Axi_ArProt  : out   std_logic_vector(2 downto 0);
        M_Axi_ArValid : out   std_logic;
        M_Axi_ArReady : in    std_logic;
        M_Axi_RData   : in    std_logic_vector(MemWidth_g - 1 downto 0);
        M_Axi_RResp   : in    std_logic_vector(1 downto 0);
        M_Axi_RLast   : in    std_logic;
        M_Axi_RValid  : in    std_logic;
        M_Axi_RReady  : out   std_logic;
        -- MM2S stream
        M_Mm2s_Data   : out   std_logic_vector(StreamWidth_g - 1 downto 0);
        M_Mm2s_Keep   : out   std_logic_vector(StreamWidth_g / 8 - 1 downto 0);
        M_Mm2s_Last   : out   std_logic;
        M_Mm2s_Valid  : out   std_logic;
        M_Mm2s_Ready  : in    std_logic;
        -- FT buffers: 0 read data buffer, 1 transfer buffer, 2 response buffer
        Ecc_Sec       : out   std_logic_vector(2 downto 0);
        Ecc_Ded       : out   std_logic_vector(2 downto 0);
        EccInj_Valid  : in    std_logic_vector(2 downto 0) := (others => '0');
        EccInj_Double : in    std_logic                    := '0';
        EccInj_Data   : in    std_logic                    := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_mm2s is

    -- Longest burst of the read master: no AXI burst crosses 4 KB, so longer bursts never occur (G13)
    constant MasterBeats_c : positive := minimum(BurstBeats_g, 4096 / (MemWidth_g / 8));
    -- Size bits of the read master: one more than the length, as for the write master of odma_s2mm (G14)
    constant SizeBits_c    : positive := LengthWidth_g + 1;

    -- Transfer buffer {code, end of packet, length} and response buffer {code}
    constant XferDepth_c : positive := 8;
    constant XferWidth_c : positive := LengthWidth_g + 3;
    constant RespWidth_c : positive := 2;

    -- Command block to the transfer and response buffers
    signal Xfer_InValid  : std_logic;
    signal Xfer_InReady  : std_logic;
    signal Xfer_InLength : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal Xfer_InEof    : std_logic;
    signal Xfer_InCode   : XferErr_t;
    signal Xfer_InData   : std_logic_vector(XferWidth_c - 1 downto 0);
    signal Resp_InValid  : std_logic;
    signal Resp_InCode   : XferErr_t;
    signal CmdIdle       : std_logic;
    signal NoEntry       : std_logic;
    signal StreamClosed  : std_logic;

    -- Transfer and response buffers to the stream block
    signal Xfer_OutData  : std_logic_vector(XferWidth_c - 1 downto 0);
    signal Xfer_OutValid : std_logic;
    signal Xfer_OutReady : std_logic;
    signal Xfer_OutSec   : std_logic;
    signal Xfer_OutDed   : std_logic;
    signal Xfer_Empty    : std_logic;
    signal Resp_OutData  : std_logic_vector(RespWidth_c - 1 downto 0);
    signal Resp_OutValid : std_logic;
    signal Resp_OutReady : std_logic;
    signal Resp_OutSec   : std_logic;
    signal Resp_OutDed   : std_logic;
    signal Resp_Empty    : std_logic;

    -- Read master
    signal CmdRd_Addr   : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal CmdRd_Size   : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal CmdRd_Fixed  : std_logic;
    signal MasterSize   : std_logic_vector(SizeBits_c - 1 downto 0);
    signal CmdRd_Valid  : std_logic;
    signal CmdRd_Ready  : std_logic;
    signal Rd_Data      : std_logic_vector(StreamWidth_g - 1 downto 0);
    signal Rd_Last      : std_logic;
    signal Rd_Valid     : std_logic;
    signal Rd_Ready     : std_logic;
    signal Rd_EccSec    : std_logic;
    signal Rd_EccDed    : std_logic;
    signal Rd_Done      : std_logic;
    signal Rd_Error     : std_logic;
    signal Rd_ErrorResp : std_logic_vector(1 downto 0);
    signal RdInjFlip    : std_logic_vector(eccCodewordWidth(StreamWidth_g + 1) - 1 downto 0);
    signal XferInjFlip  : std_logic_vector(eccCodewordWidth(XferWidth_c) - 1 downto 0);
    signal RespInjFlip  : std_logic_vector(eccCodewordWidth(RespWidth_c) - 1 downto 0);

begin

    -- *** Assertions ***
    -- The rules of the channel generics are those of the core (the second channel repeats the first one)
    assert coreConfigError(AddrWidth_g, LengthWidth_g, MemWidth_g, StreamWidth_g, BurstBeats_g, BufferBeats_g,
                           MemWidth_g, StreamWidth_g, BurstBeats_g, BufferBeats_g, ReadBursts_g) = ""
        report "odma_mm2s: " & coreConfigError(AddrWidth_g, LengthWidth_g, MemWidth_g, StreamWidth_g, BurstBeats_g,
               BufferBeats_g, MemWidth_g, StreamWidth_g, BurstBeats_g, BufferBeats_g, ReadBursts_g)
        severity failure;

    -- *** Read command (MM-1) ***
    i_command : entity work.odma_mm2s_command
        generic map (
            AddrWidth_g   => AddrWidth_g,
            LengthWidth_g => LengthWidth_g
        )
        port map (
            Clk          => Clk,
            Rst          => Rst,
            Cmd_Valid    => Cmd_Valid,
            Cmd_Ready    => Cmd_Ready,
            Cmd_Addr     => Cmd_Addr,
            Cmd_Length   => Cmd_Length,
            Cmd_Eof      => Cmd_Eof,
            Cmd_Keyhole  => Cmd_Keyhole,
            Run          => Run,
            Drain        => Drain,
            CmdRd_Addr   => CmdRd_Addr,
            CmdRd_Size   => CmdRd_Size,
            CmdRd_Fixed  => CmdRd_Fixed,
            CmdRd_Valid  => CmdRd_Valid,
            CmdRd_Ready  => CmdRd_Ready,
            Rd_Done      => Rd_Done,
            Rd_Error     => Rd_Error,
            Rd_ErrorResp => Rd_ErrorResp,
            Xfer_Valid   => Xfer_InValid,
            Xfer_Ready   => Xfer_InReady,
            Xfer_Length  => Xfer_InLength,
            Xfer_Eof     => Xfer_InEof,
            Xfer_Code    => Xfer_InCode,
            Resp_Valid   => Resp_InValid,
            Resp_Code    => Resp_InCode,
            Idle         => CmdIdle
        );

    -- *** AXI4 read master with the read data buffer ***
    RdInjFlip  <= flipPattern(RdInjFlip'length, EccInj_Double, EccInj_Data);
    MasterSize <= std_logic_vector(resize(unsigned(CmdRd_Size), SizeBits_c));

    i_master : entity olo.olo_ft_axi_master_full
        generic map (
            AxiAddrWidth_g            => AddrWidth_g,
            AxiDataWidth_g            => MemWidth_g,
            AxiMaxBeats_g             => MasterBeats_c,
            AxiMaxOpenTransactions_g  => 8,
            UserTransactionSizeBits_g => SizeBits_c,
            DataFifoDepth_g           => BufferBeats_g,
            -- ReadBursts_g bursts in flight: in high-latency mode the master requests a burst only when its internal
            -- FIFO can hold it (MM-RD-07)
            IntFifoDepth_g            => ReadBursts_g * MasterBeats_c,
            UserDataWidth_g           => StreamWidth_g,
            ImplRead_g                => true,
            ImplWrite_g               => false
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            CmdRd_Addr        => CmdRd_Addr,
            CmdRd_Size        => MasterSize,
            CmdRd_LowLat      => '0',
            CmdRd_Fixed       => CmdRd_Fixed,
            CmdRd_Valid       => CmdRd_Valid,
            CmdRd_Ready       => CmdRd_Ready,
            Rd_Data           => Rd_Data,
            Rd_Last           => Rd_Last,
            Rd_Valid          => Rd_Valid,
            Rd_Ready          => Rd_Ready,
            Rd_EccSec         => Rd_EccSec,
            Rd_EccDed         => Rd_EccDed,
            Rd_Done           => Rd_Done,
            Rd_Error          => Rd_Error,
            Rd_ErrorResp      => Rd_ErrorResp,
            Rd_ErrInj_BitFlip => RdInjFlip,
            Rd_ErrInj_Valid   => EccInj_Valid(0),
            M_Axi_ArAddr      => M_Axi_ArAddr,
            M_Axi_ArLen       => M_Axi_ArLen,
            M_Axi_ArSize      => M_Axi_ArSize,
            M_Axi_ArBurst     => M_Axi_ArBurst,
            M_Axi_ArLock      => M_Axi_ArLock,
            M_Axi_ArCache     => M_Axi_ArCache,
            M_Axi_ArProt      => M_Axi_ArProt,
            M_Axi_ArValid     => M_Axi_ArValid,
            M_Axi_ArReady     => M_Axi_ArReady,
            M_Axi_RData       => M_Axi_RData,
            M_Axi_RResp       => M_Axi_RResp,
            M_Axi_RLast       => M_Axi_RLast,
            M_Axi_RValid      => M_Axi_RValid,
            M_Axi_RReady      => M_Axi_RReady
        );

    -- *** Transfer buffer and response buffer ***
    Xfer_InData <= Xfer_InCode & Xfer_InEof & Xfer_InLength;
    XferInjFlip <= flipPattern(XferInjFlip'length, EccInj_Double, EccInj_Data);

    i_xfer : entity olo.olo_ft_fifo_sync
        generic map (
            Width_g => XferWidth_c,
            Depth_g => XferDepth_c
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Data           => Xfer_InData,
            In_Valid          => Xfer_InValid,
            In_Ready          => Xfer_InReady,
            Out_Data          => Xfer_OutData,
            Out_Valid         => Xfer_OutValid,
            Out_Ready         => Xfer_OutReady,
            Out_EccSec        => Xfer_OutSec,
            Out_EccDed        => Xfer_OutDed,
            Empty             => Xfer_Empty,
            In_ErrInj_BitFlip => XferInjFlip,
            In_ErrInj_Valid   => EccInj_Valid(1)
        );

    RespInjFlip <= flipPattern(RespInjFlip'length, EccInj_Double, EccInj_Data);

    i_resp : entity olo.olo_ft_fifo_sync
        generic map (
            Width_g => RespWidth_c,
            Depth_g => XferDepth_c
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Data           => Resp_InCode,
            In_Valid          => Resp_InValid,
            In_Ready          => open,
            Out_Data          => Resp_OutData,
            Out_Valid         => Resp_OutValid,
            Out_Ready         => Resp_OutReady,
            Out_EccSec        => Resp_OutSec,
            Out_EccDed        => Resp_OutDed,
            Empty             => Resp_Empty,
            In_ErrInj_BitFlip => RespInjFlip,
            In_ErrInj_Valid   => EccInj_Valid(2)
        );

    -- *** Stream output (MM-2) ***
    i_stream : entity work.odma_mm2s_stream
        generic map (
            LengthWidth_g => LengthWidth_g,
            StreamWidth_g => StreamWidth_g,
            Join_g        => Join_g
        )
        port map (
            Clk          => Clk,
            Rst          => Rst,
            Run          => Run,
            Drain        => Drain,
            NoEntry      => NoEntry,
            Xfer_Valid   => Xfer_OutValid,
            Xfer_Ready   => Xfer_OutReady,
            Xfer_Length  => Xfer_OutData(LengthWidth_g - 1 downto 0),
            Xfer_Eof     => Xfer_OutData(LengthWidth_g),
            Xfer_Code    => Xfer_OutData(XferWidth_c - 1 downto LengthWidth_g + 1),
            Resp_Valid   => Resp_OutValid,
            Resp_Ready   => Resp_OutReady,
            Resp_Code    => Resp_OutData,
            Rd_Data      => Rd_Data,
            Rd_Last      => Rd_Last,
            Rd_Valid     => Rd_Valid,
            Rd_Ready     => Rd_Ready,
            Res_Valid    => Res_Valid,
            Res_Ready    => Res_Ready,
            Res_Bytes    => Res_Bytes,
            Res_Eof      => Res_Eof,
            Res_Err      => Res_Err,
            Closed       => StreamClosed,
            M_Mm2s_Data  => M_Mm2s_Data,
            M_Mm2s_Keep  => M_Mm2s_Keep,
            M_Mm2s_Last  => M_Mm2s_Last,
            M_Mm2s_Valid => M_Mm2s_Valid,
            M_Mm2s_Ready => M_Mm2s_Ready
        );

    -- *** ECC events: one pulse per word read from a buffer ***
    Ecc_Sec(0) <= Rd_EccSec and Rd_Valid and Rd_Ready;
    Ecc_Ded(0) <= Rd_EccDed and Rd_Valid and Rd_Ready;
    Ecc_Sec(1) <= Xfer_OutSec and Xfer_OutValid and Xfer_OutReady;
    Ecc_Ded(1) <= Xfer_OutDed and Xfer_OutValid and Xfer_OutReady;
    Ecc_Sec(2) <= Resp_OutSec and Resp_OutValid and Resp_OutReady;
    Ecc_Ded(2) <= Resp_OutDed and Resp_OutValid and Resp_OutReady;

    -- *** Stopped: no command in progress, both buffers empty. A transfer entry with a read is popped only after
    -- the response of the read, so an empty transfer buffer also means that no read is outstanding. With Join_g
    -- also no packet open in the join (MM-SG-04) ***
    NoEntry <= CmdIdle and Xfer_Empty;
    Stopped <= CmdIdle and Xfer_Empty and Resp_Empty and StreamClosed;

end architecture;
