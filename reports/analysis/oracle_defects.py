#!/usr/bin/env python3
# How to run:  /tmp/mzvenv/bin/python oracle_defects.py
#   Expects: the venv of report section 9 (mzspeclib 1.0.7 at /tmp/mzvenv), the R
#   package at /home/hechth/dev/mzspeclib-r (Rscript + pkgload, for the writer
#   side of probes 2-4), and the spec repo at ~/dev/mzSpecLib. Runtime a few
#   minutes: probes 1-3 never load the ontology, probe 4 runs the CLI twice.
"""Executed probes for the reference-implementation defects report §4.15 records.

Each probe prints a measured yes/no; nothing outside a temporary directory is
written. Sources cited by line number are the installed mzspeclib 1.0.7 under
/tmp/mzvenv, which `diff -q` confirmed byte-identical to the git clone at
~/dev/mzspeclib-py for backends/json.py and backends/text.py.

  1 JSONSpectralLibrary.read_header() APPENDS to the attributes it already holds
    (read_header at json.py:108-124 calls _fill_attributes, json.py:188-222, and
    the constructor auto-calls read_header at json.py:86), while the text backend
    builds a fresh list and clears before installing it (text.py:587-588) and is
    idempotent. The reported header-attribute count therefore doubles per extra
    JSON read_header() call: 15 -> 30 (the R package's example library) and
    634 -> 1268 (the NIST IARPA3 head library).
  2 The JSON writer emits analyte/interpretation ids as the python objects the
    reader produced — strings after a text read (json.py:449-463) — while the
    schema types them integer (mzSpecLib_json.schema.json:146-148). The reader
    compares the object key with the id member, `analyte_id != analyte_d.get("id")`
    (json.py:225-227, 232-235), and JSON object keys are always strings, so the
    "does not match its key" warning fires only when the id is an integer, i.e.
    only for schema-conformant documents such as the R writer's output, and never
    for python's own files.
  3 cvparam "value" is read unguarded (json.py:133 in create_index, json.py:220
    in _fill_attributes) although the schema makes the member optional (cvparam
    required = [accession, name], schema:56) -> KeyError on a schema-legal
    document that omits it. The probe prints whichever frame fires first.
  4 The declared value type of a CV term, not the file's text, decides whether a
    JSON value must be a number or a string: taking the R writer's JSON (which
    keeps every value as written, since R resolves nothing against an ontology)
    and replacing the three version terms' strings with numbers makes the gold
    profile add exactly three MUST violations (MS:1003186, MS:1003190,
    MS:1003200, all xsd:string in psi-ms 4.2.6), while the same file left alone
    earns the xsd:float/xsd:double "but got <class 'str'>" family for terms the
    ontology types numerically.
  5 Two comment rules collide. Spec 4.1.1: "The plain-text serialization of a
    spectral library MUST begin with the line: <mzSpecLib>" — the reference parser
    enforces exactly that and nothing more (text.py:473-483, falling through to
    "return False, 0" at text.py:590), so a file whose first line is a comment
    fails read_header() silently and dies in read() with ValueError "Could not
    locate valid header" (base.py:522). The R package's example library carries a
    provenance comment block before the magic line, so the reference cannot read
    it — but by 4.1.1 the file, not the reader, is the non-conformant side.
    Spec 4.1.18, on the other hand, permits a comment on "a line beginning with
    the # character" with no placement restriction, yet a comment one line AFTER
    <mzSpecLib> kills the header parser with ValueError "Malformed attribute
    line" (text.py:577) while the spectrum parser skips comments (text.py:408).
  6 The interoperability counts of report §4.15 item 1, taken through the
    reference implementation itself (read_header + read, len(attributes) /
    spectra / peak_list / analytes / interpretations) for the originals and for
    what the R reader+writer pair reproduces of them.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import warnings

sys.path.insert(0, "/tmp/mzvenv/lib/python3.12/site-packages")
from mzspeclib.backends.json import JSONSpectralLibrary      # noqa: E402
from mzspeclib.backends.text import TextSpectralLibrary      # noqa: E402

EX = "/home/hechth/dev/mzSpecLib/examples"
TXT_BIG = f"{EX}/NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.txt"
JSON_BIG = TXT_BIG[:-4] + ".json"
TXT_ORIG = f"{EX}/SpectraST/fetal_brain_tiny_consensus_td.mzSpecLib.txt"
TXT_SMALL = "/home/hechth/dev/mzspeclib-r/inst/extdata/example.mzSpecLib.txt"
CLI = ["/tmp/mzvenv/bin/python", "-m", "mzspeclib.tools.cli", "validate",
       "-p", "gold", "-i", "mzSpecLib.json"]

tmp = tempfile.mkdtemp(prefix="mzspeclib-oracle-defects-")
r_small = os.path.join(tmp, "r_example.json")
r_big = os.path.join(tmp, "r_iarpa3.json")
r_small_txt = os.path.join(tmp, "r_example.txt")
r_big_txt = os.path.join(tmp, "r_iarpa3.txt")
rscript = (
    'pkgload::load_all("/home/hechth/dev/mzspeclib-r", quiet = TRUE)\n'
    f'write_mzspeclib(read_mzspeclib("{TXT_SMALL}"), "{r_small}")\n'
    f'write_mzspeclib(read_mzspeclib("{TXT_SMALL}"), "{r_small_txt}")\n'
    f'write_mzspeclib(read_mzspeclib("{TXT_BIG}"), "{r_big}")\n'
    f'write_mzspeclib(read_mzspeclib("{TXT_BIG}"), "{r_big_txt}")\n'
)
subprocess.run(["Rscript", "-e", rscript], capture_output=True, check=True)

# -- probe 1: read_header() appends ---------------------------------------------
print("probe 1 — JSONSpectralLibrary.read_header() appends; text is idempotent")
for label, path in (("IARPA3 head json", JSON_BIG), ("R-written example json", r_small)):
    lib = JSONSpectralLibrary(path)          # constructor calls read_header once
    a = len(lib.attributes)
    lib.read_header()                        # one more call
    b = len(lib.attributes)
    print(f"  json  {label:24s} {a} -> {b} after one explicit read_header()")
tl = TextSpectralLibrary(TXT_ORIG)     # consensus_td, whose first line is <mzSpecLib>;
                                       # TXT_SMALL cannot be used here — probe 5 says why
counts = [len(tl.attributes)]
tl.read_header(); counts.append(len(tl.attributes))
tl.read_header(); counts.append(len(tl.attributes))
print(f"  text  consensus_td, len(attributes) after 0/1/2 explicit calls: {counts}")

# -- probe 2: string ids vs schema integers --------------------------------------
print("\nprobe 2 — 'does not match its key' fires only for schema-conformant ids")

def read_counting_warnings(path):
    hits = []
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        n = sum(len(sp.analytes) for sp in JSONSpectralLibrary(path).read())
    for w in caught:
        if "does not match its key" in str(w.message):
            hits.append(str(w.message))
    return n, hits

for label, path in (("python's own json ", JSON_BIG), ("R writer's json   ", r_big)):
    doc = json.load(open(path))
    id_types = {type(a["id"]).__name__
                for sp in doc["spectra"] for a in sp["analytes"].values()}
    key_types = {type(k) for sp in doc["spectra"] for k in sp["analytes"]}
    n, hits = read_counting_warnings(path)
    print(f"  {label} ids {id_types}, keys {key_types}, {n} analytes, "
          f"{len(hits)} mismatch warnings"
          + (f"\n      e.g. {hits[0]!r}" if hits else ""))

# -- probe 3: optional value member raises KeyError ------------------------------
print("\nprobe 3 — cvparam without 'value' (schema-legal) raises KeyError")
doc = json.load(open(r_small))
for a in doc["spectra"][0]["attributes"]:
    a.pop("value", None)
try:
    lib = JSONSpectralLibrary(doc)          # the class accepts an in-memory Mapping
    lib.read_header()
    print("  no exception (unexpected)")
except KeyError as e:
    tb = sys.exc_info()[2]
    last = tb
    while last.tb_next:
        last = last.tb_next
    import linecache
    print(f"  KeyError: {e} at {os.path.basename(last.tb_frame.f_code.co_filename)}"
          f":{last.tb_lineno}  "
          f"({last.tb_frame.f_code.co_filename.split('site-packages/')[-1]} "
          "reads attrib[\"value\"] unguarded; schema:56 requires only "
          "accession+name; the line content: "
          f"{linecache.getline(last.tb_frame.f_code.co_filename, last.tb_lineno).strip()!r})")

# -- probe 4: the version terms' declared types live only in the ontology --------
print("\nprobe 4 — numeric 1.0 for the version terms adds exactly 3 MUST violations")
VERSIONS = ("MS:1003186", "MS:1003190", "MS:1003200")

def violations(path):
    r = subprocess.run(CLI + [path], capture_output=True, text=True)
    seen = set()
    for l in (r.stderr + r.stdout).splitlines():
        m = re.search(r"\((MUST|SHOULD|MAY)\)", l)
        if m:
            # strip the wall-clock timestamp, logger name and source location,
            # and the '... ' the __main__ echo prefixes — see report §4.15 item 3
            body = re.sub(r"^\[\d+:\d+:\d+\] \w \| [^|]+\| [^|]+\| ", "", l)
            seen.add((m.group(1), re.sub(r"\s+", " ", body.lstrip(". ").strip())))
    return r.returncode, seen

rc, base = violations(r_small)
base_ver = {v for v in base if any(a in v[1] for a in VERSIONS)}
num = json.load(open(r_small))
changed = 0
for a in num["attributes"]:
    if a.get("accession") in VERSIONS and isinstance(a.get("value"), str):
        try:
            a["value"] = float(a["value"])
            changed += 1
        except ValueError:
            pass
r_num = os.path.join(tmp, "numeric_versions.json")
json.dump(num, open(r_num, "w"))
rc2, got = violations(r_num)
ver = {v for v in got if any(a in v[1] for a in VERSIONS)}
new = ver - base_ver
print(f"  values numericised: {changed} (MS:1003186 '1.0', MS:1003190 '1.0', "
      "MS:1003200 '6.0')")
print(f"  exit codes: base {rc}, numericised {rc2} (0 despite MUST failures)")
print(f"  violations naming a version term: base {len(base_ver)}, "
      f"numericised {len(ver)}, new {len(new)}")
for lvl, msg in sorted(new):
    print(f"    {lvl}: {msg[:160]}")
must_base = sum(1 for v in base if v[0] == "MUST")
must_num = sum(1 for v in got if v[0] == "MUST")
print(f"  whole inventory (deduplicated): MUST {must_base} -> {must_num}, "
      "the delta being exactly the three above")
print("  '1.0' as text is indistinguishable from '39.0' as text; which one must "
      "stay a string is the CV term's declared value type (xsd:string for the "
      "version terms, xsd:float for collision energy) — held in the ontology, "
      "not in the file")

# -- probe 5: comments per spec 4.1.18, first line vs inside the header -----------
print("\nprobe 5 — comments: a leading one fails the reader (and violates 4.1.1); "
      "a header one crashes it (against 4.1.18)")
lead = TXT_SMALL                       # example library: provenance block first
first = open(lead).readline()
lib5 = TextSpectralLibrary(lead)
rh = lib5.read_header()
try:
    list(lib5.read())
    readres = "read() succeeded (unexpected)"
except ValueError as e:
    readres = f"read() -> ValueError: {e}"
print(f"  first line {first.strip()!r}: read_header() -> {rh}, attributes "
      f"{len(lib5.attributes)}, {readres}")
mid = os.path.join(tmp, "comment-in-header.mzSpecLib.txt")
with open(TXT_ORIG) as src:
    body = src.read().split("<mzSpecLib>", 1)[1]
with open(mid, "w") as dst:
    dst.write("<mzSpecLib>\n# a legal comment, one line later\n" + body.lstrip("\n"))
try:
    TextSpectralLibrary(mid).read_header()
    print("  comment inside the header: read_header() succeeded (unexpected)")
except ValueError as e:
    print(f"  comment inside the header: read_header() -> ValueError: {str(e)[:60]}")
no_comment = 0
n_txt = 0
for dirpath, _, names in os.walk(EX):
    for name in names:
        if name.endswith(".mzSpecLib.txt"):
            n_txt += 1
            with open(os.path.join(dirpath, name)) as fh:
                no_comment += fh.readline().startswith("<mzSpecLib>")
print(f"  spec examples dodging this: {no_comment}/{n_txt} .txt files start with "
      "<mzSpecLib> as their very first line")

# -- probe 6: interoperability counts through the reference implementation --------
print("\nprobe 6 — counts the reference implementation reports for original vs R-written")

def counts6(path, kind):
    lib = (TextSpectralLibrary(path) if kind == "txt" else JSONSpectralLibrary(path))
    lib.read_header()                    # once, on top of whatever the constructor did
    sps = list(lib.read())
    return (len(lib.attributes), len(sps), sum(len(sp.peak_list) for sp in sps),
            sum(len(sp.analytes) for sp in sps), sum(len(sp.interpretations) for sp in sps))

rows = [
    ("iarpa3 original txt", TXT_BIG, "txt"),
    ("iarpa3 R-written txt", r_big_txt, "txt"),
    ("iarpa3 R-written json", r_big, "json"),
    ("example original txt ", TXT_ORIG, "txt"),
    ("example R-written txt", r_small_txt, "txt"),
    ("example R-written jso", r_small, "json"),
]
for label, path, kind in rows:
    hdr, ns, np_, na, ni = counts6(path, kind)
    print(f"  {label}: header attrs {hdr}, spectra {ns}, peak rows {np_}, "
          f"analytes {na}, interpretations {ni}")
print("  (the JSON header would double again on each further explicit "
      "read_header() — probe 1; counts above show one constructor + one call)")

shutil.rmtree(tmp, ignore_errors=True)
