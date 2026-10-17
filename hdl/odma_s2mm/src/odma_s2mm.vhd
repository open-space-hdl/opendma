---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stream to memory channel of OpenDMA (S2-1, S2-2): takes the S2MM stream into a data buffer, cuts
-- it into chunks of one burst and writes them into the buffer of each transfer command.
--
-- Documentation: hdl/odma_s2mm/docs/architecture.md

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
    use work.odma_s2mm_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_s2mm is
    generic (
        AddrWidth_g   : positive range 32 to 64 := 32;
        LengthWidth_g : positive range 8 to 26  := 14;
        MemWidth_g    : positive                := 32;
        StreamWidth_g : positive                := 32;
        BurstBeats_g  : positive                := 16;
        BufferBeats_g : positive                := 64;
        Split_g       : boolean                 := false
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
        Cmd_Keyhole   : in    std_logic                    := '0';
        -- Transfer result
        Res_Valid     : out   std_logic;
        Res_Ready     : in    std_logic;
        Res_Bytes     : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        Res_Eof       : out   std_logic;
        Res_Err       : out   XferErr_t;
        Res_Sof       : out   std_logic;
        -- Channel control
        Run           : in    std_logic;
        Drain         : in    std_logic;
        Stopped       : out   std_logic;
        -- S2MM stream
        S_S2mm_Data   : in    std_logic_vector(StreamWidth_g - 1 downto 0);
        S_S2mm_Keep   : in    std_logic_vector(StreamWidth_g / 8 - 1 downto 0);
        S_S2mm_Last   : in    std_logic;
        S_S2mm_Valid  : in    std_logic;
        S_S2mm_Ready  : out   std_logic;
        -- AXI4 write master
        M_Axi_AwAddr  : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        M_Axi_AwLen   : out   std_logic_vector(7 downto 0);
        M_Axi_AwSize  : out   std_logic_vector(2 downto 0);
        M_Axi_AwBurst : out   std_logic_vector(1 downto 0);
        M_Axi_AwLock  : out   std_logic;
        M_Axi_AwCache : out   std_logic_vector(3 downto 0);
        M_Axi_AwProt  : out   std_logic_vector(2 downto 0);
        M_Axi_AwValid : out   std_logic;
        M_Axi_AwReady : in    std_logic;
        M_Axi_WData   : out   std_logic_vector(MemWidth_g - 1 downto 0);
        M_Axi_WStrb   : out   std_logic_vector(MemWidth_g / 8 - 1 downto 0);
        M_Axi_WLast   : out   std_logic;
        M_Axi_WValid  : out   std_logic;
        M_Axi_WReady  : in    std_logic;
        M_Axi_BResp   : in    std_logic_vector(1 downto 0);
        M_Axi_BValid  : in    std_logic;
        M_Axi_BReady  : out   std_logic;
        -- FT buffers: 0 data buffer, 1 chunk buffer, 2 write data buffer
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
architecture rtl of odma_s2mm is

    -- Longest burst of the write master (no AXI burst crosses 4 KB, G13) and stream beats of a chunk, which is
    -- one burst (S2-ST-03)
    constant MasterBeats_c : positive := masterBeats(BurstBeats_g, MemWidth_g);
    constant ChunkBeats_c  : positive := MasterBeats_c * MemWidth_g / StreamWidth_g;
    constant DescDepth_c   : positive := 32;
    -- Size bits of the write master: one more than the length, so that no command reaches the last user word
    -- below 2**size bits, where the word count of olo_axi_master_full wrapped up to Open Logic 4.7.0-ft.6 (gap G14,
    -- corrected in 4.7.0-ft.8)
    constant SizeBits_c    : positive := LengthWidth_g + 1;

    -- Chunk former to the buffers
    signal Data_InData  : std_logic_vector(StreamWidth_g - 1 downto 0);
    signal Data_InValid : std_logic;
    signal Data_InReady : std_logic;
    signal Desc_InData  : std_logic_vector(DescWidth_c - 1 downto 0);
    signal Desc_InValid : std_logic;
    signal Desc_InReady : std_logic;
    signal PacketOpen   : std_logic;
    signal Seg_Valid    : std_logic;
    signal Seg_Size     : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal Seg_Ready    : std_logic;
    signal FlushReq     : std_logic;

    -- Buffers to the write command block
    signal Data_OutData  : std_logic_vector(StreamWidth_g - 1 downto 0);
    signal Data_OutValid : std_logic;
    signal Data_OutReady : std_logic;
    signal Data_OutSec   : std_logic;
    signal Data_OutDed   : std_logic;
    signal Desc_OutData  : std_logic_vector(DescWidth_c - 1 downto 0);
    signal Desc_OutValid : std_logic;
    signal Desc_OutReady : std_logic;
    signal Desc_OutSec   : std_logic;
    signal Desc_OutDed   : std_logic;
    signal Desc_Level    : std_logic_vector(5 downto 0);
    signal Desc_Stored   : std_logic;
    signal WriteIdle     : std_logic;

    -- Write master
    signal CmdWr_Addr   : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal CmdWr_Size   : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal MasterSize   : std_logic_vector(SizeBits_c - 1 downto 0);
    signal CmdWr_Valid  : std_logic;
    signal CmdWr_Ready  : std_logic;
    signal Wr_Data      : std_logic_vector(StreamWidth_g - 1 downto 0);
    signal Wr_Valid     : std_logic;
    signal Wr_Ready     : std_logic;
    signal Wr_EccSec    : std_logic;
    signal Wr_EccDed    : std_logic;
    signal Wr_Done      : std_logic;
    signal Wr_Error     : std_logic;
    signal Wr_ErrorResp : std_logic_vector(1 downto 0);
    signal CmdWr_Fixed  : std_logic;
    signal DataInjFlip  : std_logic_vector(eccCodewordWidth(StreamWidth_g) - 1 downto 0);
    signal DescInjFlip  : std_logic_vector(eccCodewordWidth(DescWidth_c) - 1 downto 0);
    signal WrInjFlip    : std_logic_vector(eccCodewordWidth(StreamWidth_g) - 1 downto 0);

begin

    -- *** Assertions ***
    -- The rules of the channel generics are those of the core (the first channel repeats the second one)
    assert coreConfigError(AddrWidth_g, LengthWidth_g, MemWidth_g, StreamWidth_g, BurstBeats_g, BufferBeats_g,
                           MemWidth_g, StreamWidth_g, BurstBeats_g, BufferBeats_g) = ""
        report "odma_s2mm: " & coreConfigError(AddrWidth_g, LengthWidth_g, MemWidth_g, StreamWidth_g, BurstBeats_g,
               BufferBeats_g, MemWidth_g, StreamWidth_g, BurstBeats_g, BufferBeats_g)
        severity failure;

    -- *** Chunk former (S2-1) ***
    i_chunker : entity work.odma_s2mm_chunker
        generic map (
            StreamWidth_g => StreamWidth_g,
            ChunkBeats_g  => ChunkBeats_c,
            LengthWidth_g => LengthWidth_g,
            Split_g       => Split_g
        )
        port map (
            Clk          => Clk,
            Rst          => Rst,
            Run          => Run,
            Drain        => Drain,
            S_S2mm_Data  => S_S2mm_Data,
            S_S2mm_Keep  => S_S2mm_Keep,
            S_S2mm_Last  => S_S2mm_Last,
            S_S2mm_Valid => S_S2mm_Valid,
            S_S2mm_Ready => S_S2mm_Ready,
            Seg_Valid    => Seg_Valid,
            Seg_Size     => Seg_Size,
            Seg_Ready    => Seg_Ready,
            FlushReq     => FlushReq,
            Data_Data    => Data_InData,
            Data_Valid   => Data_InValid,
            Data_Ready   => Data_InReady,
            Desc_Data    => Desc_InData,
            Desc_Valid   => Desc_InValid,
            Desc_Ready   => Desc_InReady,
            PacketOpen   => PacketOpen
        );

    -- *** Data buffer and chunk buffer ***
    DataInjFlip <= flipPattern(DataInjFlip'length, EccInj_Double, EccInj_Data);

    i_data : entity olo.olo_ft_fifo_sync
        generic map (
            Width_g => StreamWidth_g,
            Depth_g => BufferBeats_g
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Data           => Data_InData,
            In_Valid          => Data_InValid,
            In_Ready          => Data_InReady,
            Out_Data          => Data_OutData,
            Out_Valid         => Data_OutValid,
            Out_Ready         => Data_OutReady,
            Out_EccSec        => Data_OutSec,
            Out_EccDed        => Data_OutDed,
            In_ErrInj_BitFlip => DataInjFlip,
            In_ErrInj_Valid   => EccInj_Valid(0)
        );

    DescInjFlip <= flipPattern(DescInjFlip'length, EccInj_Double, EccInj_Data);

    i_desc : entity olo.olo_ft_fifo_sync
        generic map (
            Width_g => DescWidth_c,
            Depth_g => DescDepth_c
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Data           => Desc_InData,
            In_Valid          => Desc_InValid,
            In_Ready          => Desc_InReady,
            In_Level          => Desc_Level,
            Out_Data          => Desc_OutData,
            Out_Valid         => Desc_OutValid,
            Out_Ready         => Desc_OutReady,
            Out_EccSec        => Desc_OutSec,
            Out_EccDed        => Desc_OutDed,
            In_ErrInj_BitFlip => DescInjFlip,
            In_ErrInj_Valid   => EccInj_Valid(1)
        );

    -- A descriptor is stored from the clock cycle after its write on, before it reaches the output
    Desc_Stored <= '1' when unsigned(Desc_Level) /= 0 else '0';

    -- *** Write command (S2-2) ***
    i_write : entity work.odma_s2mm_write
        generic map (
            AddrWidth_g   => AddrWidth_g,
            LengthWidth_g => LengthWidth_g,
            StreamWidth_g => StreamWidth_g,
            Split_g       => Split_g
        )
        port map (
            Clk          => Clk,
            Rst          => Rst,
            Run          => Run,
            Drain        => Drain,
            Cmd_Valid    => Cmd_Valid,
            Cmd_Ready    => Cmd_Ready,
            Cmd_Addr     => Cmd_Addr,
            Cmd_Length   => Cmd_Length,
            Cmd_Keyhole  => Cmd_Keyhole,
            Res_Valid    => Res_Valid,
            Res_Ready    => Res_Ready,
            Res_Bytes    => Res_Bytes,
            Res_Eof      => Res_Eof,
            Res_Err      => Res_Err,
            Res_Sof      => Res_Sof,
            Seg_Valid    => Seg_Valid,
            Seg_Size     => Seg_Size,
            Seg_Ready    => Seg_Ready,
            FlushReq     => FlushReq,
            Desc_Data    => Desc_OutData,
            Desc_Valid   => Desc_OutValid,
            Desc_Ready   => Desc_OutReady,
            Desc_Stored  => Desc_Stored,
            PacketOpen   => PacketOpen,
            Buf_Data     => Data_OutData,
            Buf_Valid    => Data_OutValid,
            Buf_Ready    => Data_OutReady,
            CmdWr_Addr   => CmdWr_Addr,
            CmdWr_Size   => CmdWr_Size,
            CmdWr_Fixed  => CmdWr_Fixed,
            CmdWr_Valid  => CmdWr_Valid,
            CmdWr_Ready  => CmdWr_Ready,
            Wr_Data      => Wr_Data,
            Wr_Valid     => Wr_Valid,
            Wr_Ready     => Wr_Ready,
            Wr_Done      => Wr_Done,
            Wr_Error     => Wr_Error,
            Wr_ErrorResp => Wr_ErrorResp,
            Idle         => WriteIdle
        );

    -- *** AXI4 write master with the write data buffer of two chunks ***
    WrInjFlip  <= flipPattern(WrInjFlip'length, EccInj_Double, EccInj_Data);
    MasterSize <= std_logic_vector(resize(unsigned(CmdWr_Size), SizeBits_c));

    i_master : entity olo.olo_ft_axi_master_full
        generic map (
            AxiAddrWidth_g            => AddrWidth_g,
            AxiDataWidth_g            => MemWidth_g,
            AxiMaxBeats_g             => MasterBeats_c,
            AxiMaxOpenTransactions_g  => 8,
            UserTransactionSizeBits_g => SizeBits_c,
            DataFifoDepth_g           => 2 * ChunkBeats_c,
            UserDataWidth_g           => StreamWidth_g,
            ImplRead_g                => false,
            ImplWrite_g               => true
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            CmdWr_Addr        => CmdWr_Addr,
            CmdWr_Size        => MasterSize,
            CmdWr_LowLat      => '0',
            CmdWr_Fixed       => CmdWr_Fixed,
            CmdWr_Valid       => CmdWr_Valid,
            CmdWr_Ready       => CmdWr_Ready,
            Wr_Data           => Wr_Data,
            Wr_Valid          => Wr_Valid,
            Wr_Ready          => Wr_Ready,
            Wr_EccSec         => Wr_EccSec,
            Wr_EccDed         => Wr_EccDed,
            Wr_Done           => Wr_Done,
            Wr_Error          => Wr_Error,
            Wr_ErrorResp      => Wr_ErrorResp,
            Wr_ErrInj_BitFlip => WrInjFlip,
            Wr_ErrInj_Valid   => EccInj_Valid(2),
            M_Axi_AwAddr      => M_Axi_AwAddr,
            M_Axi_AwLen       => M_Axi_AwLen,
            M_Axi_AwSize      => M_Axi_AwSize,
            M_Axi_AwBurst     => M_Axi_AwBurst,
            M_Axi_AwLock      => M_Axi_AwLock,
            M_Axi_AwCache     => M_Axi_AwCache,
            M_Axi_AwProt      => M_Axi_AwProt,
            M_Axi_AwValid     => M_Axi_AwValid,
            M_Axi_AwReady     => M_Axi_AwReady,
            M_Axi_WData       => M_Axi_WData,
            M_Axi_WStrb       => M_Axi_WStrb,
            M_Axi_WLast       => M_Axi_WLast,
            M_Axi_WValid      => M_Axi_WValid,
            M_Axi_WReady      => M_Axi_WReady,
            M_Axi_BResp       => M_Axi_BResp,
            M_Axi_BValid      => M_Axi_BValid,
            M_Axi_BReady      => M_Axi_BReady
        );

    -- *** ECC events: one pulse per word read from a buffer (the write master qualifies its own) ***
    Ecc_Sec(0) <= Data_OutSec and Data_OutValid and Data_OutReady;
    Ecc_Ded(0) <= Data_OutDed and Data_OutValid and Data_OutReady;
    Ecc_Sec(1) <= Desc_OutSec and Desc_OutValid and Desc_OutReady;
    Ecc_Ded(1) <= Desc_OutDed and Desc_OutValid and Desc_OutReady;
    Ecc_Sec(2) <= Wr_EccSec;
    Ecc_Ded(2) <= Wr_EccDed;

    -- *** Stopped: no transfer in progress and no write outstanding ***
    Stopped <= WriteIdle;

end architecture;
