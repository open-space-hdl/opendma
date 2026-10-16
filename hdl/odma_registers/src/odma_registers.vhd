---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Register interface of OpenDMA (RG-1 to RG-4): the registers of both channels in Direct Register
-- Mode behind the AXI4-Lite port, the transfer commands and results, interrupts, soft reset and the
-- extension window.
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
    use work.odma_pkg.all;
    use work.odma_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_registers is
    generic (
        IncludeSg_g       : boolean                 := false;
        IncludeMm2s_g     : boolean                 := true;
        IncludeS2mm_g     : boolean                 := true;
        StsCntrlStrm_g    : boolean                 := false;
        UseRxLength_g     : boolean                 := false;
        MicroDma_g        : boolean                 := false;
        LengthWidth_g     : positive range 8 to 26  := 14;
        AddrWidth_g       : positive range 32 to 64 := 32;
        Mm2sMemWidth_g    : positive                := 32;
        Mm2sStreamWidth_g : positive                := 32;
        Mm2sBurstBeats_g  : positive                := 16;
        Mm2sBufferBeats_g : positive                := 64;
        S2mmMemWidth_g    : positive                := 32;
        S2mmStreamWidth_g : positive                := 32;
        S2mmBurstBeats_g  : positive                := 16;
        S2mmBufferBeats_g : positive                := 64;
        ExtRegs_g         : boolean                 := true
    );
    port (
        -- Control Signals
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        CoreRst           : out   std_logic;
        -- AXI4-Lite register port
        S_AxiLite_ArAddr  : in    std_logic_vector(9 downto 0);
        S_AxiLite_ArValid : in    std_logic;
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(9 downto 0);
        S_AxiLite_AwValid : in    std_logic;
        S_AxiLite_AwReady : out   std_logic;
        S_AxiLite_WData   : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb   : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid  : in    std_logic;
        S_AxiLite_WReady  : out   std_logic;
        S_AxiLite_BResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid  : out   std_logic;
        S_AxiLite_BReady  : in    std_logic;
        S_AxiLite_RData   : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid  : out   std_logic;
        S_AxiLite_RReady  : in    std_logic;
        -- MM2S channel
        Mm2sCmd_Valid     : out   std_logic;
        Mm2sCmd_Ready     : in    std_logic                                    := '0';
        Mm2sCmd_Addr      : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        Mm2sCmd_Length    : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        Mm2sCmd_Sof       : out   std_logic;
        Mm2sCmd_Eof       : out   std_logic;
        Mm2sCmd_Keyhole   : out   std_logic;
        Mm2sRes_Valid     : in    std_logic                                    := '0';
        Mm2sRes_Ready     : out   std_logic;
        Mm2sRes_Bytes     : in    std_logic_vector(LengthWidth_g - 1 downto 0) := (others => '0');
        Mm2sRes_Eof       : in    std_logic                                    := '0';
        Mm2sRes_Err       : in    XferErr_t                                    := ErrNone_c;
        Mm2s_Run          : out   std_logic;
        Mm2s_Drain        : out   std_logic;
        Mm2s_Stopped      : in    std_logic                                    := '1';
        -- S2MM channel
        S2mmCmd_Valid     : out   std_logic;
        S2mmCmd_Ready     : in    std_logic                                    := '0';
        S2mmCmd_Addr      : out   std_logic_vector(AddrWidth_g - 1 downto 0);
        S2mmCmd_Length    : out   std_logic_vector(LengthWidth_g - 1 downto 0);
        S2mmCmd_Keyhole   : out   std_logic;
        S2mmRes_Valid     : in    std_logic                                    := '0';
        S2mmRes_Ready     : out   std_logic;
        S2mmRes_Bytes     : in    std_logic_vector(LengthWidth_g - 1 downto 0) := (others => '0');
        S2mmRes_Eof       : in    std_logic                                    := '0';
        S2mmRes_Err       : in    XferErr_t                                    := ErrNone_c;
        S2mm_Run          : out   std_logic;
        S2mm_Drain        : out   std_logic;
        S2mm_Stopped      : in    std_logic                                    := '1';
        -- Interrupts
        Mm2s_Irq          : out   std_logic;
        S2mm_Irq          : out   std_logic;
        Ecc_Irq           : out   std_logic;
        -- Reset outputs of the stream peers
        Mm2s_RstOut       : out   std_logic;
        S2mm_RstOut       : out   std_logic;
        -- FT buffers (index of the register map, section FT buffers)
        Ecc_Sec           : in    std_logic_vector(15 downto 0)                := (others => '0');
        Ecc_Ded           : in    std_logic_vector(15 downto 0)                := (others => '0');
        EccInj_Valid      : out   std_logic_vector(15 downto 0);
        EccInj_Double     : out   std_logic;
        EccInj_Data       : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of odma_registers is

    -- Channel indices
    constant Mm2s_c : natural := 0;
    constant S2mm_c : natural := 1;

    type Included_t is array (0 to 1) of boolean;

    constant Included_c : Included_t := (IncludeMm2s_g, IncludeS2mm_g);

    -- Registers of a channel; the fields have the same positions in both channels
    type Offsets_t is array (0 to 1) of natural;

    constant OfsDmacr_c   : Offsets_t := (RegMm2sDmacr_c, RegS2mmDmacr_c);
    constant OfsDmasr_c   : Offsets_t := (RegMm2sDmasr_c, RegS2mmDmasr_c);
    constant OfsAddr_c    : Offsets_t := (RegMm2sSa_c, RegS2mmDa_c);
    constant OfsAddrMsb_c : Offsets_t := (RegMm2sSaMsb_c, RegS2mmDaMsb_c);
    constant OfsLength_c  : Offsets_t := (RegMm2sLength_c, RegS2mmLength_c);

    -- Start of the extension window
    constant ExtBase_c : natural := RegExtId_c;

    -- DMACR.IRQThreshold after the reset
    constant ThresholdReset_c : std_logic_vector(7 downto 0) :=
        RegMm2sDmacrReset_c(Mm2sDmacrIrqThresholdHi_c downto Mm2sDmacrIrqThresholdLo_c);

    type ChannelFsm_t is (Halted_s, Started_s, Busy_s, Done_s, Stopping_s);

    type Channel_r is record
        State        : ChannelFsm_t;
        -- DMACR
        Rs           : std_logic;
        Keyhole      : std_logic;
        CyclicBd     : std_logic;
        IocIrqEn     : std_logic;
        DlyIrqEn     : std_logic;
        ErrIrqEn     : std_logic;
        IrqThreshold : std_logic_vector(7 downto 0);
        IrqDelay     : std_logic_vector(7 downto 0);
        -- DMASR error flags
        IntErr       : std_logic;
        SlvErr       : std_logic;
        DecErr       : std_logic;
        -- Buffer address and length
        Addr         : std_logic_vector(AddrWidth_g - 1 downto 0);
        Length       : std_logic_vector(LengthWidth_g - 1 downto 0);
        -- Transfer
        HaltPend     : std_logic;                                  -- DMACR.RS = 0 during the transfer
        Run          : std_logic;
        CmdValid     : std_logic;
        CmdAddr      : std_logic_vector(AddrWidth_g - 1 downto 0);
    end record;

    type Channel_a is array (0 to 1) of Channel_r;

    type TwoProcess_r is record
        Ch      : Channel_a;
        RdValid : std_logic;
        RdData  : std_logic_vector(31 downto 0);
        RdExt   : std_logic;                                       -- The read data comes from the extension window
    end record;

    signal r, r_next : TwoProcess_r;

    -- Channel ports indexed by channel
    type Bytes_a is array (0 to 1) of std_logic_vector(LengthWidth_g - 1 downto 0);
    type Err_a is array (0 to 1) of XferErr_t;

    signal Cmd_Ready : std_logic_vector(0 to 1);
    signal Res_Valid : std_logic_vector(0 to 1);
    signal Res_Bytes : Bytes_a;
    signal Res_Eof   : std_logic_vector(0 to 1);
    signal Res_Err   : Err_a;
    signal Stopped   : std_logic_vector(0 to 1);
    signal Included  : std_logic_vector(0 to 1);

    -- Register bus of the AXI4-Lite slave
    signal Rb_Addr    : std_logic_vector(9 downto 0);
    signal Rb_Wr      : std_logic;
    signal Rb_WrData  : std_logic_vector(31 downto 0);
    signal Rb_Rd      : std_logic;
    signal Rb_RdData  : std_logic_vector(31 downto 0);
    signal Rb_RdValid : std_logic;

    -- Interrupt controllers
    signal IocEvt  : std_logic_vector(0 to 1);
    signal ErrEvt  : std_logic_vector(0 to 1);
    signal IocClr  : std_logic_vector(0 to 1);
    signal ErrClr  : std_logic_vector(0 to 1);
    signal IocFlag : std_logic_vector(0 to 1);
    signal ErrFlag : std_logic_vector(0 to 1);
    signal IocEna  : std_logic_vector(0 to 1);
    signal ErrEna  : std_logic_vector(0 to 1);
    signal Irq     : std_logic_vector(0 to 1);

    -- Reset controller
    signal SoftStart : std_logic;
    signal SoftBusy  : std_logic;
    signal CoreRst_i : std_logic;
    signal RstOut    : std_logic;

    -- Extension window
    signal Ext_Wr     : std_logic;
    signal Ext_RdData : std_logic_vector(31 downto 0);

begin

    -- *** Assertions ***
    assert not IncludeSg_g
        report "odma_registers: IncludeSg_g must be false, Scatter/Gather Mode is not implemented"
        severity failure;

    -- *** Channel ports ***
    Included(Mm2s_c)  <= choose(IncludeMm2s_g, '1', '0');
    Included(S2mm_c)  <= choose(IncludeS2mm_g, '1', '0');
    Cmd_Ready(Mm2s_c) <= Mm2sCmd_Ready;
    Cmd_Ready(S2mm_c) <= S2mmCmd_Ready;
    Res_Valid(Mm2s_c) <= Mm2sRes_Valid;
    Res_Valid(S2mm_c) <= S2mmRes_Valid;
    Res_Bytes(Mm2s_c) <= Mm2sRes_Bytes;
    Res_Bytes(S2mm_c) <= S2mmRes_Bytes;
    Res_Eof(Mm2s_c)   <= Mm2sRes_Eof;
    Res_Eof(S2mm_c)   <= S2mmRes_Eof;
    Res_Err(Mm2s_c)   <= Mm2sRes_Err;
    Res_Err(S2mm_c)   <= S2mmRes_Err;
    -- A channel that is not included is always stopped
    Stopped(Mm2s_c) <= Mm2s_Stopped or not Included(Mm2s_c);
    Stopped(S2mm_c) <= S2mm_Stopped or not Included(S2mm_c);

    -- *** Combinatorial Process ***
    p_comb : process (all) is
        variable v        : TwoProcess_r;
        variable Addr_v   : natural range 0 to 1023;
        variable Wr_v     : boolean;
        variable RsWr_v   : boolean;
        variable LenWr_v  : boolean;
        variable Len_v    : std_logic_vector(LengthWidth_g - 1 downto 0);
        variable Halt_v   : boolean;
        variable Errors_v : std_logic;
        variable RdData_v : std_logic_vector(31 downto 0);
    begin
        v := r;

        -- Address of the register, bits 1 and 0 ignored
        Addr_v := to_integer(unsigned(Rb_Addr(9 downto 2))) * 4;
        -- Register writes have no effect during a soft reset
        Wr_v := Rb_Wr = '1' and SoftBusy = '0';

        -- Defaults
        SoftStart <= '0';
        IocEvt    <= (others => '0');
        ErrEvt    <= (others => '0');
        IocClr    <= (others => '0');
        ErrClr    <= (others => '0');
        RdData_v  := (others => '0');

        for ch in 0 to 1 loop
            if Included_c(ch) then

                -- *** Register writes ***
                RsWr_v  := false;
                LenWr_v := false;
                Halt_v  := false;
                Len_v   := Rb_WrData(LengthWidth_g - 1 downto 0);

                if Wr_v and Addr_v = OfsDmacr_c(ch) then
                    if Rb_WrData(Mm2sDmacrReset_c) = '1' then
                        -- DMACR.Reset: soft reset of the whole core; the other bits of the write are not taken
                        SoftStart <= '1';
                    else
                        v.Ch(ch).Keyhole  := Rb_WrData(Mm2sDmacrKeyhole_c);
                        v.Ch(ch).CyclicBd := Rb_WrData(Mm2sDmacrCyclicBd_c);
                        v.Ch(ch).IocIrqEn := Rb_WrData(Mm2sDmacrIocIrqEn_c);
                        v.Ch(ch).DlyIrqEn := Rb_WrData(Mm2sDmacrDlyIrqEn_c);
                        v.Ch(ch).ErrIrqEn := Rb_WrData(Mm2sDmacrErrIrqEn_c);
                        v.Ch(ch).IrqDelay := Rb_WrData(Mm2sDmacrIrqDelayHi_c downto Mm2sDmacrIrqDelayLo_c);
                        -- DMACR.IRQThreshold: a write of 0 leaves the field unchanged
                        if unsigned(Rb_WrData(Mm2sDmacrIrqThresholdHi_c downto Mm2sDmacrIrqThresholdLo_c)) /= 0 then
                            v.Ch(ch).IrqThreshold := Rb_WrData(Mm2sDmacrIrqThresholdHi_c downto Mm2sDmacrIrqThresholdLo_c);
                        end if;
                        -- DMACR.RS: 1 is taken by the state machine, 0 always
                        RsWr_v := Rb_WrData(Mm2sDmacrRs_c) = '1';
                        Halt_v := Rb_WrData(Mm2sDmacrRs_c) = '0';
                        if Halt_v then
                            v.Ch(ch).Rs := '0';
                        end if;
                    end if;
                end if;

                -- DMASR.IOC_Irq, DMASR.Err_Irq: write one to clear
                if Wr_v and Addr_v = OfsDmasr_c(ch) then
                    IocClr(ch) <= Rb_WrData(Mm2sDmasrIocIrq_c);
                    ErrClr(ch) <= Rb_WrData(Mm2sDmasrErrIrq_c);
                end if;

                -- MM2S_SA, MM2S_SA_MSB, S2MM_DA, S2MM_DA_MSB: bits at or above AddrWidth_g do not exist
                if Wr_v and Addr_v = OfsAddr_c(ch) then
                    v.Ch(ch).Addr(31 downto 0) := Rb_WrData;
                end if;
                if Wr_v and Addr_v = OfsAddrMsb_c(ch) then

                    for i in 32 to AddrWidth_g - 1 loop
                        v.Ch(ch).Addr(i) := Rb_WrData(i - 32);
                    end loop;

                end if;

                -- MM2S_LENGTH, S2MM_LENGTH: a write of 0 has no effect
                if Wr_v and Addr_v = OfsLength_c(ch) and unsigned(Len_v) /= 0 then
                    LenWr_v := true;
                end if;

                -- *** Channel state machine (DR mode) ***
                Errors_v := r.Ch(ch).IntErr or r.Ch(ch).SlvErr or r.Ch(ch).DecErr;

                case r.Ch(ch).State is

                    when Halted_s =>
                        -- DMACR.RS = 1 starts the channel unless an error flag is set
                        if RsWr_v and Errors_v = '0' then
                            v.Ch(ch).Rs    := '1';
                            v.Ch(ch).Run   := '1';
                            v.Ch(ch).State := Started_s;
                        end if;
                        -- A length written while halted is stored without a transfer
                        if LenWr_v then
                            v.Ch(ch).Length := Len_v;
                        end if;

                    when Started_s | Done_s =>
                        if Halt_v then
                            v.Ch(ch).Run   := '0';
                            v.Ch(ch).State := Stopping_s;
                        elsif LenWr_v then
                            -- One transfer command with the address registers of this cycle
                            v.Ch(ch).Length   := Len_v;
                            v.Ch(ch).CmdAddr  := r.Ch(ch).Addr;
                            v.Ch(ch).CmdValid := '1';
                            v.Ch(ch).State    := Busy_s;
                        end if;

                    when Busy_s =>
                        -- Length writes have no effect while the transfer is in progress
                        if Halt_v then
                            v.Ch(ch).HaltPend := '1';
                        end if;

                        -- Command handshake
                        if r.Ch(ch).CmdValid = '1' and Cmd_Ready(ch) = '1' then
                            v.Ch(ch).CmdValid := '0';
                        end if;

                        -- Result, always accepted
                        if Res_Valid(ch) = '1' then
                            if Res_Err(ch) /= ErrNone_c then
                                -- DMASR.DMAIntErr, DMASR.DMASlvErr, DMASR.DMADecErr; S2MM: DMAIntErr also
                                -- with the slave and the decode error
                                if Res_Err(ch) = ErrInt_c or ch = S2mm_c then
                                    v.Ch(ch).IntErr := '1';
                                end if;
                                if Res_Err(ch) = ErrSlv_c then
                                    v.Ch(ch).SlvErr := '1';
                                end if;
                                if Res_Err(ch) = ErrDec_c then
                                    v.Ch(ch).DecErr := '1';
                                end if;
                                ErrEvt(ch)        <= '1';
                                v.Ch(ch).Rs       := '0';
                                v.Ch(ch).Run      := '0';
                                v.Ch(ch).HaltPend := '0';
                                v.Ch(ch).State    := Stopping_s;
                            else
                                -- The transfer completed: DMASR.IOC_Irq; S2MM_LENGTH reads the bytes received
                                if Res_Eof(ch) = '1' then
                                    IocEvt(ch) <= '1';
                                    if ch = S2mm_c then
                                        v.Ch(ch).Length := Res_Bytes(ch);
                                    end if;
                                end if;
                                if v.Ch(ch).HaltPend = '1' then
                                    v.Ch(ch).State := Stopping_s;
                                else
                                    v.Ch(ch).State := Done_s;
                                end if;
                                v.Ch(ch).HaltPend := '0';
                            end if;
                        end if;

                        -- A halted transfer: Run falls once its command is accepted
                        if v.Ch(ch).HaltPend = '1' and v.Ch(ch).CmdValid = '0' then
                            v.Ch(ch).Run := '0';
                        end if;

                    when Stopping_s =>
                        if LenWr_v then
                            v.Ch(ch).Length := Len_v;
                        end if;
                        if Stopped(ch) = '1' then
                            v.Ch(ch).State := Halted_s;
                        end if;

                    -- coverage off
                    when others =>
                        -- Unreachable, safe recovery
                        v.Ch(ch).Run      := '0';
                        v.Ch(ch).CmdValid := '0';
                        v.Ch(ch).HaltPend := '0';
                        v.Ch(ch).State    := Halted_s;
                    -- coverage on

                end case;

                -- *** Read data ***
                if Addr_v = OfsDmacr_c(ch) then
                    RdData_v(Mm2sDmacrRs_c)                                              := r.Ch(ch).Rs;
                    RdData_v(Mm2sDmacrReserved_c)                                        := '1';
                    RdData_v(Mm2sDmacrReset_c)                                           := SoftBusy;
                    RdData_v(Mm2sDmacrKeyhole_c)                                         := r.Ch(ch).Keyhole;
                    RdData_v(Mm2sDmacrCyclicBd_c)                                        := r.Ch(ch).CyclicBd;
                    RdData_v(Mm2sDmacrIocIrqEn_c)                                        := r.Ch(ch).IocIrqEn;
                    RdData_v(Mm2sDmacrDlyIrqEn_c)                                        := r.Ch(ch).DlyIrqEn;
                    RdData_v(Mm2sDmacrErrIrqEn_c)                                        := r.Ch(ch).ErrIrqEn;
                    RdData_v(Mm2sDmacrIrqThresholdHi_c downto Mm2sDmacrIrqThresholdLo_c) := r.Ch(ch).IrqThreshold;
                    RdData_v(Mm2sDmacrIrqDelayHi_c downto Mm2sDmacrIrqDelayLo_c)         := r.Ch(ch).IrqDelay;
                elsif Addr_v = OfsDmasr_c(ch) then
                    RdData_v(Mm2sDmasrHalted_c)                                                := choose(r.Ch(ch).State = Halted_s, '1', '0');
                    RdData_v(Mm2sDmasrIdle_c)                                                  := choose(r.Ch(ch).State = Done_s, '1', '0');
                    RdData_v(Mm2sDmasrSgIncld_c)                                               := choose(IncludeSg_g, '1', '0');
                    RdData_v(Mm2sDmasrDmaIntErr_c)                                             := r.Ch(ch).IntErr;
                    RdData_v(Mm2sDmasrDmaSlvErr_c)                                             := r.Ch(ch).SlvErr;
                    RdData_v(Mm2sDmasrDmaDecErr_c)                                             := r.Ch(ch).DecErr;
                    RdData_v(Mm2sDmasrIocIrq_c)                                                := IocFlag(ch);
                    RdData_v(Mm2sDmasrErrIrq_c)                                                := ErrFlag(ch);
                    RdData_v(Mm2sDmasrIrqThresholdStsHi_c downto Mm2sDmasrIrqThresholdStsLo_c) := r.Ch(ch).IrqThreshold;
                elsif Addr_v = OfsAddr_c(ch) then
                    RdData_v := r.Ch(ch).Addr(31 downto 0);
                elsif Addr_v = OfsAddrMsb_c(ch) then

                    for i in 32 to AddrWidth_g - 1 loop
                        RdData_v(i - 32) := r.Ch(ch).Addr(i);
                    end loop;

                elsif Addr_v = OfsLength_c(ch) then
                    RdData_v(LengthWidth_g - 1 downto 0) := r.Ch(ch).Length;
                end if;

            end if;
        end loop;

        -- Reads: the data is valid in the clock cycle after Rb_Rd
        v.RdValid := Rb_Rd;
        if Rb_Rd = '1' then
            v.RdData := RdData_v;
            v.RdExt  := choose(ExtRegs_g and Addr_v >= ExtBase_c, '1', '0');
        end if;

        r_next <= v;
    end process;

    -- *** Outputs ***
    Rb_RdData  <= Ext_RdData when r.RdExt = '1' else r.RdData;
    Rb_RdValid <= r.RdValid;

    Mm2sCmd_Valid   <= r.Ch(Mm2s_c).CmdValid;
    Mm2sCmd_Addr    <= r.Ch(Mm2s_c).CmdAddr;
    Mm2sCmd_Length  <= r.Ch(Mm2s_c).Length;
    Mm2sCmd_Sof     <= '1';
    Mm2sCmd_Eof     <= '1';
    Mm2sCmd_Keyhole <= '0';               -- Interpretation I1: DMACR.Keyhole has no function in DR mode
    Mm2sRes_Ready   <= '1';
    Mm2s_Run        <= r.Ch(Mm2s_c).Run;
    Mm2s_Drain      <= SoftBusy and Included(Mm2s_c);

    S2mmCmd_Valid   <= r.Ch(S2mm_c).CmdValid;
    S2mmCmd_Addr    <= r.Ch(S2mm_c).CmdAddr;
    S2mmCmd_Length  <= r.Ch(S2mm_c).Length;
    S2mmCmd_Keyhole <= '0';
    S2mmRes_Ready   <= '1';
    S2mm_Run        <= r.Ch(S2mm_c).Run;
    S2mm_Drain      <= SoftBusy and Included(S2mm_c);

    Mm2s_Irq    <= Irq(Mm2s_c);
    S2mm_Irq    <= Irq(S2mm_c);
    Mm2s_RstOut <= RstOut;
    S2mm_RstOut <= RstOut;
    CoreRst     <= CoreRst_i;

    -- *** Sequential Process ***
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if CoreRst_i = '1' then

                for ch in 0 to 1 loop
                    r.Ch(ch).State        <= Halted_s;
                    r.Ch(ch).Rs           <= '0';
                    r.Ch(ch).Keyhole      <= '0';
                    r.Ch(ch).CyclicBd     <= '0';
                    r.Ch(ch).IocIrqEn     <= '0';
                    r.Ch(ch).DlyIrqEn     <= '0';
                    r.Ch(ch).ErrIrqEn     <= '0';
                    r.Ch(ch).IrqThreshold <= ThresholdReset_c;
                    r.Ch(ch).IrqDelay     <= (others => '0');
                    r.Ch(ch).IntErr       <= '0';
                    r.Ch(ch).SlvErr       <= '0';
                    r.Ch(ch).DecErr       <= '0';
                    r.Ch(ch).Addr         <= (others => '0');
                    r.Ch(ch).Length       <= (others => '0');
                    r.Ch(ch).HaltPend     <= '0';
                    r.Ch(ch).Run          <= '0';
                    r.Ch(ch).CmdValid     <= '0';
                end loop;

            end if;
            -- The read path answers during a soft reset
            if Rst = '1' then
                r.RdValid <= '0';
            end if;
        end if;
    end process;

    -- *** AXI4-Lite slave (reset by Rst only, so that no access is lost in a soft reset) ***
    i_axi : entity olo.olo_axi_lite_slave
        generic map (
            AxiAddrWidth_g => 10,
            AxiDataWidth_g => 32
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
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
            Rb_Addr           => Rb_Addr,
            Rb_Wr             => Rb_Wr,
            Rb_ByteEna        => open,
            Rb_WrData         => Rb_WrData,
            Rb_Rd             => Rb_Rd,
            Rb_RdData         => Rb_RdData,
            Rb_RdValid        => Rb_RdValid
        );

    -- *** Interrupt controllers (RG-2) ***
    g_irq : for ch in 0 to 1 generate
        IocEna(ch) <= r.Ch(ch).IocIrqEn;
        ErrEna(ch) <= r.Ch(ch).ErrIrqEn;

        i_irq : entity work.odma_interrupt
            port map (
                Clk      => Clk,
                Rst      => CoreRst_i,
                Ena_Ioc  => IocEna(ch),
                Ena_Err  => ErrEna(ch),
                Evt_Ioc  => IocEvt(ch),
                Evt_Err  => ErrEvt(ch),
                Clr_Ioc  => IocClr(ch),
                Clr_Err  => ErrClr(ch),
                Flag_Ioc => IocFlag(ch),
                Flag_Err => ErrFlag(ch),
                Irq      => Irq(ch)
            );

    end generate;

    -- *** Reset controller (RG-3) ***
    i_reset : entity work.odma_soft_reset
        port map (
            Clk          => Clk,
            Rst          => Rst,
            Start        => SoftStart,
            Mm2s_Stopped => Stopped(Mm2s_c),
            S2mm_Stopped => Stopped(S2mm_c),
            Busy         => SoftBusy,
            CoreRst      => CoreRst_i,
            RstOut       => RstOut
        );

    -- *** Extension window (RG-4) ***
    g_ext : if ExtRegs_g generate
        Ext_Wr <= Rb_Wr and not SoftBusy;

        i_ext : entity work.odma_extension
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
                S2mmBufferBeats_g => S2mmBufferBeats_g
            )
            port map (
                Clk           => Clk,
                Rst           => CoreRst_i,
                Rb_Addr       => Rb_Addr,
                Rb_Wr         => Ext_Wr,
                Rb_WrData     => Rb_WrData,
                Rb_Rd         => Rb_Rd,
                Rb_RdData     => Ext_RdData,
                Ecc_Sec       => Ecc_Sec,
                Ecc_Ded       => Ecc_Ded,
                EccInj_Valid  => EccInj_Valid,
                EccInj_Double => EccInj_Double,
                EccInj_Data   => EccInj_Data,
                Ecc_Irq       => Ecc_Irq
            );

    end generate;

    g_no_ext : if not ExtRegs_g generate
        Ext_RdData    <= (others => '0');
        EccInj_Valid  <= (others => '0');
        EccInj_Double <= '0';
        EccInj_Data   <= '0';
        Ecc_Irq       <= '0';
    end generate;

end architecture;
