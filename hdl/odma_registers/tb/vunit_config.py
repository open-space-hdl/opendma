# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of odma_registers_tb (verification plan, section 2). The tests without an entry run in the
default configuration only, the generic defaults of the testbench."""

DEFAULT = {"AddrWidth_g": 40, "LengthWidth_g": 26, "IncludeMm2s_g": True, "IncludeS2mm_g": True, "ExtRegs_g": True}
SG = {**DEFAULT, "IncludeSg_g": True}

CONFIGS = {
    "narrow": {**DEFAULT, "AddrWidth_g": 32, "LengthWidth_g": 8},
    "default": DEFAULT,
    "wide": {**DEFAULT, "AddrWidth_g": 64},
    "no_mm2s": {**DEFAULT, "IncludeMm2s_g": False},
    "no_s2mm": {**DEFAULT, "IncludeS2mm_g": False},
    "no_ext": {**DEFAULT, "ExtRegs_g": False},
    "sg_narrow": {**SG, "AddrWidth_g": 32, "LengthWidth_g": 8},
    "sg": SG,
    "sg_wide": {**SG, "AddrWidth_g": 64},
    "sg_no_mm2s": {**SG, "IncludeMm2s_g": False},
    "sg_no_s2mm": {**SG, "IncludeS2mm_g": False},
}

TESTS = {
    "test_access": ("narrow", "default"),
    "test_widths": ("narrow", "default", "wide"),
    "test_excluded_channel": ("no_mm2s", "no_s2mm"),
    "test_no_extension": ("no_ext",),
    "test_sg_map": ("sg_narrow", "sg", "sg_wide", "sg_no_mm2s", "sg_no_s2mm"),
    "test_sg_curdesc": ("sg_narrow", "sg", "sg_wide"),
    "test_sg_tail": ("sg_narrow", "sg", "sg_wide"),
    "test_sg_state": ("sg", "sg_no_mm2s", "sg_no_s2mm"),
    "test_sg_errors": ("sg", "sg_no_mm2s"),
    "test_sg_threshold": ("sg",),
    "test_sg_delay": ("sg",),
    "test_sg_modes": ("sg_narrow", "sg"),
}


# Tests that run with the generic defaults of the testbench only
DEFAULT_ONLY = ("test_reset_values", "test_mm2s_transfer", "test_s2mm_transfer", "test_start_halt",
                "test_halt_during_transfer", "test_soft_reset", "test_hard_reset", "test_errors", "test_length_rules",
                "test_irq_clear_race", "test_ecc", "test_dr_keyhole")


def configure(lib):
    tb = lib.test_bench("odma_registers_tb")
    # Every test of the testbench is in exactly one of the lists and every name of the lists a test
    tests = {test.name for test in tb.get_tests()}
    listed = set(TESTS) | set(DEFAULT_ONLY)
    twice = set(TESTS) & set(DEFAULT_ONLY)
    assert not twice, f"odma_registers_tb: listed twice {sorted(twice)}"
    assert tests == listed, (f"odma_registers_tb: tests not listed {sorted(tests - listed)}, "
                             f"listed without a test {sorted(listed - tests)}")
    for test, names in TESTS.items():
        for name in names:
            tb.test(test).add_config(name=name, generics=CONFIGS[name])
