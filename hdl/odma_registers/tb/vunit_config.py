# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of odma_registers_tb (verification plan, section 2). The tests without an entry run in the
default configuration only, the generic defaults of the testbench."""

DEFAULT = {"AddrWidth_g": 40, "LengthWidth_g": 26, "IncludeMm2s_g": True, "IncludeS2mm_g": True, "ExtRegs_g": True}

CONFIGS = {
    "narrow": {**DEFAULT, "AddrWidth_g": 32, "LengthWidth_g": 8},
    "default": DEFAULT,
    "wide": {**DEFAULT, "AddrWidth_g": 64},
    "no_mm2s": {**DEFAULT, "IncludeMm2s_g": False},
    "no_s2mm": {**DEFAULT, "IncludeS2mm_g": False},
    "no_ext": {**DEFAULT, "ExtRegs_g": False},
}

TESTS = {
    "test_access": ("narrow", "default"),
    "test_widths": ("narrow", "default", "wide"),
    "test_excluded_channel": ("no_mm2s", "no_s2mm"),
    "test_no_extension": ("no_ext",),
}


def configure(lib):
    tb = lib.test_bench("odma_registers_tb")
    for test, names in TESTS.items():
        for name in names:
            tb.test(test).add_config(name=name, generics=CONFIGS[name])
