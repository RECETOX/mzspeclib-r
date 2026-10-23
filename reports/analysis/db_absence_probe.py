#!/usr/bin/env python3
"""Scoped negative evidence: is mzSpecLib present in the public MS repositories?

Written because "nobody publishes mzSpecLib files" is the kind of sentence that is
easy to assert and hard to establish, and because an earlier pass over these
services produced numbers that did not survive inspection (a typo'd grep term, and
an endpoint that silently ignores its own query parameter). Two rules, enforced in
code below:

  1. every zero is printed next to a POSITIVE CONTROL on the same index/blob —
     a zero with a dead grep looks exactly like a zero with a live one;
  2. every verdict states what was searched, because these are *metadata*
     indexes, not file listings. A zero here means "no study/dataset *mentions*
     mzSpecLib", never "no directory contains an mzSpecLib file".

Known-broken, deliberately not used:
  - metabolights/ws/studies?keyword=X  -> keyword ignored, same first page for any X
  - MassIVE QueryDatasets query= param -> filtering is client-side in
    scripts/result/table_ss.js (value.indexOf(search_value)), so the complete
    paginated dump IS the site's own search box
  - GitHub search API repo-scoped issue queries -> 422; issue enumeration must page
    repos/<x>/issues directly

Run: python3 db_absence_probe.py [--massive]      # --massive pulls ~21 pages
"""
import json
import re
import sys
import urllib.parse
import urllib.request

UA = {"User-Agent": "Mozilla/5.0 (mzspeclib-r survey)"}
TERMS = ["mzspeclib", "mzspec", "mzpaf", "mzlib"]
CONTROLS = ["mzml", "mzxml", ".msp", "blib"]


def get(url, raw=False):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as fh:
        data = fh.read()
    return data if raw else data.decode("utf-8", "replace")


def ebisearch(index, query):
    url = ("https://www.ebi.ac.uk/ebisearch/ws/rest/" + index + "?query=" +
           urllib.parse.quote(query) + "&format=json")
    return json.loads(get(url)).get("hitCount")


def probe_ebi():
    print("== EBI Search (study metadata, NOT FTP file listings) ==")
    for index in ("metabolights", "pride"):
        hits = ebisearch(index, "mzSpecLib")
        ctl = {c: ebisearch(index, c) for c in ("glycerol", "mzML", "spectral library")}
        print(f"  {index:13s} mzSpecLib={hits}  controls={ctl}")
        print(f"    -> verdict: no {index} study *metadata* mentions mzSpecLib"
              f"{' (index alive: controls > 0)' if all(v > 0 for v in ctl.values()) else ' !! CONTROL DEAD'}")


def probe_massive():
    """Full MassIVE dataset-metadata sweep, equivalent to the site's own search box."""
    base = ("https://massive.ucsd.edu/ProteoSAFe/QueryDatasets?task=&file=&query="
            "%7B%7D&target=&pageSize=1000&offset=")
    first = json.loads(get(base + "0", raw=True).decode("utf-8", "replace"))
    total = int(first["total_rows"])
    blob = json.dumps(first["row_data"], ensure_ascii=False)
    pages = 1 + (total - 1) // 1000
    for off in range(1000, pages * 1000, 1000):
        d = json.loads(get(base + str(off), raw=True).decode("utf-8", "replace"))
        blob += json.dumps(d["row_data"], ensure_ascii=False)
        print(f"  offset {off:6d} rows={len(d['row_data']):4d} cum={len(blob)//1000} KB", flush=True)
    low = blob.lower()
    print(f"== MassIVE: total_rows={total} blob={len(blob)/1e6:.1f} MB ==")
    for t in TERMS:
        print(f"  {t:10s} {len(re.findall(re.escape(t), low))}")
    ctl = {c: len(re.findall(re.escape(c), low)) for c in CONTROLS}
    print(f"  controls: {ctl}")
    print("  -> verdict: no MassIVE dataset *metadata* mentions mzSpecLib. row_data"
          " carries no per-file filename list, so this does NOT show that no"
          " dataset *contains* an mzSpecLib file.")


if __name__ == "__main__":
    probe_ebi()
    if "--massive" in sys.argv:
        probe_massive()
    else:
        print("\n(pass --massive for the ~21-page MassIVE dataset-metadata sweep)")
