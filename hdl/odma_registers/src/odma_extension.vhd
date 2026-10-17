---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Extension window of the register map (RG-4): identification, configuration readback, the ECC
-- counters of the FT buffers with their flags and interrupt, and the error injection control.
--
-- Documentation: hdl/odma_registers/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;

library work;
    use work.odma_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_extension is
    generic (
        IncludeSg_g       : boolean;
        IncludeMm2s_g     : boolean;
        IncludeS2mm_g     : boolean;
        StsCntrlStrm_g    : boolean;
        UseRxLength_g     : boolean;
        MicroDma_g        : boolean;
        LengthWidth_g     : positive;
        AddrWidth_g       : positive;
        Mm2sMemWidth_g    : positive;
        Mm2sStreamWidth_g : positive;
        Mm2sBurstBeats_g  : positive;
        Mm2sBufferBeats_g : positive;
        S2mmMemWidth_g    : positive;
        S2mmStreamWidth_g : positive;
        S2mmBurstBeats_g  : positive;
        S2mmBufferBeats_g : positive
    );
    port (
        -- Control Signals
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- Register access (byte address of the register port, decoded in the window)
        Rb_Addr       : in    std_logic_vector(9 downto 0);
        Rb_Wr         : in    std_logic;
        Rb_WrData     : in    std_logic_vector(31 downto 0);
        Rb_Rd         : in    std_logic;
        Rb_RdData     : out   std_logic_vector(31 downto 0);
        -- FT buffers
        Ecc_Sec       : in    std_logic_vector(15 downto 0);
        Ecc_Ded       : in    std_logic_vector(15 downto 0);
        EccInj_Valid  : out   std_logic_vector(15 downto 0);
        EccInj_Double : out   std_logic;
        EccInj_Data   : out   std_logic;
        -- Interrupt
        Ecc_Irq       : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_extension is

    -- Buffer indices and counter width of the ECC monitor (ECC_INFO)
    constant Buffers_c      : positive := 16;
    constant CounterWidth_c : positive := 16;

    -- Buffers of the configuration (register map, section FT buffers); the others count nothing
    function bufferMask return std_logic_vector is
        variable Mask_v : std_logic_vector(Buffers_c - 1 downto 0) := (others => '0');
    begin
        Mask_v(0)          := choose(IncludeMm2s_g, '1', '0');
        Mask_v(3 downto 1) := (others => choose(IncludeS2mm_g, '1', '0'));
        Mask_v(5 downto 4) := (others => choose(IncludeMm2s_g, '1', '0'));
        -- Scatter/Gather engine: descriptor buffers of the channels, data buffers of the descriptor port
        Mask_v(6)          := choose(IncludeSg_g and IncludeMm2s_g, '1', '0');
        Mask_v(7)          := choose(IncludeSg_g and IncludeS2mm_g, '1', '0');
        Mask_v(9 downto 8) := (others => choose(IncludeSg_g, '1', '0'));
        return Mask_v;
    end function;

    constant BufferMask_c : std_logic_vector(Buffers_c - 1 downto 0) := bufferMask;

    -- EXT_MM2S_CONFIG, EXT_S2MM_CONFIG
    function channelConfig (
        memWidth    : positive;
        streamWidth : positive;
        burstBeats  : positive;
        bufferBeats : positive) return std_logic_vector is
        variable Word_v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        Word_v(ExtMm2sConfigMemBytesHi_c downto ExtMm2sConfigMemBytesLo_c)       := toUslv(log2(memWidth / 8), 4);
        Word_v(ExtMm2sConfigStreamBytesHi_c downto ExtMm2sConfigStreamBytesLo_c) := toUslv(log2(streamWidth / 8), 4);
        Word_v(ExtMm2sConfigBurstBeatsHi_c downto ExtMm2sConfigBurstBeatsLo_c)   := toUslv(log2(burstBeats), 4);
        Word_v(ExtMm2sConfigBufferBeatsHi_c downto ExtMm2sConfigBufferBeatsLo_c) := toUslv(bufferBeats, 20);
        return Word_v;
    end function;

    -- EXT_CONFIG
    function coreConfig return std_logic_vector is
        variable Word_v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        Word_v(ExtConfigIncludeSg_c)                                     := choose(IncludeSg_g, '1', '0');
        Word_v(ExtConfigIncludeMm2s_c)                                   := choose(IncludeMm2s_g, '1', '0');
        Word_v(ExtConfigIncludeS2mm_c)                                   := choose(IncludeS2mm_g, '1', '0');
        Word_v(ExtConfigStsCntrlStrm_c)                                  := choose(StsCntrlStrm_g, '1', '0');
        Word_v(ExtConfigUseRxLength_c)                                   := choose(UseRxLength_g, '1', '0');
        Word_v(ExtConfigMicroDma_c)                                      := choose(MicroDma_g, '1', '0');
        Word_v(ExtConfigLengthWidthHi_c downto ExtConfigLengthWidthLo_c) := toUslv(LengthWidth_g, 5);
        Word_v(ExtConfigAddrWidthHi_c downto ExtConfigAddrWidthLo_c)     := toUslv(AddrWidth_g, 7);
        return Word_v;
    end function;

    constant CoreConfig_c : std_logic_vector(31 downto 0) := coreConfig;
    constant Mm2sConfig_c : std_logic_vector(31 downto 0) := channelConfig(Mm2sMemWidth_g, Mm2sStreamWidth_g,
                                                                           Mm2sBurstBeats_g, Mm2sBufferBeats_g);
    constant S2mmConfig_c : std_logic_vector(31 downto 0) := channelConfig(S2mmMemWidth_g, S2mmStreamWidth_g,
                                                                           S2mmBurstBeats_g, S2mmBufferBeats_g);

    type TwoProcess_r is record
        RdData    : std_logic_vector(31 downto 0);
        RdCnt     : std_logic;                                -- The read data comes from the ECC monitor
        SecFlag   : std_logic;                                -- ECC_STATUS.Sec
        DedFlag   : std_logic;                                -- ECC_STATUS.Ded
        SecEna    : std_logic;                                -- ECC_ENABLE.Sec
        DedEna    : std_logic;                                -- ECC_ENABLE.Ded
        InjValid  : std_logic_vector(Buffers_c - 1 downto 0);
        InjDouble : std_logic;
        InjData   : std_logic;
        Irq       : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    -- ECC monitor
    signal Mon_Clr     : std_logic;
    signal Mon_RdChan  : std_logic_vector(3 downto 0);
    signal Mon_RdEna   : std_logic;
    signal Mon_RdClr   : std_logic;
    signal Mon_EvtSec  : std_logic;
    signal Mon_EvtDed  : std_logic;
    signal Mon_SecCnt  : std_logic_vector(CounterWidth_c - 1 downto 0);
    signal Mon_DedCnt  : std_logic_vector(CounterWidth_c - 1 downto 0);
    signal Mon_InValid : std_logic_vector(Buffers_c - 1 downto 0);

begin

    -- *** Assertions ***
    assert Mm2sBufferBeats_g < 2**20 and S2mmBufferBeats_g < 2**20
        report "odma_extension: BufferBeats_g must be below 2**20 (field width of EXT_MM2S_CONFIG.BufferBeats)"
        severity failure;

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable Addr_v : natural range 0 to 1023;
        variable Cnt_v  : boolean;
    begin
        v := r;

        -- Address of the register, bits 1 and 0 ignored
        Addr_v := to_integer(unsigned(Rb_Addr(9 downto 2))) * 4;
        Cnt_v  := Addr_v >= RegEccCountBase_c and Addr_v < RegEccCountBase_c + Buffers_c * RegEccCountStride_c;

        -- Defaults
        Mon_Clr    <= '0';
        Mon_RdEna  <= '0';
        Mon_RdClr  <= '0';
        Mon_RdChan <= Rb_Addr(5 downto 2);
        v.InjValid := (others => '0');

        -- Writes
        if Rb_Wr = '1' then
            if Addr_v = RegEccCtrl_c then
                -- ECC_CTRL.ClrAll
                Mon_Clr <= Rb_WrData(EccCtrlClrAll_c);
            elsif Addr_v = RegEccStatus_c then
                -- ECC_STATUS: write one to clear
                if Rb_WrData(EccStatusSec_c) = '1' then
                    v.SecFlag := '0';
                end if;
                if Rb_WrData(EccStatusDed_c) = '1' then
                    v.DedFlag := '0';
                end if;
            elsif Addr_v = RegEccEnable_c then
                v.SecEna := Rb_WrData(EccEnableSec_c);
                v.DedEna := Rb_WrData(EccEnableDed_c);
            elsif Addr_v = RegEccInject_c then
                -- ECC_INJECT: one strobe for the selected buffer
                if Rb_WrData(EccInjectInject_c) = '1' then

                    for i in 0 to Buffers_c - 1 loop
                        if i = fromUslv(Rb_WrData(EccInjectBufferHi_c downto EccInjectBufferLo_c)) then
                            v.InjValid(i) := BufferMask_c(i);
                        end if;
                    end loop;

                    v.InjDouble := Rb_WrData(EccInjectDouble_c);
                    v.InjData   := Rb_WrData(EccInjectData_c);
                end if;
            elsif Cnt_v then
                -- ECC_COUNT_n: any write clears both counters of buffer n
                Mon_RdEna <= '1';
                Mon_RdClr <= '1';
            end if;
        end if;

        -- Reads: the data is valid in the clock cycle after Rb_Rd
        v.RdCnt := '0';
        if Rb_Rd = '1' then
            v.RdData := (others => '0');
            if Addr_v = RegExtId_c then
                v.RdData := RegExtIdReset_c;
            elsif Addr_v = RegExtVersion_c then
                v.RdData := RegExtVersionReset_c;
            elsif Addr_v = RegExtConfig_c then
                v.RdData := CoreConfig_c;
            elsif Addr_v = RegExtMm2sConfig_c then
                v.RdData := Mm2sConfig_c;
            elsif Addr_v = RegExtS2mmConfig_c then
                v.RdData := S2mmConfig_c;
            elsif Addr_v = RegEccInfo_c then
                v.RdData := RegEccInfoReset_c;
            elsif Addr_v = RegEccStatus_c then
                v.RdData(EccStatusSec_c) := r.SecFlag;
                v.RdData(EccStatusDed_c) := r.DedFlag;
            elsif Addr_v = RegEccEnable_c then
                v.RdData(EccEnableSec_c) := r.SecEna;
                v.RdData(EccEnableDed_c) := r.DedEna;
            elsif Cnt_v then
                Mon_RdEna <= '1';
                v.RdCnt   := '1';
            end if;
        end if;

        -- ECC_STATUS: an event of the same cycle as a clear sets the flag
        if Mon_EvtSec = '1' then
            v.SecFlag := '1';
        end if;
        if Mon_EvtDed = '1' then
            v.DedFlag := '1';
        end if;

        -- Ecc_Irq, one clock cycle after the flags
        v.Irq := (r.SecFlag and r.SecEna) or (r.DedFlag and r.DedEna);

        r_next <= v;
    end process;

    -- Outputs
    Rb_RdData     <= (Mon_DedCnt & Mon_SecCnt) when r.RdCnt = '1' else r.RdData;
    EccInj_Valid  <= r.InjValid;
    EccInj_Double <= r.InjDouble;
    EccInj_Data   <= r.InjData;
    Ecc_Irq       <= r.Irq;

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.RdCnt     <= '0';
                r.SecFlag   <= '0';
                r.DedFlag   <= '0';
                r.SecEna    <= '0';
                r.DedEna    <= '0';
                r.InjValid  <= (others => '0');
                r.InjDouble <= '0';
                r.InjData   <= '0';
                r.Irq       <= '0';
            end if;
        end if;
    end process;

    -- *** ECC counters ***
    Mon_InValid <= BufferMask_c;

    i_monitor : entity olo.olo_ft_ecc_monitor
        generic map (
            Channels_g     => Buffers_c,
            CounterWidth_g => CounterWidth_c
        )
        port map (
            Clk        => Clk,
            Rst        => Rst,
            Clr        => Mon_Clr,
            In_EccSec  => Ecc_Sec,
            In_EccDed  => Ecc_Ded,
            In_Valid   => Mon_InValid,
            DedSticky  => open,
            Evt_Sec    => Mon_EvtSec,
            Evt_Ded    => Mon_EvtDed,
            Rd_Channel => Mon_RdChan,
            Rd_Ena     => Mon_RdEna,
            Rd_Clr     => Mon_RdClr,
            Rd_SecCnt  => Mon_SecCnt,
            Rd_DedCnt  => Mon_DedCnt,
            Rd_Valid   => open
        );

end architecture;
