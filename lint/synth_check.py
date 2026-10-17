# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Synthesis check of OpenDMA with GHDL: elaborates and synthesises odma_core at the values of its generics that the
verification report lists (the ends of every numeric range, every memory and stream width, the channel and extension
configurations) and checks that inconsistent configurations stop with the message of the core.

Usage: python lint/synth_check.py [-j N]
Uses the libraries compiled by the regression runner (run `python run.py --compile` first). The netlists go to
vunit_out/synth_check. Exit code 0 when every configuration synthesises without error and without inferred latch, and
every inconsistent configuration fails with its message. This is a technology-independent check of
synthesizability; resources and timing need the FPGA tools.
"""

import argparse
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBS = ROOT / "vunit_out" / "ghdl" / "libraries"
OUT = ROOT / "vunit_out" / "synth_check"


def channels(mem, stream, burst, prefix):
    """Generics of one channel with a data buffer of four bursts."""
    return {f"{prefix}MemWidth_g": str(mem), f"{prefix}StreamWidth_g": str(stream),
            f"{prefix}BurstBeats_g": str(burst), f"{prefix}BufferBeats_g": str(4 * burst * mem // stream)}


def both(mem, stream, burst):
    return {**channels(mem, stream, burst, "Mm2s"), **channels(mem, stream, burst, "S2mm")}


def configs():
    """Valid configurations: (generics, None); inconsistent ones: (generics, expected message)."""
    cfg = [({}, None)]
    # Address and length widths: the ends of the ranges
    cfg += [({"AddrWidth_g": "32", "LengthWidth_g": "8"}, None), ({"AddrWidth_g": "64", "LengthWidth_g": "26"}, None)]
    # Every memory width with the narrowest and the widest stream, the ends of the burst range
    cfg += [(both(mem, 8, 2), None) for mem in (32, 64, 128, 256, 512, 1024)]
    cfg += [(both(mem, mem, 256), None) for mem in (32, 1024)]
    # Different configurations of the two channels, data buffers of two bursts
    cfg += [({**channels(1024, 8, 256, "Mm2s"), **channels(32, 32, 2, "S2mm")}, None),
            ({"Mm2sBufferBeats_g": "32", "S2mmBufferBeats_g": "32"}, None)]
    # Channels and the extension window
    cfg += [({"IncludeMm2s_g": "false"}, None), ({"IncludeS2mm_g": "false"}, None), ({"ExtRegs_g": "false"}, None)]
    # Scatter/Gather Mode: the ends of the address and length ranges, each single-channel build
    cfg += [({"IncludeSg_g": "true"}, None),
            ({"IncludeSg_g": "true", "AddrWidth_g": "32", "LengthWidth_g": "8"}, None),
            ({"IncludeSg_g": "true", "AddrWidth_g": "64", "LengthWidth_g": "26"}, None),
            ({"IncludeSg_g": "true", "IncludeMm2s_g": "false"}, None),
            ({"IncludeSg_g": "true", "IncludeS2mm_g": "false"}, None)]
    # Inconsistent configurations
    cfg += [({"IncludeMm2s_g": "false", "IncludeS2mm_g": "false"}, "IncludeMm2s_g or IncludeS2mm_g must be true"),
            ({"StsCntrlStrm_g": "true"}, "StsCntrlStrm_g and UseRxLength_g must be false"),
            ({"UseRxLength_g": "true"}, "StsCntrlStrm_g and UseRxLength_g must be false"),
            ({"MicroDma_g": "true"}, "MicroDma_g must be false"),
            ({"Mm2sMemWidth_g": "48"}, "Mm2sMemWidth_g must be a power of 2"),
            ({"S2mmStreamWidth_g": "64"}, "S2mmStreamWidth_g must not be larger than S2mmMemWidth_g"),
            ({"Mm2sBurstBeats_g": "3"}, "Mm2sBurstBeats_g must be a power of 2"),
            ({"S2mmBufferBeats_g": "31"}, "S2mmBufferBeats_g must hold at least two bursts")]
    return cfg


def synth(generics, expected):
    cmd = ["ghdl", "--synth", "--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", "--work=opendma",
           f"--workdir={LIBS / 'opendma'}"]
    cmd += [f"-g{name}={value}" for name, value in generics.items()]
    cmd.append("odma_core")
    name = "odma_core" + "".join(f"_{k[:-2]}{v}" for k, v in generics.items())
    with open(OUT / f"{name}.vhd", "w") as netlist:
        res = subprocess.run(cmd, stdout=netlist, stderr=subprocess.PIPE, text=True)
    log = res.stderr
    if expected is not None:
        ok = res.returncode != 0 and expected in log
        return ok, f"{name}: {'rejected' if ok else 'NOT REJECTED as expected'}", []
    # Inferred latches are reported as "latch" warnings
    latches = [line for line in log.splitlines() if re.search(r"\blatch\b", line, re.IGNORECASE)]
    errors = [line for line in log.splitlines() if "error" in line.lower() or "exception" in line.lower()]
    ok = res.returncode == 0 and not latches and not errors
    return ok, f"{name}: {'OK' if ok else 'FAILED'}", (errors + latches)[:20]


def main():
    parser = argparse.ArgumentParser(description="GHDL synthesis check of odma_core")
    parser.add_argument("-j", type=int, default=1, help="parallel GHDL processes")
    args = parser.parse_args()
    if not LIBS.exists():
        raise SystemExit("compiled libraries not found, run: python run.py --compile")
    OUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=args.j) as pool:
        results = list(pool.map(lambda c: synth(c[0], c[1]), configs()))
    for ok, line, details in results:
        print(line)
        for detail in details:
            print("  " + detail)
    failed = sum(not ok for ok, _, _ in results)
    print(f"{len(results)} configurations, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
