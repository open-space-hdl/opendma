# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of odma_s2mm_tb (verification plan, section 2): the tests of phase a run in every
configuration, the tests of Scatter/Gather Mode in the configurations with the stream split (prefix s_); together
they simulate every memory and stream width, and every stream width up to 512 bits with the split. The data buffer
holds four bursts, the default of the core."""

# Name: (MemWidth_g, StreamWidth_g, BurstBeats_g, AddrWidth_g, LengthWidth_g)
CONFIGS = {
    "w32_s32": (32, 32, 16, 32, 26),
    "w64_s8": (64, 8, 16, 40, 26),
    "w128_s32": (128, 32, 256, 64, 26),
    "w128_s64": (128, 64, 32, 32, 16),
    "w256_s16": (256, 16, 8, 48, 20),
    "w256_s128": (256, 128, 4, 32, 18),
    "w512_s256": (512, 256, 8, 36, 22),
    "w512_s512": (512, 512, 2, 32, 14),
    "w1024_s8": (1024, 8, 2, 32, 8),
    "w1024_s1024": (1024, 1024, 256, 64, 12),
}

# Configurations that also run with the stream split: every stream width up to 512 bits, the shortest length width
SPLIT = ("w64_s8", "w256_s16", "w32_s32", "w128_s64", "w256_s128", "w512_s256", "w512_s512", "w1024_s8")

# Tests of Scatter/Gather Mode: only with the stream split
SG_TESTS = ("test_split", "test_split_wait", "test_split_halt")
# Tests that need a packet in the data buffer before its command or a packet longer than its buffer: only without
# the split, which excludes both by design (verification plan, section 2)
DR_TESTS = ("test_early_data", "test_overflow", "test_ecc")


def configure(lib):
    tb = lib.test_bench("odma_s2mm_tb")
    for test in tb.get_tests():
        for name, (mem, stream, burst, addr, length) in CONFIGS.items():
            generics = {
                "MemWidth_g": mem,
                "StreamWidth_g": stream,
                "BurstBeats_g": burst,
                "AddrWidth_g": addr,
                "LengthWidth_g": length,
                "BufferBeats_g": 4 * burst * mem // stream,
            }
            for split in (False, True):
                if split and (name not in SPLIT or test.name in DR_TESTS):
                    continue
                if test.name in SG_TESTS and not split:
                    continue
                test.add_config(name=("s_" if split else "") + name, generics={**generics, "Split_g": split})
