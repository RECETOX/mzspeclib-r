#!/usr/bin/env python3
# How to run:  /tmp/mzvenv/bin/python viol_inventory.py [file.mzSpecLib.txt ...]
#   No arguments: the six default files below (spec examples + what the R package
#   writes; runs R via pkgload first, so the package must load). Each CLI run
#   loads the ontology, so expect a minute or two per file on a cold cache.
"""Normalised gold-rule violation inventories from the reference CLI (report §4.15).

This is the in-repo replacement for the throwaway /tmp/violcheck.py the 2026-10-22
interoperability checks were made with, carrying its two caveats as code rather
than folklore:

  1 `mzspeclib validate` writes every violation to STDERR twice — once through
    the mzspeclib.validate.validator logger (semantic_rule.py:417 /
    validator.py:_check_value_types:298) and once as a `... `-prefixed echo from
    __main__ (cli.py:validate:240) — and prints nothing to stdout, so a
    stdout-only capture counts zero and a naive `grep -c '(MUST)' | …` on stderr
    counts exactly double.
  2 every line is prefixed with a wall-clock timestamp ([HH:MM:SS]), which
    differs between two runs of the same file, so inventories from different
    invocations can only be compared after the timestamp (and the logger/location
    prefix and the echo's `... `) have been stripped and the two copies folded.

The inventory printed here is the deduplicated, de-timestamped set; comparisons
are computed on those. Exit codes are recorded because the CLI returns 0 even
when MUST rules fail (§4.11 row 1).
"""
import collections
import os
import re
import subprocess
import sys

CLI = "/tmp/mzvenv/bin/python"
EX = "/home/hechth/dev/mzSpecLib/examples"
OUT = "/tmp/mzspeclib-r-writes"

DEFAULTS = [
    ("orig txt    ", f"{EX}/SpectraST/fetal_brain_tiny_consensus_td.mzSpecLib.txt", "mzSpecLib.txt"),
    ("orig json   ", f"{EX}/SpectraST/fetal_brain_tiny.mzSpecLib.json", "mzSpecLib.json"),
    ("iarpa3 txt  ", f"{EX}/NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.txt", "mzSpecLib.txt"),
    ("iarpa3 json ", f"{EX}/NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.json", "mzSpecLib.json"),
    ("r text      ", f"{OUT}/r_text.mzSpecLib.txt", "mzSpecLib.txt"),
    ("r json      ", f"{OUT}/r_json.mzSpecLib.json", "mzSpecLib.json"),
    ("r iarpa3 txt", f"{OUT}/r_text_iarpa3.mzSpecLib.txt", "mzSpecLib.txt"),
    ("r iarpa3 jso", f"{OUT}/r_json_iarpa3.mzSpecLib.json", "mzSpecLib.json"),
]

LEVEL = re.compile(r"\((MUST|SHOULD|MAY)\)")
PREFIX = re.compile(r"^\[\d+:\d+:\d+\] \w \| [^|]+\| [^|]+\| ")


def normalise(line):
    body = PREFIX.sub("", line)
    if body.startswith("... "):          # the __main__ echo of the same violation
        body = body[4:]
    return re.sub(r"\s+", " ", body).strip()


def inventory(path, fmt):
    r = subprocess.run([CLI, "-m", "mzspeclib.tools.cli", "validate",
                        "-p", "gold", "-i", fmt, path],
                       capture_output=True, text=True)
    n_raw = 0
    seen = set()
    for stream, name in ((r.stderr, "stderr"), (r.stdout, "stdout")):
        for l in stream.splitlines():
            m = LEVEL.search(l)
            if m:
                n_raw += 1
                seen.add((m.group(1), normalise(l)))
    return r.returncode, n_raw, collections.Counter(lvl for lvl, _ in seen), seen


def write_r_outputs():
    """(Re)create the four files the R package writes, as the default targets."""
    os.makedirs(OUT, exist_ok=True)
    rscript = (
        'pkgload::load_all("/home/hechth/dev/mzspeclib-r", quiet = TRUE)\n'
        'lib <- read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",\n'
        '    package = "mzspeclib"))\n'
        f'write_mzspeclib(lib, file.path("{OUT}", "r_text.mzSpecLib.txt"))\n'
        f'write_mzspeclib(lib, file.path("{OUT}", "r_json.mzSpecLib.json"))\n'
        f'lib2 <- read_mzspeclib("{EX}/NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.txt")\n'
        f'write_mzspeclib(lib2, file.path("{OUT}", "r_text_iarpa3.mzSpecLib.txt"))\n'
        f'write_mzspeclib(lib2, file.path("{OUT}", "r_json_iarpa3.mzSpecLib.json"))\n'
    )
    subprocess.run(["Rscript", "-e", rscript], capture_output=True, check=True)


def main():
    files = DEFAULTS
    if len(sys.argv) > 1:
        files = [(os.path.basename(p)[:12].ljust(12), p,
                  "mzSpecLib.json" if p.endswith(".json") else "mzSpecLib.txt")
                 for p in sys.argv[1:]]
    if len(sys.argv) == 1:
        write_r_outputs()
    inv, raw_counts, codes = {}, {}, {}
    for label, path, fmt in files:
        if not os.path.exists(path):
            print(f"{label} missing: {path}")
            continue
        rc, n_raw, per, seen = inventory(path, fmt)
        inv[label], raw_counts[label], codes[label] = seen, n_raw, rc
        print(f"{label} exit={rc}  raw lines={n_raw}  deduplicated: "
              + "  ".join(f"{k} {v}" for k, v in sorted(per.items())))

    def cmp(a, b):
        ca, cb = inv.get(a), inv.get(b)
        if ca is None or cb is None:
            return
        only_a, only_b = sorted(ca - cb), sorted(cb - ca)
        print(f"\n{a} vs {b}: " + ("IDENTICAL" if not only_a and not only_b else
              f"{len(only_a)} only in the first, {len(only_b)} only in the second"))
        for lvl, msg in (only_a + only_b)[:12]:
            tag = "only first " if (lvl, msg) in only_a else "only second"
            print(f"    {tag} {lvl} {msg[:165]}")

    if len(sys.argv) == 1:
        cmp("orig txt    ", "r text      ")
        cmp("iarpa3 txt  ", "r iarpa3 txt")
        cmp("iarpa3 txt  ", "r iarpa3 jso")
        cmp("orig txt    ", "r json      ")


if __name__ == "__main__":
    main()
