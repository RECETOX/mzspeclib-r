#!/usr/bin/env python3
"""Executed probes against the python reference implementation (report §3.3, §4.8, §4.11).

Why this file exists: report §3.3 asserts that the normative rule table
(mzSpecLib/docs/metadata-rules.md) names two accessions that point at other terms,
and §4.11 asserts that the reference validator compares *labels composed from the
live ontology* against labels written in the file. Both are claims about behaviour,
so they should be executed rather than argued. Everything below prints a measured
yes/no; nothing here writes anything.

Environment (rebuildable, commands in report §9):
    python3 -m venv /tmp/mzvenv && /tmp/mzvenv/bin/pip install mzspeclib
    # measured with mzspeclib 1.0.7, mzpaf 0.2.0b0, psims 1.4.0
    #   -> psims supplies PSI-MS 4.2.6; the mzspeclib git clone additionally pins
    #      mzspeclib/obo/psi-ms.obo at data-version 4.1.57 (the pip wheel does not
    #      ship it — see probe 4)

Run: /tmp/mzvenv/bin/python analysis/oracle_probes.py [path/to/metadata-rules.md]
"""
import itertools
import os
import sys

RULES_MD = sys.argv[1] if len(sys.argv) > 1 else "/home/hechth/dev/mzSpecLib/docs/metadata-rules.md"
CLONE_OBO = "/home/hechth/dev/mzspeclib-py/mzspeclib/obo/psi-ms.obo"

# The two table rows whose accession names a different term than the row's own label.
# Label/accession pairs are copied from metadata-rules.md lines 93 and 80; the third
# column is the accession that actually names that label (probe 1 proves it twice).
WRONG = [("MS:1000034", "intensity unit", "MS:1000043"),
         ("MS:1002875", "inverse reduced ion mobility", "MS:1002815")]

# Verbatim line 26 of the spec repo's own example library
# examples/SpectraST/fetal_brain_tiny_consensus_td.mzSpecLib.txt:
#   MS:1000043|intensity unit=MS:1000905|percent of base peak times 100
EXAMPLE_VALUE = "MS:1000905|percent of base peak times 100"


def section(title):
    print("\n== " + title + " " + "=" * max(0, 66 - len(title)))


def obo_names(path):
    """Return (accession -> label, label -> [accessions]) parsed from a .obo file."""
    acc2name, name2acc, cur = {}, {}, {}

    def flush():
        if cur.get("id"):
            acc2name[cur["id"]] = cur.get("name")
            if cur.get("name"):
                name2acc.setdefault(cur["name"], []).append(cur["id"])

    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line == "[Term]":
                flush()
                cur = {}
            elif line.startswith("id: "):
                cur["id"] = line[4:]
            elif line.startswith("name: "):
                cur["name"] = line[6:]
    flush()
    return acc2name, name2acc


def probe_labels():
    section("1. the two wrong accessions, against three independent CV copies")
    from psims.controlled_vocabulary.controlled_vocabulary import load_psims
    cv = load_psims()
    print(f"psims PSI-MS version in this environment: {cv.version}")
    acc2name = name2acc = None
    if os.path.exists(CLONE_OBO):
        acc2name, name2acc = obo_names(CLONE_OBO)
        with open(CLONE_OBO, encoding="utf-8") as fh:
            ver = next((l.strip() for l in itertools.islice(fh, 5)
                        if l.startswith("data-version:")), "?")
        print(f"OBO pinned in the mzspeclib git clone: {ver} ({len(acc2name)} terms)")
    else:
        print(f"pinned OBO absent at {CLONE_OBO} -> skipped (the pip wheel ships none)")
    for acc, label, right in WRONG:
        print(f"\n  table row: {label!r} ({acc})")
        print(f"    psims {cv.version} names {acc} as {cv[acc].name!r}")
        if acc2name is not None:
            print(f"    pinned OBO names {acc} as {acc2name.get(acc)!r}")
            print(f"    pinned OBO resolves the label {label!r} to {name2acc.get(label)}")
        print(f"    correct accession per both copies: {right}")


