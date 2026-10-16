# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of odma_mm2s_tb (verification plan, section 2): every test runs in every configuration;
together they simulate every memory and stream width. The data buffer holds four bursts, the default of the core."""

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


def configure(lib):
    tb = lib.test_bench("odma_mm2s_tb")
    for name, (mem, stream, burst, addr, length) in CONFIGS.items():
        tb.add_config(name=name, generics={
            "MemWidth_g": mem,
            "StreamWidth_g": stream,
            "BurstBeats_g": burst,
            "AddrWidth_g": addr,
            "LengthWidth_g": length,
            "BufferBeats_g": 4 * burst * mem // stream,
        })
