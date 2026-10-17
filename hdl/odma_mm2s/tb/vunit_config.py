# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of odma_mm2s_tb (verification plan, section 2): the tests of phase a run in every
configuration, the tests of Scatter/Gather Mode in the configurations with the stream join (prefix j_); together
they simulate every memory and stream width, and every stream width with the join. The data buffer holds four
bursts, the default of the core."""

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

# Configurations that also run with the stream join: every stream width
JOIN = ("w64_s8", "w256_s16", "w32_s32", "w128_s64", "w256_s128", "w512_s256", "w512_s512", "w1024_s1024")

# Tests of Scatter/Gather Mode: only with the stream join
SG_TESTS = ("test_join", "test_join_results", "test_join_halt")


def configure(lib):
    tb = lib.test_bench("odma_mm2s_tb")
    # Every test runs in the configurations below; the names of the lists must be tests and configurations
    names = {test.name for test in tb.get_tests()}
    assert set(SG_TESTS) <= names, f"odma_mm2s_tb: unknown tests {sorted(set(SG_TESTS) - names)}"
    assert set(JOIN) <= set(CONFIGS), f"odma_mm2s_tb: unknown configurations {sorted(set(JOIN) - set(CONFIGS))}"
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
            for join in (False, True):
                if (join and name not in JOIN) or (test.name in SG_TESTS and not join):
                    continue
                test.add_config(name=("j_" if join else "") + name, generics={**generics, "Join_g": join})
