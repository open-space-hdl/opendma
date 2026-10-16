# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Compliance matrix of OpenDMA against its published register interface.

Usage: python tools/compliance.py [--check]
Reads the requirement traceability matrix of docs/architecture.md (section 10), the requirements of every
hdl/<module>/docs/specification.md (ID and items of the published interface) and the test cases of every
verification_plan.md (test and requirement IDs), and writes docs/compliance.md: for every item of the matrix the
requirements that trace to it and the test cases that verify them.

An item is a register field (MM2S_DMACR.RS), a register (MM2S_SA), a descriptor field (DESC.MM2S_STATUS.Cmplt) or a
behaviour key (SEQ.DR.MM2S), written in backticks. The prefix "*_" stands for both channels and expands to MM2S_
and S2MM_. A requirement traces to an item when it names the item or a part of it (MM2S_DMACR.RS traces to
MM2S_DMACR.RS and would trace to an item MM2S_DMACR).

A module is in specification while it has no testbench (hdl/<module>/tb/*_tb.vhd): its requirements and test cases
are listed as planned. A requirement or a test case in a section of a specification or a verification plan whose
heading contains "waiting for Open Logic" needs a change of Open Logic that is not released yet: it is listed as
planned, never counts as verified and need not be run. An item without a verified requirement is planned while its development phase is open in
docs/roadmap.md or while none of its owner modules has a testbench yet. With --check the file is not written; the exit
code is 1 when an item that is not planned has no test case, when a requirement of a module with a testbench has no
test case or when a test case of such a module is not run by its testbench.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "compliance.md"
KEY_RE = re.compile(r"`([A-Z*][A-Za-z0-9_*]*(?:\.[A-Za-z0-9_]+)*)`")
REQ_ID_RE = re.compile(r"^[A-Z0-9]+(-[A-Z0-9]+)*-\d{2}$")
# Owner block prefix of the architecture (section 7) and the module that implements it
BLOCK_MODULE = {"RG": "odma_registers", "MM": "odma_mm2s", "S2": "odma_s2mm", "SG": "odma_sg", "CO": "odma_core"}


def table_rows(text):
    """Rows of markdown tables as lists of cells (header and separator rows included)."""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("|") and line.endswith("|"):
            yield [c.strip() for c in line.strip("|").split("|")]


def expand(key):
    """'*_DMACR.RS' -> ['MM2S_DMACR.RS', 'S2MM_DMACR.RS']; other keys unchanged."""
    if key.startswith("*_"):
        return ["MM2S_" + key[2:], "S2MM_" + key[2:]]
    return [key]


def keys(cell):
    """Expanded item keys of a cell."""
    result = []
    for key in KEY_RE.findall(cell):
        result += expand(key)
    return result


def expand_ids(cell):
    """Requirement IDs of a test row: 'RG-CR-01, RG-CR-03 to 05, MM-01' -> full list."""
    ids = []
    last = None
    for part in [p.strip() for p in cell.split(",")]:
        m = re.match(r"^([A-Z0-9]+(?:-[A-Z0-9]+)*-)(\d+)(?:\s+to\s+(?:[A-Z0-9]+(?:-[A-Z0-9]+)*-)?(\d+))?", part)
        if m:
            prefix, first = m.group(1), int(m.group(2))
            last_n = int(m.group(3)) if m.group(3) else first
            width = len(m.group(2))
            ids += [f"{prefix}{n:0{width}d}" for n in range(first, last_n + 1)]
            last = (prefix, width)
            continue
        m = re.match(r"^(\d+)(?:\s+to\s+(\d+))?$", part)
        if m and last:
            prefix, width = last
            first = int(m.group(1))
            last_n = int(m.group(2)) if m.group(2) else first
            ids += [f"{prefix}{n:0{width}d}" for n in range(first, last_n + 1)]
    return ids


WAITING_RE = re.compile(r"^(#+) .*waiting for Open Logic", re.I)


def split_waiting(text):
    """Splits a document into its text outside and inside the sections that wait for Open Logic."""
    normal, waiting = [], []
    level = 0
    for line in text.splitlines():
        heading = re.match(r"^(#+) ", line)
        if heading and level and len(heading.group(1)) <= level:
            level = 0
        m = WAITING_RE.match(line)
        if m:
            level = len(m.group(1))
        (waiting if level else normal).append(line)
    return "\n".join(normal), "\n".join(waiting)


def load_requirements():
    """Requirements of the module specifications: ID -> (module, item keys), and the IDs that wait for Open Logic."""
    reqs = {}
    waiting = set()
    for spec in sorted(ROOT.glob("hdl/*/docs/specification.md")):
        module = spec.parent.parent.name
        normal, later = split_waiting(spec.read_text(encoding="utf-8"))
        for text, is_waiting in ((normal, False), (later, True)):
            for row in table_rows(text):
                if len(row) >= 3 and REQ_ID_RE.match(row[0]):
                    reqs[row[0]] = (module, keys(row[-1]))
                    if is_waiting:
                        waiting.add(row[0])
    return reqs, waiting


def tested_modules():
    """Modules with a testbench: their requirements and test cases are checked."""
    return {tb.parent.parent.name for tb in ROOT.glob("hdl/*/tb/*_tb.vhd")}


def load_tests():
    """Test cases of the verification plans that a testbench of their module runs: test ID -> requirement IDs. Also
    returns the test names of the plans that no testbench of their module runs."""
    tests = {}
    not_run = []
    for plan in sorted(ROOT.glob("hdl/*/docs/verification_plan.md")):
        module_dir = plan.parent.parent
        run_names = set()
        for tb in module_dir.glob("tb/*.vhd"):
            run_names.update(re.findall(r'run\("(test_\w+)"\)', tb.read_text(encoding="utf-8")))
        run_ids = set()
        # Test cases that wait for Open Logic are neither required to run nor counted
        rows = list(table_rows(split_waiting(plan.read_text(encoding="utf-8"))[0]))
        for row in rows:
            if len(row) >= 3 and row[0].startswith("`test_"):
                name = row[0].split("`")[1]
                m = re.search(r"\((TC-[A-Z0-9]+-\d+)\)", row[0])
                tid = m.group(1) if m else row[0]
                if name in run_names:
                    run_ids.add(tid)
                    tests.setdefault(tid, set()).update(expand_ids(row[-1]))
                elif module_dir.name in tested_modules():
                    not_run.append(f"{module_dir.name}: {name}")
        for row in rows:
            if len(row) >= 3 and re.match(r"^TC-[A-Z0-9]+-\d+", row[0]):
                # Rows that reference test IDs directly (for example "TC-CO-02 (two configurations)")
                for tid in re.findall(r"TC-[A-Z0-9]+-\d+", row[0]):
                    if tid in run_ids:
                        tests.setdefault(tid, set()).update(expand_ids(row[-1]))
    return tests, sorted(not_run)


def load_matrix():
    """Rows of the traceability matrix, one per expanded item: (item, reference, owner, phase)."""
    text = (ROOT / "docs" / "architecture.md").read_text(encoding="utf-8")
    section = text[text.index("## 10 Requirement traceability matrix"):text.index("## 11 ")]
    rows = []
    for row in table_rows(section):
        if len(row) >= 6 and KEY_RE.fullmatch(row[0]):
            for item in keys(row[0]):
                rows.append((item, row[1], row[2], row[4]))
    return rows


def open_phases():
    """Development phases whose state in docs/roadmap.md is "Open"."""
    text = (ROOT / "docs" / "roadmap.md").read_text(encoding="utf-8")
    section = text[text.index("## Development phases"):]
    return {row[0] for row in table_rows(section) if len(row) >= 3 and row[-1] == "Open"}


def owner_modules(owner):
    """Modules of the owner blocks of a matrix row: 'MM-1 (MM2S), S2-2 (S2MM)' -> {'odma_mm2s', 'odma_s2mm'}."""
    return {BLOCK_MODULE[b] for b in re.findall(r"\b([A-Z][A-Z0-9])-\d+", owner) if b in BLOCK_MODULE}


def matches(req_keys, item):
    return any(rk == item or rk.startswith(item + ".") for rk in req_keys)


def test_key(tid):
    parts = tid.split("-")
    return (parts[1], int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0)


def main():
    reqs, waiting = load_requirements()
    tests, not_run = load_tests()
    matrix = load_matrix()
    phases_open = open_phases()
    specified = {m for m, _ in reqs.values()}
    tested = tested_modules()
    lines = [
        "# OpenDMA: Compliance Matrix",
        "",
        "Generated by `python tools/compliance.py` from the requirement traceability matrix of the",
        "[architecture](architecture.md) (section 10), the requirements of the module specifications and the test cases",
        "of the module verification plans. `python tools/compliance.py --check` fails when an item or a requirement has",
        "no test case, or when a test case of a plan is not run by a testbench.",
        "",
        "## 1. Items of the published interface",
        "",
        "An item is listed with every requirement that traces to it and with the test cases that verify these",
        "requirements. An item is verified when every requirement that traces to it is verified by a test case, and",
        "partly verified while the other requirements belong to modules without a testbench yet or wait for a change",
        "of Open Logic. An item is planned while its development phase is open, none of its owner modules has a",
        "testbench yet or all its requirements wait for Open Logic. The interpretations of the published interface",
        "are listed in section 6 of the architecture and in the module specifications.",
        "",
        "| Item | PG021 reference | Owner | Phase | Requirements | Test cases | Status |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    missing = []
    counts = {}
    for item, reference, owner, phase in matrix:
        req_ids = sorted(r for r, (_, rk) in reqs.items() if matches(rk, item))
        test_ids = sorted({t for t, ids in tests.items() if ids & set(req_ids)}, key=test_key)
        verified = {r for r in req_ids if r not in waiting and any(r in ids for ids in tests.values())}
        pending = {r for r in req_ids if r in waiting or reqs[r][0] not in tested}
        if owner.startswith("Out of scope"):
            status = "Out of scope"
        elif req_ids and verified == set(req_ids):
            status = "Verified"
        elif verified:
            # The other requirements belong to modules without a testbench; a gap of a module with a testbench
            # fails the requirement check below
            status = "Partly verified"
        elif phase in phases_open or not owner_modules(owner) & tested or (req_ids and set(req_ids) <= pending):
            status = "Planned"
        elif req_ids:
            status = "Not verified"
            missing.append(item)
        else:
            status = "Not traced"
            missing.append(item)
        counts[status] = counts.get(status, 0) + 1
        lines.append(f"| `{item}` | {reference} | {owner} | {phase} | {', '.join(req_ids) or '-'} | "
                     f"{', '.join(test_ids) or '-'} | {status} |")
    lines += [
        "",
        f"Items: {len(matrix)}; " + "; ".join(f"{s.lower()}: {n}" for s, n in sorted(counts.items())) + ".",
        "",
        "## 2. Requirements",
        "",
        "Requirements of the module specifications and the test cases that verify them (requirements without an item",
        "of the published interface included).",
        "",
        "| Module | Requirements | Verified by a test case | Without a test case | Waiting for Open Logic |",
        "| --- | --- | --- | --- | --- |",
    ]
    covered = set().union(*tests.values()) if tests else set()
    untested = sorted(r for r, (m, _) in reqs.items() if r not in covered and m in tested and r not in waiting)
    for module in sorted(specified):
        ids = [r for r, (m, _) in reqs.items() if m == module]
        later = [r for r in ids if r in waiting]
        gaps = [r for r in ids if r not in covered and r not in waiting]
        done = [r for r in ids if r in covered and r not in waiting]
        if module in tested:
            lines.append(f"| `{module}` | {len(ids)} | {len(done)} | {', '.join(gaps) or '-'} | "
                         f"{', '.join(later) or '-'} |")
        else:
            lines.append(f"| `{module}` | {len(ids)} | - | planned (no testbench yet) | {', '.join(later) or '-'} |")
    if not specified:
        lines.append("| - | 0 | 0 | - |")
    lines += [
        "",
        f"Requirements: {len(reqs)}; without a test case: {len(untested)}; test cases of the plans not run by a "
        f"testbench: {len(not_run)}.",
        "",
    ]
    if "--check" not in sys.argv:
        OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
        print(f"written {OUT.relative_to(ROOT)}")
    for item in missing:
        print(f"item without a test case: {item}")
    for r in untested:
        print(f"requirement without a test case: {r}")
    for n in not_run:
        print(f"test case of a plan not run by a testbench: {n}")
    failed = missing or untested or not_run
    sys.exit(1 if failed and "--check" in sys.argv else 0)


if __name__ == "__main__":
    main()
