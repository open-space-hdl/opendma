# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of odma_s2mm_tb (verification plan, section 2): the tests of phase a run in every
configuration, the tests of Scatter/Gather Mode in the configurations with the stream split (prefix s_); together
they simulate every memory and stream width, and every stream width with the split. The data buffer
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

# Configurations that also run with the stream split: every stream width, the shortest length width, bursts limited
# by 4 KB (w1024_s1024)
SPLIT = ("w64_s8", "w256_s16", "w32_s32", "w128_s64", "w256_s128", "w512_s256", "w512_s512", "w1024_s8",
         "w1024_s1024")

# Tests of Scatter/Gather Mode: only with the stream split
SG_TESTS = ("test_split", "test_split_wait", "test_split_halt")
# Tests that need a packet in the data buffer before its command or a packet longer than its buffer: only without
# the split, which excludes both by design (verification plan, section 2)
DR_TESTS = ("test_early_data", "test_overflow")
# The halt sweep: the default and the 2-beat chunks without the split, and with the split the narrowest lag (two
# bytes of an 8-bit stream) and the widest (two beats of 512 bits, a whole chunk)
SWEEP = {"test_halt_sweep": ("w32_s32", "w512_s512", "s_w64_s8", "s_w512_s512")}


def configure(lib):
    tb = lib.test_bench("odma_s2mm_tb")
    # Every test runs in the configurations below; the names of the lists must be tests and configurations
    names = {test.name for test in tb.get_tests()}
    unknown = (set(SG_TESTS) | set(DR_TESTS) | set(SWEEP)) - names
    assert not unknown, f"odma_s2mm_tb: unknown tests {sorted(unknown)}"
    assert set(SPLIT) <= set(CONFIGS), f"odma_s2mm_tb: unknown configurations {sorted(set(SPLIT) - set(CONFIGS))}"
    sweep = {c for cfgs in SWEEP.values() for c in cfgs}
    known = set(CONFIGS) | {"s_" + c for c in SPLIT}
    assert sweep <= known, f"odma_s2mm_tb: unknown sweep configurations {sorted(sweep - known)}"
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
                cfg = ("s_" if split else "") + name
                if test.name in SWEEP and cfg not in SWEEP[test.name]:
                    continue
                test.add_config(name=cfg, generics={**generics, "Split_g": split})
