#!/usr/bin/env python3
"""Audit the surface labels in the spec's normative rule table against PSI-MS in OLS.

Why this exists: report §4.11 row 12 established that a reader must key on the
accession, never on the term name, because the corpus contains two surface labels
for one accession. That is a *corpus* problem. This script asks the sharper
question: does the normative table itself agree with the ontology it cites?

Method (all local + one HTTP call per accession, cached):
  1. parse every rule row of mzSpecLib/docs/metadata-rules.md -> (scope, level,
     surface label, accession, value-type cell text)
  2. for each distinct accession, fetch the OLS4 PSI-MS term: preferred label +
     synonyms
  3. classify: EXACT (label == OLS pref label) / SYNONYM (label is an OLS
     synonym) / MISMATCH (neither) / NOT_IN_OLS

Run:  python3 cv_label_audit.py [path/to/metadata-rules.md]
Cache: cv_label_audit_cache.json next to this script (delete to re-fetch).
"""
import json
import os
import re
import sys
import urllib.request

SPEC = "/home/hechth/dev/mzSpecLib/docs/metadata-rules.md"
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cv_label_audit_cache.json")

level_re = re.compile(r"^####\s+(MUST|SHOULD|MAY)\b")
scope_re = re.compile(r"^###\s+(.+)$")


def parse(md_path):
    """Return list of dicts: scope, level, label, accession.

    Accessions live inside markdown links ([MS:1000744](ols-url)) in table cells,
    so plain 'MS:\\d+' greps over-count (they also hit the value-type column). The
    rule row is identified by 'label ([ACC](url))' in the first cell.
    """
    rules, scope, level = [], "/", "-"
    for line in open(md_path, encoding="utf-8"):
        m = scope_re.match(line)
        if m:
            scope, level = m.group(1).strip(), "-"
            continue
        m = level_re.match(line)
        if m:
            level = m.group(1)
            continue
        if not line.startswith("|"):
            continue
        first = line.split("|")[1].strip()
        if not first or first.startswith("---") or first.lower().startswith("term"):
            continue
        am = re.search(r"\[(?P<acc>[A-Za-z]+:[0-9]+)\]\(", first)
        if not am:
            continue
        label = re.sub(r"\s*\(\[.*$", "", first).strip().strip("`")
        rules.append({"scope": scope, "level": level,
                      "label": label, "accession": am.group("acc")})
    return rules


def ols_term(acc, cache):
    if acc in cache:
        return cache[acc]
    local = acc.replace(":", "_")
    url = ("https://www.ebi.ac.uk/ols4/api/ontologies/ms/terms?iri="
           "http%3A%2F%2Fpurl.obolibrary.org%2Fobo%2F" + local)
    out = None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
        with urllib.request.urlopen(req, timeout=30) as fh:
            d = json.load(fh)
        t = d["_embedded"]["terms"][0]
        out = {"label": t["label"], "synonyms": list(t.get("synonyms") or [])}
    except Exception as exc:                       # noqa: BLE001
        out = {"label": None, "synonyms": [], "error": str(exc)}
    cache[acc] = out
    return out


def main():
    md = sys.argv[1] if len(sys.argv) > 1 else SPEC
    rules = parse(md)
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    accs = sorted({r["accession"] for r in rules})
    print(f"parsed {len(rules)} rule rows, {len(accs)} distinct accessions from {md}")

    buckets = {"EXACT": [], "SYNONYM": [], "MISMATCH": [], "NOT_IN_OLS": []}
    norm = lambda s: re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()  # noqa: E731
    for acc in accs:
        info = ols_term(acc, cache)
        labels = {r["label"] for r in rules if r["accession"] == acc}
        if info.get("label") is None:
            buckets["NOT_IN_OLS"].append((acc, sorted(labels), info.get("error", "")))
            continue
        pref = norm(info["label"])
        syns = {norm(s) for s in info["synonyms"]}
        for lab in sorted(labels):
            if norm(lab) == pref:
                buckets["EXACT"].append((acc, lab, info["label"]))
            elif norm(lab) in syns:
                buckets["SYNONYM"].append((acc, lab, info["label"]))
            else:
                buckets["MISMATCH"].append((acc, lab, info["label"]))

    json.dump(cache, open(CACHE, "w"), indent=1, sort_keys=True)

    print(f"\nEXACT pref-label match : {len(buckets['EXACT'])}")
    print(f"OLS synonym            : {len(buckets['SYNONYM'])}")
    print(f"MISMATCH (neither)     : {len(buckets['MISMATCH'])}")
    print(f"accession absent from OLS PSI-MS : {len(buckets['NOT_IN_OLS'])}")

    print("\n-- MISMATCH detail (normative label vs current PSI-MS label) --")
    for acc, lab, ols in sorted(buckets["MISMATCH"]):
        scopes = sorted({r["scope"] for r in rules if r["accession"] == acc})
        print(f"  {acc}  table says {lab!r}  PSI-MS says {ols!r}   [{' '.join(scopes)}]")
    print("\n-- absent from PSI-MS (UO/NCBITaxon/other ontology expected) --")
    for acc, labs, err in sorted(buckets["NOT_IN_OLS"]):
        print(f"  {acc}  {sorted(labs)}  ({err[:60]})")
    print("\n-- accessions the table uses under more than one surface label --")
    for acc in accs:
        labs = sorted({r["label"] for r in rules if r["accession"] == acc})
        if len(labs) > 1:
            print(f"  {acc}: {labs}")


if __name__ == "__main__":
    main()
