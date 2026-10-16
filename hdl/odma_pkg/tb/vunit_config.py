# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configuration of odma_pkg_tb: the model test generates the files of the reference scenario before the
simulation (tb/model/odma_model.py), into the output path of the test."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tb" / "model"))

import odma_model  # noqa: E402  (after the path insertion)


def write_reference(output_path):
    odma_model.dr_reference().write(output_path)
    return True


def configure(lib):
    lib.test_bench("odma_pkg_tb").test("test_model_dr").set_pre_config(write_reference)
