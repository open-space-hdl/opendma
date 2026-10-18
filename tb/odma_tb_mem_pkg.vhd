---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Memory of the AXI memory model odma_tb_axi_ram: a protected type with a sparse 64-bit byte space
-- per model instance (pages of 4096 bytes allocated on first write), error ranges with SLVERR or
-- DECERR responses, a write window, the burst limit, backpressure, latency and access statistics.
-- The object itself is the shared variable Mem_v of odma_tb_memvar_pkg.
--
-- Documentation: hdl/odma_pkg/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package odma_tb_mem_pkg is

    constant TbMemInstances_c : positive := 4;
    constant TbMemPages_c     : positive := 2048; -- Pages of 4096 bytes per instance
    constant TbMemRanges_c    : positive := 8;    -- Error ranges per instance

    -- Direction of an error range
    type TbDir_t is (TbDirRead, TbDirWrite, TbDirBoth);

    -- Fill pattern: a byte that depends on every bit of the byte address and on the seed. The bytes of
    -- consecutive addresses advance by a fixed step modulo the prime 65521, so a range read from an
    -- address shifted by a power of two (a whole burst, 256 bytes, 4 KB, ...) differs from the expected one.
    function odmaMemByte (
        addr : unsigned;
        seed : natural) return std_logic_vector;

    type TbMem_t is protected

        -- Backdoor access; unwritten bytes read as 0x00
        procedure write8 (
            idx  : natural;
            addr : unsigned;
            data : std_logic_vector(7 downto 0));

        impure function read8 (
            idx  : natural;
            addr : unsigned) return std_logic_vector;

        -- Fills the n bytes from addr with odmaMemByte(address, seed)
        procedure fill (
            idx  : natural;
            addr : unsigned;
            n    : natural;
            seed : natural);

        -- Error range n: accesses to the bytes from first to last respond with resp ("10" SLVERR,
        -- "11" DECERR, "01" EXOKAY) in direction dir; resp "00" disables the range
        procedure setError (
            idx   : natural;
            n     : natural;
            first : unsigned;
            last  : unsigned;
            resp  : std_logic_vector(1 downto 0);
            dir   : TbDir_t);

        procedure clearErrors (idx : natural);

        -- Response of an access to one byte: "00" when no enabled range of the direction contains it,
        -- otherwise the response of the first such range
        impure function errorResp (
            idx   : natural;
            addr  : unsigned;
            write : boolean) return std_logic_vector;

        -- Write window: strobed bytes outside it are reported by the model (whole space by default)
        procedure setWindow (
            idx   : natural;
            first : unsigned;
            last  : unsigned);

        impure function inWindow (
            idx  : natural;
            addr : unsigned) return boolean;

        -- Longest accepted burst (AxLen + 1), 1 to 256 (default 256)
        procedure setMaxBeats (
            idx : natural;
            n   : positive);

        impure function getMaxBeats (idx : natural) return positive;

        -- Percentage of cycles in which the model holds its ready and valid signals low (0 to 90)
        procedure setStall (
            idx     : natural;
            percent : natural);

        impure function getStall (idx : natural) return natural;

        -- Additional cycles before the first read beat of a burst and before a write response
        procedure setLatency (
            idx    : natural;
            cycles : natural);

        impure function getLatency (idx : natural) return natural;

        -- Statistics
        procedure clearStats (idx : natural);

        procedure noteWrite (
            idx  : natural;
            addr : unsigned);

        procedure noteRead (idx : natural);

        procedure noteBurst (idx : natural);

        procedure noteOutstanding (
            idx   : natural;
            write : boolean;
            n     : natural);

        -- Bytes written (strobed and not failed), lowest and highest address written
        impure function bytesWritten (idx : natural) return natural;

        impure function lowestWritten (idx : natural) return unsigned;

        impure function highestWritten (idx : natural) return unsigned;

        -- Read beats taken, bursts accepted (AW and AR), largest number of bursts without response
        impure function beatsRead (idx : natural) return natural;

        impure function bursts (idx : natural) return natural;

        impure function maxOutstanding (
            idx   : natural;
            write : boolean) return natural;

        -- FIFO window (PKG-12): the k-th read beat and the k-th write beat at the memory word that
        -- contains window access the word at backing + k x the data width; both counters start at 0
        procedure setFifo (
            idx     : natural;
            window  : unsigned;
            backing : unsigned);

        -- Address of a beat at base (aligned to bytes, the data width of the instance) after the FIFO
        -- window; counts the beat when it is at the window
        procedure fifoMap (
            idx    : natural;
            base   : in    unsigned(63 downto 0);
            bytes  : positive;
            write  : boolean;
            mapped : out   unsigned(63 downto 0));

    end protected;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body odma_tb_mem_pkg is

    function odmaMemByte (
        addr : unsigned;
        seed : natural) return std_logic_vector is
        constant Addr_c : unsigned(63 downto 0) := resize(addr, 64);
        variable H_v    : natural               := seed mod 65521 + 1;
    begin

        for k in 0 to 7 loop
            H_v := (H_v * 257 + to_integer(Addr_c(8 * k + 7 downto 8 * k)) + 17) mod 65521;
        end loop;

        H_v := (H_v * 257 + 17) mod 65521;
        return std_logic_vector(to_unsigned(H_v mod 256, 8) xor to_unsigned(H_v / 256 mod 256, 8));
    end function;

    type TbMem_t is protected body

        subtype Addr_t is unsigned(63 downto 0);
        subtype Key_t is unsigned(51 downto 0);

        type Page_t is array (0 to 4095) of std_logic_vector(7 downto 0);
        type PagePtr_t is access Page_t;
        type Keys_t is array (0 to TbMemPages_c - 1) of Key_t;
        type Ptrs_t is array (0 to TbMemPages_c - 1) of PagePtr_t;
        type KeyTable_t is array (0 to TbMemInstances_c - 1) of Keys_t;
        type PtrTable_t is array (0 to TbMemInstances_c - 1) of Ptrs_t;

        type Range_t is record
            First : Addr_t;
            Last  : Addr_t;
            Resp  : std_logic_vector(1 downto 0);
            Dir   : TbDir_t;
        end record;

        type Ranges_t is array (0 to TbMemRanges_c - 1) of Range_t;
        type RangeTable_t is array (0 to TbMemInstances_c - 1) of Ranges_t;
        type NatArray_t is array (0 to TbMemInstances_c - 1) of natural;
        type AddrArray_t is array (0 to TbMemInstances_c - 1) of Addr_t;

        constant RangeOff_c : Range_t := (First => (others => '0'), Last => (others => '0'), Resp => "00",
                                          Dir => TbDirBoth);

        variable Keys_v     : KeyTable_t;
        variable Ptrs_v     : PtrTable_t;
        variable Pages_v    : NatArray_t   := (others => 0);
        variable Hit_v      : NatArray_t   := (others => 0);
        variable Ranges_v   : RangeTable_t := (others => (others => RangeOff_c));
        variable WinFirst_v : AddrArray_t  := (others => (others => '0'));
        variable WinLast_v  : AddrArray_t  := (others => (others => '1'));
        variable MaxBeats_v : NatArray_t   := (others => 256);
        variable Stall_v    : NatArray_t   := (others => 0);
        variable Lat_v      : NatArray_t   := (others => 0);
        variable WrCnt_v    : NatArray_t   := (others => 0);
        variable WrLow_v    : AddrArray_t  := (others => (others => '1'));
        variable WrHigh_v   : AddrArray_t  := (others => (others => '0'));
        variable RdCnt_v    : NatArray_t   := (others => 0);
        variable Bursts_v   : NatArray_t   := (others => 0);
        variable WrOut_v    : NatArray_t   := (others => 0);
        variable RdOut_v    : NatArray_t   := (others => 0);
        variable FifoOn_v   : NatArray_t   := (others => 0);
        variable FifoWin_v  : AddrArray_t  := (others => (others => '0'));
        variable FifoBack_v : AddrArray_t  := (others => (others => '0'));
        variable FifoRd_v   : NatArray_t   := (others => 0);
        variable FifoWr_v   : NatArray_t   := (others => 0);

        -- Index of the page of addr, -1 when it is not allocated; with create, a missing page is allocated
        impure function page (
            idx    : natural;
            addr   : Addr_t;
            create : boolean) return integer is
            constant Key_c : Key_t := addr(63 downto 12);
        begin
            if Pages_v(idx) > 0 and Keys_v(idx)(Hit_v(idx)) = Key_c then
                return Hit_v(idx);
            end if;

            for i in 0 to Pages_v(idx) - 1 loop
                if Keys_v(idx)(i) = Key_c then
                    Hit_v(idx) := i;
                    return i;
                end if;
            end loop;

            if not create then
                return -1;
            end if;
            assert Pages_v(idx) < TbMemPages_c
                report "odma_tb_mem_pkg: more than TbMemPages_c pages written"
                severity failure;
            Keys_v(idx)(Pages_v(idx)) := Key_c;
            Ptrs_v(idx)(Pages_v(idx)) := new Page_t'(others => x"00");
            Hit_v(idx)                := Pages_v(idx);
            Pages_v(idx)              := Pages_v(idx) + 1;
            return Hit_v(idx);
        end function;

        procedure write8 (
            idx  : natural;
            addr : unsigned;
            data : std_logic_vector(7 downto 0)) is
            constant Addr_c : Addr_t := resize(addr, 64);
            variable Page_v : integer;
        begin
            Page_v                                               := page(idx, Addr_c, true);
            Ptrs_v(idx)(Page_v)(to_integer(Addr_c(11 downto 0))) := data;
        end procedure;

        impure function read8 (
            idx  : natural;
            addr : unsigned) return std_logic_vector is
            constant Addr_c : Addr_t  := resize(addr, 64);
            constant Page_c : integer := page(idx, Addr_c, false);
        begin
            if Page_c < 0 then
                return x"00";
            end if;
            return Ptrs_v(idx)(Page_c)(to_integer(Addr_c(11 downto 0)));
        end function;

        procedure fill (
            idx  : natural;
            addr : unsigned;
            n    : natural;
            seed : natural) is
            constant Addr_c : Addr_t := resize(addr, 64);
        begin

            for i in 0 to n - 1 loop
                write8(idx, Addr_c + i, odmaMemByte(Addr_c + i, seed));
            end loop;

        end procedure;

        procedure setError (
            idx   : natural;
            n     : natural;
            first : unsigned;
            last  : unsigned;
            resp  : std_logic_vector(1 downto 0);
            dir   : TbDir_t) is
        begin
            Ranges_v(idx)(n) := (First => resize(first, 64),
                                 Last => resize(last, 64),
                                 Resp => resp,
                                 Dir => dir);
        end procedure;

        procedure clearErrors (idx : natural) is
        begin
            Ranges_v(idx) := (others => RangeOff_c);
        end procedure;

        impure function errorResp (
            idx   : natural;
            addr  : unsigned;
            write : boolean) return std_logic_vector is
            constant Addr_c : Addr_t := resize(addr, 64);
            variable R_v    : Range_t;
        begin

            for i in 0 to TbMemRanges_c - 1 loop
                R_v := Ranges_v(idx)(i);
                if R_v.Resp /= "00" and Addr_c >= R_v.First and Addr_c <= R_v.Last and
                   (R_v.Dir = TbDirBoth or (R_v.Dir = TbDirWrite) = write) then
                    return R_v.Resp;
                end if;
            end loop;

            return "00";
        end function;

        procedure setWindow (
            idx   : natural;
            first : unsigned;
            last  : unsigned) is
        begin
            WinFirst_v(idx) := resize(first, 64);
            WinLast_v(idx)  := resize(last, 64);
        end procedure;

        impure function inWindow (
            idx  : natural;
            addr : unsigned) return boolean is
            constant Addr_c : Addr_t := resize(addr, 64);
        begin
            return Addr_c >= WinFirst_v(idx) and Addr_c <= WinLast_v(idx);
        end function;

        procedure setMaxBeats (
            idx : natural;
            n   : positive) is
        begin
            MaxBeats_v(idx) := minimum(n, 256);
        end procedure;

        impure function getMaxBeats (idx : natural) return positive is
        begin
            return MaxBeats_v(idx);
        end function;

        procedure setStall (
            idx     : natural;
            percent : natural) is
        begin
            Stall_v(idx) := minimum(percent, 90);
        end procedure;

        impure function getStall (idx : natural) return natural is
        begin
            return Stall_v(idx);
        end function;

        procedure setLatency (
            idx    : natural;
            cycles : natural) is
        begin
            Lat_v(idx) := cycles;
        end procedure;

        impure function getLatency (idx : natural) return natural is
        begin
            return Lat_v(idx);
        end function;

        procedure clearStats (idx : natural) is
        begin
            WrCnt_v(idx)  := 0;
            WrLow_v(idx)  := (others => '1');
            WrHigh_v(idx) := (others => '0');
            RdCnt_v(idx)  := 0;
            Bursts_v(idx) := 0;
            WrOut_v(idx)  := 0;
            RdOut_v(idx)  := 0;
        end procedure;

        procedure noteWrite (
            idx  : natural;
            addr : unsigned) is
            constant Addr_c : Addr_t := resize(addr, 64);
        begin
            WrCnt_v(idx) := WrCnt_v(idx) + 1;
            if Addr_c < WrLow_v(idx) then
                WrLow_v(idx) := Addr_c;
            end if;
            if Addr_c > WrHigh_v(idx) then
                WrHigh_v(idx) := Addr_c;
            end if;
        end procedure;

        procedure noteRead (idx : natural) is
        begin
            RdCnt_v(idx) := RdCnt_v(idx) + 1;
        end procedure;

        procedure noteBurst (idx : natural) is
        begin
            Bursts_v(idx) := Bursts_v(idx) + 1;
        end procedure;

        procedure noteOutstanding (
            idx   : natural;
            write : boolean;
            n     : natural) is
        begin
            if write then
                WrOut_v(idx) := maximum(WrOut_v(idx), n);
            else
                RdOut_v(idx) := maximum(RdOut_v(idx), n);
            end if;
        end procedure;

        impure function bytesWritten (idx : natural) return natural is
        begin
            return WrCnt_v(idx);
        end function;

        impure function lowestWritten (idx : natural) return unsigned is
        begin
            return WrLow_v(idx);
        end function;

        impure function highestWritten (idx : natural) return unsigned is
        begin
            return WrHigh_v(idx);
        end function;

        impure function beatsRead (idx : natural) return natural is
        begin
            return RdCnt_v(idx);
        end function;

        impure function bursts (idx : natural) return natural is
        begin
            return Bursts_v(idx);
        end function;

        impure function maxOutstanding (
            idx   : natural;
            write : boolean) return natural is
        begin
            if write then
                return WrOut_v(idx);
            end if;
            return RdOut_v(idx);
        end function;

        procedure setFifo (
            idx     : natural;
            window  : unsigned;
            backing : unsigned) is
        begin
            FifoOn_v(idx)   := 1;
            FifoWin_v(idx)  := resize(window, 64);
            FifoBack_v(idx) := resize(backing, 64);
            FifoRd_v(idx)   := 0;
            FifoWr_v(idx)   := 0;
        end procedure;

        procedure fifoMap (
            idx    : natural;
            base   : in    unsigned(63 downto 0);
            bytes  : positive;
            write  : boolean;
            mapped : out   unsigned(63 downto 0)) is
            constant Bytes_c : Addr_t := to_unsigned(bytes, 64);
            variable Win_v   : Addr_t;
        begin
            mapped := base;
            if FifoOn_v(idx) = 1 then
                Win_v := FifoWin_v(idx) - (FifoWin_v(idx) mod Bytes_c);
                if base = Win_v then
                    if write then
                        mapped        := FifoBack_v(idx) + to_unsigned(FifoWr_v(idx) * bytes, 64);
                        FifoWr_v(idx) := FifoWr_v(idx) + 1;
                    else
                        mapped        := FifoBack_v(idx) + to_unsigned(FifoRd_v(idx) * bytes, 64);
                        FifoRd_v(idx) := FifoRd_v(idx) + 1;
                    end if;
                end if;
            end if;
        end procedure;

    end protected body;

end package body;
