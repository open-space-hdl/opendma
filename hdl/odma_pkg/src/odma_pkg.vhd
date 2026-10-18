---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Definitions shared by all OpenDMA modules: error codes of a transfer result, byte lane functions
-- of the stream conventions, the address range check and the consistency check of the core generics.
--
-- Documentation: hdl/odma_pkg/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_pkg is

    -- Error code of a transfer result; SLVERR and DECERR have the values of the AXI response codes
    subtype XferErr_t is std_logic_vector(1 downto 0);
    constant ErrNone_c : XferErr_t := "00";
    constant ErrInt_c  : XferErr_t := "01"; -- DMASR.DMAIntErr
    constant ErrSlv_c  : XferErr_t := "10"; -- DMASR.DMASlvErr
    constant ErrDec_c  : XferErr_t := "11"; -- DMASR.DMADecErr

    -- TKeep of the last beat of a transfer of bytes bytes on a stream of w bytes (w a power of two):
    -- lanes 0 to (bytes - 1) mod w set; no lane set for bytes = 0
    function lastKeep (
        bytes : unsigned;
        w     : positive) return std_logic_vector;

    -- Valid bytes of a last beat: the index of the lowest lane whose TKeep bit is not '1'
    function keepBytes (keep : std_logic_vector) return natural;

    -- True when the buffer of bytes bytes from addr does not fit below the top of the address space of
    -- addr'length bits; false for bytes = 0 (an empty buffer touches no byte)
    function beyondTop (
        addr  : unsigned;
        bytes : unsigned) return boolean;

    -- Empty for consistent core generics, otherwise a message naming the first inconsistent generic
    function coreConfigError (
        addrWidth       : natural;
        lengthWidth     : natural;
        mm2sMemWidth    : natural;
        mm2sStreamWidth : natural;
        mm2sBurstBeats  : natural;
        mm2sBufferBeats : natural;
        s2mmMemWidth    : natural;
        s2mmStreamWidth : natural;
        s2mmBurstBeats  : natural;
        s2mmBufferBeats : natural) return string;

    -- Flip pattern of an injected error in a codeword of olo_ft_pkg_ecc of width bits. Parity mode (data '0'):
    -- the overall parity (bit 0) and, for a double error, the Hamming parity p0 (bit 1), so the data never
    -- changes. Data mode: data bit 0 (codeword bit 3) and, for a double error, data bit 1 (codeword bit 5); a
    -- double error then corrupts the word
    function flipPattern (
        width  : positive;
        double : std_logic;
        data   : std_logic) return std_logic_vector;

    -- Error code of a failed AXI command from its response code: the decode error for DECERR, the slave
    -- error for SLVERR and for EXOKAY ("01", which must not become ErrInt_c; interpretation I14)
    function respErr (resp : std_logic_vector(1 downto 0)) return XferErr_t;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body odma_pkg is

    function lastKeep (
        bytes : unsigned;
        w     : positive) return std_logic_vector is
        constant LowBits_c : natural                          := log2ceil(w);
        constant Width_c   : positive                         := maximum(bytes'length, LowBits_c);
        variable Bytes_v   : unsigned(Width_c - 1 downto 0);
        variable Low_v     : natural                          := 0;
        variable Keep_v    : std_logic_vector(w - 1 downto 0) := (others => '0');
    begin
        Bytes_v := resize(bytes, Width_c);
        if Bytes_v /= 0 then
            if LowBits_c > 0 then
                Low_v := to_integer(Bytes_v(LowBits_c - 1 downto 0));
            end if;

            -- Low_v = 0: the last beat is full
            for i in 0 to w - 1 loop
                if Low_v = 0 or i < Low_v then
                    Keep_v(i) := '1';
                end if;
            end loop;

        end if;
        return Keep_v;
    end function;

    function keepBytes (keep : std_logic_vector) return natural is
        alias KeepNorm : std_logic_vector(keep'length - 1 downto 0) is keep;

        variable Cnt_v  : natural := keep'length;
        variable Done_v : boolean := false;
    begin

        for i in 0 to keep'length - 1 loop
            if not Done_v and KeepNorm(i) /= '1' then
                Cnt_v  := i;
                Done_v := true;
            end if;
        end loop;

        return Cnt_v;
    end function;

    function beyondTop (
        addr  : unsigned;
        bytes : unsigned) return boolean is
        constant Width_c : positive := maximum(addr'length, bytes'length) + 1;
        variable Last_v  : unsigned(Width_c - 1 downto 0);
    begin
        if bytes = 0 then
            return false;
        end if;
        Last_v := resize(addr, Width_c) + resize(bytes, Width_c) - 1;
        return Last_v(Width_c - 1 downto addr'length) /= 0;
    end function;

    -- First inconsistent generic of one channel, empty when consistent
    function channelError (
        prefix      : string;
        memWidth    : natural;
        streamWidth : natural;
        burstBeats  : natural;
        bufferBeats : natural) return string is
    begin
        if memWidth < 32 or memWidth > 1024 or not isPower2(memWidth) then
            return prefix & "MemWidth_g must be a power of 2 from 32 to 1024";
        elsif streamWidth < 8 or streamWidth > 1024 or not isPower2(streamWidth) then
            return prefix & "StreamWidth_g must be a power of 2 from 8 to 1024";
        elsif streamWidth > memWidth then
            return prefix & "StreamWidth_g must not be larger than " & prefix & "MemWidth_g";
        elsif burstBeats < 2 or burstBeats > 256 or not isPower2(burstBeats) then
            return prefix & "BurstBeats_g must be a power of 2 from 2 to 256";
        elsif bufferBeats < 2 * burstBeats * (memWidth / streamWidth) then
            return prefix & "BufferBeats_g must hold at least two bursts";
        end if;
        return "";
    end function;

    function coreConfigError (
        addrWidth       : natural;
        lengthWidth     : natural;
        mm2sMemWidth    : natural;
        mm2sStreamWidth : natural;
        mm2sBurstBeats  : natural;
        mm2sBufferBeats : natural;
        s2mmMemWidth    : natural;
        s2mmStreamWidth : natural;
        s2mmBurstBeats  : natural;
        s2mmBufferBeats : natural) return string is
    begin
        if addrWidth < 32 or addrWidth > 64 then
            return "AddrWidth_g must be 32 to 64";
        elsif lengthWidth < 8 or lengthWidth > 26 then
            return "LengthWidth_g must be 8 to 26";
        elsif channelError("Mm2s", mm2sMemWidth, mm2sStreamWidth, mm2sBurstBeats, mm2sBufferBeats) /= "" then
            return channelError("Mm2s", mm2sMemWidth, mm2sStreamWidth, mm2sBurstBeats, mm2sBufferBeats);
        else
            return channelError("S2mm", s2mmMemWidth, s2mmStreamWidth, s2mmBurstBeats, s2mmBufferBeats);
        end if;
    end function;

    function flipPattern (
        width  : positive;
        double : std_logic;
        data   : std_logic) return std_logic_vector is
        variable Flip_v : std_logic_vector(width - 1 downto 0) := (others => '0');
    begin
        if data = '1' then
            Flip_v(3) := '1';
            Flip_v(5) := double;
        else
            Flip_v(0) := '1';
            Flip_v(1) := double;
        end if;
        return Flip_v;
    end function;

    function respErr (resp : std_logic_vector(1 downto 0)) return XferErr_t is
    begin
        if resp = "11" then
            return ErrDec_c;
        end if;
        return ErrSlv_c;
    end function;

end package body;
