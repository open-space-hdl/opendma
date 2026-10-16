---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- AXI memory model: behavioural AXI4 slave with INCR and FIXED bursts, write strobes, addresses of
-- up to 64 bits and up to 16 queued bursts per direction. Memory, error ranges, write window, burst
-- limit, backpressure, latency and statistics are those of instance Index_g of
-- odma_tb_memvar_pkg.Mem_v. Protocol violations raise UVVM error alerts.
--
-- What this model does not check or reproduce: AXI IDs, reordering and interleaving (no ID
-- signals); AxCache, AxProt, AxLock and AxQos (not connected); exclusive accesses; narrow transfers
-- (reported and then treated as full-width beats); write data before its address (data is taken for
-- an accepted AW burst only, which AXI allows a slave to do); the timing of a real interconnect
-- beyond the random backpressure and the fixed latency.
--
-- Documentation: hdl/odma_pkg/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library work;
    use work.odma_tb_memvar_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity odma_tb_axi_ram is
    generic (
        Index_g     : natural;
        AddrWidth_g : positive range 1 to 64 := 32;
        DataWidth_g : positive               := 32
    );
    port (
        Clk     : in    std_logic;
        Rst     : in    std_logic := '0'; -- Drops all outstanding transactions
        AwAddr  : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        AwLen   : in    std_logic_vector(7 downto 0);
        AwSize  : in    std_logic_vector(2 downto 0);
        AwBurst : in    std_logic_vector(1 downto 0);
        AwValid : in    std_logic;
        AwReady : out   std_logic;
        WData   : in    std_logic_vector(DataWidth_g - 1 downto 0);
        WStrb   : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        WLast   : in    std_logic;
        WValid  : in    std_logic;
        WReady  : out   std_logic;
        BResp   : out   std_logic_vector(1 downto 0);
        BValid  : out   std_logic;
        BReady  : in    std_logic;
        ArAddr  : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        ArLen   : in    std_logic_vector(7 downto 0);
        ArSize  : in    std_logic_vector(2 downto 0);
        ArBurst : in    std_logic_vector(1 downto 0);
        ArValid : in    std_logic;
        ArReady : out   std_logic;
        RData   : out   std_logic_vector(DataWidth_g - 1 downto 0);
        RResp   : out   std_logic_vector(1 downto 0);
        RLast   : out   std_logic;
        RValid  : out   std_logic;
        RReady  : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of odma_tb_axi_ram is

    constant Bytes_c : positive := DataWidth_g / 8;
    constant Size_c  : natural  := integer(log2(real(Bytes_c)));
    constant Queue_c : positive := 16;
    constant Scope_c : string   := "odma_tb_axi_ram(" & integer'image(Index_g) & ")";

    subtype Addr_t is unsigned(63 downto 0);

    type AddrQueue_t is array (0 to Queue_c - 1) of Addr_t;
    type LenQueue_t is array (0 to Queue_c - 1) of natural range 0 to 255;
    type FlagQueue_t is array (0 to Queue_c - 1) of boolean;
    type RespQueue_t is array (0 to Queue_c - 1) of std_logic_vector(1 downto 0);
    type CycleQueue_t is array (0 to Queue_c - 1) of natural;

    signal AwReady_i : std_logic := '0';
    signal WReady_i  : std_logic := '0';
    signal ArReady_i : std_logic := '0';
    signal RValid_i  : std_logic := '0';
    signal BValid_i  : std_logic := '0';

    -- Address of the first byte of the aligned beat containing addr
    function aligned (addr : Addr_t) return Addr_t is
        variable A_v : Addr_t := addr;
    begin
        if Size_c > 0 then
            A_v(Size_c - 1 downto 0) := (others => '0');
        end if;
        return A_v;
    end function;

    -- Worse of two responses: DECERR over SLVERR over OKAY
    function worse (
        a : std_logic_vector(1 downto 0);
        b : std_logic_vector(1 downto 0)) return std_logic_vector is
    begin
        if a = "11" or b = "11" then
            return "11";
        elsif a = "10" or b = "10" then
            return "10";
        end if;
        return "00";
    end function;

    function hex (a : Addr_t) return string is
    begin
        return to_string(std_logic_vector(a), HEX, AS_IS, INCL_RADIX);
    end function;

    -- Checks of an accepted address: burst type, size, length, 4 KB boundary
    procedure checkAddress (
        dir   : string;
        addr  : Addr_t;
        len   : natural;
        size  : std_logic_vector(2 downto 0);
        burst : std_logic_vector(1 downto 0)) is
        constant Last_c : Addr_t := aligned(addr) + to_unsigned((len + 1) * Bytes_c - 1, 64);
    begin
        if burst = "10" or burst = "11" then
            alert(ERROR, dir & " burst type " & to_string(burst) & " at " & hex(addr) & ": only INCR and FIXED", Scope_c);
        end if;
        if to_integer(unsigned(size)) /= Size_c then
            alert(ERROR, dir & " beat size " & to_string(to_integer(unsigned(size))) & " at " & hex(addr) &
                  ": only full-width beats", Scope_c);
        end if;
        if len + 1 > Mem_v.getMaxBeats(Index_g) then
            alert(ERROR, dir & " burst of " & to_string(len + 1) & " beats at " & hex(addr) & " above the maximum of " &
                  to_string(Mem_v.getMaxBeats(Index_g)), Scope_c);
        end if;
        if burst = "00" and len + 1 > 16 then
            alert(ERROR, dir & " FIXED burst of " & to_string(len + 1) & " beats at " & hex(addr), Scope_c);
        end if;
        if burst = "01" and Last_c(63 downto 12) /= addr(63 downto 12) then
            alert(ERROR, dir & " burst from " & hex(addr) & " to " & hex(Last_c) & " crosses a 4 KB boundary", Scope_c);
        end if;
    end procedure;

begin

    AwReady <= AwReady_i;
    WReady  <= WReady_i;
    ArReady <= ArReady_i;
    RValid  <= RValid_i;
    BValid  <= BValid_i;

    -- Write channels: AW queue, W beats of the oldest burst, B queue
    p_write : process (Clk) is
        variable AwQ_v     : AddrQueue_t;
        variable AwL_v     : LenQueue_t;
        variable AwF_v     : FlagQueue_t; -- FIXED burst
        variable AwHead_v  : natural                      := 0;
        variable AwCnt_v   : natural                      := 0;
        variable Beat_v    : natural                      := 0;
        variable Resp_v    : std_logic_vector(1 downto 0) := "00";
        variable BQ_v      : RespQueue_t;
        variable BT_v      : CycleQueue_t;
        variable BHead_v   : natural                      := 0;
        variable BCnt_v    : natural                      := 0;
        variable Out_v     : natural                      := 0;
        variable Cyc_v     : natural                      := 0;
        variable Seed1_v   : positive                     := 11 + Index_g;
        variable Seed2_v   : positive                     := 23;
        variable Rnd_v     : real;
        variable Base_v    : Addr_t;
        variable A_v       : Addr_t;
        variable BeatR_v   : std_logic_vector(1 downto 0);
        variable Outside_v : boolean;

        impure function stall return boolean is
        begin
            uniform(Seed1_v, Seed2_v, Rnd_v);
            return Rnd_v * 100.0 < real(Mem_v.getStall(Index_g));
        end function;

    -- Comment for the style checker: functions above, statements below
    begin
        if rising_edge(Clk) then
            Cyc_v := Cyc_v + 1;
            -- AW handshake
            if AwValid = '1' and AwReady_i = '1' then
                A_v                                     := resize(unsigned(AwAddr), 64);
                AwQ_v((AwHead_v + AwCnt_v) mod Queue_c) := A_v;
                AwL_v((AwHead_v + AwCnt_v) mod Queue_c) := to_integer(unsigned(AwLen));
                AwF_v((AwHead_v + AwCnt_v) mod Queue_c) := AwBurst = "00";
                checkAddress("write", A_v, to_integer(unsigned(AwLen)), AwSize, AwBurst);
                AwCnt_v                                 := AwCnt_v + 1;
                Out_v                                   := Out_v + 1;
                Mem_v.noteBurst(Index_g);
                Mem_v.noteOutstanding(Index_g, true, Out_v);
            end if;

            -- W handshake: a beat with a strobed byte in an error range writes none of its bytes
            if WValid = '1' and WReady_i = '1' then
                if AwF_v(AwHead_v) then
                    Base_v := aligned(AwQ_v(AwHead_v));
                else
                    Base_v := aligned(AwQ_v(AwHead_v)) + to_unsigned(Beat_v * Bytes_c, 64);
                end if;
                BeatR_v   := "00";
                Outside_v := false;

                for i in 0 to Bytes_c - 1 loop
                    if WStrb(i) = '1' then
                        BeatR_v := worse(BeatR_v, Mem_v.errorResp(Index_g, Base_v + i, true));
                        if not Mem_v.inWindow(Index_g, Base_v + i) then
                            Outside_v := true;
                        end if;
                    end if;
                end loop;

                if Outside_v then
                    alert(ERROR, "strobed write outside the window in the beat at " & hex(Base_v), Scope_c);
                end if;
                if BeatR_v = "00" then

                    for i in 0 to Bytes_c - 1 loop
                        if WStrb(i) = '1' then
                            Mem_v.write8(Index_g, Base_v + i, WData(8 * i + 7 downto 8 * i));
                            Mem_v.noteWrite(Index_g, Base_v + i);
                        end if;
                    end loop;

                end if;
                Resp_v := worse(Resp_v, BeatR_v);

                if Beat_v = AwL_v(AwHead_v) then
                    if WLast /= '1' then
                        alert(ERROR, "WLast missing on the last beat of the burst at " & hex(AwQ_v(AwHead_v)), Scope_c);
                    end if;
                    BQ_v((BHead_v + BCnt_v) mod Queue_c) := Resp_v;
                    BT_v((BHead_v + BCnt_v) mod Queue_c) := Cyc_v + Mem_v.getLatency(Index_g);
                    BCnt_v                               := BCnt_v + 1;
                    Resp_v                               := "00";
                    Beat_v                               := 0;
                    AwHead_v                             := (AwHead_v + 1) mod Queue_c;
                    AwCnt_v                              := AwCnt_v - 1;
                else
                    if WLast = '1' then
                        alert(ERROR, "WLast before the last beat of the burst at " & hex(AwQ_v(AwHead_v)), Scope_c);
                    end if;
                    Beat_v := Beat_v + 1;
                end if;
            end if;

            -- B handshake
            if BValid_i = '1' and BReady = '1' then
                BHead_v := (BHead_v + 1) mod Queue_c;
                BCnt_v  := BCnt_v - 1;
                Out_v   := Out_v - 1;
            end if;

            AwReady_i <= '1' when AwCnt_v < Queue_c - 1 and not stall else '0';
            WReady_i  <= '1' when AwCnt_v > 0 and not stall else '0';
            if BCnt_v > 0 and Cyc_v >= BT_v(BHead_v) then
                BResp    <= BQ_v(BHead_v);
                BValid_i <= '1';
            else
                BResp    <= "00";
                BValid_i <= '0';
            end if;

            if Rst = '1' then
                AwHead_v  := 0;
                AwCnt_v   := 0;
                Beat_v    := 0;
                Resp_v    := "00";
                BHead_v   := 0;
                BCnt_v    := 0;
                Out_v     := 0;
                AwReady_i <= '0';
                WReady_i  <= '0';
                BValid_i  <= '0';
            end if;
        end if;
    end process;

    -- Read channels: AR queue, R beats of the oldest burst
    p_read : process (Clk) is
        variable ArQ_v    : AddrQueue_t;
        variable ArL_v    : LenQueue_t;
        variable ArF_v    : FlagQueue_t;
        variable ArT_v    : CycleQueue_t;
        variable ArHead_v : natural  := 0;
        variable ArCnt_v  : natural  := 0;
        variable Beat_v   : natural  := 0;
        variable Cyc_v    : natural  := 0;
        variable Seed1_v  : positive := 37 + Index_g;
        variable Seed2_v  : positive := 41;
        variable Rnd_v    : real;
        variable Base_v   : Addr_t;
        variable A_v      : Addr_t;
        variable Resp_v   : std_logic_vector(1 downto 0);

        impure function stall return boolean is
        begin
            uniform(Seed1_v, Seed2_v, Rnd_v);
            return Rnd_v * 100.0 < real(Mem_v.getStall(Index_g));
        end function;

    -- Comment for the style checker: functions above, statements below
    begin
        if rising_edge(Clk) then
            Cyc_v := Cyc_v + 1;
            if ArValid = '1' and ArReady_i = '1' then
                A_v                                     := resize(unsigned(ArAddr), 64);
                ArQ_v((ArHead_v + ArCnt_v) mod Queue_c) := A_v;
                ArL_v((ArHead_v + ArCnt_v) mod Queue_c) := to_integer(unsigned(ArLen));
                ArF_v((ArHead_v + ArCnt_v) mod Queue_c) := ArBurst = "00";
                ArT_v((ArHead_v + ArCnt_v) mod Queue_c) := Cyc_v + Mem_v.getLatency(Index_g);
                checkAddress("read", A_v, to_integer(unsigned(ArLen)), ArSize, ArBurst);
                ArCnt_v                                 := ArCnt_v + 1;
                Mem_v.noteBurst(Index_g);
                Mem_v.noteOutstanding(Index_g, false, ArCnt_v);
            end if;

            -- Beat taken
            if RValid_i = '1' and RReady = '1' then
                Mem_v.noteRead(Index_g);
                if Beat_v = ArL_v(ArHead_v) then
                    Beat_v   := 0;
                    ArHead_v := (ArHead_v + 1) mod Queue_c;
                    ArCnt_v  := ArCnt_v - 1;
                else
                    Beat_v := Beat_v + 1;
                end if;
            end if;

            ArReady_i <= '1' when ArCnt_v < Queue_c - 1 and not stall else '0';

            -- Next beat (a presented beat stays until it is taken); the first beat of a burst waits for the latency
            if ArCnt_v > 0 and (RValid_i = '0' or RReady = '1') then
                if stall or (Beat_v = 0 and Cyc_v < ArT_v(ArHead_v)) then
                    RValid_i <= '0';
                else
                    if ArF_v(ArHead_v) then
                        Base_v := aligned(ArQ_v(ArHead_v));
                    else
                        Base_v := aligned(ArQ_v(ArHead_v)) + to_unsigned(Beat_v * Bytes_c, 64);
                    end if;
                    Resp_v := "00";

                    for i in 0 to Bytes_c - 1 loop
                        RData(8 * i + 7 downto 8 * i) <= Mem_v.read8(Index_g, Base_v + i);
                        Resp_v                        := worse(Resp_v, Mem_v.errorResp(Index_g, Base_v + i, false));
                    end loop;

                    RResp    <= Resp_v;
                    RLast    <= '1' when Beat_v = ArL_v(ArHead_v) else '0';
                    RValid_i <= '1';
                end if;
            elsif ArCnt_v = 0 and RReady = '1' then
                RValid_i <= '0';
            end if;

            if Rst = '1' then
                ArHead_v  := 0;
                ArCnt_v   := 0;
                Beat_v    := 0;
                ArReady_i <= '0';
                RValid_i  <= '0';
            end if;
        end if;
    end process;

end architecture;
