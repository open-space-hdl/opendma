---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Top level of OpenDMA (CO-1): the register interface and the MM2S and S2MM channels of the
-- configuration, with the consistency check of the generics.
--
-- Documentation: hdl/odma_core/docs/architecture.md

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
entity odma_core is
    generic (
        IncludeSg_g       : boolean                 := false;
        IncludeMm2s_g     : boolean                 := true;
        IncludeS2mm_g     : boolean                 := true;
        LengthWidth_g     : positive range 8 to 26  := 14;
        AddrWidth_g       : positive range 32 to 64 := 32;
        Mm2sMemWidth_g    : positive                := 32;
        S2mmMemWidth_g    : positive                := 32;
        Mm2sStreamWidth_g : positive                := 32;
        S2mmStreamWidth_g : positive                := 32;
        Mm2sBurstBeats_g  : positive                := 16;
        S2mmBurstBeats_g  : positive                := 16;
        StsCntrlStrm_g    : boolean                 := false;
        UseRxLength_g     : boolean                 := false;
        MicroDma_g        : boolean                 := false;
        Mm2sBufferBeats_g : positive                := 64;
        S2mmBufferBeats_g : positive                := 64;
        ExtRegs_g         : boolean                 := true
    );
    port (
        -- Control Signals
        Clk                : in    std_logic;
        Rst                : in    std_logic;
        -- Register port
        S_AxiLite_ArAddr   : in    std_logic_vector(9 downto 0);
        S_AxiLite_ArValid  : in    std_logic;
        S_AxiLite_ArReady  : out   std_logic;
        S_AxiLite_AwAddr   : in    std_logic_vector(9 downto 0);
        S_AxiLite_AwValid  : in    std_logic;
        S_AxiLite_AwReady  : out   std_logic;
        S_AxiLite_WData    : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb    : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid   : in    std_logic;
        S_AxiLite_WReady   : out   std_logic;
        S_AxiLite_BResp    : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid   : out   std_logic;
        S_AxiLite_BReady   : in    std_logic;
        S_AxiLite_RData    : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp    : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid   : out   std_logic;
        S_AxiLite_RReady   : in    std_logic;
        -- MM2S memory port
        M_AxiMm2s_ArAddr   : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        M_AxiMm2s_ArLen    : out   std_logic_vector(7 downto 0);
        M_AxiMm2s_ArSize   : out   std_logic_vector(2 downto 0);
        M_AxiMm2s_ArBurst  : out   std_logic_vector(1 downto 0);
        M_AxiMm2s_ArLock   : out   std_logic;
        M_AxiMm2s_ArCache  : out   std_logic_vector(3 downto 0);
        M_AxiMm2s_ArProt   : out   std_logic_vector(2 downto 0);
        M_AxiMm2s_ArValid  : out   std_logic;
        M_AxiMm2s_ArReady  : in    std_logic                                            := '0';
        M_AxiMm2s_RData    : in    std_logic_vector(Mm2sMemWidth_g - 1 downto 0)        := (others => '0');
        M_AxiMm2s_RResp    : in    std_logic_vector(1 downto 0)                         := (others => '0');
        M_AxiMm2s_RLast    : in    std_logic                                            := '0';
        M_AxiMm2s_RValid   : in    std_logic                                            := '0';
        M_AxiMm2s_RReady   : out   std_logic;
        -- MM2S stream
        M_Mm2s_Data        : out   std_logic_vector(Mm2sStreamWidth_g - 1 downto 0);
        M_Mm2s_Keep        : out   std_logic_vector(Mm2sStreamWidth_g / 8 - 1 downto 0);
        M_Mm2s_Last        : out   std_logic;
        M_Mm2s_Valid       : out   std_logic;
        M_Mm2s_Ready       : in    std_logic                                            := '0';
        -- S2MM stream
        S_S2mm_Data        : in    std_logic_vector(S2mmStreamWidth_g - 1 downto 0)     := (others => '0');
        S_S2mm_Keep        : in    std_logic_vector(S2mmStreamWidth_g / 8 - 1 downto 0) := (others => '0');
        S_S2mm_Last        : in    std_logic                                            := '0';
        S_S2mm_Valid       : in    std_logic                                            := '0';
        S_S2mm_Ready       : out   std_logic;
        -- S2MM memory port
        M_AxiS2mm_AwAddr   : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        M_AxiS2mm_AwLen    : out   std_logic_vector(7 downto 0);
        M_AxiS2mm_AwSize   : out   std_logic_vector(2 downto 0);
        M_AxiS2mm_AwBurst  : out   std_logic_vector(1 downto 0);
        M_AxiS2mm_AwLock   : out   std_logic;
        M_AxiS2mm_AwCache  : out   std_logic_vector(3 downto 0);
        M_AxiS2mm_AwProt   : out   std_logic_vector(2 downto 0);
        M_AxiS2mm_AwValid  : out   std_logic;
        M_AxiS2mm_AwReady  : in    std_logic                                            := '0';
        M_AxiS2mm_WData    : out   std_logic_vector(S2mmMemWidth_g - 1 downto 0);
        M_AxiS2mm_WStrb    : out   std_logic_vector(S2mmMemWidth_g / 8 - 1 downto 0);
        M_AxiS2mm_WLast    : out   std_logic;
        M_AxiS2mm_WValid   : out   std_logic;
        M_AxiS2mm_WReady   : in    std_logic                                            := '0';
        M_AxiS2mm_BResp    : in    std_logic_vector(1 downto 0)                         := (others => '0');
        M_AxiS2mm_BValid   : in    std_logic                                            := '0';
        M_AxiS2mm_BReady   : out   std_logic;
        -- Descriptor port (Scatter/Gather Mode)
        M_AxiSg_ArAddr     : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        M_AxiSg_ArLen      : out   std_logic_vector(7 downto 0);
        M_AxiSg_ArSize     : out   std_logic_vector(2 downto 0);
        M_AxiSg_ArBurst    : out   std_logic_vector(1 downto 0);
        M_AxiSg_ArLock     : out   std_logic;
        M_AxiSg_ArCache    : out   std_logic_vector(3 downto 0);
        M_AxiSg_ArProt     : out   std_logic_vector(2 downto 0);
        M_AxiSg_ArValid    : out   std_logic;
        M_AxiSg_ArReady    : in    std_logic                                            := '0';
        M_AxiSg_RData      : in    std_logic_vector(31 downto 0)                        := (others => '0');
        M_AxiSg_RResp      : in    std_logic_vector(1 downto 0)                         := (others => '0');
        M_AxiSg_RLast      : in    std_logic                                            := '0';
        M_AxiSg_RValid     : in    std_logic                                            := '0';
        M_AxiSg_RReady     : out   std_logic;
        M_AxiSg_AwAddr     : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        M_AxiSg_AwLen      : out   std_logic_vector(7 downto 0);
        M_AxiSg_AwSize     : out   std_logic_vector(2 downto 0);
        M_AxiSg_AwBurst    : out   std_logic_vector(1 downto 0);
        M_AxiSg_AwLock     : out   std_logic;
        M_AxiSg_AwCache    : out   std_logic_vector(3 downto 0);
        M_AxiSg_AwProt     : out   std_logic_vector(2 downto 0);
        M_AxiSg_AwValid    : out   std_logic;
        M_AxiSg_AwReady    : in    std_logic                                            := '0';
        M_AxiSg_WData      : out   std_logic_vector(31 downto 0);
        M_AxiSg_WStrb      : out   std_logic_vector(3 downto 0);
        M_AxiSg_WLast      : out   std_logic;
        M_AxiSg_WValid     : out   std_logic;
        M_AxiSg_WReady     : in    std_logic                                            := '0';
        M_AxiSg_BResp      : in    std_logic_vector(1 downto 0)                         := (others => '0');
        M_AxiSg_BValid     : in    std_logic                                            := '0';
        M_AxiSg_BReady     : out   std_logic;
        -- Interrupts and reset outputs
        Mm2s_Irq           : out   std_logic;
        S2mm_Irq           : out   std_logic;
        Ecc_Irq            : out   std_logic;
        Mm2s_RstOut        : out   std_logic;
        S2mm_RstOut        : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_core is

    -- Indices of the FT buffers in the extension window (architecture of odma_registers, section 8)
    constant EccMm2sData_c : natural := 0;
    constant EccS2mmData_c : natural := 1;
    constant EccS2mmDesc_c : natural := 2;
    constant EccS2mmWr_c   : natural := 3;
    constant EccMm2sXfer_c : natural := 4;
    constant EccMm2sResp_c : natural := 5;
    constant EccSgLo_c     : natural := 6;      -- Scatter/Gather engine: 6 to 9

    -- ECC events of the buffers of both channels and of the engine in the order of the extension window; the other
    -- indices 0
    function eccIndex (
        mm2s : std_logic_vector(2 downto 0);
        s2mm : std_logic_vector(2 downto 0);
        sg   : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable Idx_v : std_logic_vector(15 downto 0) := (others => '0');
    begin
        Idx_v(EccMm2sData_c)                  := mm2s(0);
        Idx_v(EccMm2sXfer_c)                  := mm2s(1);
        Idx_v(EccMm2sResp_c)                  := mm2s(2);
        Idx_v(EccS2mmData_c)                  := s2mm(0);
        Idx_v(EccS2mmDesc_c)                  := s2mm(1);
        Idx_v(EccS2mmWr_c)                    := s2mm(2);
        Idx_v(EccSgLo_c + 3 downto EccSgLo_c) := sg;
        return Idx_v;
    end function;

    constant ConfigError_c : string := coreConfigError(AddrWidth_g, LengthWidth_g, Mm2sMemWidth_g, Mm2sStreamWidth_g,
                                                       Mm2sBurstBeats_g, Mm2sBufferBeats_g, S2mmMemWidth_g,
                                                       S2mmStreamWidth_g, S2mmBurstBeats_g, S2mmBufferBeats_g);

    -- Core reset of the channels
    signal CoreRst : std_logic;

    -- MM2S channel
    signal Mm2sCmd_Valid   : std_logic;
    signal Mm2sCmd_Ready   : std_logic;
    signal Mm2sCmd_Addr    : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal Mm2sCmd_Length  : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal Mm2sCmd_Sof     : std_logic;
    signal Mm2sCmd_Eof     : std_logic;
    signal Mm2sCmd_Keyhole : std_logic;
    signal Mm2sRes_Valid   : std_logic;
    signal Mm2sRes_Ready   : std_logic;
    signal Mm2sRes_Bytes   : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal Mm2sRes_Eof     : std_logic;
    signal Mm2sRes_Err     : XferErr_t;
    signal Mm2s_Run        : std_logic;
    signal Mm2s_Drain      : std_logic;
    signal Mm2s_Stopped    : std_logic;
    signal Mm2sEcc_Sec     : std_logic_vector(2 downto 0);
    signal Mm2sEcc_Ded     : std_logic_vector(2 downto 0);
    signal Mm2sEccInj      : std_logic_vector(2 downto 0);

    -- S2MM channel
    signal S2mmCmd_Valid   : std_logic;
    signal S2mmCmd_Ready   : std_logic;
    signal S2mmCmd_Addr    : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal S2mmCmd_Length  : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal S2mmCmd_Keyhole : std_logic;
    signal S2mmRes_Valid   : std_logic;
    signal S2mmRes_Ready   : std_logic;
    signal S2mmRes_Bytes   : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal S2mmRes_Eof     : std_logic;
    signal S2mmRes_Err     : XferErr_t;
    signal S2mm_Run        : std_logic;
    signal S2mm_Drain      : std_logic;
    signal S2mm_Stopped    : std_logic;
    signal S2mmEcc_Sec     : std_logic_vector(2 downto 0);
    signal S2mmEcc_Ded     : std_logic_vector(2 downto 0);
    signal S2mmEccInj      : std_logic_vector(2 downto 0);

    -- Register interface side of the commands and results (Direct Register Mode) and the stopped levels it sees
    signal RegMm2sCmd_Valid   : std_logic;
    signal RegMm2sCmd_Addr    : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal RegMm2sCmd_Length  : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal RegMm2sCmd_Sof     : std_logic;
    signal RegMm2sCmd_Eof     : std_logic;
    signal RegMm2sCmd_Keyhole : std_logic;
    signal RegMm2sRes_Valid   : std_logic;
    signal RegMm2sRes_Ready   : std_logic;
    signal RegMm2s_Stopped    : std_logic;
    signal RegS2mmCmd_Valid   : std_logic;
    signal RegS2mmCmd_Addr    : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal RegS2mmCmd_Length  : std_logic_vector(LengthWidth_g - 1 downto 0);
    signal RegS2mmCmd_Keyhole : std_logic;
    signal RegS2mmRes_Valid   : std_logic;
    signal RegS2mmRes_Ready   : std_logic;
    signal RegS2mm_Stopped    : std_logic;

    -- Scatter/Gather engine
    signal Mm2sSg_CurDesc  : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal Mm2sSg_Tail     : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal Mm2sSg_TailWr   : std_logic;
    signal Mm2sSg_Cyclic   : std_logic;
    signal Mm2sSg_Keyhole  : std_logic;
    signal Mm2sSg_CurPtr   : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal Mm2sSg_Idle     : std_logic;
    signal Mm2sSg_Stopped  : std_logic;
    signal Mm2sSg_Pkt      : std_logic;
    signal Mm2sSg_ErrValid : std_logic;
    signal Mm2sSg_ErrXfer  : XferErr_t;
    signal Mm2sSg_ErrSg    : XferErr_t;
    signal S2mmSg_CurDesc  : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal S2mmSg_Tail     : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal S2mmSg_TailWr   : std_logic;
    signal S2mmSg_Cyclic   : std_logic;
    signal S2mmSg_Keyhole  : std_logic;
    signal S2mmSg_CurPtr   : std_logic_vector(AddrWidth_g - 1 downto 0);
    signal S2mmSg_Idle     : std_logic;
    signal S2mmSg_Stopped  : std_logic;
    signal S2mmSg_Pkt      : std_logic;
    signal S2mmSg_ErrValid : std_logic;
    signal S2mmSg_ErrXfer  : XferErr_t;
    signal S2mmSg_ErrSg    : XferErr_t;
    signal S2mmRes_Sof     : std_logic;
    signal SgEcc_Sec       : std_logic_vector(3 downto 0);
    signal SgEcc_Ded       : std_logic_vector(3 downto 0);

    -- Start of a packet at the stream ports (delay timer of odma_registers)
    type PktStart_r is record
        InPkt    : std_logic_vector(0 to 1);
        PktStart : std_logic_vector(0 to 1);
    end record;

    signal r, r_next : PktStart_r;

    -- FT buffers in the order of the extension window
    signal Ecc_Sec       : std_logic_vector(15 downto 0);
    signal Ecc_Ded       : std_logic_vector(15 downto 0);
    signal EccInj_Valid  : std_logic_vector(15 downto 0);
    signal EccInj_Double : std_logic;
    signal EccInj_Data   : std_logic;

begin

    -- *** Assertions ***
    assert ConfigError_c = ""
        report "odma_core: " & ConfigError_c
        severity failure;
    assert IncludeMm2s_g or IncludeS2mm_g
        report "odma_core: IncludeMm2s_g or IncludeS2mm_g must be true"
        severity failure;
    assert not StsCntrlStrm_g and not UseRxLength_g
        report "odma_core: StsCntrlStrm_g and UseRxLength_g must be false, " &
               "the control and status streams are not implemented"
        severity failure;
    assert not MicroDma_g
        report "odma_core: MicroDma_g must be false, the micro DMA configuration is not implemented"
        severity failure;

    -- *** Register interface (RG-1 to RG-4) ***
    i_registers : entity work.odma_registers
        generic map (
            IncludeSg_g       => IncludeSg_g,
            IncludeMm2s_g     => IncludeMm2s_g,
            IncludeS2mm_g     => IncludeS2mm_g,
            StsCntrlStrm_g    => StsCntrlStrm_g,
            UseRxLength_g     => UseRxLength_g,
            MicroDma_g        => MicroDma_g,
            LengthWidth_g     => LengthWidth_g,
            AddrWidth_g       => AddrWidth_g,
            Mm2sMemWidth_g    => Mm2sMemWidth_g,
            Mm2sStreamWidth_g => Mm2sStreamWidth_g,
            Mm2sBurstBeats_g  => Mm2sBurstBeats_g,
            Mm2sBufferBeats_g => Mm2sBufferBeats_g,
            S2mmMemWidth_g    => S2mmMemWidth_g,
            S2mmStreamWidth_g => S2mmStreamWidth_g,
            S2mmBurstBeats_g  => S2mmBurstBeats_g,
            S2mmBufferBeats_g => S2mmBufferBeats_g,
            ExtRegs_g         => ExtRegs_g
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            CoreRst           => CoreRst,
            S_AxiLite_ArAddr  => S_AxiLite_ArAddr,
            S_AxiLite_ArValid => S_AxiLite_ArValid,
            S_AxiLite_ArReady => S_AxiLite_ArReady,
            S_AxiLite_AwAddr  => S_AxiLite_AwAddr,
            S_AxiLite_AwValid => S_AxiLite_AwValid,
            S_AxiLite_AwReady => S_AxiLite_AwReady,
            S_AxiLite_WData   => S_AxiLite_WData,
            S_AxiLite_WStrb   => S_AxiLite_WStrb,
            S_AxiLite_WValid  => S_AxiLite_WValid,
            S_AxiLite_WReady  => S_AxiLite_WReady,
            S_AxiLite_BResp   => S_AxiLite_BResp,
            S_AxiLite_BValid  => S_AxiLite_BValid,
            S_AxiLite_BReady  => S_AxiLite_BReady,
            S_AxiLite_RData   => S_AxiLite_RData,
            S_AxiLite_RResp   => S_AxiLite_RResp,
            S_AxiLite_RValid  => S_AxiLite_RValid,
            S_AxiLite_RReady  => S_AxiLite_RReady,
            Mm2sCmd_Valid     => RegMm2sCmd_Valid,
            Mm2sCmd_Ready     => Mm2sCmd_Ready,
            Mm2sCmd_Addr      => RegMm2sCmd_Addr,
            Mm2sCmd_Length    => RegMm2sCmd_Length,
            Mm2sCmd_Sof       => RegMm2sCmd_Sof,
            Mm2sCmd_Eof       => RegMm2sCmd_Eof,
            Mm2sCmd_Keyhole   => RegMm2sCmd_Keyhole,
            Mm2sRes_Valid     => RegMm2sRes_Valid,
            Mm2sRes_Ready     => RegMm2sRes_Ready,
            Mm2sRes_Bytes     => Mm2sRes_Bytes,
            Mm2sRes_Eof       => Mm2sRes_Eof,
            Mm2sRes_Err       => Mm2sRes_Err,
            Mm2s_Run          => Mm2s_Run,
            Mm2s_Drain        => Mm2s_Drain,
            Mm2s_Stopped      => RegMm2s_Stopped,
            S2mmCmd_Valid     => RegS2mmCmd_Valid,
            S2mmCmd_Ready     => S2mmCmd_Ready,
            S2mmCmd_Addr      => RegS2mmCmd_Addr,
            S2mmCmd_Length    => RegS2mmCmd_Length,
            S2mmCmd_Keyhole   => RegS2mmCmd_Keyhole,
            S2mmRes_Valid     => RegS2mmRes_Valid,
            S2mmRes_Ready     => RegS2mmRes_Ready,
            S2mmRes_Bytes     => S2mmRes_Bytes,
            S2mmRes_Eof       => S2mmRes_Eof,
            S2mmRes_Err       => S2mmRes_Err,
            S2mm_Run          => S2mm_Run,
            S2mm_Drain        => S2mm_Drain,
            S2mm_Stopped      => RegS2mm_Stopped,
            Mm2sSg_CurDesc    => Mm2sSg_CurDesc,
            Mm2sSg_Tail       => Mm2sSg_Tail,
            Mm2sSg_TailWr     => Mm2sSg_TailWr,
            Mm2sSg_Cyclic     => Mm2sSg_Cyclic,
            Mm2sSg_Keyhole    => Mm2sSg_Keyhole,
            Mm2sSg_CurPtr     => Mm2sSg_CurPtr,
            Mm2sSg_Idle       => Mm2sSg_Idle,
            Mm2sSg_Pkt        => Mm2sSg_Pkt,
            Mm2sSg_ErrValid   => Mm2sSg_ErrValid,
            Mm2sSg_ErrXfer    => Mm2sSg_ErrXfer,
            Mm2sSg_ErrSg      => Mm2sSg_ErrSg,
            Mm2s_PktStart     => r.PktStart(0),
            S2mmSg_CurDesc    => S2mmSg_CurDesc,
            S2mmSg_Tail       => S2mmSg_Tail,
            S2mmSg_TailWr     => S2mmSg_TailWr,
            S2mmSg_Cyclic     => S2mmSg_Cyclic,
            S2mmSg_Keyhole    => S2mmSg_Keyhole,
            S2mmSg_CurPtr     => S2mmSg_CurPtr,
            S2mmSg_Idle       => S2mmSg_Idle,
            S2mmSg_Pkt        => S2mmSg_Pkt,
            S2mmSg_ErrValid   => S2mmSg_ErrValid,
            S2mmSg_ErrXfer    => S2mmSg_ErrXfer,
            S2mmSg_ErrSg      => S2mmSg_ErrSg,
            S2mm_PktStart     => r.PktStart(1),
            Mm2s_Irq          => Mm2s_Irq,
            S2mm_Irq          => S2mm_Irq,
            Ecc_Irq           => Ecc_Irq,
            Mm2s_RstOut       => Mm2s_RstOut,
            S2mm_RstOut       => S2mm_RstOut,
            Ecc_Sec           => Ecc_Sec,
            Ecc_Ded           => Ecc_Ded,
            EccInj_Valid      => EccInj_Valid,
            EccInj_Double     => EccInj_Double,
            EccInj_Data       => EccInj_Data
        );

    -- *** FT buffers of the channels and of the engine in the order of the extension window ***
    Ecc_Sec <= eccIndex(Mm2sEcc_Sec, S2mmEcc_Sec, SgEcc_Sec);
    Ecc_Ded <= eccIndex(Mm2sEcc_Ded, S2mmEcc_Ded, SgEcc_Ded);

    Mm2sEccInj <= EccInj_Valid(EccMm2sResp_c) & EccInj_Valid(EccMm2sXfer_c) & EccInj_Valid(EccMm2sData_c);
    S2mmEccInj <= EccInj_Valid(EccS2mmWr_c) & EccInj_Valid(EccS2mmDesc_c) & EccInj_Valid(EccS2mmData_c);

    -- *** Direct Register Mode: the register interface issues the commands and takes the results ***
    g_dr : if not IncludeSg_g generate
        Mm2sCmd_Valid    <= RegMm2sCmd_Valid;
        Mm2sCmd_Addr     <= RegMm2sCmd_Addr;
        Mm2sCmd_Length   <= RegMm2sCmd_Length;
        Mm2sCmd_Sof      <= RegMm2sCmd_Sof;
        Mm2sCmd_Eof      <= RegMm2sCmd_Eof;
        Mm2sCmd_Keyhole  <= RegMm2sCmd_Keyhole;
        RegMm2sRes_Valid <= Mm2sRes_Valid;
        Mm2sRes_Ready    <= RegMm2sRes_Ready;
        RegMm2s_Stopped  <= Mm2s_Stopped;
        S2mmCmd_Valid    <= RegS2mmCmd_Valid;
        S2mmCmd_Addr     <= RegS2mmCmd_Addr;
        S2mmCmd_Length   <= RegS2mmCmd_Length;
        S2mmCmd_Keyhole  <= RegS2mmCmd_Keyhole;
        RegS2mmRes_Valid <= S2mmRes_Valid;
        S2mmRes_Ready    <= RegS2mmRes_Ready;
        RegS2mm_Stopped  <= S2mm_Stopped;
        -- Idle values of the descriptor port and of the engine
        Mm2sSg_CurPtr   <= (others => '0');
        Mm2sSg_Idle     <= '0';
        Mm2sSg_Pkt      <= '0';
        Mm2sSg_ErrValid <= '0';
        Mm2sSg_ErrXfer  <= ErrNone_c;
        Mm2sSg_ErrSg    <= ErrNone_c;
        S2mmSg_CurPtr   <= (others => '0');
        S2mmSg_Idle     <= '0';
        S2mmSg_Pkt      <= '0';
        S2mmSg_ErrValid <= '0';
        S2mmSg_ErrXfer  <= ErrNone_c;
        S2mmSg_ErrSg    <= ErrNone_c;
        SgEcc_Sec       <= (others => '0');
        SgEcc_Ded       <= (others => '0');
        M_AxiSg_ArAddr  <= (others => '0');
        M_AxiSg_ArLen   <= (others => '0');
        M_AxiSg_ArSize  <= "010";
        M_AxiSg_ArBurst <= "01";
        M_AxiSg_ArLock  <= '0';
        M_AxiSg_ArCache <= "0011";
        M_AxiSg_ArProt  <= "000";
        M_AxiSg_ArValid <= '0';
        M_AxiSg_RReady  <= '0';
        M_AxiSg_AwAddr  <= (others => '0');
        M_AxiSg_AwLen   <= (others => '0');
        M_AxiSg_AwSize  <= "010";
        M_AxiSg_AwBurst <= "01";
        M_AxiSg_AwLock  <= '0';
        M_AxiSg_AwCache <= "0011";
        M_AxiSg_AwProt  <= "000";
        M_AxiSg_AwValid <= '0';
        M_AxiSg_WData   <= (others => '0');
        M_AxiSg_WStrb   <= (others => '0');
        M_AxiSg_WLast   <= '0';
        M_AxiSg_WValid  <= '0';
        M_AxiSg_BReady  <= '0';
    end generate;

    -- *** Scatter/Gather Mode: the engine issues the commands and takes the results (SG-1 to SG-3) ***
    g_sg : if IncludeSg_g generate
        RegMm2sRes_Valid <= '0';
        RegS2mmRes_Valid <= '0';
        -- A channel has stopped when the channel and its engine have (odma_registers RG-SG-10)
        RegMm2s_Stopped <= Mm2s_Stopped and Mm2sSg_Stopped;
        RegS2mm_Stopped <= S2mm_Stopped and S2mmSg_Stopped;
        -- Until packets continue over several buffers (gap G10), every S2MM buffer that receives a byte holds the
        -- first byte of its packet (odma_sg architecture, section 11)
        S2mmRes_Sof <= '1' when unsigned(S2mmRes_Bytes) /= 0 else '0';

        i_sg : entity work.odma_sg
            generic map (
                IncludeMm2s_g => IncludeMm2s_g,
                IncludeS2mm_g => IncludeS2mm_g,
                AddrWidth_g   => AddrWidth_g,
                LengthWidth_g => LengthWidth_g
            )
            port map (
                Clk             => Clk,
                Rst             => CoreRst,
                Mm2s_Run        => Mm2s_Run,
                Mm2s_Drain      => Mm2s_Drain,
                Mm2s_CurDesc    => Mm2sSg_CurDesc,
                Mm2s_Tail       => Mm2sSg_Tail,
                Mm2s_TailWr     => Mm2sSg_TailWr,
                Mm2s_Cyclic     => Mm2sSg_Cyclic,
                Mm2s_Keyhole    => Mm2sSg_Keyhole,
                Mm2s_CurPtr     => Mm2sSg_CurPtr,
                Mm2s_Idle       => Mm2sSg_Idle,
                Mm2s_Stopped    => Mm2sSg_Stopped,
                Mm2s_Pkt        => Mm2sSg_Pkt,
                Mm2s_ErrValid   => Mm2sSg_ErrValid,
                Mm2s_ErrXfer    => Mm2sSg_ErrXfer,
                Mm2s_ErrSg      => Mm2sSg_ErrSg,
                Mm2sCmd_Valid   => Mm2sCmd_Valid,
                Mm2sCmd_Ready   => Mm2sCmd_Ready,
                Mm2sCmd_Addr    => Mm2sCmd_Addr,
                Mm2sCmd_Length  => Mm2sCmd_Length,
                Mm2sCmd_Sof     => Mm2sCmd_Sof,
                Mm2sCmd_Eof     => Mm2sCmd_Eof,
                Mm2sCmd_Keyhole => Mm2sCmd_Keyhole,
                Mm2sRes_Valid   => Mm2sRes_Valid,
                Mm2sRes_Ready   => Mm2sRes_Ready,
                Mm2sRes_Bytes   => Mm2sRes_Bytes,
                Mm2sRes_Eof     => Mm2sRes_Eof,
                Mm2sRes_Err     => Mm2sRes_Err,
                S2mm_Run        => S2mm_Run,
                S2mm_Drain      => S2mm_Drain,
                S2mm_CurDesc    => S2mmSg_CurDesc,
                S2mm_Tail       => S2mmSg_Tail,
                S2mm_TailWr     => S2mmSg_TailWr,
                S2mm_Cyclic     => S2mmSg_Cyclic,
                S2mm_Keyhole    => S2mmSg_Keyhole,
                S2mm_CurPtr     => S2mmSg_CurPtr,
                S2mm_Idle       => S2mmSg_Idle,
                S2mm_Stopped    => S2mmSg_Stopped,
                S2mm_Pkt        => S2mmSg_Pkt,
                S2mm_ErrValid   => S2mmSg_ErrValid,
                S2mm_ErrXfer    => S2mmSg_ErrXfer,
                S2mm_ErrSg      => S2mmSg_ErrSg,
                S2mmCmd_Valid   => S2mmCmd_Valid,
                S2mmCmd_Ready   => S2mmCmd_Ready,
                S2mmCmd_Addr    => S2mmCmd_Addr,
                S2mmCmd_Length  => S2mmCmd_Length,
                S2mmCmd_Keyhole => S2mmCmd_Keyhole,
                S2mmRes_Valid   => S2mmRes_Valid,
                S2mmRes_Ready   => S2mmRes_Ready,
                S2mmRes_Bytes   => S2mmRes_Bytes,
                S2mmRes_Sof     => S2mmRes_Sof,
                S2mmRes_Eof     => S2mmRes_Eof,
                S2mmRes_Err     => S2mmRes_Err,
                M_Axi_AwAddr    => M_AxiSg_AwAddr,
                M_Axi_AwLen     => M_AxiSg_AwLen,
                M_Axi_AwSize    => M_AxiSg_AwSize,
                M_Axi_AwBurst   => M_AxiSg_AwBurst,
                M_Axi_AwLock    => M_AxiSg_AwLock,
                M_Axi_AwCache   => M_AxiSg_AwCache,
                M_Axi_AwProt    => M_AxiSg_AwProt,
                M_Axi_AwValid   => M_AxiSg_AwValid,
                M_Axi_AwReady   => M_AxiSg_AwReady,
                M_Axi_WData     => M_AxiSg_WData,
                M_Axi_WStrb     => M_AxiSg_WStrb,
                M_Axi_WLast     => M_AxiSg_WLast,
                M_Axi_WValid    => M_AxiSg_WValid,
                M_Axi_WReady    => M_AxiSg_WReady,
                M_Axi_BResp     => M_AxiSg_BResp,
                M_Axi_BValid    => M_AxiSg_BValid,
                M_Axi_BReady    => M_AxiSg_BReady,
                M_Axi_ArAddr    => M_AxiSg_ArAddr,
                M_Axi_ArLen     => M_AxiSg_ArLen,
                M_Axi_ArSize    => M_AxiSg_ArSize,
                M_Axi_ArBurst   => M_AxiSg_ArBurst,
                M_Axi_ArLock    => M_AxiSg_ArLock,
                M_Axi_ArCache   => M_AxiSg_ArCache,
                M_Axi_ArProt    => M_AxiSg_ArProt,
                M_Axi_ArValid   => M_AxiSg_ArValid,
                M_Axi_ArReady   => M_AxiSg_ArReady,
                M_Axi_RData     => M_AxiSg_RData,
                M_Axi_RResp     => M_AxiSg_RResp,
                M_Axi_RLast     => M_AxiSg_RLast,
                M_Axi_RValid    => M_AxiSg_RValid,
                M_Axi_RReady    => M_AxiSg_RReady,
                Ecc_Sec         => SgEcc_Sec,
                Ecc_Ded         => SgEcc_Ded,
                EccInj_Valid    => EccInj_Valid(EccSgLo_c + 3 downto EccSgLo_c),
                EccInj_Double   => EccInj_Double,
                EccInj_Data     => EccInj_Data
            );

    end generate;

    -- *** Start of a packet at the stream ports: the first beat after a TLast (odma_registers RG-SG-07) ***
    p_comb : process (all) is
        variable v : PktStart_r;
    begin
        v          := r;
        v.PktStart := "00";
        if M_Mm2s_Valid = '1' and M_Mm2s_Ready = '1' then
            v.PktStart(0) := not r.InPkt(0);
            v.InPkt(0)    := not M_Mm2s_Last;
        end if;
        if S_S2mm_Valid = '1' and S_S2mm_Ready = '1' then
            v.PktStart(1) := not r.InPkt(1);
            v.InPkt(1)    := not S_S2mm_Last;
        end if;
        r_next <= v;
    end process;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if CoreRst = '1' then
                r.InPkt    <= "00";
                r.PktStart <= "00";
            end if;
        end if;
    end process;

    -- *** MM2S channel (MM-1, MM-2) ***
    g_mm2s : if IncludeMm2s_g generate

        i_mm2s : entity work.odma_mm2s
            generic map (
                AddrWidth_g   => AddrWidth_g,
                LengthWidth_g => LengthWidth_g,
                MemWidth_g    => Mm2sMemWidth_g,
                StreamWidth_g => Mm2sStreamWidth_g,
                BurstBeats_g  => Mm2sBurstBeats_g,
                BufferBeats_g => Mm2sBufferBeats_g
            )
            port map (
                Clk           => Clk,
                Rst           => CoreRst,
                Cmd_Valid     => Mm2sCmd_Valid,
                Cmd_Ready     => Mm2sCmd_Ready,
                Cmd_Addr      => Mm2sCmd_Addr,
                Cmd_Length    => Mm2sCmd_Length,
                Cmd_Sof       => Mm2sCmd_Sof,
                Cmd_Eof       => Mm2sCmd_Eof,
                Cmd_Keyhole   => Mm2sCmd_Keyhole,
                Res_Valid     => Mm2sRes_Valid,
                Res_Ready     => Mm2sRes_Ready,
                Res_Bytes     => Mm2sRes_Bytes,
                Res_Eof       => Mm2sRes_Eof,
                Res_Err       => Mm2sRes_Err,
                Run           => Mm2s_Run,
                Drain         => Mm2s_Drain,
                Stopped       => Mm2s_Stopped,
                M_Axi_ArAddr  => M_AxiMm2s_ArAddr,
                M_Axi_ArLen   => M_AxiMm2s_ArLen,
                M_Axi_ArSize  => M_AxiMm2s_ArSize,
                M_Axi_ArBurst => M_AxiMm2s_ArBurst,
                M_Axi_ArLock  => M_AxiMm2s_ArLock,
                M_Axi_ArCache => M_AxiMm2s_ArCache,
                M_Axi_ArProt  => M_AxiMm2s_ArProt,
                M_Axi_ArValid => M_AxiMm2s_ArValid,
                M_Axi_ArReady => M_AxiMm2s_ArReady,
                M_Axi_RData   => M_AxiMm2s_RData,
                M_Axi_RResp   => M_AxiMm2s_RResp,
                M_Axi_RLast   => M_AxiMm2s_RLast,
                M_Axi_RValid  => M_AxiMm2s_RValid,
                M_Axi_RReady  => M_AxiMm2s_RReady,
                M_Mm2s_Data   => M_Mm2s_Data,
                M_Mm2s_Keep   => M_Mm2s_Keep,
                M_Mm2s_Last   => M_Mm2s_Last,
                M_Mm2s_Valid  => M_Mm2s_Valid,
                M_Mm2s_Ready  => M_Mm2s_Ready,
                Ecc_Sec       => Mm2sEcc_Sec,
                Ecc_Ded       => Mm2sEcc_Ded,
                EccInj_Valid  => Mm2sEccInj,
                EccInj_Double => EccInj_Double,
                EccInj_Data   => EccInj_Data
            );

    end generate;

    g_no_mm2s : if not IncludeMm2s_g generate
        -- Idle values of the ports of a channel that is not included
        Mm2sCmd_Ready     <= '0';
        Mm2sRes_Valid     <= '0';
        Mm2sRes_Bytes     <= (others => '0');
        Mm2sRes_Eof       <= '0';
        Mm2sRes_Err       <= ErrNone_c;
        Mm2s_Stopped      <= '1';
        Mm2sEcc_Sec       <= (others => '0');
        Mm2sEcc_Ded       <= (others => '0');
        M_AxiMm2s_ArAddr  <= (others => '0');
        M_AxiMm2s_ArLen   <= (others => '0');
        M_AxiMm2s_ArSize  <= (others => '0');
        M_AxiMm2s_ArBurst <= "01";
        M_AxiMm2s_ArLock  <= '0';
        M_AxiMm2s_ArCache <= "0011";
        M_AxiMm2s_ArProt  <= "000";
        M_AxiMm2s_ArValid <= '0';
        M_AxiMm2s_RReady  <= '0';
        M_Mm2s_Data       <= (others => '0');
        M_Mm2s_Keep       <= (others => '0');
        M_Mm2s_Last       <= '0';
        M_Mm2s_Valid      <= '0';
    end generate;

    -- *** S2MM channel (S2-1, S2-2) ***
    g_s2mm : if IncludeS2mm_g generate

        i_s2mm : entity work.odma_s2mm
            generic map (
                AddrWidth_g   => AddrWidth_g,
                LengthWidth_g => LengthWidth_g,
                MemWidth_g    => S2mmMemWidth_g,
                StreamWidth_g => S2mmStreamWidth_g,
                BurstBeats_g  => S2mmBurstBeats_g,
                BufferBeats_g => S2mmBufferBeats_g
            )
            port map (
                Clk           => Clk,
                Rst           => CoreRst,
                Cmd_Valid     => S2mmCmd_Valid,
                Cmd_Ready     => S2mmCmd_Ready,
                Cmd_Addr      => S2mmCmd_Addr,
                Cmd_Length    => S2mmCmd_Length,
                Cmd_Keyhole   => S2mmCmd_Keyhole,
                Res_Valid     => S2mmRes_Valid,
                Res_Ready     => S2mmRes_Ready,
                Res_Bytes     => S2mmRes_Bytes,
                Res_Eof       => S2mmRes_Eof,
                Res_Err       => S2mmRes_Err,
                Run           => S2mm_Run,
                Drain         => S2mm_Drain,
                Stopped       => S2mm_Stopped,
                S_S2mm_Data   => S_S2mm_Data,
                S_S2mm_Keep   => S_S2mm_Keep,
                S_S2mm_Last   => S_S2mm_Last,
                S_S2mm_Valid  => S_S2mm_Valid,
                S_S2mm_Ready  => S_S2mm_Ready,
                M_Axi_AwAddr  => M_AxiS2mm_AwAddr,
                M_Axi_AwLen   => M_AxiS2mm_AwLen,
                M_Axi_AwSize  => M_AxiS2mm_AwSize,
                M_Axi_AwBurst => M_AxiS2mm_AwBurst,
                M_Axi_AwLock  => M_AxiS2mm_AwLock,
                M_Axi_AwCache => M_AxiS2mm_AwCache,
                M_Axi_AwProt  => M_AxiS2mm_AwProt,
                M_Axi_AwValid => M_AxiS2mm_AwValid,
                M_Axi_AwReady => M_AxiS2mm_AwReady,
                M_Axi_WData   => M_AxiS2mm_WData,
                M_Axi_WStrb   => M_AxiS2mm_WStrb,
                M_Axi_WLast   => M_AxiS2mm_WLast,
                M_Axi_WValid  => M_AxiS2mm_WValid,
                M_Axi_WReady  => M_AxiS2mm_WReady,
                M_Axi_BResp   => M_AxiS2mm_BResp,
                M_Axi_BValid  => M_AxiS2mm_BValid,
                M_Axi_BReady  => M_AxiS2mm_BReady,
                Ecc_Sec       => S2mmEcc_Sec,
                Ecc_Ded       => S2mmEcc_Ded,
                EccInj_Valid  => S2mmEccInj,
                EccInj_Double => EccInj_Double,
                EccInj_Data   => EccInj_Data
            );

    end generate;

    g_no_s2mm : if not IncludeS2mm_g generate
        -- Idle values of the ports of a channel that is not included
        S2mmCmd_Ready     <= '0';
        S2mmRes_Valid     <= '0';
        S2mmRes_Bytes     <= (others => '0');
        S2mmRes_Eof       <= '0';
        S2mmRes_Err       <= ErrNone_c;
        S2mm_Stopped      <= '1';
        S2mmEcc_Sec       <= (others => '0');
        S2mmEcc_Ded       <= (others => '0');
        S_S2mm_Ready      <= '0';
        M_AxiS2mm_AwAddr  <= (others => '0');
        M_AxiS2mm_AwLen   <= (others => '0');
        M_AxiS2mm_AwSize  <= (others => '0');
        M_AxiS2mm_AwBurst <= "01";
        M_AxiS2mm_AwLock  <= '0';
        M_AxiS2mm_AwCache <= "0011";
        M_AxiS2mm_AwProt  <= "000";
        M_AxiS2mm_AwValid <= '0';
        M_AxiS2mm_WData   <= (others => '0');
        M_AxiS2mm_WStrb   <= (others => '0');
        M_AxiS2mm_WLast   <= '0';
        M_AxiS2mm_WValid  <= '0';
        M_AxiS2mm_BReady  <= '0';
    end generate;

end architecture;
