# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of odma_sg_tb (verification plan, section 2). Every test runs in every configuration that
has the channels it needs; the configurations cover the boundaries of AddrWidth_g and LengthWidth_g and the builds
with one channel. The descriptor rate is measured in the default configuration only."""

# Name: (AddrWidth_g, LengthWidth_g, IncludeMm2s_g, IncludeS2mm_g)
CONFIGS = {
    "default": (32, 14, True, True),
    "aw40": (40, 26, True, True),
    "aw64": (64, 20, True, True),
    "lw8": (32, 8, True, True),
    "mm2s_only": (32, 14, True, False),
    "s2mm_only": (48, 16, False, True),
}

TESTS = ["test_fetch", "test_status", "test_tail", "test_prefetch", "test_curdesc", "test_packet_events",
         "test_stale", "test_transfer_errors", "test_error_codes", "test_descriptor_errors", "test_channels",
         "test_halt", "test_drain", "test_cyclic", "test_keyhole", "test_ecc", "test_random", "test_rate",
         "test_hard_reset"]

# Tests that need both channels, tests that run in one configuration only
BOTH = {"test_channels"}
ONLY = {"test_rate": ("default",)}


def configure(lib):
    tb = lib.test_bench("odma_sg_tb")
    # Every test of the testbench is in the list and every name of the lists a test: a test missing from the list
    # would run once with the generic defaults only
    names = {test.name for test in tb.get_tests()}
    assert names == set(TESTS), (f"odma_sg_tb: tests not listed {sorted(names - set(TESTS))}, "
                                 f"listed without a test {sorted(set(TESTS) - names)}")
    assert BOTH | set(ONLY) <= names, f"odma_sg_tb: unknown tests {sorted((BOTH | set(ONLY)) - names)}"
    for test in TESTS:
        for name, (addr, length, mm2s, s2mm) in CONFIGS.items():
            if test in BOTH and not (mm2s and s2mm):
                continue
            if test in ONLY and name not in ONLY[test]:
                continue
            tb.test(test).add_config(name=name, generics={
                "AddrWidth_g": addr,
                "LengthWidth_g": length,
                "IncludeMm2s_g": mm2s,
                "IncludeS2mm_g": s2mm,
            })
