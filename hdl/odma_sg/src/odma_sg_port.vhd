---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Descriptor port of the Scatter/Gather engine (SG-3): round-robin arbitration of the descriptor
-- fetches and of the status writes of both channel engines on one AXI4 master with 32 data bits,
-- one fetch and one status write at a time; the read words go to the owner of the fetch, every
-- access ends with an end pulse and its error code.
--
-- Documentation: hdl/odma_sg/docs/architecture.md

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
entity odma_sg_port is
    generic (
        AddrWidth_g : positive range 32 to 64
    );
    port (
        -- Control Signals
        Clk                 : in    std_logic;
        Rst                 : in    std_logic;
        Drain               : in    std_logic;
        -- Fetches of the MM2S engine
        Mm2sFetch_Req       : in    std_logic;
        Mm2sFetch_Addr      : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        Mm2sFetch_Ack       : out   std_logic;
        Mm2sFetch_WordValid : out   std_logic;
        Mm2sFetch_End       : out   std_logic;
        -- Fetches of the S2MM engine
        S2mmFetch_Req       : in    std_logic;
        S2mmFetch_Addr      : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        S2mmFetch_Ack       : out   std_logic;
        S2mmFetch_WordValid : out   std_logic;
        S2mmFetch_End       : out   std_logic;
        -- Read words and error code of a fetch (to its owner)
        Fetch_Word          : out   std_logic_vector(31 downto 0);
        Fetch_Err           : out   XferErr_t;
        -- Status writes of the MM2S engine
        Mm2sUpd_Req         : in    std_logic;
        Mm2sUpd_Addr        : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        Mm2sUpd_Data        : in    std_logic_vector(31 downto 0);
        Mm2sUpd_Ack         : out   std_logic;
        Mm2sUpd_End         : out   std_logic;
        -- Status writes of the S2MM engine
        S2mmUpd_Req         : in    std_logic;
        S2mmUpd_Addr        : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        S2mmUpd_Data        : in    std_logic_vector(31 downto 0);
        S2mmUpd_Ack         : out   std_logic;
        S2mmUpd_End         : out   std_logic;
        -- Error code of a status write (to its owner)
        Upd_Err             : out   XferErr_t;
        -- AXI4 master
        M_Axi_AwAddr        : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        M_Axi_AwLen         : out   std_logic_vector(7 downto 0);
        M_Axi_AwSize        : out   std_logic_vector(2 downto 0);
        M_Axi_AwBurst       : out   std_logic_vector(1 downto 0);
        M_Axi_AwLock        : out   std_logic;
        M_Axi_AwCache       : out   std_logic_vector(3 downto 0);
        M_Axi_AwProt        : out   std_logic_vector(2 downto 0);
        M_Axi_AwValid       : out   std_logic;
        M_Axi_AwReady       : in    std_logic;
        M_Axi_WData         : out   std_logic_vector(31 downto 0);
        M_Axi_WStrb         : out   std_logic_vector(3 downto 0);
        M_Axi_WLast         : out   std_logic;
        M_Axi_WValid        : out   std_logic;
        M_Axi_WReady        : in    std_logic;
        M_Axi_BResp         : in    std_logic_vector(1 downto 0);
        M_Axi_BValid        : in    std_logic;
        M_Axi_BReady        : out   std_logic;
        M_Axi_ArAddr        : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        M_Axi_ArLen         : out   std_logic_vector(7 downto 0);
        M_Axi_ArSize        : out   std_logic_vector(2 downto 0);
        M_Axi_ArBurst       : out   std_logic_vector(1 downto 0);
        M_Axi_ArLock        : out   std_logic;
        M_Axi_ArCache       : out   std_logic_vector(3 downto 0);
        M_Axi_ArProt        : out   std_logic_vector(2 downto 0);
        M_Axi_ArValid       : out   std_logic;
        M_Axi_ArReady       : in    std_logic;
        M_Axi_RData         : in    std_logic_vector(31 downto 0);
        M_Axi_RResp         : in    std_logic_vector(1 downto 0);
        M_Axi_RLast         : in    std_logic;
        M_Axi_RValid        : in    std_logic;
        M_Axi_RReady        : out   std_logic;
        -- FT buffers: 0 read data buffer, 1 write data buffer
        Ecc_Sec             : out   std_logic_vector(1 downto 0);
        Ecc_Ded             : out   std_logic_vector(1 downto 0);
        EccInj_Valid        : in    std_logic_vector(1 downto 0);
        EccInj_Double       : in    std_logic;
        EccInj_Data         : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_sg_port is

    -----------------------------------------------------------------------------------------------
    -- G5 interim: olo_ft_axi_master_simple of Open Logic 4.7.0-ft.6 signals a failed command with
    -- Rd_Error or Wr_Error only, without the AXI response code. Until the Open Logic release with
    -- the response code (gap G5, specification section 3.8), every failed descriptor access gets
    -- the slave error code.
    -----------------------------------------------------------------------------------------------
    constant SgErrCode_c : XferErr_t := ErrSlv_c;

    -- Beats of a fetch (8 words) and of a status write (1 word)
    constant SizeBits_c   : positive                                  := 5;
    constant FetchBeats_c : std_logic_vector(SizeBits_c - 1 downto 0) := std_logic_vector(to_unsigned(8, SizeBits_c));
    constant UpdBeats_c   : std_logic_vector(SizeBits_c - 1 downto 0) := std_logic_vector(to_unsigned(1, SizeBits_c));

    -- Requesters of the arbiters: bit 1 MM2S, bit 0 S2MM
    constant ArbMm2s_c : natural := 1;
    constant ArbS2mm_c : natural := 0;

    type ReadFsm_t is (Idle_s, Command_s, Data_s);
    type WriteFsm_t is (Idle_s, Command_s, Response_s);

    type TwoProcess_r is record
        -- Fetch
        Rd      : ReadFsm_t;
        RdOwner : std_logic_vector(1 downto 0);
        RdAddr  : std_logic_vector(AddrWidth_g - 1 downto 0);
        RdLast  : std_logic;
        RdResp  : std_logic;
        RdErr   : XferErr_t;
        RdEnd   : std_logic_vector(1 downto 0);
        -- Status write
        Wr      : WriteFsm_t;
        WrOwner : std_logic_vector(1 downto 0);
        WrAddr  : std_logic_vector(AddrWidth_g - 1 downto 0);
        WrData  : std_logic_vector(31 downto 0);
        WrCmd   : std_logic;
        WrDat   : std_logic;
        WrErr   : XferErr_t;
        WrEnd   : std_logic_vector(1 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- Arbiters
    signal RdReq      : std_logic_vector(1 downto 0);
    signal RdGrant    : std_logic_vector(1 downto 0);
    signal RdGrantVld : std_logic;
    signal RdGrantRdy : std_logic;
    signal WrReq      : std_logic_vector(1 downto 0);
    signal WrGrant    : std_logic_vector(1 downto 0);
    signal WrGrantVld : std_logic;
    signal WrGrantRdy : std_logic;

    -- AXI4 master
    signal CmdRd_Valid : std_logic;
    signal CmdRd_Ready : std_logic;
    signal CmdWr_Valid : std_logic;
    signal CmdWr_Ready : std_logic;
    signal Wr_Valid    : std_logic;
    signal Wr_Ready    : std_logic;
    signal Rd_Data     : std_logic_vector(31 downto 0);
    signal Rd_Last     : std_logic;
    signal Rd_Valid    : std_logic;
    signal Rd_EccSec   : std_logic;
    signal Rd_EccDed   : std_logic;
    signal Wr_EccSec   : std_logic;
    signal Wr_EccDed   : std_logic;
    signal Wr_Done     : std_logic;
    signal Wr_Error    : std_logic;
    signal Rd_Done     : std_logic;
    signal Rd_Error    : std_logic;
    signal RdInjFlip   : std_logic_vector(eccCodewordWidth(32 + 1) - 1 downto 0);
    signal WrInjFlip   : std_logic_vector(eccCodewordWidth(32 + 4) - 1 downto 0);

begin

    -- *** Arbiters: a request takes part while the side is idle ***
    RdReq(ArbMm2s_c) <= Mm2sFetch_Req;
    RdReq(ArbS2mm_c) <= S2mmFetch_Req;
    WrReq(ArbMm2s_c) <= Mm2sUpd_Req;
    WrReq(ArbS2mm_c) <= S2mmUpd_Req;
    RdGrantRdy       <= '1' when r.Rd = Idle_s and Drain = '0' else '0';
    WrGrantRdy       <= '1' when r.Wr = Idle_s and Drain = '0' else '0';

    i_rd_arb : entity olo.olo_base_arb_rr
        generic map (
            Width_g => 2
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Req    => RdReq,
            Out_Grant => RdGrant,
            Out_Ready => RdGrantRdy,
            Out_Valid => RdGrantVld
        );

    i_wr_arb : entity olo.olo_base_arb_rr
        generic map (
            Width_g => 2
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Req    => WrReq,
            Out_Grant => WrGrant,
            Out_Ready => WrGrantRdy,
            Out_Valid => WrGrantVld
        );

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v : TwoProcess_r;
    begin
        v := r;

        -- End pulses last one clock cycle
        v.RdEnd := (others => '0');
        v.WrEnd := (others => '0');

        -- *** Fetch ***
        case r.Rd is

            when Idle_s =>
                -- The grant is taken with its owner and address
                if RdGrantVld = '1' and RdGrantRdy = '1' then
                    v.RdOwner := RdGrant;
                    if RdGrant(ArbMm2s_c) = '1' then
                        v.RdAddr := Mm2sFetch_Addr;
                    else
                        v.RdAddr := S2mmFetch_Addr;
                    end if;
                    v.Rd := Command_s;
                end if;

            when Command_s =>
                -- A granted fetch completes, also during a drain
                if CmdRd_Valid = '1' and CmdRd_Ready = '1' then
                    v.RdLast := '0';
                    v.RdResp := '0';
                    v.RdErr  := ErrNone_c;
                    v.Rd     := Data_s;
                end if;

            when Data_s =>
                -- The 8 words, then the response (it can come before or after the last word)
                if Rd_Valid = '1' and Rd_Last = '1' then
                    v.RdLast := '1';
                end if;
                if Rd_Done = '1' then
                    v.RdResp := '1';
                end if;
                if Rd_Error = '1' then
                    v.RdResp := '1';
                    v.RdErr  := SgErrCode_c;
                end if;
                -- The end pulse follows the last word by at least one clock cycle
                if r.RdLast = '1' and r.RdResp = '1' then
                    v.RdEnd := r.RdOwner;
                    v.Rd    := Idle_s;
                end if;

            -- coverage off
            when others =>
                -- Unreachable, safe recovery
                v.Rd := Idle_s;
            -- coverage on

        end case;

        -- *** Status write ***
        case r.Wr is

            when Idle_s =>
                if WrGrantVld = '1' and WrGrantRdy = '1' then
                    v.WrOwner := WrGrant;
                    if WrGrant(ArbMm2s_c) = '1' then
                        v.WrAddr := Mm2sUpd_Addr;
                        v.WrData := Mm2sUpd_Data;
                    else
                        v.WrAddr := S2mmUpd_Addr;
                        v.WrData := S2mmUpd_Data;
                    end if;
                    v.WrCmd := '0';
                    v.WrDat := '0';
                    v.Wr    := Command_s;
                end if;

            when Command_s =>
                -- Command and data word; a granted status write completes, also during a drain
                if CmdWr_Valid = '1' and CmdWr_Ready = '1' then
                    v.WrCmd := '1';
                end if;
                if Wr_Valid = '1' and Wr_Ready = '1' then
                    v.WrDat := '1';
                end if;
                if v.WrCmd = '1' and v.WrDat = '1' then
                    v.WrErr := ErrNone_c;
                    v.Wr    := Response_s;
                end if;

            when Response_s =>
                if Wr_Done = '1' or Wr_Error = '1' then
                    if Wr_Error = '1' then
                        v.WrErr := SgErrCode_c;
                    else
                        v.WrErr := ErrNone_c;
                    end if;
                    v.WrEnd := r.WrOwner;
                    v.Wr    := Idle_s;
                end if;

            -- coverage off
            when others =>
                -- Unreachable, safe recovery
                v.Wr := Idle_s;
            -- coverage on

        end case;

        r_next <= v;
    end process;

    -- *** Outputs ***
    Mm2sFetch_Ack       <= RdGrantVld and RdGrantRdy and RdGrant(ArbMm2s_c);
    S2mmFetch_Ack       <= RdGrantVld and RdGrantRdy and RdGrant(ArbS2mm_c);
    Mm2sFetch_WordValid <= Rd_Valid when r.Rd = Data_s and r.RdOwner(ArbMm2s_c) = '1' else '0';
    S2mmFetch_WordValid <= Rd_Valid when r.Rd = Data_s and r.RdOwner(ArbS2mm_c) = '1' else '0';
    Mm2sFetch_End       <= r.RdEnd(ArbMm2s_c);
    S2mmFetch_End       <= r.RdEnd(ArbS2mm_c);
    Fetch_Word          <= Rd_Data;
    Fetch_Err           <= r.RdErr;
    Mm2sUpd_Ack         <= WrGrantVld and WrGrantRdy and WrGrant(ArbMm2s_c);
    S2mmUpd_Ack         <= WrGrantVld and WrGrantRdy and WrGrant(ArbS2mm_c);
    Mm2sUpd_End         <= r.WrEnd(ArbMm2s_c);
    S2mmUpd_End         <= r.WrEnd(ArbS2mm_c);
    Upd_Err             <= r.WrErr;

    CmdRd_Valid <= '1' when r.Rd = Command_s else '0';
    CmdWr_Valid <= '1' when r.Wr = Command_s and r.WrCmd = '0' else '0';
    Wr_Valid    <= '1' when r.Wr = Command_s and r.WrDat = '0' else '0';

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Rd      <= Idle_s;
                r.RdOwner <= (others => '0');
                r.RdAddr  <= (others => '0');
                r.RdLast  <= '0';
                r.RdResp  <= '0';
                r.RdErr   <= ErrNone_c;
                r.RdEnd   <= (others => '0');
                r.Wr      <= Idle_s;
                r.WrOwner <= (others => '0');
                r.WrAddr  <= (others => '0');
                r.WrData  <= (others => '0');
                r.WrCmd   <= '0';
                r.WrDat   <= '0';
                r.WrErr   <= ErrNone_c;
                r.WrEnd   <= (others => '0');
            end if;
        end if;
    end process;

    -- *** AXI4 master ***
    RdInjFlip <= flipPattern(RdInjFlip'length, EccInj_Double, EccInj_Data);
    WrInjFlip <= flipPattern(WrInjFlip'length, EccInj_Double, EccInj_Data);

    i_master : entity olo.olo_ft_axi_master_simple
        generic map (
            AxiAddrWidth_g            => AddrWidth_g,
            AxiDataWidth_g            => 32,
            AxiMaxBeats_g             => 16,
            AxiMaxOpenTransactions_g  => 2,
            UserTransactionSizeBits_g => SizeBits_c,
            DataFifoDepth_g           => 32,
            ImplRead_g                => true,
            ImplWrite_g               => true
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            CmdWr_Addr        => r.WrAddr,
            CmdWr_Size        => UpdBeats_c,
            CmdWr_LowLat      => '0',
            CmdWr_Valid       => CmdWr_Valid,
            CmdWr_Ready       => CmdWr_Ready,
            CmdRd_Addr        => r.RdAddr,
            CmdRd_Size        => FetchBeats_c,
            CmdRd_LowLat      => '0',
            CmdRd_Valid       => CmdRd_Valid,
            CmdRd_Ready       => CmdRd_Ready,
            Wr_Data           => r.WrData,
            Wr_Be             => "1111",
            Wr_Valid          => Wr_Valid,
            Wr_Ready          => Wr_Ready,
            Wr_EccSec         => Wr_EccSec,
            Wr_EccDed         => Wr_EccDed,
            Rd_Data           => Rd_Data,
            Rd_Last           => Rd_Last,
            Rd_Valid          => Rd_Valid,
            Rd_Ready          => '1',
            Rd_EccSec         => Rd_EccSec,
            Rd_EccDed         => Rd_EccDed,
            Wr_Done           => Wr_Done,
            Wr_Error          => Wr_Error,
            Rd_Done           => Rd_Done,
            Rd_Error          => Rd_Error,
            Wr_ErrInj_BitFlip => WrInjFlip,
            Wr_ErrInj_Valid   => EccInj_Valid(1),
            Rd_ErrInj_BitFlip => RdInjFlip,
            Rd_ErrInj_Valid   => EccInj_Valid(0),
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
            M_Axi_BReady      => M_Axi_BReady,
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

    -- ECC events: the read flags qualified with the handshake of the read word, the write events are pulses
    Ecc_Sec(0) <= Rd_EccSec and Rd_Valid;
    Ecc_Ded(0) <= Rd_EccDed and Rd_Valid;
    Ecc_Sec(1) <= Wr_EccSec;
    Ecc_Ded(1) <= Wr_EccDed;

end architecture;
