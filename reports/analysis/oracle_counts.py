#!/usr/bin/env python3
"""Oracle side of the §4.3 count comparison: the same six numbers as proto_reader.R,
computed by the *reference implementation* rather than by my reader.

This is the shape milestone 0's fixture harness will need. For each spec example
library it prints (header CV lines, spectra, mean peaks/spectrum, analyte sections,
interpretation sections, attribute-set sections) three ways:

  raw    — counted off the text with a regex, mediated by no library at all
  python — from mzspeclib's own object graph
  (R)    — run `Rscript analysis/proto_reader.R` and read its six columns

Three outputs instead of two because a two-way disagreement is uninterpretable: when
my R reader and python differ, the raw count says which of us dropped something.

Run:  /tmp/mzvenv/bin/python analysis/oracle_counts.py
Then: Rscript analysis/proto_reader.R

Two rules this script had to learn the hard way, both of them the §4.3 class of trap,
and both recorded here because each one produced a confidently wrong number first:

  hdr       "library-level CV lines" is NOT "CV lines before the first <Spectrum>".
            Every example file puts its <AttributeSet Spectrum=all> / Analyte=all /
            Interpretation=all blocks before the first spectrum, so a counter that
            keeps counting until <Spectrum> over-reads the library scope by 2 of 4
            lines in spice.mzSpecLib.txt and 17 of 12 in fetal_brain_tiny. The header
            scope ends at the first section line that is not itself library-scoped.
  attrsets  the reference implementation does not expose the sets it parsed through
            .attribute_sets (that is the *reference* attribute, `MS:1003205|attribute
            set=...`, resolved via attributes.py:470). The parsed definitions live in
            four per-scope dicts on the backend — spectrum/analyte/
            interpretation/cluster_attribute_sets — each of which is pre-seeded with
            an "all" entry (base.py:219-230) whether or not the file defines one. So
            python's attrsets is a different quantity from "lines starting with
            '<AttributeSet'", and the pre-seed is why it can exceed the raw count.
            Both numbers are printed; the per-scope names are printed too so the
            pre-seed is visible rather than inferred.
"""
import os
import re
import sys

EXAMPLES = "/home/hechth/dev/mzSpecLib/examples"
FILES = [
    "spice.mzSpecLib.txt",
    "NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.txt",
    "SpectraST/fetal_brain_tiny.mzSpecLib.txt",
    "NIST-CPTAC/broad_tcga_nonphospho_consensus_rec.head.mzSpecLib.txt",
    "DIA-NN/phl004_canonical_sall_pv_plasma.head.diann.mzSpecLib.txt",
    "Spectronaut/human_serum.head.spectronaut.mzSpecLib.txt",
]

# `[A-Za-z]+` then a delimiter. The delimiter class MUST include a space: the
# AttributeSet form is `<AttributeSet Spectrum=all>`, with a space before the
# qualifier, and a regex that demands '=' or '>' right after the name sees zero
# attribute sets in a file that defines four. (The reference implementation uses a
# dedicated regex for exactly this form — text.py:77 — so the space is syntax, not
# sloppiness in the examples.)
SECTION_RE = re.compile(r"^<([A-Za-z]+)([=>\s]|$)")
CV_RE = re.compile(r"^(MS:|UO:|NCBITaxon:|\[[0-9]+\]MS:)")


def raw_counts(path):
    """Counts taken straight off the text, mediated by no library at all."""
    hdr = analytes = interpretations = attrsets = spectra = 0
    peaks = 0
    in_peaks = in_header = False
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            m = SECTION_RE.match(line)
            if m:
                name = m.group(1)
                # Only <mzSpecLib> opens the library scope; <AttributeSet ...> and
                # everything else closes it (see the hdr note in the docstring).
                in_header = name == "mzSpecLib"
                in_peaks = name == "Peaks"
                if name == "Spectrum" and m.group(2) == "=":
                    spectra += 1
                elif name == "Analyte":
                    analytes += 1
                elif name == "Interpretation":
                    interpretations += 1
                elif name == "AttributeSet":
                    attrsets += 1
                continue
            if in_peaks and re.match(r"^[0-9]", line):
                peaks += 1
            elif in_header and CV_RE.match(line):
                hdr += 1
    return dict(hdr=hdr, spectra=spectra, peaks=peaks, analytes=analytes,
                interpretations=interpretations, attrsets=attrsets)


def py_counts(path):
    """Same quantities from the reference implementation's object graph."""
    from mzspeclib.backends import TextSpectralLibrary
    lib = TextSpectralLibrary(path)
    lib.read_header()
    scopes = {
        "spectrum": lib.spectrum_attribute_sets,
        "analyte": lib.analyte_attribute_sets,
        "interpretation": lib.interpretation_attribute_sets,
        "cluster": lib.cluster_attribute_sets,
    }
    out = dict(hdr=len(lib.attributes), spectra=0, peaks=0, analytes=0,
               interpretations=0, attrsets=sum(len(d) for d in scopes.values()))
    for sp in lib.read():
        out["spectra"] += 1
        out["peaks"] += len(sp.peak_list)
        out["analytes"] += len(list(sp.analytes))
        out["interpretations"] += len(list(sp.interpretations))
    return out, {k: sorted(d.keys()) for k, d in scopes.items()}


def main():
    try:
        import mzspeclib
    except ImportError:
        sys.exit("needs the reference implementation: "
                 "python3 -m venv .venv && .venv/bin/pip install mzspeclib")
    print(f"# reference implementation "
          f"{getattr(mzspeclib, '__version__', 'version not exposed')}")
    print("# columns match analysis/proto_reader.R: "
          "hdr spectra peaks/spec analytes interpretations attrsets")
    agree = differ = 0
    cols = ("hdr", "spectra", "analytes", "interpretations", "attrsets")
    for rel in FILES:
        path = os.path.join(EXAMPLES, rel)
        if not os.path.exists(path):
            print(f"MISSING {rel}")
            continue
        raw = raw_counts(path)
        try:
            py, scopes = py_counts(path)
        except Exception as exc:                                    # noqa: BLE001
            print(f"{os.path.basename(rel):58s} python reader FAILED: "
                  f"{type(exc).__name__}: {str(exc)[:90]}")
            continue
        mean_pk = py["peaks"] / py["spectra"] if py["spectra"] else 0.0
        print(f"{os.path.basename(rel):58s} hdr={py['hdr']:3d} spectra={py['spectra']:3d} "
              f"peaks/spec={mean_pk:5.0f} analytes={py['analytes']:3d} "
              f"interpretations={py['interpretations']:2d} attrsets={py['attrsets']}")
        print("      sets defined per scope: " + " ".join(
            f"{k}:{v}" for k, v in scopes.items()))
        for key in cols:
            if raw[key] == py[key]:
                agree += 1
            else:
                differ += 1
                print(f"    !! {key}: raw text = {raw[key]}, python exposes = {py[key]}"
                      f"   (raw peaks = {raw['peaks']}, python peaks = {py['peaks']})")
    print(f"# raw text vs python, {len(cols)} columns x {len(FILES)} files: "
          f"{agree} agree / {differ} differ")
    print("# peaks/spectrum is deliberately excluded above: python reports parsed peak "
          "objects, the raw counter counts numeric lines inside <Peaks>, and the two "
          "quantities coincide only because no example uses a peak-list comment or a "
          "multi-line m/z-intensity pair.")


if __name__ == "__main__":
    main()