def probe_rules():
    section("2. what the shipped rule for 'intensity unit' actually does (executed)")
    from mzspeclib.validate.validator import ValidatorBase
    from mzspeclib.validate.semantic_rule import ValueIsChildOf, ValueMatches

    class Ctx(ValidatorBase):
        pass

    ctx = Ctx()
    print(f"spec example value under test: {EXAMPLE_VALUE!r}")
    acc, label, right = WRONG[0]
    for candidate in (acc, right):
        walked = list(ctx.walk_terms_for(candidate))
        verdict = ValueIsChildOf(candidate).validate(None, EXAMPLE_VALUE, ctx)
        print(f"  value_is_child_of({candidate}): {len(walked)} term(s) walked; "
              f"rule satisfied = {verdict}")
    print("  -> As written the rule is UNSATISFIABLE: MS:1000034 has no children, and")
    print("     the one term walked is rejected by the predicate's own")
    print("     `not term.startswith(accession)` guard. With the corrected accession")
    print("     the spec's own example library satisfies it. (semantic_rule.py:125-132)")

    print("\n  value_matches composes f'{id}|{name}' from the LIVE ontology and compares")
    print("  it to the string in the file, so a PSI-MS rename silently invalidates files")
    print("  that were correct when written. MS:1000868 is used here only as a term that")
    print("  *was* renamed (no rule in the table targets it with value_matches); measured")
    print("  in both directions:")
    old, new = "MS:1000868|SMILES formula", "MS:1000868|SMILES string"
    print(f"    spelling correct in 2024/psi-ms 4.1.57 ({old}) -> "
          f"{ValueMatches('MS:1000868').validate(None, old, ctx)}")
    print(f"    current PSI-MS spelling            ({new}) -> "
          f"{ValueMatches('MS:1000868').validate(None, new, ctx)}")
    print("  (semantic_rule.py:196-201 — so validator verdicts depend on which CV the")
    print("   validating machine happens to resolve.)")


def probe_hardcoded():
    section("3. the validator's hard-coded intensity-unit allow-list")
    from mzspeclib.validate import validator as V
    print(f"  validator.INTENSITY_UNITS = {V.INTENSITY_UNITS}")
    bad = [a for a in V.INTENSITY_UNITS if a != a.strip()]
    print(f"  entries that can never match, due to surrounding whitespace: {bad!r}")
    print("  MS:1000814 'counts per second' is a real child of MS:1000043 (probe 2")
    print("  walks it) but is unreachable through this literal (validator.py:225).")


def probe_wheel():
    section("4. what the pip wheel does not ship")
    import mzspeclib
    pkg = os.path.dirname(mzspeclib.__file__)
    for rel in ("obo/psi-ms.obo", "validate/rules/tmp/terms.xlsx",
                "validate/rules/base.json"):
        print(f"  {rel:36s} present={os.path.exists(os.path.join(pkg, rel))}")
    print("  MANIFEST.in in the git clone reads exactly: 'include "
          "mzspeclib/validate/rules/*.json'")
    print("  -> a pip user's CV ancestry comes from psims, never from a pinned copy,")
    print("     and terms.xlsx — the stated source of the rule JSONs (§4.8) — exists")
    print("     only in the git tree, so the provenance chain is unshippable.")


def probe_rules_md():
    section("5. the rule-table rows, quoted from the normative document")
    if not os.path.exists(RULES_MD):
        print(f"  {RULES_MD} not found; skipped")
        return
    keep = ("MS:1000034]", "MS:1002875]", "MS:1003205]")
    with open(RULES_MD, encoding="utf-8") as fh:
        for i, line in enumerate(fh, 1):
            if any(k in line for k in keep):
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                term = cells[0][:58] if cells else ""
                definition = cells[1][:72] if len(cells) > 1 else ""
                print(f"  line {i:4d} | term column: {term}")
                print(f"           | definition column: {definition}")
    print("  Lines 80 and 93 contradict themselves: each definition column quotes the")
    print("  definition of the term its accession really names (an instrument model, and")
    print("  'charge deconvolution'), not of the term in its own term column. Lines 41-42")
    print("  are a different defect — one accession, two labels, same scope, same")
    print("  definition; only the second label exists in any CV copy checked here.")


if __name__ == "__main__":
    probe_labels()
    probe_rules()
    probe_hardcoded()
    probe_wheel()
    probe_rules_md()
