# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of odma_core_tb (verification plan, section 2). Each test runs in the configurations its
function needs; the pre_config of a test writes the files of its model scenarios (tb/model/odma_model.py) for the
generics of the configuration into the output path of the test."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tb" / "model"))

import odma_model  # noqa: E402  (after the path insertion)

# Generics of the testbench (the defaults of the core)
DEFAULTS = {
    "IncludeMm2s_g": True, "IncludeS2mm_g": True, "LengthWidth_g": 14, "AddrWidth_g": 32,
    "Mm2sMemWidth_g": 32, "S2mmMemWidth_g": 32, "Mm2sStreamWidth_g": 32, "S2mmStreamWidth_g": 32,
    "Mm2sBurstBeats_g": 16, "S2mmBurstBeats_g": 16, "Mm2sBufferBeats_g": 64, "S2mmBufferBeats_g": 64,
    "ExtRegs_g": True, "IncludeSg_g": False,
}


def channel(prefix, mem, stream, burst):
    """Generics of one channel with a data buffer of four bursts."""
    return {f"{prefix}MemWidth_g": mem, f"{prefix}StreamWidth_g": stream, f"{prefix}BurstBeats_g": burst,
            f"{prefix}BufferBeats_g": 4 * burst * mem // stream}


# Stream widths stay at or below 256 bits, the limit of the AXI4-Stream VVC; the unit benches of the channels
# simulate the wider streams
CONFIGS = {
    "default": {},
    "aw40": {"AddrWidth_g": 40, "LengthWidth_g": 26, **channel("Mm2s", 64, 32, 16), **channel("S2mm", 128, 64, 32)},
    "aw64": {"AddrWidth_g": 64, "LengthWidth_g": 20, **channel("Mm2s", 256, 64, 8), **channel("S2mm", 512, 256, 4)},
    "lw8": {"LengthWidth_g": 8, **channel("Mm2s", 128, 8, 4), **channel("S2mm", 64, 8, 2)},
    "no_ext": {"ExtRegs_g": False},
    "mm2s_only": {"IncludeS2mm_g": False},
    "s2mm_only": {"IncludeMm2s_g": False},
    "sg": {"IncludeSg_g": True},
    "sg_aw64": {"IncludeSg_g": True, "AddrWidth_g": 64, "LengthWidth_g": 20, **channel("Mm2s", 256, 64, 8),
                **channel("S2mm", 512, 256, 4)},
    "sg_lw8": {"IncludeSg_g": True, "LengthWidth_g": 8, **channel("Mm2s", 128, 8, 4), **channel("S2mm", 64, 8, 2)},
    "sg_mm2s_only": {"IncludeSg_g": True, "IncludeS2mm_g": False},
    "sg_s2mm_only": {"IncludeSg_g": True, "IncludeMm2s_g": False},
}


def both(g):
    return g["IncludeMm2s_g"] and g["IncludeS2mm_g"] and not g["IncludeSg_g"]


def dr(g):
    return not g["IncludeSg_g"]


def sg(g):
    return g["IncludeSg_g"]


def channels(g):
    return tuple(ch for ch, key in (("MM2S", "IncludeMm2s_g"), ("S2MM", "IncludeS2mm_g")) if g[key])


def files_reference(g, path):
    odma_model.dr_reference().write(path)


def files_random(g, path):
    odma_model.dr_random(g["AddrWidth_g"], g["LengthWidth_g"]).write(path)


def files_concurrent(g, path):
    odma_model.dr_concurrent(g["AddrWidth_g"], g["LengthWidth_g"]).write(path)


def files_errors(g, path):
    odma_model.dr_errors(g["AddrWidth_g"], g["LengthWidth_g"]).write(path)


def files_after_reset(g, path):
    odma_model.dr_random(g["AddrWidth_g"], g["LengthWidth_g"], seed=5, count=4, name="after_reset").write(path)


def files_ecc(g, path):
    for ch in channels(g):
        odma_model.dr_single(ch, g["AddrWidth_g"], g["LengthWidth_g"], name=f"ecc_{ch.lower()}").write(
            Path(path) / f"ecc_{ch.lower()}")


def files_sg_reference(g, path):
    odma_model.sg_reference(g["AddrWidth_g"], g["LengthWidth_g"], channels(g)).write(path)


def files_sg_tail_moves(g, path):
    odma_model.sg_tail_moves(g["AddrWidth_g"], g["LengthWidth_g"], channels(g)).write(path)


def files_sg_cyclic(g, path):
    odma_model.sg_cyclic(g["AddrWidth_g"], g["LengthWidth_g"], channels(g)).write(path)


def files_sg_errors(g, path):
    odma_model.sg_errors(g["AddrWidth_g"], g["LengthWidth_g"], channels(g)).write(path)


def files_sg_delay(g, path):
    odma_model.sg_delay(g["AddrWidth_g"], g["LengthWidth_g"], channels(g)).write(Path(path) / "hold")
    beats = {"MM2S": g["Mm2sStreamWidth_g"] // 8, "S2MM": g["S2mmStreamWidth_g"] // 8}
    odma_model.sg_delay_overlap(g["AddrWidth_g"], g["LengthWidth_g"], channels(g), beats).write(
        Path(path) / "overlap")


def files_sg_soft_reset(g, path):
    odma_model.sg_reset_load(g["AddrWidth_g"], g["LengthWidth_g"], channels(g)).write(Path(path) / "start")
    odma_model.sg_reference(g["AddrWidth_g"], g["LengthWidth_g"], channels(g)).write(Path(path) / "after")


def files_sg_ecc(g, path):
    odma_model.sg_reference(g["AddrWidth_g"], g["LengthWidth_g"], channels(g), reset=False).write(path)


def files_excluded(g, path):
    odma_model.dr_random(g["AddrWidth_g"], g["LengthWidth_g"], channels=channels(g), seed=6, count=6,
                         name="single_channel").write(path)


# Test: (configurations it runs in, writer of its scenario files or None)
TESTS = {
    "test_dr_reference": (lambda g: both(g) and g["AddrWidth_g"] > 32, files_reference),
    "test_dr_random": (both, files_random),
    "test_concurrent": (both, files_concurrent),
    "test_errors": (both, files_errors),
    "test_soft_reset_load": (both, files_after_reset),
    "test_ecc_index": (dr, files_ecc),
    "test_ecc_data": (lambda g: dr(g) and g["ExtRegs_g"] and min(g["Mm2sStreamWidth_g"], g["S2mmStreamWidth_g"]) >= 16,
                      None),
    "test_configuration": (lambda g: True, None),
    "test_excluded_channel": (lambda g: dr(g) and not (g["IncludeMm2s_g"] and g["IncludeS2mm_g"]), files_excluded),
    "test_sg_reference": (sg, files_sg_reference),
    "test_sg_tail_moves": (sg, files_sg_tail_moves),
    "test_sg_cyclic": (sg, files_sg_cyclic),
    "test_sg_errors": (sg, files_sg_errors),
    "test_sg_delay": (sg, files_sg_delay),
    "test_sg_soft_reset": (sg, files_sg_soft_reset),
    "test_sg_ecc_index": (sg, files_sg_ecc),
}


def pre_config(writer, generics):
    def write(output_path):
        writer(generics, output_path)
        return True
    return write


def configure(lib):
    tb = lib.test_bench("odma_core_tb")
    for name, (selected, writer) in TESTS.items():
        test = tb.test(name)
        for cfg, generics in CONFIGS.items():
            full = {**DEFAULTS, **generics}
            if selected(full):
                test.add_config(name=cfg, generics=generics,
                                pre_config=pre_config(writer, full) if writer else None)
