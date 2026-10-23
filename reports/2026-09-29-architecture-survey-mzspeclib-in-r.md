# Should R get a standalone mzSpecLib package, or a Spectra backend directly?

**A survey and architecture recommendation for `mzspeclib-r`**

Date: 2026-09-29, revised twice on 2026-10-22 and again on 2026-10-23 (§4.15's
rule-set counts, §8.2 rows g–i) · Status: research report; the package it
recommends has since been built and checked — `mzspeclib` 0.1.0, dated
2026-10-22, unpublished (§6, §9)
Author: Claude (researcher profile), for Helge Hecht (Masaryk University), the
package's sole author

**What changed in the 2026-10-22 revision, in one paragraph.** Eight things, all of
them material: the standard is **ratified** (2025-08-07), not DRAFT (§3.3); an R
backend for this exact purpose **now exists** in the RfMS org, which converts
Option B from hypothetical to live and narrows the decision to one question (§4.12,
§6); a **99 GB real mzSpecLib corpus** was located, so the "no large library to
benchmark against" objection is gone (§4.13); equally, **no public MS repository
distributes mzSpecLib files at all**, which turns that finding's opposite into a
constraint on the test strategy (§4.14, §6 milestone 0); the normative rule table
was audited term-by-term against PSI-MS and contains two hard accession/label
errors (§3.3); the rule-file provenance was traced to its end (§4.8); two of my own
headline claims did not survive re-measurement — the JSON `simplifyVector` speed
claim and the characterisation of `mzspeclib-rs` — and one whole section was
re-measured on a checked-in generator (§4.7); and all six open questions moved, four
to closure (§8). Numbers previously quoted from a lost `/tmp` corpus are re-derived
from `analysis/bench_gen.R`. A second measurement pass the same day, run after the
package's first release, added §4.15: the reference implementation turned against
what the R package writes (six executed probes, four reference-side defects, counts
and gold-profile violation inventories identical for the text serialization), a
corrected PSI-MS copy census, and a counting-tool sweep whose headline is that two
of its own leads — five disagreeing tools, gzipped twins in the spec tree — did
*not* reproduce, and are recorded as not reproducing.

Reproducible artefacts for every measured number: [`analysis/`](analysis/) in this
directory. R: `mapping_gap.R`, `proto_reader.R`, `loss_experiment.R`, `bench_gen.R`,
`bench2.R`, `json_modes.R`. Python: `cv_label_audit.py` (carries a cache of its OLS
responses, so it re-runs offline), `oracle_probes.py` (probes *executed* against the
installed `mzspeclib` 1.0.7 — §3.3's accession errors and §4.11 rows 13–14; needs the
python environment of §9), `oracle_counts.py` (the same six counts from the reference
implementation's object graph plus a regex pass over the raw text — the three-way
comparison §4.3 and §4.11 row 5 rest on), `db_absence_probe.py` (the control-checked
repository negatives in §4.14, deliberately *not* cached), `oracle_defects.py` (the
six executed probes of §4.15 — `read_header()` append semantics, string-vs-integer
ids, the schema-optional `value` member, ontology-driven value typing, comment
lines, and the reference-implementation counts behind the interoperability claim —
needs the python environment of §9 plus `pkgload`) and `viol_inventory.py` (the
normalised gold-profile violation inventories of §4.15; turns the CLI's double
output and wall-clock timestamps from folklore into code). Shell:
`tool_tree_grep.sh` (the five-tool whole-tree negatives in §4.14, with live
controls; ~200 MB of downloads) and `count_tool_sweep.sh` (the five-tool whole-tree
*positives* of §4.15 item 4, which reports honestly when a tool is absent). §9
lists what each needs installed and which measurements were made in environments
that no longer exist on this machine.

---

## 1. Executive summary

**Recommendation: build the format core as its own package, and put it *under*
the backend that already exists rather than building a rival one.** (Revised
2026-10-22: the first draft said "build both, in two packages, core first" — the
core half of that survives unchanged; the backend half was overtaken by
`RforMassSpectrometry/MsBackendMzSpecLib`, §4.12.)

The decision question was framed as a binary: a raw R implementation of the
mzSpecLib standard (package 1) with a second package providing a `Spectra`
backend on top of it, versus implementing the backend directly without the
intermediate. The evidence does not support the second option, and it does not
support the first option *alone* either. Two findings drive this:

1. **Spectra's data model can carry only ~12–29 % of the metadata that real
   mzSpecLib files actually contain** (measured on all 8 real `.mzSpecLib.txt`
   libraries shipped in the specification repository — 7 unique, one is
   byte-identical in two directories; §4.2). Everything else —
   analytes, interpretations, CV accessions, provenance, aggregation lineage,
   CV parameter *groups*, and the entire library header — has no representation
   in `Spectra`. A backend-only implementation would therefore have to invent a
   parallel private representation of the standard *inside* the backend package
   anyway. That is the intermediate, just unlabelled and undocumented.

2. **A single package cannot implement an `MsBackend` without a hard dependency
   on Spectra.** This is not an opinion; I tested it and installation fails
   (`§4.4`). So "backend directly, no intermediate" does not merely couple the
   code to Spectra — it makes Spectra a prerequisite for *anyone* who wants to
   read an mzSpecLib file in R, including Galaxy/CLI users where that is not
   even installable (§4.5).

The honest counterweight: **RforMassSpectrometry convention is strongly against
the split.** Every existing text/SQL backend package implements its format parser
in-package and exports the low-level reader; none imports a standalone format
package. The whole backend ecosystem is small — Spectra's own (self-described as
"possibly incomplete") README lists 18 backend classes across 13 packages, only 4
of which ship inside Spectra, and just 6 of the 12 external hosts are in
Bioconductor 3.18 at all (§4.6).
Note, though, that this convention argues against a *third* package rather than
against a format layer — and `mzR`, the ecosystem's flagship format, is exactly
"standalone format package + thin backend" (§4.6).

**Correction to this paragraph in the first draft**, because it was the load-bearing
part of the risk assessment and it is now simply wrong: I wrote *"There is no
demand-side pull today: nobody has asked for R support in either HUPO-PSI repo"*,
and concluded the backend was "a genuine bet, not a safe deliverable".
`RforMassSpectrometry/MsBackendMzSpecLib` now exists **inside the RfMS org**
(§4.12), and the standard's own text invites non-python implementations (§8.1 Q1).
The demand risk is gone; a different risk took its place — **building the same
parser twice** (§7). That is why the recommendation below is now phrased as
"build the core, offer it upstream", and why the coordination question (§8.2 b)
has to be asked before any code.

**A third finding the decision hinges on, which neither option was framed
around:** the model is stable — mzSpecLib v1.0 was **ratified 2025-08-07** (§3.3) —
but the standard's *supporting artefacts* disagree with the standard and with each
other, and the reference implementation does not conform to the thing it
implements. I measured that
`mzspeclib validate` **exits 0 even when MUST rules fail**, that the spec's *own
example files* fail 12–20 MUST rules under the `gold` profile, that its largest
rule set (`all.json`, 99 rules) **cannot be loaded by its own loader**, and that
the normative mzPAF grammar and the parser python actually uses accept **different
languages** (the grammar has no `w`/`v`/`d` ion series; the regex does). All of
that lives in the *format*, not in the Spectra mapping — which is precisely the
layer option B hides inside a backend (§4.11).

**What to build, concretely:**

| Order | Package | Depends | Purpose | Rough size |
|---|---|---|---|---|
| **0** | *one issue on `RforMassSpectrometry/MsBackendMzSpecLib`, three questions to the mzSpecLib maintainers* | — | ask whether they want a parser + conformance fixtures upstream (§8.2 a,b) | 0 LOC — and it decides the shape of everything below |
| 1 | `mzspeclib` | nothing heavy (`jsonlite`) | read/write/validate the standard, no Spectra knowledge; usable as an engine by someone else's backend | ~3.5–6.5k LOC |
| 2 | backend layer over package 1 | `Spectra` | thin `MsBackend`, lossy-by-design + a written loss list — **as a PR to the existing `MsBackendMzSpecLib` if they want it, otherwise as this project's own** | ~0.4–1.5k LOC, or 0 |

Package 1 is independently useful, testable and CRAN-shaped from day one:
milestones 1–5 give a text↔JSON converter and a validator with no Spectra
involvement at all. Package 2 is cheap (3–10 S4 methods is the documented
precedent) and can be dropped, deferred, or handed to the existing repo without
invalidating package 1. The dependency order is what makes either outcome
affordable — which is the real reason to keep the split now that the backend itself
is no longer in question.

---

## 2. Scope, method, and how to read this

Sources consulted:

- `/home/hechth/dev/mzSpecLib` — HUPO-PSI specification repo (normative PDF v1.0,
  cover page 2025-05-23, 36 pp. — the cover still prints `Status: DRAFT` while the
  document's own "Status of this document" section and psidev.info both record
  **ratified 2025-08-07**, see §3.3; JSON Schema draft-07; `annotation.lark`;
  `docs/metadata-rules.md`; the dead
  `.github/workflows/scripts/generate_metadata_docs.py` (§4.8); 12 example files: 8
  `.mzSpecLib.txt` (7 unique — `broad_tcga_…` is byte-identical under `NIST/` and
  `NIST-CPTAC/`, md5 `e9513ed1…`), 2 `.json`, plus the `.msp`/`.tsv` vendor
  originals).
- `/home/hechth/dev/mzspeclib-py` — python reference implementation, v1.0.7,
  13 252 LOC.
- Upstream `RforMassSpectrometry` sources (Spectra main = 1.23.5; Bioconductor
  release = 1.22.2; and Spectra **1.12.0 installed on this machine from the Bioc
  3.18 archive into `/tmp/rlib`**), plus local clones in `/tmp/rpkgs/`.
  **Both `/tmp` locations have since been emptied** — the installed packages and
  clones are gone, so those measurements must be re-installed to be repeated; see
  the caveat at the top of §9.
- Own measurements on this machine (R 4.3.3): parse benchmarks, prototype
  reader, metadata-mapping census, R packaging probes.
- GitHub API for repo/issue status; CRAN (25 235 packages scanned) and
  Bioconductor 3.18 package indexes.
- **Added in the revision:** psidev.info's mzSpecLib page (ratification date,
  implementations, tool registry) and the release paper `10.1021/acs.analchem.4c04091`;
  `HUPO-PSI/mzspeclib-py` rule JSONs and its `tmp/terms.xlsx` provenance chain;
  `mobiusklein/mzspeclib-rs`, `rusteomics/mzcore` + `mzannotate` (API trees + raw
  sources); `RforMassSpectrometry/MsBackendMzSpecLib` including
  `inst/txt/mzSpecLib-mapping.txt`; Galaxy PR #22888, OpenMS #10172/#10175,
  `matchms` issue states, `CarafeSharp`; Zenodo record 13685813 + the
  `Noble-Lab/multi-species-benchmark` producer source.
- Two background research passes collected candidates for the last two bullets, the
  adoption picture in §4.13 and the negatives in §4.14. **Their reports were treated
  as leads, not evidence**, because the search tool returned demonstrably
  fabricated results during the pass, and the pass itself twice reported numbers
  that its own author later invalidated (a grep whose two terms were the same
  typo'd string; a repository-search endpoint that ignores its query parameter).
  What happened to each category:
  - **Adoption claims** (Galaxy, OpenMS, `matchms`, ProteoWizard, `sage-plus`,
    `timsbuktoolkit`, `msspeculator`, `spxtacular`, `mzcore`, `mzspeclib-rs`,
    `MsBackendMzSpecLib`, Zenodo): **re-established by me** against a primary
    source — API object, raw source file, or `HEAD` request — and each names the
    file or endpoint. §4.13 and §9 carry my numbers, which in two cases (MassIVE
    control counts, and the extension count) differ from theirs.
  - **Database negatives**: re-measured here with controls, in
    `analysis/db_absence_probe.py`, and cited in §4.14 **with their scope stated**.
  - **Tool zeros** (`koina`, `FlashLFQ`, `MSBooster`, `sirius`, `spectrum_utils`):
    these were **not established** at the last revision — GitHub rate-limited the
    control queries mid-check — and are now **established by me** a stronger way than
    the API would have allowed: the complete default-branch tree of each repository
    was fetched and grepped with live per-tool controls
    (`analysis/tool_tree_grep.sh`, counts in §4.14). That pass also turned one of the
    five zeros into a **positive** (koina declares its Altimeter peak annotations
    mzPAF-conformant) and caught two `mzlib` substring false positives, neither of
    which the code-search route could have shown. **The literature/bibliography list
    remains not established** and is otherwise absent from this report.
  - **A proposed mzSpecLib consumer that does not exist**: "DIAlect" — withdrawn,
    no claim made (§4.14).
  - **Claims about the python reference implementation's behaviour**: re-derived on
    2026-10-22 against a freshly installed `mzspeclib` 1.0.7 (the previous oracle
    environment had been deleted), by executing the library's own rule predicates
    rather than reading them — `analysis/oracle_probes.py`. Two new defects came out of
    that run (`§3.3` items 5–6), and one §3.3 claim that had been argued from the rule
    table's text is now a measured True/False.

Throughout, claims are tagged:

- **[verified]** — I read it at the cited file/line or ran it.
- **[measured]** — a number produced by a script in [`analysis/`](analysis/).
- **[inferred]** — my conclusion from those facts; challenge it.
- **[unverified]** — reported by a source I did not independently confirm.

> **Provenance note — read this before quoting numbers.** Two architecture
> surveys and one python-internals survey were delegated to subagents. Two
> returned detailed reports; a workflow-based adjudication round was **aborted by
> infrastructure errors and produced no results** (4 agents started, 0 completed),
> and three attempts at a python-internals survey died on API errors. Everything
> marked [verified] or [measured] below I confirmed myself on this machine.
>
> During the work I made, and later retracted or corrected, the following. They
> are listed because a report this size will be quoted from, and you should know
> which numbers were re-derived:
>
> - *"R 4.3.3 cannot install Spectra"* — **false**; 1.12.0 installs from the live
>   Bioc 3.18 archive. (I had trusted the aborted workflow's buggy helper script.)
> - *"`MsBackendCached` is missing from 1.12.0"* — **false**; it is present.
> - *"no Rust implementation exists"* — **false**; `mzspeclib-rs` exists.
> - A Bioconductor "binary availability" quotation — **removed**; I could not find
>   such a policy sentence, so §4.5 now cites my own HTTP measurements and says
>   explicitly that it is not a quotation.
> - *"3 of ~17 backends exist; 1 commit; 41 stars"* — **replaced** with the
>   re-derived 18-classes/13-packages/6-in-Bioc-3.18 figures and star counts read
>   from the GitHub API (§4.6).
> - *"148-line `mzpaf/__init__.py`"* — **wrong**; `__init__.py` is 16 lines and the
>   real work is a 1 288-line `annotation.py` (§4.9).
> - Analyte/interpretation counts in §4.3 were originally **line counts, not
>   section counts** (e.g. 280 vs the true 21 for `fetal_brain_tiny`). Fixed in
>   both the script and the table, and now cross-checked against python
>   (which is how the error was caught — see §4.3 trap 5).
>
> Retracted in the 2026-10-22 revision — each of these appeared in an earlier
> draft of this report and one or more of them was in the §9 evidence index:
>
> - *"JSON `simplifyVector = TRUE` is ~15× (an order of magnitude) slower than
>   `FALSE`"* — **overstated**. It measured a lost ad-hoc corpus that nested an
>   object per peak; on the real serialisation (parallel `mzs`/`intensities`/
>   `peak_annotations` arrays) the ratio is **2.7–5.7×** (§4.7,
>   `analysis/json_modes.R`). The finding that survived is stronger anyway: the
>   mode choice is a **correctness** bug (`length(spectra)` returns the column
>   count), not a speed one.
> - *"`mzspeclib-rs` models the full graph, text-writer only"* — **wrong**, and
>   the wrongness pointed the extendr question the wrong way. It is a full
>   streaming *reader* (28 493 B `parse.rs`, `build_index()`, cluster states).
>   Wrapping it fails for different reasons: no license file at all, `extendr`
>   not on CRAN, no JSON codec (§8.1 Q3).
> - *"the standard is still DRAFT / not finished"* and the companion *"no public
>   statement was found on non-python implementations"* — **both wrong**. It was
>   ratified 2025-08-07, and spec §3.4 explicitly invites other implementations
>   (§3.3, §8.1 Q1). I had read the PDF cover page and stopped there.
> - *"There is no demand-side pull today"* — **superseded** by
>   `MsBackendMzSpecLib` existing in the RfMS org (§4.12).
> - *"JSON is the slow path in R (6.3 s / 10 MB)"* — **re-measured**: 1.9 s for
>   13.5 MB, and the corpus behind the old figure no longer existed when I
>   re-ran it. §4.7 now states the generator and the machine-load caveat.
> - *"`value_is_child_of` … the 17 uses"* — the count is **18** (§4.8).
> - Rule-set typing mismatches between `metadata-rules.md` and the rule JSONs:
>   my first parser reported **28**; the correct answer is **0** — my regex was
>   dropping the accession from `Children of [MS:x](url)` cells. Likewise
>   `value_is_child_of` parents: 18 distinct, not 17.
>
> The python↔R cross-check, the mzpaf measurements, the rule-file and `validate`
> exit-code findings (§4.8, §4.11) and the §4.6 backend census were all produced
> in the final verification pass and supersede anything earlier in this session's
> transcripts. The same holds for §4.12/§4.13, which are entirely new.

---

## 3. Background: what mzSpecLib is

### 3.1 Data model

Six components: **Library → N Spectra**; each Spectrum has **0..N Analytes**,
**0..N Interpretations** (each with **1..N InterpretationMembers** pointing back
at analytes), and **1..N Peaks**, each peak carrying 0..N **mzPAF** annotations.
Optional **Clusters** group spectra (and MUST NOT contain analytes).
[verified: spec PDF §3.3–4.1]

Two design choices matter enormously for the architecture question, and both are
deliberate breaks from MSP/MGF/SpectraST:

- A spectrum may be **chimeric** (several analytes) and may carry **several
  competing interpretations** of the same peaks. This is a relational model, not
  a flat per-spectrum record.
- **All** metadata is PSI-MS controlled-vocabulary terms, encoded as
  `MS:1003208|experimental precursor monoisotopic m/z=445.2`, with optional
  `[group]` prefixes that bind related parameters together (e.g. a collision
  energy with its unit), optional CV-term *values*, comma-separated lists,
  Unit-ontology units, and named *attribute sets* forming inheritance/override
  chains. The term set is **open** — an implementation cannot hard-code a closed
  field list. [verified: spec §4.1.2, §4.1.4, §4.1.11–12]

### 3.2 Serializations

Two are normative today: `.mzSpecLib.txt` (single text file; CV lines plus
TAB-separated peak rows — col 1 m/z, col 2 intensity, col 3 mzPAF annotation,
col ≥ 4 extra per-peak attributes) and `.mzSpecLib.json` (parallel numeric
arrays). HDF5 and SQLite serializations are **announced but unspecified**
(PDF §4.3 "Other serializations"), and an Apache-Avro pitch is open as issue #74.
**Indexing and random access are explicitly out of scope** — §3.4 says so in so many
words (*"An indexing mechanism is explicitly not specified here"*, followed by the
recommendation that *"Tool developers are recommended to generate sidecar indexes"*)
and §4.1 repeats it for the text serialization. [verified: `pdftotext` of the v1.0
PDF — §4.3 for HDF5/SQLite/Avro; §3.4 and §4.1 for the sidecar-index wording. Note
that §3.4 is headed *"Overview of mzSpecLib data model"*, i.e. it is the data-model
section *and* the home of the "other implementations are welcome" sentence quoted in
§3.3 and §8.1 — not a serializations section]

### 3.3 The standard *is* ratified — its supporting artefacts are not consistent

**[corrected 2026-10-22 — the first draft of this section said the opposite]** The
evidence that made the first draft call the standard unfinished is real but stale
text: the PDF's cover page says **DRAFT** and the README still says the spec is
"nearly complete … hoped to be complete at the end of 2024". I had read the cover
and stopped. The actual status:

| artefact | what it says | verified |
|---|---|---|
| `psidev.info/mzspeclib` (the PSI registry) | *"Status Updated: 2025-08-07 The specification has been **formally ratified** via the PSI Document Process to become an official PSI standard."* and links *"The FINAL specification 1.0"* | fetched 2026-10-22 |
| spec PDF, "Status of this document" | *"This Recommendation was **ratified** via the PSI Document Process. Any alterations of this document MUST also follow the HUPO PSI Document Process."* | `pdftotext` on the local PDF |
| spec PDF, cover page | *"PSI Recommendation … **Status: DRAFT**"* (2025-05-23) — never updated after ratification | same |
| spec repo `README.md` / `specification/README.md` | *"nearly complete … hoped to be complete at the end of 2024"* — still present at HEAD | read locally |
| release paper | DOI `10.1021/acs.analchem.4c04091` (Analytical Chemistry) | linked from psidev.info |

**Why this matters more than a status label.** A ratified v1.0 with RFC 2119
language is a *frozen target*: implementing it is much less risky than the first
draft of this report assumed, and the "spec may change under us" risk in §7 drops
from high to low. What did **not** ship with ratification is the engineering
contract around it — there is still no compatibility or deprecation policy
(versioning is just a declared string, `MS:1003186|library format version=1.0` /
JSON `format_version`), **no conformance suite** (§4.12), and the normative rule
table carries **three accessions that name the wrong term** (the audit is below;
also §4.8). The spec also states, §3.4 verbatim:
*"other implementations are welcome and forthcoming"* — so a second implementation
is explicitly invited, and §4.12 records that two already exist (Rust, R).

The remaining inconsistencies, restated with counts I measured myself:

- The shipped JSON Schema **rejects the repo's own example files**, and by a wide
  margin: **4 876 errors** for `fetal_brain_tiny.mzSpecLib.json` and **3 328** for
  the IARPA3 head [measured, `jsonschema` 4.10.3, Draft7]. The dominant cause was
  not previously identified: `spectrum.peak_annotations` is declared as
  **array → array → array**, while every real document (and the reference writer)
  emits a **flat array of strings** — so *every peak* in every real library is a
  validation error (4 443 of the 4 876). `aggregations` has the same extra nesting
  level (1 474 errors in IARPA3). On top of that: `additionalProperties: false`
  forbids `interpretations`, which both implementations emit (21 errors), and
  `analyte.id` / `cvparam.cv_param_group` are typed `integer` while the data uses
  strings (21 + 391). The schema also `$ref`s a **remote** mzPAF schema URL, so
  validating requires network access. **Consequence: "validates against the
  shipped JSON Schema" must not be an acceptance criterion for any milestone**
  (see §6 milestone 2).
- Validation tiers — the MUST/SHOULD/MAY rule sets (`base` 10 rules, `all` 99,
  plus `gold` / `silver` / `single` / `consensus` / `peptide`) — live **inside the
  python package**; the spec repo keeps only their markdown rendering, whose
  generator is dead code (§4.8). The de-facto conformance standard is python code.
- JSON `cluster` declares only `attributes`, while the text format supports
  member keys, member USIs, best-representative and summary statistics
  [verified: same files].
- Open issues: HDF representation (#13, 15 comments, **last activity 2023-10-21
  and the thread's final message is an unanswered question**), Avro (#74, silent
  since 2024-01-26), "Features Not Yet Implemented" (#48), metadata/CV refinement
  (#7, open since 2018). Exactly **5 open issues and 0 open PRs** in the spec repo
  [GitHub API, 2026-10-22] — i.e. the model is not being churned.
- **New in the revision, and the most actionable defect found: the normative rule
  table's accession↔label mapping is wrong in at least 2 of its 97 rows.** I
  audited every surface label in `docs/metadata-rules.md` against PSI-MS in OLS4
  (`analysis/cv_label_audit.py`; OLS responses cached in-repo, so the audit is
  reproducible offline): **90 of 97 rows equal the OLS preferred label, 1 is a
  declared synonym, 7 match neither.** Checking those 7 against two *more* independent
  CV copies (below) splits them into three kinds, which matters because only the first
  two are bugs worth an issue:
  - **3 rows cite an accession that names a different term** — `MS:1000034`
    (*charge deconvolution*) under the label *intensity unit*, `MS:1002875`
    (*TSQ Quantis*, an instrument model) under *inverse reduced ion mobility*, and
    line 41's `MS:1003205` under *constituent identification file*, which is really
    **`MS:1003204`**. The third was mis-read as a duplicate row in the first draft of
    this revision; lines 41–42 are two distinct terms whose first accession was
    mistyped, and `MsBackendMzSpecLib`'s own mapping table already carries them as
    two distinct terms (§4.12) — so the R side already has a second witness that the
    normative table is the wrong one.
  - **1 label typo**: `collision cross sectional area` where PSI-MS has said
    `collisional cross sectional area` (MS:1002954) all along — including in the
    older pinned copy, so this one never was correct.
  - **3 wording drifts**: `SMILES formula` (MS:1000868) was the *correct* PSI-MS label
    in psi-ms 4.1.57 and became `SMILES string` by 4.2.6 — dated, and the only one I
    can date; `summary statistics of replicate spectra` (MS:1003295) and `number of
    replicate spectra from source` (MS:1003296) are newer than 4.1.57 and their current
    labels read `… of replicates` and the ungrammatical `number of replicates spectra
    used from source`, so whether the table paraphrased or PSI renamed them cannot be
    settled from what I have.
  **The three accession errors are the ones that break tooling:**

  | row in `metadata-rules.md` | accession cited | what PSI-MS says that accession *is* | correct accession for that label |
  |---|---|---|---|
  | "intensity unit" (library spectra) | `MS:1000034` | **`charge deconvolution`** | `MS:1000043` = `intensity unit` — and `MS:1000043` is what the shipped libraries actually write (`MS:1000043\|intensity unit=MS:1000905\|percent of base peak times 100`, 23 occurrences) |
  | "inverse reduced ion mobility" (library spectra) | `MS:1002875` | **`TSQ Quantis`** (a Thermo instrument model) | `MS:1002815` = `inverse reduced ion mobility` |
  | "constituent identification file" (library, line 41) | `MS:1003205` | **`constituent library file`** — which the *next* row (line 42) already documents correctly | `MS:1003204` = `constituent identification file`. Both terms are absent from psi-ms 4.1.57 and distinct in 4.2.6, so the mistake post-dates the older CV copy |

  Each of those rows also **contradicts itself within the row**: its definition
  column prints the definition of the term its accession really names — `"Thermo
  Scientific TSQ Quantis Triple Quadrupole MS." [PSI:PI]` under a row labelled
  *inverse reduced ion mobility* (line 80), and `"The determination of the mass of an
  ion based on the mass spectral peaks that represent multiple-charge ions."` under a
  row labelled *intensity unit* (line 93). Whoever maintains the table can confirm
  both defects from a single rendered row, without any ontology tooling.

  **The correction is now confirmed in three independent CV copies, not one.** OLS4
  (the audit above), the PSI-MS copy that `psims` 1.4.0 serves (**4.2.6**), and the
  copy pinned inside the python package's git tree (`mzspeclib/obo/psi-ms.obo`,
  `data-version: 4.1.57`, 3 096 `[Term]` stanzas — `grep -c '^\[Term\]'`, re-counted
  2026-10-22; the first draft's "3 097" was off by one) all name `MS:1000034` =
  *charge deconvolution*
  and `MS:1002875` = *TSQ Quantis*, and all resolve the labels *intensity unit* →
  `MS:1000043` and *inverse reduced ion mobility* → `MS:1002815`. The same third
  witness **re-classifies two of the seven "drift" rows**: `SMILES formula` was the
  correct PSI-MS label for `MS:1000868` in 4.1.57, so that row is dated drift, but
  `collision cross sectional area` was already spelled `collisional…` in 4.1.57, so
  that one is an authoring typo like the other two. `analysis/oracle_probes.py` prints
  all of this.

  **And the consequence is no longer hypothetical — I executed the shipped rule.**
  Neither wrong accession appears in any example file (verified: `MS:1002815`/
  `MS:1002875` are absent from all 10 example libraries), so no existing test could
  notice; but `MS:1000034` is *also* that row's value-type reference ("Children of
  [MS:1000034]"), and that row exists verbatim in python's `rules/all.json` as
  `has_intensity_unit` (`path /Library/Spectrum`, `value_is_child_of MS:1000034`).
  Run against the value the spec's own example library writes
  (`MS:1000905|percent of base peak times 100`, from
  `examples/SpectraST/fetal_brain_tiny_consensus_td.mzSpecLib.txt:26`):

  | rule as executed (`mzspeclib` 1.0.7 + `psims` 4.2.6) | terms walked | rule satisfied |
  |---|---|---|
  | `value_is_child_of("MS:1000034")` — as the table says | 1 (the term itself; it has **no children**) | **False** |
  | `value_is_child_of("MS:1000043")` — corrected | 5 (`intensity unit` + `MS:1000131/1000132/1000814/1000905`) | **True** |

  So the rule as authored is **unsatisfiable by any file** (not merely mis-firing: the
  single walked term is rejected by the predicate's own
  `not term.startswith(accession)` guard, `semantic_rule.py:125-132`), while the
  corrected accession is satisfied by the spec's own example. A MAY-rule that can
  never hold is invisible in a pass/fail summary, which is presumably why it survived;
  the same row under `MS:1002875` would accept *instrument models* as ion-mobility
  values.
  **Consequences:** (i) §4.11 row 12's "key on accession, not name" is necessary but
  not sufficient — for such rows neither authored field can be trusted, so the OLS
  label has to be joined in at build time; (ii) this audit belongs in milestone 0 as
  a machine check rather than a human review; (iii) it turns §8.2(a) from a request
  into a defect list. Seven items, each reproducible in one command:
  **1–3.** the three wrong accessions (fixes: `MS:1000043`, `MS:1002815`,
  `MS:1003204`);
  **4.** the JSON Schema that rejects its own examples (§3.3 above);
  **5.** the same error propagated into the *generated* rules: `rules/all.json` has
  `has_constituent_identification_file` citing `MS:1003205` (2 occurrences of that
  accession in the file, `MS:1003204` 0), so — given composite-key matching (§4.11 row
  12) — that rule can never fire against a file that uses the correct accession. One
  mistyped spreadsheet cell, two dead artefacts;
  **6.** `INTENSITY_UNITS` in `validate/validator.py:225` contains the literal
  `" MS:1000814"` with a leading space, so *counts per second* can never match the
  validator's own hard-coded intensity-unit allow-list even though it is a real child
  of `MS:1000043`;
  **7.** `ValueMatches` (`validate/semantic_rule.py:196-201`) compares the file's
  `accession|label` string against a label **composed from whichever ontology copy
  the validating machine resolves**, so a PSI-MS rename retroactively invalidates
  conformant files — measured both ways: `MS:1000868|SMILES formula` (correct under
  psi-ms 4.1.57) → **False**, `MS:1000868|SMILES string` (current) → **True**.
  Item 7 is not a typo but a reproducibility property, and §4.8's design consequences
  and §7's new CV-version risk row both follow from it.
- Also unchanged from the first draft, and worth restating now that the table is
  under scrutiny: `docs/metadata-rules.md` is **not** generated from the python rule
  JSONs (that was the first draft's claim; §4.8 traces both artefacts back to
  `rules/tmp/terms.xlsx`). **The shared defect is now identified precisely rather
  than as a "duplicate row":** lines 41–42 document two genuinely distinct PSI-MS
  terms — `MS:1003204 constituent identification file` and `MS:1003205 constituent
  library file`, distinct in psi-ms 4.2.6 and absent from 4.1.57 — but both rows cite
  `MS:1003205`, and `rules/all.json` inherits the same mistake
  (`has_constituent_identification_file` → `MS:1003205`). One mistyped cell in the
  upstream spreadsheet is therefore visible in three artefacts at once, which is the
  clearest available illustration of why §4.8's "vendor the table, diff it
  mechanically" recommendation is not paranoia.

---

## 4. Findings

### 4.1 Spectra's data model is a flat per-spectrum table

`MsBackend` is a deliberately *fat* virtual class (~80 default methods,
`R/MsBackend.R`), and the core spectra variables are 19 flat columns
(`.SPECTRA_DATA_COLUMNS`: `msLevel, rtime, acquisitionNum, scanIndex, mz,
intensity, dataStorage, dataOrigin, centroided, smoothed, polarity, precScanNum,
precursorMz, precursorIntensity, precursorCharge, collisionEnergy,
isolationWindow{Lower,Target,Upper}Mz`). [verified, and reproduced locally:]

```
> coreSpectraVariables()            # Spectra 1.12.0, /tmp/rlib
 [1] "integer" "numeric" "integer" "integer" "NumericList" "NumericList" ...
```

Verified consequences:

- **Library-level metadata has no public home.** `metadata` is a *slot* on
  `Spectra` but is **not exported**: `"metadata" %in% getNamespaceExports("Spectra")`
  → `FALSE`, while `"metadata" %in% slotNames("Spectra")` → `TRUE` [measured,
  Spectra 1.12.0]. The entire mzSpecLib library header (name, version, URI,
  licence, contacts, constituent files, creation provenance) has nowhere
  standards-compliant to go.
- **No analyte / interpretation / adduct / cluster / cross-reference concept
  exists.** The nearest things are `countIdentifications()` (a *statistic* stored
  as a spectra variable, driven by a free-text `sequence` column) and
  `ProtGenerics::compounds()` (a database lookup accessor). Greps for
  `adduct|ccs|analyte|ionMobility|driftTime` across `R/AllGenerics.R`,
  `R/MsBackend.R`, `R/Spectra.R` return nothing [verified].
- **Per-peak extra columns *are* supported** (`peaksVariables`,
  `MsBackendMemory@peaksDataFrame`), and `MsBackendAnnotatedMgf` already parses
  per-peak annotations out of MGF into them. Good news for mzPAF-as-opaque-string.
- **Per-spectrum nested/list columns** are only feasible on the `DataFrame`-backed
  backend and are **exercised by no test** — unvalidated territory for
  `backendMerge`, `selectSpectraVariables`, subsetting and `export`.
- **There is no backend registry.** `backendRegister`, `supportedBackends`,
  `supportedSpectraVariables` do not exist [measured: `exists(..., asNamespace("Spectra"))`
  → `FALSE` for all three]. Wiring is S4 inheritance plus `Depends: Spectra`.
  Neutral for the decision — it removes one possible argument for the split.

### 4.2 The census that matters: 88 % of real metadata has no home in Spectra

Rather than argue this from first principles, I measured it. `analysis/mapping_gap.R`
extracts every spectrum-level CV parameter from the **8 `.mzSpecLib.txt`
files shipped in the spec repo (7 unique; one is duplicated byte-identically in
two directories, which doubles its weight in these totals — I have left it in
because that is what a naive reader, and the reference implementation's own
tooling, will also see)** and asks which map onto a Spectra spectra
variable [measured]:

| Scenario | mappable | no home in Spectra |
|---|---|---|
| strict (19 core variables only) | 558 / 4 742 = **11.8 %** | **88.2 %** |
| excluding the `other attribute name/value` escape hatch and `unit` | 558 / 3 549 = 15.7 % | 84.3 % |
| **generous** — allow 16 *additional* custom columns (USI, spectrum name, aggregation type, origin type, protein accession, peptide sequence, missed cleavages, flanking residues, NCE, CCS, drift time, …) | 1 374 / 4 742 = **29.0 %** | **71.0 %** |

72 distinct terms occur; even under the generous scenario **50 remain
unmappable**. Per-file gap ranges 54.6 %–96.4 % across the 7 files with spectrum
metadata, so this is not an artefact of one unusual library.

Largest unmapped offenders: `contributing replicate spectrum USI` (1 003),
`other attribute name`/`value` (470/469 — the vendor escape hatch), `unit` (254,
which is intrinsic to CV parameter groups), `number of peaks` (120), `library
spectrum name` (118), `spectrum aggregation type` (109), `protein accession`
(72), `proforma peptidoform ion notation` (69), and five separate
unassigned-peak statistics.

**Is that gap a proteomics problem or a metabolomics problem? Mostly neither**
[measured; classification by accession, full term list in §8 Q6]. Splitting the
4 184 unmapped occurrences by whether the CV term is peptide/protein-specific
(`protein accession`, `stripped peptide sequence`, ProForma, flanking residues,
missed cleavages, enzymatic termini, residues, cleavage agent, PSM probability /
q-value, `Comet:xcorr`, `delta m/z`), small-molecule-specific (`adduct ion mass`,
`molecular formula`), or domain-neutral:

| bucket | occurrences | share | distinct accessions |
|---|---|---|---|
| domain-neutral (provenance, aggregation, replicate USIs, unassigned-peak stats, `unit`, attribute-set names, …) | 3 581 | **85.6 %** | 46 |
| proteomics-specific | 563 | 13.5 % | 15 |
| small-molecule-specific | 40 | 1.0 % | 2 |

The one small-molecule example, `spice.mzSpecLib.txt`, contributes **53** unmapped
occurrences in total (9 of them chemistry terms). So the metadata gap is driven by
mzSpecLib's *provenance and aggregation* model, which no flat per-spectrum table
can hold in either domain — and the metabolomics profile is real but has almost
no upstream data behind it (§8 Q6).

The two decisive items are not in these counts because they are *structural*:
**CV parameter groups** (`[1]` binding a value to its unit) and **attribute-set
inheritance**, plus the analyte/interpretation graph. Spectra has no place for
any of them at all.

**[inferred]** A backend-only implementation would end up storing a serialized
private mzSpecLib representation in extra columns to avoid data loss. That
private representation *is* the format package; the choice is whether it is
named, documented, versioned and tested, or not.

### 4.3 A format core is separable — demonstrated, not asserted

`analysis/proto_reader.R` is a **127-line, dependency-free R script** that reads
the real spec text format: CV parameters (with `[group]`, CV-valued terms),
section nesting, peak rows. To make "correctly" checkable rather than asserted, I
ran the **python reference implementation over the same 6 files** and compared six
counts per file. **30 of the 36 cells agree exactly**; the other six are the
attribute-set column, and the paragraph under the table shows the difference is
exactly predictable per file rather than a fuzzy disagreement. Re-measured
**2026-10-22** on a freshly installed oracle (`mzspeclib` 1.0.7), because the
environment the 2026-09-29 run used was a `/tmp` throwaway that no longer exists and
a claim this load-bearing for milestone 1 should not rest on trust:

* R side — `Rscript analysis/proto_reader.R`
* python side — `analysis/oracle_counts.py`, over
  `backends.TextSpectralLibrary(path)` + `read_header()` + `read()`, counting
  `len(lib.attributes)`, `len(sp.peak_list)`, `len(sp.analytes)`,
  `len(sp.interpretations)`
* raw side — the regex pass in the same script, mediated by no library at all

All thirty numbers are **identical to the 2026-09-29 run**, and python's six rows are
cell-for-cell the R rows. The third instrument was added on 2026-10-22 for one
reason: when two readers disagree you cannot tell which one dropped something, and a
dumber third one usually can. It paid for itself immediately — see trap 6. [measured
2026-10-22; both commands are checked in, so this table no longer depends on a lost
environment:]

| file | spectra | peaks/spec | analytes | interp | header CV | attr. sets: declared → python |
|---|---|---|---|---|---|---|
| spice | 11 | 45 | 11 | 0 | 4 | 1 → 4 |
| IARPA3 (NIST) | 20 | 74 | 20 | 20 | 634 | 3 → 4 |
| fetal_brain_tiny (SpectraST) | 21 | 212 | 21 | 21 | 12 | 4 → 5 |
| broad_tcga (NIST-CPTAC) | 20 | 31 | 0 | 0 | 2 | 3 → 4 |
| phl004 (DIA-NN) | 9 | 16 | 9 | 0 | 3 | 3 → 4 |
| human_serum (Spectronaut) | 9 | 16 | 9 | 0 | 3 | 3 → 4 |

The first five columns now agree across **three** instruments (my R reader, the
reference implementation's object graph, a regex pass over the raw text), so a
disagreement anywhere in them is attributable rather than arguable.

The last column is the one that never agreed, and on 2026-10-22 it was measured cell
by cell instead of characterised. Python keeps the sets it parsed in four per-scope
dicts — `lib.{spectrum,analyte,interpretation,cluster}_attribute_sets` — each
**pre-seeded with an `"all"` entry** (`backends/base.py:219-230`, read in the
installed 1.0.7), so its count exceeds the declared count by exactly one per scope the
file never mentions: 1→4 for spice, 3→4 for the four producer examples, 4→5 for
fetal_brain_tiny (the only file declaring a second analyte set, `HUMAN_TRYPTIC`).
`oracle_counts.py` prints the per-scope member names beside every row so the phantoms
are visible rather than inferred; in six of six files the `cluster` dict holds nothing
but its pre-seeded `all`. My R reader counts declared `<AttributeSet …>` sections,
which is the *other* defensible quantity, and the raw regex pass agrees with it
exactly (1/3/4/3/3/3). That is the shape milestone 1's fixtures need: two quantities,
each precisely defined, differing by an amount predictable from the file — not a fuzzy
"close enough".

The trap in that spot is worth naming, because it produces a *passing* wrong test:
`lib.attribute_sets` and `sp.attribute_sets` are **not** those dicts. They resolve the
*reference* attribute `MS:1003212|library attribute set name`
(`attributes.py:470-476`, `const.py:12`) and returned `[]` for every one of the six
examples — an implementation that read attribute sets through the obvious accessor
would be vacuously conformant. (An earlier draft of the table above carried "python 3"
for spice; that accessor is no longer reconstructible, the 1.0.7 figure is 4, and the
row has been replaced rather than quietly kept.)

127 lines is *not* an estimate of the real package — it omits the JSON
serialization, writers, mzPAF, attribute-set resolution, validation, indexing,
error handling and tests, which is why §6 estimates 3.5–6.5k LOC. What it *does*
show is that the parsing layer is small, mechanical and completely independent of
any Spectra type.

It also surfaced six traps, none of them hypothetical: traps 1–5 are bugs I wrote in
R and had to fix, trap 6 is a bug I wrote on 2026-10-22 in the *third* instrument,
after R and python had already been made to agree:

1. **`<Peaks>` has no index**, so peak rows must be attributed to the *enclosing*
   `<Spectrum=N>`; a naïve section-membership model returns **zero peaks for every
   file, silently**. This was my first bug.
2. **Peak rows are ambiguous by content.** Distinguishing them from CV lines by
   "starts with a digit, contains no `=`" is fragile — real CV values include bare
   numbers (`number of peaks=51`) and formula characters. python uses a
   `float_number` regex plus a whitespace-delimiter fallback that emits a
   `ValidationWarning` (`backends/text.py:323-340`). A format implementation must
   own this ambiguity resolution; it is *not* derivable from the spec text alone.
3. **`<Analyte>` nests under `<Spectrum>`**, so a flat section model destroys the
   analyte↔spectrum relation — precisely the relation Spectra cannot represent (§4.1).
4. **`<AttributeSet Spectrum=all>` has a space, not an `=`, before its qualifier.**
   A `^<([^>=]+)(=.*)?>$` name regex captures `"AttributeSet Spectrum"` and the
   attribute-set sections vanish from the parse — which is how my first version
   reported `attrsets=0` for files that declare them. Re-measured 2026-10-22 with a
   delimiter class of `[=>]` instead of `[=>\s]`: **0 attribute sets in all six
   files**, which declare 1–4. The reference implementation carries a *dedicated*
   pattern for this one section — `r"<AttributeSet (Spectrum|Analyte|Interpretation|Cluster)\s*=\s*(.+)>"`
   (`backends/text.py:77`) — so the space is syntax, not untidiness in the examples.
5. **Counting lines attributed to a section is not counting sections.** My first
   tally reported **280 "analytes" for fetal_brain_tiny, which has 21** `<Analyte>`
   blocks, because I summed CV lines carrying that section tag. A wrong counter
   that *looks* plausible is worse than a crash: it took the python oracle to
   catch it. That is the strongest argument I can make for building the R
   conformance fixtures (milestone 1) against the reference implementation on day
   one rather than eyeballing output.
6. **"Library header" is not "the CV lines before the first `<Spectrum>`".** Every
   one of the six examples declares its `<AttributeSet Spectrum=all>`,
   `<Analyte=all>` and `<Interpretation=all>` blocks *before* its first spectrum, so
   a counter that keeps the header scope open until `<Spectrum>` quietly folds
   attribute-set attributes into the library scope: **+2 of 4 lines on spice, +17 of
   12 on fetal_brain_tiny** — a 50 % and a 142 % error, both silent, both in the
   direction of "found more metadata than is there". The scope ends at the first
   section line that is not itself library-scoped, which is what both my R reader and
   `read_header()` do and what the naive counter did not. Written down as a rule,
   this belongs in the milestone 1 fixture set next to traps 1 and 5, because all
   three are the same failure: a *quantity* the format does not name explicitly, which
   each implementation therefore defines for itself.

### 4.4 One package cannot host a backend without hard-depending on Spectra

I built the probe rather than reasoning about it [measured]:

```
# DESCRIPTION: Suggests: Spectra   (Spectra installed and loadable)
setClass("MsBackendMzSpecLibProbe", contains = "MsBackendCached", ...)

Error in reconcilePropertiesAndPrototype(...) :
  no definition was found for superclass "MsBackendCached"
ERROR: lazy loading failed for package 'cext'
```

Deferring the class definition into `.onLoad()` with a `requireNamespace()`
guard **also fails to install**, even with Spectra present. R resolves
superclasses when the code is loaded at install time.

**[verified]** A single-package design must put Spectra in `Depends`/`Imports`.
That makes Spectra — and transitively `S4Vectors`, `IRanges`, `BiocParallel`,
`ProtGenerics`, `MsCoreUtils`, `MetaboCoreUtils` — a prerequisite for reading an
mzSpecLib file in R. Option C ("one package, two layers") is therefore not
available in the clean form; it degrades into option A with the seams hidden.

### 4.5 Deployment: the R Spectra ecosystem is not installable where mzSpecLib already runs

- The python `mzspeclib` **is** on bioconda, with Galaxy tool wrappers for
  `convert` / `validate` / `describe` that shell out to the python **CLI**
  [verified: `~/dev/bioconda-recipes/recipes/mzspeclib/meta.yaml`,
  `~/dev/galaxytools/tools/mzspeclib/*.xml`].
- **No conda channel ships the R Spectra stack**: `bioconductor-spectra`,
  `r-spectra`, `r-mbackendmsp`, `r-protgenerics` all absent from conda-forge and
  bioconda (anaconda.org API) [measured]. `r-jsonlite` is present on both.
- **[verified, with a correction]** *Locally*, R 4.3.3 installs Spectra 1.12.0
  from the still-live Bioc 3.18 archive; the 19 core spectra variables and the
  `MsBackend` contract behave as documented, and `Spectra`'s backend
  **compliance test suite** ships at `system.file("test_backends","test_MsBackend")`
  — present in 1.12.0 and 1.23.x alike. Caveat: Bioconductor documents only two
  live versions — "The current release of Bioconductor is version 3.23; it works
  with R version 4.6.0 … The development version of Bioconductor is version 3.24"
  — so a new user on a supported R reaches only 3.23/3.24, and 3.18 is reachable
  only by explicitly overriding `BiocManager::repositories(version = "3.18")`
  [verified: bioconductor.org/install/, and used for the local install].
- **[measured]** For *new* R users, a CRAN package is the lower-friction target.
  CRAN keeps binaries for older R lines — `bin/windows/contrib/4.3/` answers
  HTTP 200 and still serves `jsonlite_2.0.0.zip` — whereas the analogous legacy
  Bioconductor binary directory (`packages/3.18/bioc/bin/linux/ubuntu/noble-4.3/`)
  returns 404. A dependency-light CRAN package is therefore installable on an
  older-R machine like this one without compiling; a Bioconductor one may not be.
  (I did **not** find a Bioconductor policy sentence stating that legacy binaries
  are withdrawn; the 404 above is my evidence, not a quotation.)

**[inferred]** Whatever R work happens, the python CLI remains the ETL and
Galaxy workhorse for the foreseeable future. An R package that must be usable
alongside it should not require the RfMS stack to even open a file.

### 4.6 Ecosystem precedent — and the precedent that undercuts the convention

**Against the split [verified]:**

- **Every** text/SQL backend package implements its format parser **in-package**
  and exports the low-level reader [verified against local clones in
  `/tmp/rpkgs/`: the parser lives in `R/functions-msp.R`, `R/functions-mgf.R`,
  `R/functions-massbank.R`, and the DESCRIPTIONs list no format dependency —
  `MsBackendMsp` `Depends: R, Spectra (>= 1.5.14)` and `Imports:` with no
  third-party reader]. None imports a standalone format package.
- The `MsBackend*` family is genuinely thin. I parsed the backend list in
  Spectra's README (which calls itself *"possibly incomplete"*) and counted
  **18 classes across 13 providing packages** — i.e. a median of 1–2 classes per
  package. Only **4 classes ship inside Spectra itself** (`Memory`, `DataFrame`,
  `Hdf5Peaks`, `MzR`); of the remaining 14 classes, **2 are hosted by packages
  named after something else** (`MassbankSql` → `MsBackendMassbank`,
  `OfflineSql` → `MsBackendSql`) and `CompDb` lives in `CompoundDb`. Only
  **6 of those 12 external host packages ship in Bioconductor 3.18**
  (CompoundDb, MsBackendMassbank, MsBackendMgf, MsBackendMsp, MsBackendSql,
  MsBackendRawFileReader — measured against that release's `src/contrib/PACKAGES`,
  2 216 packages); the rest exist only as RforMassSpectrometry GitHub repos
  (`MsBackendHmdb`, `MsBackendMassIVE`, `MsBackendMetaboLights`,
  `MsBackendMetabolomicsWorkbench`, `MsBackendTimsTof`, `MsBackendWeizMass`),
  and the org additionally keeps `Deprecated-MsBackendSql` plus unshipped
  `MsBackendDuckDb`, `MsBackendHSDS`, `MsBackendMongoDb`, `MsBackendMzPeak`.
  Measured interest is low: `MsBackendMsp`, `MsBackendMgf`, `MsBackendMassbank`
  have 5, 5 and 4 GitHub stars (GitHub API, 2026-09-29). This is a thin,
  low-traffic area — and note the counter-reading: the convention here is
  "*one format, one backend package, parser included*", which is an argument
  against a *third* package, not against a format layer (see §5).
- The documented recommended route (`vignettes/MsBackend.Rmd`, verbatim): *"if
  the only purpose of a backend is to import or export data in a specific
  format, the `MsBackendMemory` might be extended and a single method
  (`backendInitialize()`) would need to be implemented"*.
- **Nobody is asking for it.** No mzSpecLib R package exists anywhere; the
  RforMassSpectrometry org (49 repos, GitHub API) has none; no GitHub issue in
  either HUPO-PSI repo asks for R. Proteomics DIA-library *library-optimisation*
  tooling in R is a single personal repo — `MarcIsak/MSLibrarian`, 14 stars, last
  pushed 2022-08-25, on neither CRAN nor Bioconductor (GitHub API + CRAN/Bioc
  indexes, 2026-09-29). So there is no existing R constituency to inherit, and
  equally no installed base to displace: whichever package shape is chosen starts
  from zero.

**For the split [verified]:**

- **`mzR` is the exact precedent for the split, and it is the flagship case.**
  `mzR` `Depends: R, Rcpp, methods, utils; Imports: Biobase, BiocGenerics,
  ProtGenerics` — **no Spectra dependency at all** — and Spectra reaches it via
  `Suggests` (line 37 of its DESCRIPTION, alongside `rhdf5`), used by
  `MsBackendMzR`. For the one file format that dominates the ecosystem,
  RforMassSpectrometry itself chose *standalone format package + thin backend*.
  It is the single strongest fact in favour of option A, and it is the same
  format class (binary/complex MS format, non-RfMS parsers wrapped behind a
  backend) that mzSpecLib resembles.
- `DBI` shows the same discipline: backend code written against an abstraction,
  concrete drivers in `Suggests`.
- `SpectraStash` is accepted as a *standalone* package in this space (a Spectra
  consumer, not a backend), so the org does accept non-backend packages around
  Spectra.
- `mzspeclib-rs` (Rust, `mobiusklein`, 2 stars, pushed 2025-09-08) models the
  full graph — `Analyte, AnnotatedPeak, IdType, Interpretation,
  InterpretationMember, LibraryHeader, LibrarySpectrum` plus `AttributeSet` /
  `EntryType` and a `LibraryIndex` — in ~75 KB of Rust, **with no Spectra-like
  consumer type anywhere**. Independent implementers converge on a standalone
  format layer. (Caveat: `write.rs` is 863 bytes — text writing only, no JSON.)

### 4.7 Performance is not a constraint (this kills a class of objections)

Both architectures can be fast.

**Correction, and why this section was re-measured.** The corpus behind the first
two drafts of this section was an ad-hoc file in `/tmp` that was never checked in,
and by the time of the final pass it was gone — so §4.7 was not reproducible, and
one of its headline claims did not survive regeneration. `analysis/bench_gen.R`
(now in-repo, fixed seed `20260929`) regenerates a corpus of the same *shape*:
**6 000 spectra, 330 497 peak rows, 66 008 CV parameter lines, 15.20 MB text /
13.53 MB JSON** (sha256 prefixes `928e9e08` / `c581b4d6`; the earlier
`d392981f`/`6fe46d97` corpus differed only in its library-header lines — see the
note below the table). Median of 3 runs of `analysis/bench2.R`, range in brackets,
on a **quiet machine** [measured; `heapMB` reporting in the harness is still broken
— it prints 0 — so **memory remains unmeasured, time is not**]:

| Operation | elapsed (s) |
|---|---|
| `readLines()` whole 15.2 MB text file | 0.52 [0.51–0.62] |
| CV parse (`readLines` + `regmatches`) → 90 009-row data.frame | 1.57 [1.50–1.61] |
| peak-list parse, base R `strsplit` + `vapply` | 1.54 [1.49–1.68] |
| peak-list parse, `data.table::fread` | **0.14 [0.14–0.15]** |
| per-spectrum grouped split (what a real reader must do) | 0.58 [0.56–0.61] |
| `jsonlite::fromJSON(simplifyVector = TRUE)` | **1.91 [1.79–1.92]** |
| `jsonlite::fromJSON(simplifyVector = FALSE)` | 0.36 [0.35–0.39] |
| materialise all m/z + intensity as list of matrices | 0.46 [0.43–0.46] |

**Machine load moves every number above by ~2×, and one re-measurement proves it.**
Re-run later the same day on the same corpus while other jobs were active, medians
of 3 became: `readLines` **0.97 s** [0.51–1.26], CV parse **2.46 s** [1.51–3.94],
`strsplit` **2.14 s** [1.65–3.30], `fread` **0.21 s** [0.19–0.27],
`fromJSON(TRUE)` **2.50 s** [2.40–3.95], `fromJSON(FALSE)` **0.54 s** [0.40–0.87].
Every absolute number grew; **no conclusion changed**, because the load-robust
quantity is the ratio: `fread`/`strsplit` = 11× quiet vs 10× loaded;
`fromJSON(TRUE)`/`FALSE` = 5.3× vs 4.6×. Read this section for orders of magnitude
and relative cost, never for an absolute second.

**[corpus correction]** The generator's library header previously wrote
`UO:0000266|intensity unit=relative intensity`. `UO:0000266` is **electronvolt**
(checked in OLS, and 115 occurrences in the real examples all pair it with
`[n]UO:0000000|unit=` on collision-energy lines), so that line was an invented term
pairing — exactly the mistake this report accuses other artefacts of. It is fixed:
the synthetic header now copies eight **verbatim** header lines from
`examples/SpectraST/fetal_brain_tiny.mzSpecLib.txt` (all 19 accession|name pairs the
script emits were then re-checked against the examples and the normative table:
17 appear verbatim in an example library, 2 (`library spectrum key`,
`library spectrum index`) only in the normative table, 0 unverifiable). Only the
header text
changed, so line and term counts (and therefore every timing conclusion) are
unaffected; the corpus hash is not. **A reader-writing benchmark is only as good as
its corpus's conformance**, which is why §4.13's real-file profile matters more
than any of the numbers in this table.

**[retracted claim]** *"JSON `simplifyVector = TRUE` is an order of magnitude
(~15×) slower than `FALSE`."* That measured the lost corpus, whose JSON nested one
object **per peak**. The real serialisation uses three parallel arrays
(`mzs`, `intensities`, `peak_annotations`), and on that shape the ratio is
**2.7–5.7×**, measured 5 ways on the real files and the regenerated corpus
(`analysis/json_modes.R`): fetal_brain_tiny 0.019 s vs 0.007 s (**2.7×**),
IARPA3 head 0.034 s vs 0.006 s (**5.7×**), 13.5 MB corpus 1.037 s vs 0.344 s
(**3.0×**). Several-fold, not an order of magnitude. Note also that the *same*
`fromJSON(TRUE)` call measures **1.0–1.9 s** depending on whether it runs in
`bench2.R`'s GC-forcing harness or in `json_modes.R` on a warm heap — the harness
moves this number more than the setting does, which is a warning about trusting
any single-cell timing here.

**[new, and more useful than the timing]** the mode choice is a **correctness**
trap, not a speed one: with `simplifyVector = TRUE`, `jsonlite` turns `spectra`
into a **data.frame (21 × 6)**, so `length(j$spectra)` returns **6** — the number
of columns — while the library holds **21** spectra (verified against the 21
`<Spectrum=N>` sections in the same library's `.txt`). No error, no warning, 3×
off. `simplifyVector = FALSE` gives the correct 21. This is precisely the class of
bug milestone 0 exists to catch, and it is §4.3 trap 5 (`grep`-counting lines)
reversed: a *parse* that looks richer is the one that lies.

On the *real* checked-in example files everything is instant: the largest text
example (279 254 B, 3 873 lines — `NIST/IARPA3_best_tissue_add_info.head`) takes
0.002 s for `readLines()`, and the largest JSON example (591 549 B, the same
library) reads in 0.034 s;
all 8 text examples are 0.00 s. That is the honest framing — **the real corpus is
too small to measure**, which is also open question 5.

Design implications: (i) full in-memory parse of a mid-size library costs
seconds — an R reader does not need lazy IO to be usable; (ii) `fread` is ~11×
`strsplit` and worth the single `Imports` entry; (iii) use
`simplifyVector = FALSE` and say why in a comment — the reason is the
`length()`-returns-columns trap above, not speed; (iv) **JSON is the slower
serialization in R** (a 13.5 MB JSON parse ≈ a 15 MB text CV parse), so text is
the default read path, which strengthens the case for a sidecar index for large
libraries.

### 4.8 The validator rules are a portable rule language

The rule files are **pure declarative JSON** — keys are only
`id / path / attr / requirement_level` — with a closed predicate vocabulary:
`value_of_type` (`xsd:string` 42, `xsd:float` 17, `xsd:integer` 12,
`xsd:double` 4, `xsd:datetime` 1 — 76 predicate occurrences in all),
`value_is_child_of` (18 occurrences, 18 distinct parents — needs **ontology
traversal**), `value_is_unique`, `value_matches` (regex), plus `combination_logic`
and group semantics [verified: `validate/rules/all.json`,
`validate/semantic_rule.py`]. Requirement split — `all.json` (99 rules):
**MUST 3 / SHOULD 7 / MAY 89**; the profile that is actually usable, `base.json`
(10 rules): **MUST 5 / SHOULD 3 / MAY 2**; `gold` 2, `silver` 3, `single` 2,
`consensus` 1, `peptide` 1. Paths: `/Library` 27, `/Library/Spectrum` 57,
`/Library/Spectrum/Analyte` 12, `/Library/Cluster` 3.

**[verified defect — matters for anyone reusing these files]** The severity key
name is *not* consistent across the rule files. `base/gold/silver/single/
consensus/peptide` use `"level"`; `all.json` uses `"requirement_level"`. The
reference loader reads `rule_spec['level']` (`semantic_rule.py:477`), so the
largest rule set cannot be loaded by its own implementation:

```
>>> load_rule_set('base')     -> RuleSet, 10 rules        (also gold/silver/
                                                            single/consensus/peptide)
>>> load_rule_set('all')      -> KeyError: 'level'
```

I confirmed this by running the loader against a live install for all six
loadable names plus `all`. `all.json` is also not reachable from the CLI:
`mzspeclib validate -p …` accepts only `consensus, single, silver, peptide, gold`
(measured — `-p base` is rejected as "not one of …"). An R validator that wants
the full 99 rules must therefore read the JSON directly rather than assume the
python loader defines the interface — which is an argument for *my* §6 milestone
6 pinning verdicts against the CLI profiles that do load, not against `all`.

**[inferred]** These files are reusable from R as-is, which is a real argument
for the format package owning validation: it keeps R conformance verdicts
aligned with python's by construction. It also creates a coupling to manage —
if the rule files ever move into the spec repo, both implementations should
switch together.

**Where the rule files actually come from — resolves §8 Q2.** The rule JSONs are
not hand-authored, and they are not the normative list. Following the provenance
chain [verified: `validate/rules/tmp/README.md`, `excel_terms_to_json_rules.py`,
`convert_to_xlsx.py`, all dated 2025-03-10 and still shipping in the package]:

```
terms.xlsx  (sheet "general", 25 KB, hand-maintained, self-described
   │         "temporary … This folder and its contents can be removed in the future")
   └─ excel_terms_to_json_rules.py ──► all.json          (machine-readable, generated)
   │                                        │
   │                                        └─(planned: "a Python script will be run
   │                                           in GitHub Actions" to render markdown)
   │                                           — no such CI exists in the repo
   └─ convert_to_xlsx.py (JSON → xlsx, via a psims CV) — review export

~/dev/mzSpecLib/docs/metadata-rules.md  (141 lines, markdown tables)  ← the NORMATIVE list
```

I diffed the normative markdown table against the executable JSONs [measured;
the doc encodes accessions as `[MS:1003186](ols-url)` inside table cells, not as
`MS:acc|name=` lines, so it needs its own parser — first attempt returned 0 rules]:

| comparison | result |
|---|---|
| `docs/metadata-rules.md` ↔ `all.json`, accessions | **97 ↔ 97, exact**: 0 doc-only, 0 json-only |
| value typing (87 machine-typed cells) | **0 mismatches** (`xsd:*` ↔ `value_of_type`, `Children of X` ↔ `value_is_child_of`) |
| `repeatable` | **0 / 97 mismatches** |
| requirement level vs `all.json` | **3 conflicts**: MS:1000525 MAY/SHOULD, MS:1003062 **MUST/MAY**, MS:1003208 MUST/SHOULD |
| requirement level vs `base.json` | **5 conflicts** (charge state, possible charge state, theoretical mass MAY→SHOULD; MS:1003208 MUST→MAY) |
| accessions in `base.json`, absent from the doc | **3**: MS:1000744 selected ion m/z, MS:1000224 molecular mass, MS:1003270 proforma peptidoform ion notation |
| doc cells that are prose, not types | **10** — 5 read `Undefined`, 5 carry editorial text where the JSON has a real predicate (e.g. MS:1003059 `number of peaks` → `xsd:integer`) |
| scopes | doc has **3** (library / library spectra / analyte); `all.json` has rules at `/Library/Cluster` (3) → **cluster rules have no scope in the normative doc** |

So coverage and typing agree exactly, and the drift is confined to *severity* —
which is precisely the field a validator's verdict depends on. Two of the three
`all.json` conflicts are the generator's fault-free consequence of being derived
from a spreadsheet snapshot: MS:1003062 (`library spectrum index`) is a **MUST**
in the spec's own table and a **MAY** in `all.json`, while `base.json` — hand-written,
not generated — *does* enforce it as MUST. The two rule families even disagree
with each other, not just with the doc.

That also explains the `level` / `requirement_level` split from above as
provenance rather than carelessness: `excel_terms_to_json_rules.py` emits
`"requirement_level"`, the hand-maintained profiles use `"level"`, and the loader
reads only `"level"`. Any generated file will reintroduce the bug.

**Consequence for the R design (this is the answer to Q2).** Do not treat
`mzspeclib/validate/rules/*.json` as the source of truth, and do not hard-code
levels either:

1. Vendor the **spec repo's** `docs/metadata-rules.md` into the R package as a
   generated, hash-pinned `metadata-rules.tsv`, with a test that re-derives it
   and fails on drift. The markdown is normative; the JSON is a derivative.
2. Use the python JSONs only as a **differential-testing oracle** — expecting
   disagreement on exactly these 3 + 5 accessions, and recording which side is
   right per the spec, not per the loader.
3. Never assert a verdict on the 3 cluster terms as though the doc covered them,
   and never on `MS:1003062` without picking a side explicitly.
4. **Join the ontology in when generating the TSV, and fail on label disagreement.**
   The diff above compares the doc against python; it cannot see that the doc
   disagrees with *PSI-MS itself*, which it does in 7 of 97 rows and — worse — cites
   a wrong accession in 2 (`MS:1000034` for "intensity unit", `MS:1002875` for
   "inverse reduced ion mobility"; §3.3). So the vendored TSV should carry
   `(accession, doc_label, ols_pref_label, ols_synonyms, agrees)` and its drift test
   should flag rows where `agrees` flips, i.e. track upstream correction of these two
   bugs instead of silently inheriting them. `analysis/cv_label_audit.py` already
   emits exactly that data.
5. **Pin the ontology, and never let a verdict depend on which CV copy the machine
   happens to resolve.** This is not a hypothetical about my implementation — it is
   what the reference implementation does today, measured: `ValueMatches` builds
   `f"{id}|{name}"` from the live ontology and string-compares it to the file
   (`semantic_rule.py:196-201`), so `MS:1000868|SMILES formula` — the spelling that
   was *correct* in psi-ms 4.1.57 — now fails while `MS:1000868|SMILES string` passes
   (`analysis/oracle_probes.py`, probe 2). Three CV copies are already in play in this
   ecosystem and they are not equal: psi-ms **4.1.57** pinned in the python git tree,
   **4.2.6** served by the `psims` that a `pip install mzspeclib` pulls in, and
   whatever OLS holds today. Two facts make this worse for a Python-side comparison
   than it looks: the wheel ships **no** OBO at all (`MANIFEST.in` is exactly
   `include mzspeclib/validate/rules/*.json`, verified against an installed 1.0.7 —
   `mzspeclib/obo/psi-ms.obo` and `validate/rules/tmp/terms.xlsx` exist only in the
   git tree, so the provenance chain of §4.8 cannot be *installed*, only cloned), and
   `INTENSITY_UNITS` (`validator.py:225`) hard-codes five accessions instead of asking
   the ontology, one of them as `" MS:1000814"` with a leading space so it can never
   match. **For the R package this means:** record the PSI-MS version used in every
   validation report; compare on accession and treat labels as display-only; make the
   CV source and version an explicit argument with a pinned default rather than an
   ambient download.

One hard dependency falls out of this: `value_is_child_of` requires PSI-MS
ontology ancestry. **No R package provides PSI-MS CV access** — scanning 25 235
CRAN packages for `psi-ms`, `psims`, `controlled vocab`, `cv term`, `spectral
lib`, `mass spectral`, `adduct`, `universal spectrum` returns **zero** hits
[measured]; the only usable primitives are generic OBO readers
(`ontologyIndex` 2.12, `ontologyPlot`, `ontologySimilarity`). So an R
implementation needs its own small CV access layer regardless of architecture.

### 4.9 The python implementation's layering is *not* a good model to copy

Worth recording, because a naive port would inherit problems:

- **The package cannot be imported without sqlalchemy, pyteomics and psims.**
  `mzspeclib/__init__.py` imports `Analyte` (`analyte.py:5 from pyteomics import
  proforma`) and `index` (`index/sql.py` → sqlalchemy at module level), and
  `backends/base.py:13` imports psims at module level — so *every* format
  backend drags in CV machinery, SQL ORM and ProForma [verified]. There is no
  import path that opens a `.mzSpecLib.txt` without all three.
- **`annotation.py` is 1 line**: `from mzpaf.annotation import *`. The work is
  all in the separate `mzpaf` distribution — `annotation.py` there is
  **1 288 LOC** (1 388 with its `__init__.py` 16 and `reference.py` 84), and the
  parser's centre of gravity is a single inline `re.X` pattern of 1 063
  characters / 33 lines with 13 top-level alternations, compiled twice
  [measured from the PyPI sdist `mzpaf-0.2.0b0`]. mzPAF is therefore a required
  runtime dependency from a separate, pre-release package (`mzpaf 0.2.0b0`,
  single maintainer, no description on PyPI).
- Conversion/ETL backends dominate the code: `msp.py` is 2 557 LOC — 37 % of
  `backends/`, 19 % of the package — and `bibliospec/sptxt/diann/spectronaut/
  encyclopedia` together another ~1 500. These are *vendor importers*, not the
  mzSpecLib format.
- Subsystems: `backends/` 6 963 (of which `text.py` 1 067 and `json.py` 524 are
  the real format), `validate/` 1 574, `index/` 816, `tools/` 320; core data
  model ~2 192 (`attributes.py` 977 is the largest). Tests are correspondingly
  thin: **7 test files, 269 LOC** (304 across `tests/` including 2 helpers and a
  fixture generator) against ~13 252 LOC of package code [measured].

**[inferred]** An R port should be scoped to the format (text + JSON + CV model +
attribute sets + mzPAF + validation), **not** to the python package. Vendor-format
ingestion should stay in the python CLI, which is what Galaxy and bioconda already
depend on. This is the single biggest lever on making the R effort tractable.

### 4.10 mzPAF needs a new parser either way

`specification/peak-annotation-format/annotation.lark`: 88 lines, **41
productions**, 8 ion-series alternatives (peptide `b11`/`y7`, internal `m3:5`,
immonium `I<AA>`, reporter `r[…]`, formula `f{…}`, external `_{…}`, SMILES
`s{…}`, unknown `?`) plus qualifiers (`-H2O`, `+i`, `^2`, `/2.0ppm`, `*0.9`,
`2@` analyte reference). Nothing in R parses ion-annotation strings
[unverified-but-supported: no CRAN hit for any ion-annotation parsing, §4.8].
The spec says users *"SHOULD NOT write their own parser"* and points to a
normative regex **that is not in the repo** — so some reimplementation is
unavoidable; `mzpaf` itself is not reusable in R.

**[inferred, revised after measuring `mzpaf`]** My first estimate was 300–500 LOC
for a "hand-written" parser. Having now measured the python side (§4.9: one 1 063
character `re.X` pattern, 13 top-level alternations, ~1 388 LOC of `mzpaf` around
it), I would not hand-write a recursive descent parser in R, and I do not think
300–500 LOC is credible for anything that claims grammar coverage. Two cheaper
routes, in order of preference:

1. **Port the grammar to a single annotated `regexpr`/`gregexec` pattern** — R
   has per-alternative capture-group reporting (`capture.output = TRUE` on
   `regmatches`-style matching, and PCRE named groups via `perl = TRUE`), which
   maps almost directly onto `mzpaf`'s named groups (`series`, `ordinal`,
   `neutral_loss`, `isotope`, `charge`, `ppm`, …). The grammar is regular enough
   (41 productions, mostly terminal-heavy, and the 8 ion-series alternatives are
   mutually exclusive at their first character) that this should land around
   **150–300 LOC of R plus a table-driven test harness**, and the grammar file
   itself becomes the test oracle.
2. Generate a parser from `annotation.lark` with an R parser-generator — no
   maintained one exists in the ecosystem I surveyed, so this is more work than
   route 1 and I do not recommend it.

Either way, adopt an *opaque-but-typed* representation: store the annotation
string verbatim, parse on demand, and **never round-trip through a lossy parse**
— that single decision removes the whole class of "R disagrees with python about
`b11{2-4}`" defects.

**The normative grammar and the reference implementation do not accept the same
language [verified].** This is the most consequential thing I found about mzPAF,
and it decides which artefact an R implementer should treat as normative:

| artefact | ion-series symbols accepted |
|---|---|
| `annotation.lark:33,67` (normative) | `a x b y c z` only, then an ordinal |
| `mzpaf/annotation.py:32` (the parser python actually uses) | `(?:da\|db\|wa\|wb)\|[axbyczdwv]\.?` — i.e. adds **w, v, d** and the `da/db/wa/wb` dimers, allows a trailing `.` (`b.`), and adds a `precursor` alternative `(?P<precursor>p)` and `:?I…` forms |

So `w1` is legal per the reference implementation and **illegal per the shipped
grammar** — and this is no longer a defect only this report noticed: OpenMS #10175,
*"Support satellite ions (d, v, w) — currently an mzPAF v1.0 conformance gap"*
(open, 2026-09-17, title verbatim) is a third implementation reporting the same
seam [verified via the GitHub API]. `grammar.md`/`grammar.py` add a third opinion — their SVG rail
diagrams diverge from the `.lark` too. My recommendation: implement to
`annotation.lark` (it is the only artefact the standard ships as normative),
make the parser *permissive-by-flag* so `w/v/d/da/wa` can be accepted for
real-world data, and record every accepted-but-ungrammatical form in a test so
that when the spec resolves this — and it needs an issue — the R package is the
implementation that already has the evidence. Two smaller defects in the same
file, worth upstreaming: `annotation.lark` defines `is_auxiliary` **twice** (41
definitions, 40 unique), and the normative regex the prose points at is absent
from the repo.

---

### 4.11 Conformance hazards to pin on day one

Each of these is measured against the reference implementation, not inferred, and
each one is a test the R package will fail unless it decides deliberately what to
do. They are the practical content of milestone 1.

| # | Hazard | Evidence |
|---|---|---|
| 1 | **`mzspeclib validate` exits 0 even when MUST rules fail.** I deleted the `library format version` (MS:1003186) line from a real example and re-ran `validate -p gold`: **exit 0**. The pristine file also exits 0 while reporting **12 MUST + 24 SHOULD violations**. Exit status is therefore *not* usable as a pass/fail signal, by any tool or in CI. [measured: `python -m mzspeclib.tools.cli validate -p gold …`] **Re-run 2026-10-22 on 1.0.7, and it is worse than this row first said:** deleting that MUST attribute changes the validator's *output* not at all — the violation inventories of the stripped and pristine files are identical (`diff` empty across 36 normalised violation lines per run) and `MS:1003186` is never mentioned. So the `gold` profile does not merely tolerate the failure silently; it does not detect it. | `tools/cli.py:validate` never sets a failing exit code; only `click.Abort()` on *load* failure does. Exit codes and violation inventories re-measured 2026-10-22 on `mzspeclib` 1.0.7 |
| 2 | **The spec's own example files violate MUST rules.** Under `-p gold`: spice **12 MUST / 24 SHOULD**; broad_tcga **20 MUST / 617 SHOULD**. An R validator that is *stricter* than python will look broken on day one. Both figures reproduce on 1.0.7. | measured over all 7 real example `.txt` files; spice and broad_tcga re-measured 2026-10-22 (12/24 and 20/617, both exit 0). **Counting caveat:** the CLI emits every violation *twice* — once from `mzspeclib.validate.validator`, once from `__main__ | cli.py:validate:240` prefixed with `... ` — so `grep -c '(MUST)'` over its output reports exactly double. My 2026-10-22 first pass did exactly that and got 24/48; the correct count keeps one logger. A second caveat found the same day: every line carries an `[HH:MM:SS]` wall-clock prefix, so two runs of the *same* file emit 42 non-identical lines for 21 identical violations — inventories compare only after timestamp, logger/location prefix and the `... ` echo are stripped and the two copies folded (`analysis/viol_inventory.py`; §4.15 item 3). |
| 3 | **The largest rule set cannot be loaded by its own loader** (`load_rule_set('all')` → `KeyError: 'level'`, because `all.json` uses `requirement_level` where the loader reads `level`), and the CLI cannot even select `all` or `base`. Reproduced 2026-10-22 on 1.0.7, where the same call loads `base` (10 rules) and `gold` (2) cleanly — so the breakage is specific to `all.json`, not to a stale environment. | `semantic_rule.py:477` vs the rule JSONs; measured, re-measured 2026-10-22 |
| 4 | **CV-driven value typing is part of the format**, not an afterthought: python casts every value through the PSI-MS term's `value_type` and only falls back to a heuristic `try_cast` when the term is unknown (`text.py:779-786`). An R reader that keeps everything as `character` will disagree with python about `collision energy=40.0`. | `backends/text.py:779-786` |
| 5 | **Attribute-set counting is off by convention:** python pre-seeds `"all"` into all four set dicts (`base.py:219-230`), so "number of attribute sets" differs between an implementation that reports declared sets and one that reports live dicts. Measured cell by cell 2026-10-22, and the gap is *not* a constant: declared → reported is 1→4 (spice), 3→4 (IARPA3, broad_tcga, phl004, human_serum) and 4→5 (fetal_brain_tiny) — exactly one phantom per scope the file never mentions, which in six of six files includes `cluster`. Two accessors exist and only one is the sets themselves: they live on `lib.{spectrum,analyte,interpretation,cluster}_attribute_sets`, whereas `lib.attribute_sets` / `sp.attribute_sets` resolves the *reference* attribute `MS:1003212\|library attribute set name` (`attributes.py:470-476`, `const.py:12`) and returned `[]` on all six examples — an accessor that makes a conformance test pass on an empty list. | `analysis/oracle_counts.py` (prints the per-scope member names per file); 1.0.7. An earlier draft of this row said "3 reported" for spice, from an accessor that is no longer reconstructible; 1.0.7 reports 4 |
| 6 | **Cluster attribute sets are read and written but never *populated* by the JSON writer.** `write_header` (`json.py:362-374`) emits spectrum/analyte/interpretation sets — there is no `buffer[CLUSTER_CLASSES] = …` anywhere in the file — so a text→JSON→text round trip cannot preserve `<AttributeSet Cluster=…>` even though `_fill_attributes` handles it on read (`json.py:212`). | measured (`json.py` `write_header`, absence of any `CLUSTER_CLASSES` write) |
| 7 | **Clusters exist in the reader, and in zero example files.** All 7 real `.txt` and 2 `.json` examples have 0 clusters, so no round-trip test data for them exists upstream. The R package will be the only implementation with cluster fixtures unless someone authors them. | measured (`grep -c '<Cluster'`, `len(clusters)` in JSON) |
| 8 | **Comments are `#`-only, first character, and deliberately not round-tripped.** The spec is explicit (§4.1.18, verbatim): *"Comments are permitted purely for human discussion and are generally NOT transcribed to other serializations."* The python reader agrees and says so in a comment: `# Skip comments for now, no round-trip` (`text.py:408`). So *losing* comments on conversion is standard-conformant — do not "fix" it, but do preserve them on same-format rewrite. **Executed 2026-10-22, the reference reader's comment handling turned out scope-dependent:** a comment inside the library header stops its header parser (`ValueError: Malformed attribute line`, `text.py:577`) while a comment in a spectrum section is skipped, and a comment *before* `<mzSpecLib>` makes `read_header()` return `False` silently, after which `read()` dies with `ValueError: Could not locate valid header` (`base.py:522`) — defensible against §4.1.1 (*"MUST begin with the line `<mzSpecLib>`"*), but the header crash contradicts §4.1.18, which restricts comment placement nowhere (§4.15 item 2). | spec PDF §4.1.18/§4.1.1; `backends/text.py:408`, `:577`, `base.py:522`; `analysis/oracle_defects.py` probe 5 |
| 9 | **The JSON writer sorts every key alphabetically** — top level is `analyte_attribute_sets, attributes, clusters, format_version, interpretation_attribute_sets, spectra, spectrum_attribute_sets`, and each spectrum is `analytes, attributes, intensities, interpretations, mzs, peak_annotations`. The spec does not mandate key order, but any R writer that wants the byte-stable round-trip demanded by milestone 2 must match it (and match alphabetical sorting of attribute lists). | measured (`json.load` key order on both shipped `.json` examples) |
| 10 | **`jsonlite::fromJSON(simplifyVector = TRUE)` reports the wrong number of spectra** — `spectra` becomes a 21 × 6 data.frame, so `length()` returns 6 instead of 21. Silent. Use `simplifyVector = FALSE`. | measured (`analysis/json_modes.R`) — see §4.7 |
| 11 | **Two different libraries are checked in under the same filename.** `mzspeclib-rs/test/data/fetal_brain_tiny.mzSpecLib.txt` is 148 670 B / 5 347 lines (`md5 171c1984…`) while `mzSpecLib/examples/SpectraST/fetal_brain_tiny.mzSpecLib.txt` is 165 046 B / 5 600 lines (`md5 5486d815…`). A fixture harness that keys on basenames will silently compare across versions. | measured (downloaded both, `md5sum`/`wc -l`) |
| 12 | **The same accession carries two surface labels in the corpus**: `MS:1003061` appears as `library spectrum name` 118× and `spectrum name` 2×. Nothing in the examples is validated against the CV's preferred label, so a reader must key on **accession**, never on the name string. — **Sharpened 2026-10-22, because the reference implementation does the opposite and it is not cosmetic:** python's rules match on the **composite** key, `AttributeSemanticRule.attribute = f"{accession}|{name}"` (`semantic_rule.py:258-260`). So when the normative table's accession and a real file's accession disagree (§3.3's `MS:1000034` vs the corpus's `MS:1000043\|intensity unit`, 23 occurrences), the rule does not fail — it **matches nothing and is silently skipped**, with no "rule never fired" diagnostic anywhere in the output. Keying on accession alone is the safer design precisely because it fails loudly instead. | code read at the cited lines + §3.3's measured counts |
| 13 | **A validation verdict can change without the file changing**, because `ValueMatches` composes `f"{id}|{name}"` from whichever ontology copy the machine resolves and string-compares it to the file (`semantic_rule.py:196-201`). Both directions executed: `MS:1000868\|SMILES formula` (correct under psi-ms 4.1.57) → **False**, `MS:1000868\|SMILES string` (current) → **True**. Three different PSI-MS versions are already in circulation in this ecosystem (4.1.57 pinned in git, 4.2.6 via `psims`, whatever OLS serves). | `analysis/oracle_probes.py` (executed, mzspeclib 1.0.7) |
| 14 | **The validator's intensity-unit check is a hard-coded 5-element tuple, and one element cannot match**: `INTENSITY_UNITS = ("MS:1000131", "MS:1000132", "MS:1000905", " MS:1000814", "UO:0000269")` — `MS:1000814` *counts per second* carries a leading space, so `*counts per second*` never validates as an intensity unit even though the walk in §3.3 proves it is a child of `MS:1000043`. Two lessons in one line: string equality on accessions is fragile, and an allow-list silently duplicates what the ontology already knows. | `validate/validator.py:225`, printed by `analysis/oracle_probes.py` |

The point of tabulating these: **the reference implementation is not a
specification.** Where python and the spec disagree, an R implementation needs a
written decision, and where python is silently wrong (rows 1–3, and now also 13–14,
both added by executing the library rather than reading it), R should not inherit the
bug. Rows 13 and 14 differ from the rest in kind: they are not format hazards but
*verification* hazards — they mean a pass can become a fail with no change to the
file, which is why §7 now carries a CV-version risk row and milestone 7 has to report
the CV version it validated against.

### 4.12 The R backend already exists — which reframes the question

**This is the single most consequential finding added on 2026-10-22, and it
invalidates the "no demand signal" premise of the first draft.**

`RforMassSpectrometry/MsBackendMzSpecLib` exists. Not a wish in an issue tracker —
a repository under the RfMS org, by the people who maintain `Spectra`
[all verified via the GitHub API + raw sources on 2026-10-22]:

| | |
|---|---|
| created / last push | 2026-10-16 / **2026-10-22** (today) |
| authors | Gabriele Tomè, **Johannes Rainer** (`aut`, `cre`) — Rainer maintains `Spectra` |
| version / licence | `0.97.0` (Bioconductor sprint version) / `Artistic-2.0` in DESCRIPTION (no LICENSE file detected by GitHub) |
| `Depends` / `Imports` | `R (>= 4.6.0)` / `MetaboCoreUtils (>= 1.21.2), Spectra, methods` |
| biocViews | Infrastructure, MassSpectrometry, **Metabolomics**, DataImport, Proteomics |
| funding | MetaRbolomics4Galaxy project, Autonomous Province of Bolzano (named in DESCRIPTION + README) |
| code so far | `R/` = 4 files, ~5.3 kB total, **no parser**; plus `inst/txt/mzSpecLib-mapping.txt` (9.5 kB) |
| history | issue #1 (2026-10-16, jorainer): *"Create mapping `data.frame` from mzSpecLib attributes to `Spectra` `spectraVariables`"* → PR #2 (merged 2026-10-20, 6 comments) added the TSV + translation helpers + the class skeleton → **PR #3 opened 2026-10-22: "base function to open connection to mzSpecLib file"** |

So the mapping layer was built first and the reader is being started *this week*.
That ordering is precisely what §4.2 predicts is backwards, and I could measure
the consequence, because their mapping table is public data:

| what happens to a real spectrum-level CV occurrence under the **official** mapping | occurrences | share |
|---|---|---|
| lands on a genuine Spectra spectraVariable (`peaksCount`, `rtime`, `precursorMz`, `collisionEnergy`, `polarity`, …) | 509 | **10.7 %** |
| lands on a **newly invented custom column** (`contributing_replicate_spectrum_usi`, `spectrum_aggregation_type`, `library_attribute_set_name`, …) | 2 095 | 44.2 % |
| has **no row at all** in the 98-term mapping → `NA` / dropped | 2 138 | **45.1 %** |

[measured: `inst/txt/mzSpecLib-mapping.txt` (98 rows, 98 distinct `cv_term`,
`domain`: library 30 / spectrum 56 / analyte 11 / spectrum\|analyte 1) joined
against all 4 742 spectrum-scope-and-below CV occurrences in the 8 real example
libraries; script in `analysis/`, cf. `mapping_gap.R`]

Three things follow, and they are the reason to keep reading rather than re-litigate §5:

1. **My §4.2 estimate is corroborated by the other side's own artefact.** I
   predicted 11.8 % mappable onto core spectraVariables from Spectra's 19
   variables alone; their table, built independently by the `Spectra` maintainer,
   delivers **10.7 %**. Two independent estimates agreeing to ~1 point on a real
   corpus is as close to a settled number as this survey gets.
2. **"Everything is mapped" is an illusion created by custom columns.** All 98
   rows *have* a `spectra_variable`, which reads as 100 % coverage, but only 10 of
   the 98 targets are real Spectra variables; the other 88 are ad-hoc names whose
   semantics live in one TSV. `MsBackendMemory` will hold them, so nothing
   crashes — the meaning is simply not shared with any other backend, which is the
   §4.2 "private representation *is* the format package" argument, now observed.
3. **The analyte level is being flattened onto the per-spectrum table** — 12 of
   the 98 rows carry `domain=analyte` (`SMILES formula`, `adduct ion formula`,
   `theoretical mass`, taxonomy, `sample label`, and `charge state` as
   `spectrum|analyte`). mzSpecLib allows **0..N analytes per spectrum**, so a
   single-valued per-spectrum column silently assumes 1:1. Every example library
   happens to be 1:1 (fetal_brain_tiny: 21 spectra, 21 `<Analyte>` sections), so
   upstream data cannot catch this — a chimeric or multi-analyte library would.

It is also worth recording what they got **right**, because it constrains my own
design: the TSV's `required` column agrees with the spec's normative MUST/SHOULD/MAY
on **98/98** rows, and it lists `MS:1003204 constituent identification file` +
`MS:1003205 constituent library file` as **two distinct terms** — i.e. it already
fixes the duplicate-accession defect that the normative table and `all.json` still
carry (§4.8), which is exactly what Rainer's own spec-repo issue #95 (2026-10-19,
still unanswered) asks about.

What it does not (yet) cover: the JSON serialization; `[group]` CV parameter
groups; attribute-set inheritance; clusters; interpretation members; any index;
and any deployment outside Bioconductor (`Depends: R (>= 4.6.0)` + hard
`Spectra` import means §4.5's Galaxy/conda argument is untouched).

**Effect on the decision.** Option B is not a hypothetical alternative any more —
it is funded work in the RfMS org, and it will ship. The live question is therefore
narrower and much more answerable: **what should `MsBackendMzSpecLib` read
through?** Option A's core package is now candidate infrastructure for a real
consumer rather than a package seeking a purpose; and the cheapest contribution to
make is a parser + conformance fixtures under their backend, not a competing
backend. See the revised §6.

### 4.13 Adoption outside python — and what the only large real corpus actually looks like

Three things the first draft could not say, added 2026-10-22. All were verified
against primary sources (API responses, raw files, `HEAD` requests); the research
pass that collected them reported that the search tool returned fabricated
results, so nothing here rests on a search snippet — every claim below names the
file or endpoint I read.

**(a) The standard has a positive statement in its favour, and four non-python
codecs.** The spec itself, §3.4, verbatim: *"Lossless interconversion between
these serialization methods is provided by a reference implementation Python
library … **other implementations are welcome and forthcoming**."* PSI's registry
lists **Python** and **Rust** under "Implementations" — the Rust entry points at
`rusteomics/mzcore`'s `mzannotate` module, which I confirmed ships both a reader
and a writer (`src/mzspeclib/{read,write}.rs`, plus a `fuzz/fuzz_targets/mzspeclib.rs`
target and 7 example libraries in `data/`). Shipping third-party support also
includes **Galaxy**, which merged native mzSpecLib datatypes for both
serializations on **2026-09-11** (PR #22888, `merged=true`, title *"Add mzSpecLib
datatype support (JSON and text formats) for proteomics spectral libraries"* —
verified via the API). Four further tools touch
the format in code, each verified by code-searching its repository for
`mzspeclib` hits and reading the file that owns the support
[verified 2026-10-22, GitHub code-search API]:
`sage-plus` (14 hits, `crates/sage/src/spec*`, `FEATURES.md`),
`timsbuktoolkit` (44 hits, `rust/timsquery/src/serde/mzspeclib_io.rs`),
`msspeculator` (17 hits, `rust/inference/src/mzspeclib.rs`), and
**`spxtacular`** (16 hits, `src/spxtacular/mzspeclib.py`, `docs/mzspeclib.md`) —
the last of these deserves its own paragraph, because it is the closest existing
answer to the question this report was asked. OpenMS carries an open,
specific request — #10172 *"Add mzSpecLib (HUPO-PSI spectral library standard)
read/write support"* (2026-09-17) — **and an open conformance bug, #10175
*"Support satellite ions (d, v, w) — currently an mzPAF v1.0 conformance gap"*,
which is independent confirmation of §4.10**: the spec's `annotation.lark` grammar
does not accept the `w`/`v`/`d` series that the reference parser's regex does, and
a third implementation has now hit exactly that seam.

**And there is a fifth tool that adopts the annotation layer only.** `koina`
(`wilhelm-lab/koina`, a Triton model zoo for proteomics ML) contains no mzSpecLib
code — but its Altimeter 2024 model cards state, verbatim, *"Annotations follow the
[mzPAF](https://www.psidev.info/mzPAF) specification"* (two `notes.yaml` files, read
in the fetched tree by `analysis/tool_tree_grep.sh`), and the model code carries an
ion-annotation object with a neutral-loss string accessor. So a tool in active use
publishes mzPAF annotation strings without ever producing an mzSpecLib file. Two
things follow for the design: the mzPAF parser (milestone 4) is worth exposing as a
**public, standalone entry point** — `parse_mzpaf()` is useful to people who have a
TSV of annotations and no library file — and §4.14's zeros should be read as
"absent at the *file* layer", which is a narrower claim than "unused".

**The two negatives are also verified, and the interesting one is not a
refusal.** `matchms/matchms` is **write-only** today: #752 *"Implement mzSpecLib
export"* and #757 landed (closed `completed`, March 2025) and ship as
`matchms/exporting/save_as_mzspeclib.py`, while #751 *"Implement support for
mzSpecLib"* and #758 *"Implement import for mzSpecLib"* were both closed
**`not_planned`**. Read together: the main small-molecule similarity library will
*hands you* mzSpecLib and will not take it back — which is a demand signal for a
**reader**, in precisely the domain §4.2 found has no upstream test data. (Its
exporter also maps 4 analyte + 5 spectrum attributes and standardises
`collision energy` with a `UO:0000266|electronvolt` unit — a real, correct use of
the grouped-unit form this report's own benchmark corpus had to be corrected to.
And its test file is `Hydrogen_chloride.mzspeclib`: a **fourth** extension
spelling, joining `.mzSpecLib.txt`, `.mzspeclib.txt` and `.mzlib.txt`.)
**ProteoWizard refuses the format outright**: `CarafeSharp.Proteome/LibraryOutputs.cs:69-70`
throws `NotSupportedException("-lf_type mzSpecLib is not supported by CarafeSharp")`,
its own doc comment at `:32` says *"`mzSpecLib` is not ported"*, and
`CommandLineErrorTest.cs:96` asserts the failure. So the adoption picture is:
**real and accelerating in proteomics-adjacent infrastructure (Galaxy, Rust,
python CLI, prediction tools), explicitly refused by the flagship quantification
toolchain, and in metabolomics asymmetric — writers yes, readers no.**

> **Note how this re-reads §4.5.** R is not behind because R is unloved: the
> non-python codecs that shipped are all in ecosystems whose users run
> command-line or Rust-native pipelines. The R gap is a *deployment-surface* gap
> (§4.5), not a demand gap.

**(b) The only large real mzSpecLib files in existence are nothing like the spec's
examples.** Zenodo record **10.5281/zenodo.13685813** (Noble Lab multi-species
benchmark, *Sci Data* 2024, `10.1038/s41597-024-04068-4`, CC-BY-4.0) deposits
**99.0 GB** across four archives (59.5 + 25.7 + 8.3 + 5.5 GB; sizes verified by
`HEAD`, e.g. `nine-species-balanced.zip` = 5 531 428 474 B), whose `main`/
`balanced` members are mzSpecLib text — ≈ 7.4 GB decompressed in `balanced` alone,
largest single member ~1.8 GB. This settles open question 5: **a 100 MB+ library
exists**, so the indexing question is answerable with real data.

I then read the producer's source rather than trusting the deposit
(`Noble-Lab/multi-species-benchmark` → `MGFUtils.mgf2mzSpecLib`), and what it
writes is a strict subset of the format — which changes what "large library" means
for a reader:

| property of the only large real corpus | value | why it matters |
|---|---|---|
| magic line | `<mzSpecLib 1.0>` (hardcoded, `MGFUtils.java:97`) | the spec's own examples use bare `<mzSpecLib>` — a reader that `==`-compares line 1 fails on 100 % of the large real files, which is exactly the check `proto_reader.R:37` performs |
| file extension | **`.mzlib.txt`**, not `.mzSpecLib.txt` | extension-based detection misses them entirely. **Four spellings now coexist**: HUPO-PSI/spec `.mzSpecLib.txt`, Galaxy + `mzspeclib-py` + `mzcore` + tims `.mzspeclib.txt`, Noble `.mzlib.txt`, matchms `.mzspeclib` (no second suffix). `rusteomics/mzcore/data/` alone carries **both** `.mzSpecLib.txt` (6 files) and `.mzspeclib.txt` (2), including `fetal_brain_tiny.mzspeclib.txt` next to `fetal_brain_tiny_consensus_td.mzSpecLib.txt` — one implementation, two spellings, same library |
| `MS:1003186\|library format version` | **absent** (0 occurrences in the writer) | the one MUST term the spec's rule set opens with; a validator that treats it as fatal rejects the entire real corpus |
| `<AttributeSet>` sections | **absent** | milestone 3's override semantics are exercised by no real file at any scale |
| distinct CV terms emitted | **11** | at real scale the workload is ~peaks + 11 terms, not 97 |
| of those 11, terms absent from the normative rule table | **5** (`MS:1001121`, `MS:1001362`, `MS:1000888`, `MS:1003275`, `MS:1003276`) | real-world usage already exceeds the normative set, in both directions — the corpus uses terms the rules never enumerate |
| of those 11, terms with a row in `MsBackendMzSpecLib`'s mapping | 6 (55 %) — **3 onto real Spectra variables** (27 %) | the lossy path loses the interpretation-scoped matched/unmatched peak counts and the `[group]`-paired other-attribute pairs, i.e. the *structural* losses, not the exotic terms |

**Design consequences, and they are cheap to honour now:** detect mzSpecLib by
*content* (first non-blank line matches `^<mzSpecLib(\s+[\d.]+)?>$`) rather than by
extension or exact string; treat a missing `MS:1003186` as a warning, not an error,
and say which convention you assumed; keep the reader's term set open (no
hard-coded field list), since 5/11 of a real producer's terms are outside the
normative rule table; and use one of these Zenodo members — not a spec example —
as the milestone-8 index benchmark, since it is the only file large enough to make
the question non-hypothetical.

**(c) Somebody has already run this experiment in python, and they landed on
Option A.** `spxtacular` (`tacular-omics/spxtacular`, "Chainable Spectrum API for
MS processing") is a Spectra-shaped spectra library that is *not* HUPO-PSI's
reference stack: `src/spxtacular/mzspeclib.py` implements mzSpecLib 1.0 itself —
its own `CvParam` / `Analyte` / `Interpretation` / `LibraryEntry` /
`SpectralLibrary` model, its own mzPAF parser (`paftacular`) and ProForma parser
(`peptacular`), and no import of `mzspeclib-py` anywhere in its import list
[verified: raw module, docstring + imports]. What matters here is how that module
sits relative to its spectra abstraction (docstring, verbatim):

- *"the spectrum becomes an `MsnSpectrum` (precursor m/z and charge, retention
  time, ion mobility, polarity, collision energy, dissociation method, MS level,
  scan number, TIC, injection time)"* — a flat per-spectrum record, the same shape
  as an `MsBackend` (§4.1);
- *"**every attribute without a field keeps its CV form in an `attributes`
  tuple**"* — the 88 % is carried through rather than dropped (§4.2);
- *"Reading resolves attribute sets … into each element. **Writing never emits
  attribute sets.**"*;
- *":func:`read_mzspeclib` returns the whole library;
  :class:`MzSpecLibReader` streams it one entry at a time."*

That is the Option-A shape arriving in a third ecosystem by a route that had
nothing to do with this report: an mzSpecLib object model that exists
independently of the spectra object, a mapping layer into the flat record, and an
explicit carry-through for what the flat record cannot hold. Two implementation
details are worth stealing directly — a streaming reader class separate from the
whole-library loader (exactly §6's "usable as an engine" boundary), and the CV
tuple as the lossless remainder. And the admitted write-side asymmetry is
*the same class of defect as §4.11 row 6* in the reference implementation
(attribute sets survive reading, vanish on writing): two independent
implementations making the same round-trip mistake is a structural property of
this format, not two slips, and milestone 5's round-trip test must assert on
attribute sets specifically. Honest limit: I read its source, not its test suite,
and its model is a python model — this corroborates the **architecture**, not any
number in this report.

### 4.14 Where mzSpecLib is demonstrably *absent* — with the scope each negative carries

A survey that only lists what supports the format has a known bias, so this section
records the negatives — and, because a zero found with a broken query is
indistinguishable from a zero found with a working one, **every zero below is
printed next to a positive control on the same index**, and next to a statement of
what the search could not see. Two of these searches had already been run once and
got the answer wrong (one with both grep terms typo'd to the same string, one
against an endpoint that silently ignores its own query parameter), so the controls
are not decoration. `analysis/db_absence_probe.py` re-runs the repository half of
this table.

| source | scope actually searched | mzSpecLib | positive control (same index) | verdict, and what it does *not* establish |
|---|---|---|---|---|
| **MassIVE** | all **20 428** dataset-metadata records (21 pages of `ProteoSAFe/QueryDatasets`, 56.4 MB) | `mzspeclib` 0, `mzspec` 0, `mzpaf` 0, `mzlib` 0 | `mzxml` 550, `mzml` 168, `blib` 10, `.msp` 2 | no dataset *metadata* mentions mzSpecLib. `row_data` carries `file_count`/`fileSizeGB` but **no filename list**, so this does **not** exclude an mzSpecLib file *inside* a dataset. [measured: `db_absence_probe.py --massive`] |
| **MetaboLights** | EBI Search index `metabolights` (study metadata) | 0 | `glycerol` 938, `mzML` 344, `spectral library` 561 | no study metadata mentions it; **not** "no study FTP directory contains one" |
| **PRIDE** | EBI Search index `pride` | 0 | `glycerol` 2 171, `mzML` 790, `spectral library` 2 200 | same scope limit |
| **FragPipe** | GitHub issue search `repo:Nesvilab/FragPipe mzspec` | 0 | `"spectral library"` in the same repo → **329** | no feature request, no discussion. (The org `FragPipe` does not exist — `orgs/FragPipe` → 404; the tracker is `Nesvilab/FragPipe`.) Docs host `fragpipe.nesvilab.org` reachable, `docs.nesvilab.org` → NXDOMAIN |
| **Spectronaut** (Biognosys) | the vendor's own product page, 445 591 B | 0 for `mzspeclib\|mzpaf` | page contains its normal feature text | **scope this hard:** "no mention on a fetchable vendor page". `biognosys.net` is *unregistered* (DNS `Status: 3` NXDOMAIN at both Google and Cloudflare, RDAP → 404); the live site is `biognosys.com`. Spectronaut's library-export format list is not published on any page I could fetch, so **"Spectronaut does not support mzSpecLib" is not established** |
| **ProteoWizard / Carafe** | source code | — | — | the one *hard* negative, because it is in code rather than in the absence of text: `LibraryOutputs.cs:69` throws `NotSupportedException("-lf_type mzSpecLib is not supported by CarafeSharp")` (§4.13) |
| **Five analysis tools, whole source trees** — `wilhelm-lab/koina` (951 files), `smith-chem-wisc/FlashLFQ` (78), `Nesvilab/MSBooster` (202), `sirius-ms/sirius` (3 690), `bittremieuxlab/spectrum_utils` (60) | the **complete default-branch working tree** of each, fetched as tarballs and grepped (`analysis/tool_tree_grep.sh`) — *not* GitHub code search, which rate-limited the controls on the first attempt | `mzspeclib` **0 files in all five**. `mzpaf` 0 in four, and **2 in koina — which is a hit, not a miss**, see the paragraph below | per-tool controls in the same trees: `peptide` 243/24/95/20/12 files, `mgf` 3/8/19/43/1 files, `spectral library` 4/0/14/51/1 files. Every grep is live | these are now **established**, replacing the first pass's rate-limited zeros. Scope: the source tree only — not wikis, issue text, vendor docs, closed editions, or separately-installed plugins. "No mzSpecLib code in the tree" ≠ "cannot support it" |
| **"DIAlect"** | repo/registry/literature search | — | — | **withdrawn.** A research pass proposed this tool as an mzSpecLib consumer; no repository of that name in proteomics could be located (GitHub repo search returns `dialect-app/dialect`, a GNOME translation app, and the two code hits are the English word in someone else's README). **No claim is made about it.** |

**The one hit among the zeros, and why it matters more than the zeros.** koina's
Altimeter 2024 model cards (`models/Altimeter/Altimeter_2024_intensities/notes.yaml`
and `…_isotopes/notes.yaml`) state, verbatim: *"Annotations follow the
[mzPAF](https://www.psidev.info/mzPAF) specification."* Its code carries an ion
annotation object with a neutral-loss string accessor (`…/Altimeter_2024_filter_splines_index/1/model.py`,
`annot.getNLString()`). So a widely-used prediction service publishes mzSpecLib's
**annotation layer** without touching its **file layer** — which is direct evidence
for the §6 recommendation to keep the mzPAF parser (milestone 4) a separately usable
entry point rather than a private detail of the reader, and evidence against reading
§4.14's zeros as "nobody uses any part of this".

**Two substring traps found on the way, kept because they justify the controls.**
`mzlib` — one of the four terms swept across MassIVE in §4.14's first row — matches
**14 files in FlashLFQ**, all of them `PackageReference Include="mzLib"`, i.e. PNNL's
*unrelated* spectral-library format (FlashLFQ even runs a CI job that watches mzLib's
releases). It also matches **1 file in SIRIUS**, inside base64 in a minified JS bundle.
A grep for `mzlib` with no controls would have "found" mzSpecLib in two tools that
have never heard of it.

Three things follow, and they are the reason this table is worth a section rather
than a footnote:

1. **No public mass-spectral repository distributes mzSpecLib files.** Every one of
   the archives that a reader would normally pull test data from — MassIVE,
   PRIDE, MetaboLights — is silent on it at the metadata level, and the one place
   real files exist is a single Zenodo deposit with a non-conformant extension and
   magic line (§4.13). For this project that is an engineering constraint, not a
   curiosity: **the fixture corpus has to be constructed** (spec examples + Zenodo
   slices + converter output), and "grab a library from the web" is not a test
   strategy. It also caps how large the near-term user base can plausibly be.
2. **Adoption is code-mediated, not data-mediated.** Everything that handles
   mzSpecLib does so because it *writes* it (Galaxy datatypes, `sage-plus`, the
   tims tools, `msspeculator`, `matchms` export, the Noble deposit); nothing
   *distributes* it. A reader is therefore ahead of the ecosystem — which is an
   argument for building one, and simultaneously an argument for keeping it cheap.
3. **The negative space is now measured, not assumed — and it is narrower than "the
   tools refuse it".** The five analysis tools whose zeros a previous pass could not
   re-verify (GitHub rate-limited the *control* queries mid-check) are now established
   by grepping their complete default-branch source trees with live controls
   (`analysis/tool_tree_grep.sh`), so "no mzSpecLib code in koina, FlashLFQ, MSBooster,
   SIRIUS or spectrum_utils" is a measurement rather than a gap. What is still **not**
   established is any claim about vendors' *products*: Spectronaut's support matrix is
   not published on a page I could fetch (`biognosys.net` is not even registered), and
   a source tree says nothing about a closed edition. So "flagship quantification
   tools refuse mzSpecLib" rests on exactly three things — ProteoWizard's thrown
   `NotSupportedException`, FragPipe's issue-tracker silence, and five empty source
   trees — while the one positive found at the annotation layer (koina declaring its
   Altimeter annotations mzPAF-conformant, above) points the other way.

---

### 4.15 The first release, measured against the oracle (added 2026-10-22, post-release)

Everything above this section was written against a package that did not exist.
`mzspeclib` 0.1.0 was released the day of this revision (NEWS.md), so the second
2026-10-22 pass turned the reference implementation around and pointed it at the
R package's output. Five things came out of it; each number below is from
`analysis/oracle_defects.py` (six executed probes), `analysis/viol_inventory.py`
or `analysis/count_tool_sweep.sh`, all re-runnable, and the file:line cites are
the installed mzspeclib 1.0.7, which `diff -q` confirmed byte-identical to
`~/dev/mzspeclib-py` for `backends/json.py` and `backends/text.py`.

**1. Interoperability: the text serialization is indistinguishable to the oracle;
the JSON one is not yet.** Read back through `TextSpectralLibrary` after a
R-reader → R-writer pass, the NIST IARPA3 head library reports *cell-for-cell
identical* counts — header attributes 634, spectra 20, peak rows 1 474, analytes
20, interpretations 20 (probe 6, same command on the original file) — and its
normalised gold-profile violation inventory is **IDENTICAL** (21 SHOULD, nothing
added, nothing dropped; same verdict for the small library at 2 SHOULD —
"orig txt vs r text: IDENTICAL" as `viol_inventory.py` prints it). The R JSON
writer's output reports the same spectrum-scope counts (20/1 474/20/20), but two
things differ, and neither is a lost byte: the header attribute count shows
1 268 = 2 × 634 — probe 6 calls `read_header()` once explicitly on top of the
constructor's automatic call, the same calling pattern used for the text files,
and it is exactly this extra call that doubles a JSON header (item 2; with a
constructor-only read the JSON header also reads 634) — and the violation
inventory grows by exactly the value-type MUST family: 15 additional MUSTs on the
example library, 34 on the IARPA3 head, 0 removed, every one of the form *"The
value type of … must be a value of type xsd:float, but got <class 'str'>"* (all
four comparisons: `analysis/viol_inventory.py`). Milestone 5's acceptance
("violation counts unchanged") is therefore met by the text writer and missed by
the JSON writer, and item 2 shows *why* — it is the value-typing decision,
with an invoice attached, not a serialization bug. One count comparison to keep
honest about: the package's shipped example is an **excerpt** of
`fetal_brain_tiny_consensus_td` — its 556 non-blank non-comment lines are a
byte-identical prefix of the original (line-by-line prefix comparison: 556/556
match) — so its counts are a third of the original's for spectrum-scoped
quantities only (3 of 10 spectra, 392 of 1 242 peak rows ≈ 32 %), while the
header is complete: 15 attributes in both files (probe 6). "About a third" is a
description of the spectra, not of the file.

**2. Six reference-implementation facts, each established by execution** — five
are defects and one (the fourth: what a file has to contain is not in the file)
is a property of the format; none of them was visible from reading the spec:

* `JSONSpectralLibrary.read_header()` **appends** instead of replacing. The
  constructor already calls it once (`json.py:86`); one explicit extra call turns
  the IARPA3 head's header into 1 268 attributes and the example library's into
  30 (probe 1). The text backend clears before installing (`text.py:587-588`) and
  measures idempotent: 15 attributes after 0, 1 and 2 explicit calls. Any python
  code that "re-reads a header" reports a library whose header grows per call.
* The JSON writer emits analyte/interpretation ids as whatever the reader held —
  strings after a text read (`json.py:449-463`) — where the schema types them
  integer (`mzSpecLib_json.schema.json:146-148`), and the reader's consistency
  check `analyte_id != analyte_d.get("id")` (`json.py:225-227, 232-235`) compares
  against an object key, which is *always* a string in JSON. The warning
  therefore never fires for python's own files (0 warnings over 20 analytes) and
  fires for schema-conformant documents: the R writer's integer ids produced
  **40** warnings on the same 20 analytes, e.g. `"An analyte with explicit id 1
  does not match its key '1'"` (probe 2; the same integer-vs-string disagreement
  §3.3's schema audit counted 391/21 of). Being schema-conformant here means
  being warned at.
* The `value` member of a cvparam is **optional in the schema** (`required =
  [accession, name]`, `schema:56`) but read unguarded — `KeyError: 'value'`,
  caught at `json.py:133` in `create_index` (the same pattern sits at
  `json.py:220` in `_fill_attributes`) — so a schema-legal document that omits it
  cannot be opened at all (probe 3).
* What must be a JSON number and what must be a JSON string is **not in the
  file**: the text `1.0` of a version term (xsd:string in psi-ms 4.2.6) is
  indistinguishable from the `39.0` of a collision energy (xsd:float); the type
  lives in the ontology's `has_value_type`. Executed in both directions: taking
  the R writer's JSON (which types nothing, since R resolves nothing) and
  numericising the three version terms adds **exactly 3** MUST violations —
  inventory 15 → 18 MUST, CLI exit code 0 both times (probe 4) — while leaving
  the floats as strings earns the *complement* of that inventory (item 1's 15/34).
  This is §4.11 row 4's typed-cast hazard quantified — the decision milestone 0's
  fixture list already demands ("CV-driven value typing") and milestone 5's
  acceptance test now measures.
* Comments are handled **per-section, inconsistently**: a comment inside the
  library header kills the header parser (`ValueError: Malformed attribute line`,
  `text.py:577`) although §4.1.18 places no restriction on where a `#` line may
  sit, while a comment in a spectrum section is skipped (`text.py:408`); and a
  comment *before* `<mzSpecLib>` yields `read_header()` → `False` with no warning
  and `read()` → `ValueError: Could not locate valid header` (`base.py:522`) —
  which is actually §4.1.1's *"MUST begin with the line `<mzSpecLib>`"* being
  enforced. It also caught a real file: the R package's shipped example *used* to
  carry its provenance block before the magic line, which made the oracle unable
  to open it. That block is gone — the shipped `inst/extdata/example.mzSpecLib.txt`
  now has **0** comment lines, begins with `<mzSpecLib>`, keeps the attribution in
  the manual instead, and is still the 556-line byte-identical prefix of item 1
  (re-measured 2026-10-22: 556 of 1 749 non-blank non-comment lines of the
  original, 556/556 identical) — so the oracle's counts and the package's counts
  are now taken from the *same* file rather than from its upstream original.
  `viol_inventory.py` re-run after that change reports, unchanged from before it:
  2 SHOULD for the example, 2 SHOULD for the R-written text, **IDENTICAL**; 21
  SHOULD for the IARPA3 head, text and R-written text **IDENTICAL**; the JSON side
  at MUST 15 + SHOULD 2 and MUST 34 + SHOULD 21; exit 0 on all eight runs.
  §4.11 row 8 carries the hazard.
* A `<Spectrum>` without `MS:1003061|library spectrum name` is required by
  nothing — the accession occurs exactly once in the specification PDF, inside an
  example, and no rule set the reference actually validates with demands it —
  counted 2026-10-22 by parsing every shipped rules file for the accession:
  `gold`, `base`, `silver`, `consensus`, `single` and `peptide` 0 rules each,
  `all.json` exactly 1 (`has_library_spectrum_name`, `all.json:514`) — and
  `all.json` is reachable by nothing: the validate command's own profile
  `click.Choice` lists only `consensus, single, silver, peptide, gold`
  (`tools/cli.py:196-198`), `load_default_validator()` loads `base`
  (`validator.py:573`), and the only code that touches `all.json` is the
  `validate/rules/tmp/` script that regenerates it; besides it only
  `const.py:40 SPECTRUM_NAME`, which the *backends* use — yet the reference text
  backend insists on it, and inconsistently. Mid-file, the section line which ends
  such a spectrum raises `ValueError: No spectrum name` (`text.py:690`); at end of
  file, the `if spectrum_name:` guard in front of `index.add(number=…, name=…)`
  (`text.py:736`) is simply false, so the spectrum is never indexed and
  **disappears without a word**. Both halves measured directly against 1.0.7 on
  2026-10-22 with `SpectrumLibrary(filename=…, index_type=MemoryIndex)`: the
  package's own `canonical.mzSpecLib.txt` fixture, whose `<Spectrum=2>` is unnamed
  and last, reads as **1 spectrum / 3 peaks** there where this package and a raw
  scan of the file agree on **2 spectra / 5 peak rows** — the lost spectrum is the
  2-peak one; and the same unnamed spectrum placed *before* another section raises
  instead. Nine of the package's thirteen text fixtures carry at least one
  spectrum without the term — they identify their spectra by key alone, which is
  all §4.1.7 asks of them — and the reference splits them by accident of position:
  eight raise (their unnamed spectrum is not the last thing in the file), the
  ninth is the silent truncation above. A differential against the reference
  therefore has to feed it comment-stripped copies and must record those refusals
  as the reference's behaviour rather than score them as R-side failures. (The
  file *name* is not one of the constraints: `probe.txt`, `probe.mzlib.txt` and an
  extension-less copy of the same fixture all read identically through
  `SpectrumLibrary(filename = ...)`, even though `backends/base.py:213` has a
  `FormatInferenceFailure` for names it cannot place.) Two controls belong with
  the finding, because both were assumed before they were measured. The drop is
  not a quirk of that fixture: a six-line library whose *only* spectrum is
  unnamed loses it on the plain `<mzSpecLib>` line and on a versioned
  `<mzSpecLib 1.0>` line alike — **0 spectra** from the reference where this
  package and the file itself have 1. And the version tag is *not* itself a
  divergence, which a first probe of exactly that file mistook it for: name the
  spectrum and both readers report 1 spectrum/1 peak with or without the tag, the
  reference prefacing its answer with `ValidationWarning: Library format header
  contains version tag 1.0, this is no longer part of the specification and is
  ignored`. This package reports the tag in `issues` rather than warning about it,
  keeps the library either way, and writes the conformant line back — the format
  version of a library is its `MS:1003186` parameter, never its section line.

One more finding, procedural rather than probed: the validator's python API is
not a usable seam —
the class names a differential harness would reach for do not exist in 1.0.7
(`mzspeclib.validate.validator.SpectralLibraryValidator` → ImportError;
`mzspeclib.CV.cv.OBOEnvironment` matches nothing anywhere in the package,
`grep -rn` over the installed tree). Any differential validator has to drive
`mzspeclib.tools.cli` or the `validate/` internals, which is what
`viol_inventory.py` does.

**3. The CLI's violation output is not a countable artefact.** Each violation is
written to **STDERR twice** — once through the `mzspeclib.validate.validator`
logger during the walk and once at the end as a `... `-prefixed echo from
`__main__ | cli.py:validate:240` — and **nothing goes to stdout**: a
stdout-only capture counts zero violations, and a naive
`grep -c '(MUST)'`/`wc -l` over stderr counts exactly double (measured: 4 STDERR
lines for 2 violations on the example library, 42 for 21 on IARPA3; raw-vs-dedup
for all eight files: `analysis/viol_inventory.py`). Worse for
comparisons than the doubling: every line is prefixed with a wall-clock
`[HH:MM:SS]` **and** the source location, and the two copies of one violation
are stamped milliseconds apart — so `diff` of two runs reports differences where
the violations are identical. The throwaway comparison script this section
started life as (/tmp, superseded by `viol_inventory.py`) reported "42
differing lines" for the original and the R-written *text* file, which after
stripping timestamp, logger/location prefix and the `... ` echo and folding the
two copies turned out to be **zero**. Every inventory quoted in this report —
§4.11 rows 1–2, item 1 above — is computed on that normalisation, and exit codes
are recorded beside it: 0 for all eight files, including the runs with 34 MUST
violations (§4.11 row 1, re-confirmed).

**4. A whole-tree count is a property of the tool and its file selection, not of
the tree.** `analysis/count_tool_sweep.sh` runs the same whole-tree count over
the spec repo (`MS:1000045`, added 2026-10-22) with up to five tools. Measured
result: `grep -rc` → 200, a python `os.walk` occurrence count → 200, and
`find -type f -exec grep -o … +` → 200; **ugrep is not installed**, and there is
**no ripgrep executable on PATH** — `type -P rg` is empty and `bash -c 'rg
--version'` fails, because the `rg` an interactive shell resolves here is a
wrapper *function* around a bundled binary, which no script can call. Two leads
that came with the assignment did **not** reproduce, and are recorded as not
reproducing: the five tools did not disagree with each other (the three real
ones agreed exactly, and two were absent), and there are **no compressed files
anywhere in the spec repo** (`find … -name '*.gz' -o -name '*.zst' -o -name
'*.bz2'` → 0 files), so "counts differ because some twins are gzipped" cannot be
what makes counts differ *on this tree*. What does move the number is selection
and pattern, which the script prints beside the totals: the accession occurs in
115 hits in `.txt` files and 84 more in their `.json` twins (plus 1 in a docs
file), and the text-only concatenation `MS:1000045|collision energy` — which the
JSON serialization physically cannot contain, since it splits accession and name
into two fields — occurs 115 times. A "200 occurrences across the repository"
and a "115 occurrences in the library files" are both true statements about the
same repository, and the whole difference is file selection: the 84 `.json`
twins and one docs mention. (The `.git` directory the wide tools walk
contributes nothing — its objects are deflate-compressed and `grep`-unreadable,
which is exactly the kind of assumption the sweep exists to replace with a
number.)
That is the rule this sweep buys: every count in this report names its tool *and*
its file selection, and §4.14's whole-tree negatives carry the same disclosure
via `tool_tree_grep.sh`.

**5. PSI-MS copies: not "three, one of them the spec repo's" — six on this
machine, four versions, and zero in the spec repo.** The claim that a third
ontology copy lives in `~/dev/mzSpecLib` does not reproduce: the spec repo
contains no OBO file of any kind (full `find` over the clone; its only term
tables are the tiny `docs/guidelines/{mz,mass}_terms.csv`). What actually exists
under `~/dev` and the oracle venv (`grep -m1 '^data-version:'`,
`grep -c '^\[Term\]'`, `md5sum` per file): the python package's pinned
`mzspeclib/obo/psi-ms.obo` **4.1.57** (3 096 terms, §3.3's third witness), a
`mzml2isa` clone's **4.1.104** (3 366) with a byte-identical vendored instance
under `raw2isa`'s own venv (the sixth file), psims's vendored fallback
`psi-ms.obo.gz` **4.1.258** (4 114 — served only when the live
`purl.obolibrary.org` fetch fails, so a validator verdict silently depends on
the network), and **4.2.6** (6 082 terms) twice over: a `psi-ms-CV` clone and
`raw2isa`'s copy, byte-identical by md5. §4.11 row 13's "three versions in
circulation" is thus conservative — four are reachable from one machine without
network, five with it, and the version that decides a verdict is whichever
resolution path ran, which is exactly why milestone 7's acceptance test names the
CV version.

What this section changes downstream: §6 carries the milestone status as of
0.1.0, §8.2 re-states each open item against it, and §9's caveat and evidence
rows were corrected (the oracle environment exists again; one stale 36/36 claim
and one off-by-one term count did not survive the re-check).

---

## 5. Option comparison

| Criterion | A: core + backend (2 pkgs) | B: backend only | C: 1 pkg, 2 layers |
|---|---|---|---|
| Feasible in R as stated | yes | yes | **no** (§4.4: install fails) |
| Format usable without Spectra | **yes** | no | no |
| Fits RfMS convention | weak (§4.6) | **strongest** | weak |
| Lossless standard conformance | **yes, by construction** | no — 71–88 % homeless (§4.2) | yes |
| Fits CRAN (older R, `install.packages`) | **yes for the core** | no | no |
| Fits Galaxy/conda deployment | core: yes | no | no |
| Reuse by validator / CLI / conversion | **yes** | no | yes |
| Standard model forced into Spectra's shape | no | **yes — highest drift risk** | partially |
| Maintenance surface | 2 releases, lockstep | **1** | 1 |
| Cost to first useful capability | core only ≈ same as B | lowest | — |
| Community adoption probability | low–medium *(written before §4.12; for a core package this row is now dominated by question §8.2(b), not by general appetite)* | **high — it is already being built by RfMS** | low |

The two options that survive are A and B, and they disagree on one thing:
**where the standard's data model lives.** B does not delete it — it just makes
it invisible, undocumented and unversioned, while paying Spectra's 19-column
flat model as a permanent tax on every feature.

**Three updates to this table, added 2026-10-22.**
(i) **B is no longer a proposal.** `RforMassSpectrometry/MsBackendMzSpecLib`
exists (§4.12), so "adopt B" is not a choice available to me — the choice is
whether to work *with* it. Its own mapping table is the first hard measurement of
what B looks like in practice: 10.7 % of rows land on real Spectra variables,
and the fact that "everything got mapped" is an artefact of 88 invented columns
is precisely the §4.2 critique, observed live.
(ii) Row "Lossless standard conformance: B → no, 71–88 % homeless" should be read
with §4.13's measurement: at real scale the workload is peaks + ~11 CV terms, so
B loses *less data* than §4.2 implies on production files while losing *more
structure* (a 0..N analyte/interpretation graph flattened into columns, 12
`domain=analyte` rows). Both halves of that sentence are true, and a reader who
remembers only the first half will pick B for the wrong reason.
(iii) **"A and B are mutually exclusive" is an assumption, not a measurement.**
Nothing in Spectra's backend contract forbids an `MsBackend` whose
`peaksData()`/`spectraVariables()` read through a lossless core — `mzR` +
`MsBackendMzR` is that arrangement, and §4.6's `MsBackendMzPeak` is the same
pattern one layer down. So the honest reading of "Fits RfMS convention: A weak" is
"weak if the core is published as an *end-user* package; unremarkable if it is
published as the engine inside someone else's backend" — which is precisely the
shape §6 now recommends, and the shape `spxtacular` chose independently (§4.13 c).

---

## 6. Recommendation and sequencing

**Build `mzspeclib` (format core, no Spectra) now. Do not build a competing
backend — build the parser that `MsBackendMzSpecLib` should be reading through,
and open the coordination conversation first.**

The recommendation is unchanged in structure from the first draft but its *reason*
has changed, and honesty requires saying so. It used to be: "the core is separable
and the backend is speculative." Now the backend is real (§4.12), so the argument
is narrower and stronger: **a format core is the only contribution that repo cannot
make for itself cheaply, and the only artefact that serves lossless users, the
validator, and that backend at once.** Conversely, if §8.2(b) comes back "we keep
our own reader", Option A is still worth doing on its own terms — milestones 1–5
deliver a converter with zero Spectra involvement, and §8.1(Q1) shows HUPO-PSI has
asked for exactly that kind of second implementation in writing.

Two things must be true for this not to become duplicated effort: the parser
package must be **usable as an engine** (no CLI, no plot, no Spectra in
`Imports`; a stable read → object-graph → write boundary), and the offer to
`MsBackendMzSpecLib` must go out **before** milestone 1, not after a package exists
that they are then expected to adopt.

### Milestones

| # | Deliverable | Rough LOC | Acceptance test |
|---|---|---|---|
| **0** | **Conformance fixtures + oracle harness** (see below) | 150–300 | `python -m … \| Rscript` comparison reproduces §4.3's agreement on its six text example files — 30 of 36 cells identical, the six exceptions being the attribute-set column whose two defensible quantities differ predictably (§4.3); fixtures checked in with the python command that generated them. **Beyond the spec examples, the fixture set must cover the shapes real files actually take and the spec examples do not contain** (§4.13): a `.mzlib.txt` name, a versioned magic line `<mzSpecLib 1.0>`, a library with **no** `MS:1003186`, a library with **no** `<AttributeSet>` at all, a Zenodo member or a truncated slice of one, and ≥ 1 small-molecule case — plus the §4.11 hazards that only a fixture can pin: `MS:1003061`'s two surface labels (row 12), the two distinct `fetal_brain_tiny` files that share a filename (row 11 — key fixtures on path + hash), and CV-driven value typing, so `collision energy=40.0` agrees with python's typed cast rather than staying `character` (row 4). Every fixture records *which* artefact the expectation follows: spec, python, or "both are wrong, this is our documented choice". |
| 1 | CV parameter model + text reader | 500–800 | all example libraries parse; peak/analyte/interpretation/header-CV counts match the python oracle (fixture-driven, not eyeballed) |
| 2 | JSON reader (`simplifyVector=FALSE`) + JSON writer | 300–500 | round-trip text↔JSON↔text byte-stable on examples (modulo float formatting), matching python's **alphabetical key order** (§4.11 row 9). **Acceptance must NOT be gated on the shipped `mzSpecLib_json.schema.json`** — it rejects its own inputs with 4 876 / 3 328 errors, including a `peak_annotations` type that no real file matches (§3.3); validate against the round-tripped *content*, and treat schema conformance as an upstream bug to report, not a target |
| 3 | Attribute-set resolution + `[group]` semantics | 250–400 | hand-built override cases from spec §4.1.4/§4.1.11–12; must also cover `<AttributeSet Cluster=…>`, which no example file exercises (§4.11 row 7) |
| 4 | mzPAF parser (opaque string + lazy parse, permissive flag) | 200–400 | annotation strings survive round-trip byte-identically; table of cases from `annotation.lark` **plus** the `w/v/d/da/wa` forms only `mzpaf` accepts (§4.10) |
| 5 | Writer for text | 250–400 | **python CLI reads R-written files** (the real oracle test, not my own reader reading my own writer); `validate -p gold` violation counts unchanged |
| 6 | Validator against the existing rule JSONs | 350–600 | same MUST/SHOULD verdicts as python **per profile** (`base/gold/silver/single/consensus/peptide`) on all examples; do *not* target `all.json` (§4.8) — and do not mirror python's exit-code behaviour (§4.11 row 1): return non-zero on MUST failure |
| 7 | CV access layer (OBO parse + ancestry) | 200–400 | `value_is_child_of` matches python for all **18** uses (18 occurrences / 18 distinct parents — §4.8's corrected count; the first draft said 17), and `value_of_type` covers the 5 xsd types behind its 76 occurrences. **Two extra conditions, both from §4.11 rows 13–14:** the differential test must state which PSI-MS version each side used (python resolves 4.1.57 in-git vs 4.2.6-via-psims, and a label-dependent comparison is not reproducible), and the R matcher must be accession-only — a test that feeds a file whose label disagrees with the CV while the accession agrees has to *pass*, which is the opposite of python's composite-key behaviour |
| 8 | Sidecar index (peak/precursor lookup) | 250–450 | sublinear precursor query on a **real** 100 MB+ library — a Zenodo 13685813 member (§4.13, §8.1 Q5), not a synthetic file. Linearly extrapolating §4.7's measured throughput (~15 MB in ~2 s of parse work) puts a **1.8 GB member at roughly 4 minutes** for one cold linear scan — plausible enough for a batch job, not for an interactive backend, which is exactly the judgement §4.7's data *cannot* make. **This milestone is therefore conditional on §8.2(d):** measure the real scan, and build the index only if per-query latency actually matters to users. |
| — | tests throughout | +40–60 % | ≥ 90 % of `R/` lines; `testthat` |
| 9 | **Backend integration, not a new backend**: make `RforMassSpectrometry/MsBackendMzSpecLib` read through package 1 (or, if they decline, `MsBackendMemory`-derived, ~3–10 methods, 400–1 500 LOC) | 0 upstream / 400–1 500 own | **Spectra's own `test_backends` suite passes** (`test_dir(system.file("test_backends","test_MsBackend", package="Spectra"))` — verified present in 1.12.0: `test_peaks_variables.R`, `test_spectra_subsetting.R`, `test_spectra_variables.R`); **and a written loss list that states the 88 % figure and the structural losses explicitly** — their mapping table currently makes "everything mapped" look true by inventing columns (§4.12), which is the one outcome this report exists to prevent |

Estimated: milestones 0–8 sum to **2 450–4 250 LOC of code**, and with the
+40–60 % test budget that is **~3.5–6.5k LOC** for package 1; **~0.4–1.5k** for
package 2.
Milestones 1–2 + a writer (5) already give a usable converter, i.e. real value
before any Spectra involvement.

**Status of this table as of the 2026-10-22 second revision, re-measured on
2026-10-23 after the review pass and after the authorship and licence decisions of
§8.2 g–i.** What "0.1.0" means as a state, stated exactly: the tree was packaged
and checked again on 2026-10-23 (`R CMD build` and `R CMD check --no-manual`, both
exit 0, `Status: OK` — nothing to report, the last NOTE having been the `LICENSE`
file, which row h settled by moving the package to MIT), so `mzspeclib` 0.1.0
exists as a source tarball with a clean check. It is not published anywhere, and —
measured the same day — the working directory is not a version control repository
at all (`git rev-parse --is-inside-work-tree` → `fatal: not a git repository`), by
the user's choice rather than by oversight, so there is no commit history behind
it and nothing to bisect or attribute. `R/` is 2 814 lines in 10 files, and
`tests/testthat/*.R` 4 818 in 15 test files plus one helper, over 26 fixture
files in `tests/testthat/files` (`cat R/*.R | wc -l`,
`cat tests/testthat/*.R | wc -l`, `ls tests/testthat/files | wc -l`),
`Imports: jsonlite` alone (DESCRIPTION:25 — `utils` was dropped on 2026-10-22,
its only two uses having been a `utils::head()` in a warning and one in a parse
message, replaced by the three-line internal `.first` at `R/utils.R:12-14`;
re-measured 2026-10-23, `grep -rn "utils::" R/` now matches exactly one line,
and it is the comment above `.first` that explains why the call is gone), and
`grep -rn "fread\|data.table" R/` still matches nothing, so the
`data.table` option above was not taken. Milestones 1, 2, 3 and 5 are implemented
— text reader, JSON reader *and* writer, attribute-set and `[group]` resolution,
text writer — as plain lists and `data.frame`s, which is also what "S7 or plain
lists" (§6, Package shape) decided. Milestone 5's acceptance test is now
*measurable* and it splits: **text passes** (gold-profile violation inventories
identical to the originals, §4.15 item 1), **JSON does not** — the writer types
nothing, which is not the same decision python makes, and §4.15 item 2 puts a
number on the difference (15 MUST violations on the example library, 34 on the
IARPA3 head). Milestone 0 is now half checked in, and the half that is checked in
is the half that matters most: `tests/testthat/test-reference-python.R` reads a
library through both implementations and compares the counts, then compares the
`gold` violation inventory of the original against that of the file this package
wrote from it — seven pairs when the specification repository is present — and
pins the nine libraries the reference refuses to open, with their reason, so that
a change there fails a test instead of silently narrowing the comparison
(`MZSPECLIB_PYTHON` gates the whole file for the network reason of §4.15 item 5).
What the milestone still demands beyond that is the *fixture* set — a
`.mzlib.txt` name, a versioned magic line, a library with no `MS:1003186`, a Zenodo
member, a small-molecule case beyond the conditional `spice` example — of which
the versioned magic line, the missing version term and a library without any
`<AttributeSet>` are now covered as inline cases of the reader rather than as
checked-in fixtures, and the `.mzlib.txt` name and a real Zenodo member not at
all. The oracle scripts under `reports/analysis/` remain the seed for the rest.
The mzPAF parser
(4), validator (6), CV access layer (7), sidecar index (8) and backend integration
(9) are not implemented — structured mzPAF annotations are carried as their JSON
text, and 0.1.0's "Known limitations" (NEWS.md) state the missing ontology work
as deliberate, which is a documented gap, not a silent one.

**Why milestone 0 exists and comes first.** Three independent traps in this work
were near-misses that *looked* like success — zero peaks parsed, attribute sets
silently dropped, 280 "analytes" where there are 21 (§4.3). A self-consistent R
reader validating itself is worthless here; the only meaningful oracle is the
python implementation, and §4.11 shows it is itself partly wrong, so fixtures
must record *which* artefact (spec, python, or both) each expectation follows.
The python side also has essentially no test coverage to inherit — 269 LOC of
tests against 13 252 LOC of package — so this fixture directory is, in practice,
the first real conformance suite for mzSpecLib in any language, which is also the
cheapest possible upstream contribution from this project.

**Milestone 0 is also the only milestone whose inputs have to be manufactured.**
§4.14 established that no public mass-spectral repository distributes mzSpecLib
files at the scope its metadata indexes expose, so there is no corpus to download
and slice: the fixture set is spec examples + the one Zenodo deposit's members +
converter output, i.e. exactly the constructed data whose biases the rest of this
report keeps flagging. That is a cost to plan for (fixture authoring is most of
milestone 0's 150–300 LOC) and a risk to carry (§7), not a reason to postpone the
milestone — an untested reader fails the way §4.3's three near-misses did.

### Package shape

- **`mzspeclib`** — `Imports: jsonlite` (+ `data.table` optional for `fread`,
  + `ontologyIndex` optional for CV ancestry). No `Depends`. Target **CRAN**
  first (older-R installability per §4.5), Bioconductor later if it stays small.
  Class system: prefer **S7 or plain lists + S3** over S4 for the format model —
  no S4 inheritance requirement exists without a backend, and S4 buys nothing for
  a data reader. Keep the object graph simple: `library → list(spectra)`,
  spectrum = list(cv, analytes, interpretations, peaks, annotations).
- **`MsBackendMzSpecLib` already exists upstream** (§4.12), so the second package
  here is a *proposal to that repo*, not a new repo. What to offer them: `Depends:
  Spectra (>= 1.12)` + `Imports: mzspeclib`, extend `MsBackendMemory` (present in
  1.12.0; `MsBackendCached` also exists there if a lazy read-only backend is
  wanted), keep `backendInitialize` / `spectraVariableMapping` / `export` +
  `extractByIndex` / `peaksData` as the only methods, ship Spectra's compliance
  suite, and **state the loss list explicitly** — 88 % of spectrum-level metadata
  has no home in Spectra (§4.2) and the analyte/interpretation graph is flattened,
  not stored. A backend that says that is honest; one that invents 88 columns until
  everything looks mapped is not.
- **What "usable as an engine" has to mean** for package 1's API, since that is the
  whole value of milestone 9: a single documented boundary —
  `read_mzspeclib(path) → object graph`, `write_mzspeclib(obj, path, format=)`,
  plus accessors that never assume Spectra — such that a backend can call
  `read_*` once in `backendInitialize` and never touch the format again. If
  milestone 1's reader ends up exposing line numbers, section state or parse
  internals, no backend will adopt it and Option A degenerates into a package
  without a consumer.

### Explicit non-goals

No vendor-format importers in R (msp/mgf/spectrast/DIA-NN/Spectronaut/NIST stay
in the python CLI); no HDF5/SQLite serialization until the spec specifies one;
no attempt to represent analytes/interpretations *inside* Spectra.

---

## 7. Risks

Risks as of the final pass. One severity moved down (the "standard may still change"
row, after §3.3 established ratification); two rows were added because of
§4.12/§4.13, one because of §4.14, and one because of the executed probes against the
reference implementation (§3.3, §4.11 rows 13–14) — that last one is the only risk in
this table that is *known* to be live rather than forecast.

| Risk | Severity | Mitigation |
|---|---|---|
| **Conformance rules live in python** (severity: unchanged, still the top engineering risk) | **high** | Vendor the spec's own `metadata-rules.md` as a hash-pinned TSV with a drift test; keep the rule JSONs as a *differential oracle* only, never the source of truth; never assert on the 3 `/Library/Cluster` terms or `MS:1003062` without picking a side (§4.8) |
| **Duplicated effort with `MsBackendMzSpecLib`** — the risk that actually replaced "nobody uses the backend" | **high, and it is now the real risk** | Ask §8.2(b) *before* writing milestone 1. A parser contributed into their repo under a permissive license beats a parallel package that no backend uses; if they decline, Option A stands on its own merits (milestones 1–5 give a converter with no Spectra involvement) |
| **Real files do not match the spec's examples** — the only large corpus writes `<mzSpecLib 1.0>`, `.mzlib.txt`, no `MS:1003186`, no attribute sets, and 5 terms outside the normative table (§4.13) | **high, and easy to miss** | Detect by content not extension; warn (never fail) on a missing format-version term; keep the term set open; and put a Zenodo member in the fixture directory as a *non-conforming-by-design* case, asserting the specific behaviour you chose |
| **There is no public corpus to test against, so every fixture is constructed** — §4.14: MassIVE / PRIDE / MetaboLights are silent at metadata scope, and the only real files trace to one Zenodo deposit. A self-built fixture suite proves self-consistency, not interop | medium | Record the generating command next to each fixture (§6 milestone 0) so a reviewer can see what was assumed; label the suite honestly as a *conformance* suite, not an interop suite; state in the package docs that "parses real third-party libraries" is unverified until someone brings a file outside the one deposit; treat the first such file as a bug report upstream, not just a local test |
| **Spec defects** (JSON schema rejects its own examples — 4 876 errors on one file; cluster under-specified; peak-row delimiters pinned only by example; `MS:1003205` used for two different terms, an error `all.json` inherits) | medium | Pin an error-tolerance policy in writing; conformance fixtures recording *which* artefact each expectation follows; upstream the fixes (§3.3) |
| **Standard still DRAFT; model may change** — **downgraded: the standard was ratified 2025-08-07** (§3.3), so the model is frozen even though the PDF cover still prints `Status: DRAFT` | **medium** (was high) | Version-pin against the v1.0 tag; keep the CV model open so new terms cost nothing; the live change risk is not the model but the *announced* binary serialization (§4.3 issues #13/#74) — treat it as v1.1 scope, and treat `interpretations` as opaque-carry-through until a real consumer needs it |
| **mzPAF drift** (undocumented `mzpaf`, absent normative regex, grammar-vs-diagram divergence) | medium | Opaque-string representation; parse-on-demand; test byte-identical round-trip rather than parse equality |
| **CV ancestry needs a hand-rolled layer** | medium | Wrap `ontologyIndex`; fall back to "cannot verify" rather than a wrong verdict |
| **A validation verdict can change while the file does not**, because term labels are resolved from whichever PSI-MS copy the machine has — and this is measured behaviour of the reference validator, not a hypothetical about mine (§4.11 row 13; three CV copies already circulate: psi-ms 4.1.57, 4.2.6, live OLS) | medium | Key every comparison on accession and treat labels as display-only; **record the PSI-MS version in every validation report** and make the CV source an explicit, pinned argument; differential tests against python must pin *both* environments and expect disagreement on renamed terms, not treat it as a bug in either |
| **Single-maintainer bus factor** | medium | This report + `analysis/` scripts + conformance fixtures in-repo; §8.2(b) doubles as the "hand it over" path |
| **Two-package release lockstep** | low | Backend declares a version floor, never a ceiling; keep backend API surface to a handful of functions |
| **JSON is the slower serialization in R** — **re-measured: 1.9 s for 13.5 MB** (not 6.3 s/10 MB), i.e. seconds, not a problem; the real hazard is that `simplifyVector = TRUE` makes `length(spectra)` return the **column count** (§4.7) | **low** (was low, but the stated reason was wrong) | Default to text; use `simplifyVector = FALSE` and comment *why* (the `length()` trap, not speed); add the sidecar index only if §8.2(d) says it earns it |

---

## 8. Open questions

All six questions from the first draft have moved, and four are closed: two by
measurement, two by evidence that simply did not exist when I wrote them (§8.1).
The remaining gaps are narrower than the original questions and are listed
separately in §8.2 — none of them is answerable by reading files.

### 8.1 Answered since the first draft

1. **HUPO-PSI's intent for non-python implementations. — Answered as to intent,
   still open as to mechanics.** My first pass recorded "no public statement
   found". That was wrong in a way worth naming, because the statement is in the
   normative document itself: spec **§3.4** says, verbatim, *"other
   implementations are welcome and forthcoming"*, and psidev.info's mzSpecLib page
   already lists a **Rust** implementation under "Implementations"
   (`rusteomics/mzcore`/`mzannotate`, verified to ship reader *and* writer)
   alongside python. So "may I write a second implementation" is answered yes, in
   writing, twice, and `MsBackendMzSpecLib` (§4.12) is the R side of the same
   permission. What is *still* not on the record anywhere, and only HUPO-PSI can
   say it, is the three mechanical things that decide package 1's shape:
   (i) will the spec repo own a **machine-readable** rule table with a CI diff
   against python's rule JSONs, so neither implementation owns the source of truth
   (§4.8 proposes the job in one paragraph); (ii) will they adopt a
   conformance suite — there is none in any language today (§4.3: 269 LOC of
   python tests against 13 252 LOC of package); (iii) is the shipped
   `mzSpecLib_json.schema.json` meant to be normative at all, given that it
   reports 4 876 validation errors against one of the spec's own example files
   (§3.3).
   → *ask the mzSpecLib maintainers these three, not the first question.*

2. **Where do the MUST/SHOULD/MAY rule JSONs belong? — Answered: neither side
   as-is; vendor the spec's own table and treat the JSONs as an oracle.** The
   normative list is `mzSpecLib/docs/metadata-rules.md`, the JSONs are generated
   from a spreadsheet the python authors labelled temporary, and the rendering
   step that was supposed to keep them in sync does not exist. Accessions and
   value types agree exactly (97/97, 0 typing mismatches); *severity* drifts (3
   conflicts against `all.json`, 5 against `base.json`, including `MS:1003062`
   MUST-vs-MAY). Full diff and the four design consequences are in §4.8. What
   remains a question for the maintainers is only *which artefact becomes
   machine-readable and normative*. To be precise about the current state, because
   it is easy to get backwards: `docs/metadata-rules.md` **is already in the spec
   repo**, but it is a hand-maintained markdown rendering with no generator that
   runs; the JSON rule sets are in the *python* repo, generated from
   `rules/tmp/terms.xlsx`; and nothing tests that the two agree (§4.8). The proposal
   I would put to them is therefore small and concrete — **add a CI job in the spec
   repo that renders `metadata-rules.tsv` from the same spreadsheet and diffs it
   against the markdown and against python's `all.json`, failing on accession or
   type drift** — which retires the "temporary" spreadsheet as an untracked source of
   truth without moving any files. The four wrong-label rows in §3.3 give that
   proposal a test case on day one.

3. **Should `mzspeclib-rs` be wrapped via `{extendr}` instead of ported? —
   Answered: no, and not for the reason I first wrote.** Checking the actual
   repository changed the picture on three counts [verified via the GitHub API
   and raw sources, 2026-10-22]:
   - **It is a reader, not "text-writer only"** (my earlier evidence row was
     wrong and is corrected in §9). `src/parse.rs` is 28 493 B: `MzSpecLibParser`
     is a streaming `Iterator<Item = Result<LibrarySpectrum, _>>` with
     `read_header()` / `read_next()`, attribute-set, analyte, interpretation and
     peak-line states, `EntryType::Cluster`, `#`-comment skipping, and —
     for seekable inputs — `build_index()`. The writer is the 863 B
     `MzSpecLibTextWriter`. That is *exactly* the shape milestone 1 wants.
   - **`extendr` is not on CRAN** (`https://cloud.r-project.org/web/packages/
     extendr/` → HTTP 404, measured; the CRAN `PACKAGES` index has no `extendr`
     or `extendrmacro`, only an unrelated `rust` = "Ratio-of-Uniforms Simulation
     with Transformation"). The R-side glue is vendored from `cargo extendr`
     templates, so an R package would need `SystemRequirements: cargo` and a
     Rust toolchain at install time.
   - **`mzspeclib-rs` has no license file at all.** The full tree (12 blobs, API
     reports `truncated: false`) is source + `Cargo.lock` + test data; the API
     reports `license: null`. Absent a license, default copyright applies: R
     cannot vendor, copy, or relicense it without asking
     @mobiusklein, which is a prerequisite conversation, not an engineering task.
   - Also: not published on crates.io (`?q=mzspeclib` returns only `mzannotate`
     and `mzident`), so it would be a git dependency; it implements **no JSON
     codec** (milestone 2 uncovered); and its tests are 2 `#[test]`s in
     `parse.rs` + 5 in `mzpaf/parser.rs`, 0 in `model.rs`/`attr.rs`.
   - It cannot even be probed here: no `cargo`/`rustc` on this machine, so I
     could not use it as a third differential oracle (worth doing later — it
     resolves `<AttributeSet Spectrum=all>` by `starts_with("<AttributeSet")`,
     independently of both my R reader and python, which is corroborating
     evidence for §4.3 trap 4).
   **Recommendation:** port in R, read `mzspeclib-rs`'s state machine for the
   peak-line and attribute-set edge cases, and open an issue asking for a
   license + crates.io publish so a future Rust layer becomes possible at all.
   The `MsBackendMzPeak` precedent still argues against neither option.

4. **Does a lossy Spectra backend help anyone this year? — Answered: yes, and the
   evidence is not a survey, it is a repository.** The first draft said "no demand
   signal exists (§4.6: 3 community backends, none with CI, none by an RfMS core
   team)". Both halves of that sentence were overtaken by events:
   `RforMassSpectrometry/MsBackendMzSpecLib` now exists **inside the RfMS org**
   (§4.12), which is the exact signal I said was missing — someone with standing in
   the ecosystem decided this year's backend was worth building. So the question as
   posed is closed. It has to be re-posed, and *that* version is not answerable by
   me:

   - Not "should a backend exist" but **"should `MsBackendMzSpecLib` read through
     an R format core, or keep its own parsing?"** — a coordination question for
     that repo's maintainers, and the whole content of the revised §6.
   - And not "does a lossy backend help" but **"is losing 88 % of the metadata
     acceptable to the users who would actually read mzSpecLib in R?"** §4.2
     measures the loss; only users can say whether it is survivable. Their own
     mapping table landing 10.7 % of rows on real Spectra variables suggests the
     intended use is *peak lists plus a handful of columns*, which is a real and
     useful thing — and is also exactly the use that does not need mzSpecLib's
     model, so it argues for keeping the lossless layer somewhere visible.

5. **Is there a real large library to benchmark against? — Answered: yes, 99 GB of
   it, and it is open-licensed.** Zenodo **10.5281/zenodo.13685813** (Noble Lab
   multi-species benchmark, CC-BY-4.0) deposits four archives — 59 462 050 277 /
   25 692 122 648 / 8 341 722 875 / **5 531 428 474** B — whose `main`/`balanced`
   members are mzSpecLib text, ≈ 7.4 GB decompressed in `balanced` alone with a
   largest single member ≈ 1.8 GB. Sizes verified by `HEAD`, not by the landing
   page. So milestone 8's acceptance test ("sublinear precursor query on a 100 MB
   library") is executable against real data instead of a synthetic corpus.

   Two honest caveats. First, **I did not download and time it** — that is a
   5.5 GB fetch, out of scope for a survey; what I did instead was read the
   producer (`MGFUtils.java`) and profile what it emits, which is in §4.13 and
   already changes the milestone: the corpus is peaks + **11** CV terms with no
   attribute sets and no clusters, so it will measure *peak-row throughput*, not
   the metadata model. Second, the deposit's own quirks (`.mzlib.txt`,
   `<mzSpecLib 1.0>`, absent `MS:1003186`) mean a reader that passes the spec
   examples can still read **0 of these files** — they are the most valuable
   conformance fixtures in this whole report, precisely because they disagree with
   the spec's examples.

6. **Proteomics or metabolomics first? — Answered as far as the evidence goes:
   the corpus is proteomics, and the metadata gap is *not* a domain problem.**
   I classified all 4 184 unmapped CV occurrences by accession (§4.2):
   **domain-neutral 3 581 (85.6 %), proteomics-specific 563 (13.5 %),
   small-molecule-specific 40 (1.0 %)**. The unmapped mass is dominated by
   mzSpecLib's provenance/aggregation model — `contributing replicate spectrum
   USI` (1 003), `other attribute name`/`value` (939), `unit` (254),
   `number of peaks` (120), `spectrum aggregation type` (109) — which no flat
   Spectra column can hold in *either* domain. The proteomics-only terms are a
   long tail of 15 accessions (protein accession 72, ProForma 69, flanking
   residues 54 + 54, missed cleavages 54, …). The one small-molecule example,
   `spice.mzSpecLib.txt`, contributes **53** unmapped occurrences, of which 9
   are chemistry terms (`molecular formula`). So: (i) the architecture decision
   does not turn on the domain; (ii) the metabolomics case is asserted by the
   spec but essentially **untested by upstream data** — if small molecules matter
   to the intended users, that is a reason to author metabolomics conformance
   fixtures in milestone 0, not a reason to change the design.

### 8.2 What actually remains open

Nothing here can be settled by reading files, which is why it survived every pass.
Each is phrased so that one answer changes one decision.

| # | Question | Who answers | What it decides |
|---|---|---|---|
| a | Will HUPO-PSI add a spec-repo CI job that renders the rule table machine-readably and diffs it against python's rule JSONs (concrete proposal in Q1 above), adopt a conformance suite, and state whether the JSON Schema is normative? | mzSpecLib maintainers | whether package 1 vendors a generated file or parses a spreadsheet by hand; whether milestone 0 is an upstream contribution or a private one |
| b | Does `MsBackendMzSpecLib` want a parser + conformance fixtures contributed upstream, under their package? | that repo's maintainers | whether this project's package 1 is standalone (Option A) or an engine inside their backend (Option B with my constraints) — the only live architectural question left |
| c | Is losing 88 % of the metadata acceptable to intended users, and do they need the analyte/interpretation graph at all in R? | users (proteomics + metabolomics) | whether a lossless API needs to be *discoverable* by users, or is fine as infrastructure underneath a backend |
| d | Does the sidecar index earn its cost on the Zenodo corpus — i.e. what is a full text scan actually like on a 1.8 GB member? | needs a 5.5 GB fetch and a run | whether milestone 8 ships; §4.7's in-memory figures are all ≤ 15 MB and do not extrapolate honestly |
| e | Will anyone author metabolomics conformance fixtures? | someone with small-molecule data | whether §4.2's finding that the metadata gap is domain-neutral gets *tested* on small molecules — one 647-line `spice` example is not coverage (§8.1 Q6) |
| f | Can `mzspeclib-rs` be licensed, and published to crates.io? | @mobiusklein | whether any Rust layer is legally possible later; today it is not (no license file in the tree) |
| g | **Closed 2026-10-23.** Who authored this package, and who maintains it? The pass that produced 0.1.0 had written `DESCRIPTION` with two authors and every `\author{}` field with one of them, and this report's header named the same single name. The user's answer, verbatim: *"There is no Heiko Dietrich - sole author should be Helge Hecht from Masaryk University."* | — | applied the same day, in all four places that carried the wrong name: `Authors@R` is now a single `person()` (`aut` + `cre`, ORCID 0000-0001-6744-996X, `affiliation = "Masaryk University"`, `DESCRIPTION:4-7`), the thirteen `@author` lines in `R/` and the thirteen generated `man/*.Rd` name Helge Hecht, this report's header names Helge Hecht, and `LICENSE`'s `COPYRIGHT HOLDER` line — which read "The mzspeclib authors" — names Helge Hecht. Re-checked after the change: `grep -rn "Heiko\|Dietrich\|LZI" .` matches only this row, which quotes the answer |
| h | **Closed 2026-10-23.** Under which licence the code goes out, and whose copyright the file names. The pass had measured the Artistic-2.0 triangle (file kept → "File `LICENSE` is not mentioned in the `DESCRIPTION` file"; `Artistic-2.0 + file LICENSE` → "License components with restrictions not permitted"; file deleted → `Status: OK`) and asked the user to choose. Answer, verbatim: *"Use MIT License and remove the stub"*. MIT, it turns out, cannot go without a file: measured the same day on the same tree, `License: MIT` alone gives `checking DESCRIPTION meta-information ... NOTE`, "License components which are templates and need `'+ file LICENSE'`: MIT", while `MIT + file LICENSE` gives `Status: OK` — with either the two-line `YEAR`/`COPYRIGHT HOLDER` template or the full MIT text as the file. | — | applied as `License: MIT + file LICENSE` (`DESCRIPTION:23`) with the Artistic template *replaced* by the licence text itself, `Copyright (c) 2026 Helge Hecht`, 21 lines (`LICENSE`), so nothing named a stub survives; the README's and NEWS's licence sentences changed with it, and the shipped example stays a separate Apache-2.0 component, which both files say |
| i | **Answered 2026-10-23: no.** Should this tree be under version control, and with what history? Measured that day, `git rev-parse --is-inside-work-tree` → `fatal: not a git repository`, nothing of 0.1.0 committed anywhere in the directory; asked whether to `git init` and commit in logical chunks, the user chose to leave it un-versioned | — | stays as it is: no `git init`, no commits, so "commits kept logically separated" is explicitly waived rather than forgotten. The consequences are recorded wherever they matter — no bisect or blame behind a regression, and the README therefore claims no cloneable remote |

Of these, (b) is the only one that blocks writing code. Of the three rows added
with the release, g and h are answered and applied and i is answered "no".

**State after the first release (2026-10-22).** The pass behind §4.15 changes the
*shape* of every row and closes none of them, because none of a–f is answerable
from inside this repository: **(a)** still a HUPO-PSI decision, now with one more
question to put on that list — whether a comment may precede `<mzSpecLib>` at all
(§4.1.1 vs §4.1.18). §4.15 item 2's second half on that changed on 2026-10-22 and
the question did not go away: the package's shipped example now obeys §4.1.1 and
carries no comments at all, so it no longer disagrees with the reference
implementation — but 12 of its 13 test fixtures do carry comment lines, all of
them provenance blocks in front of `<mzSpecLib>`, and three of those twelve
contain nothing else the reference objects to: unstripped the reference dies on
them, stripped they read 1/2, 2/0 and 1/76 spectra/peaks (`crlf-bom`,
`spec-4-1-5-cluster`, `spec-4-1-17-chimeric`), which is exactly what this package
reports for them. The contradiction is unchanged, only relocated from a shipped
file to a fixture directory. **(b)** still that repo's
maintainers, but the offer is concrete now that a package exists whose text
serialization the reference implementation cannot distinguish from the spec's own
files (§4.15 item 1) — and whose equivalence claim is not a paragraph in a report
but a test another implementation can run, `tests/testthat/test-reference-python.R`
(§9); **(c)** still the users' — 0.1.0 keeps everything lossless,
so the 88 % question now applies only to the backend layer above it; **(d)**
cannot be closed here at all: it needs the 5.5 GB Zenodo fetch, which is out of
scope for this machine and this pass, so milestone 8 stays conditional; **(e)**
open — the 0.1.0 test suite touches small molecules through exactly one file,
`spice.mzSpecLib.txt`, and only conditionally: `tests/testthat/helper-mzspeclib.R`
resolves it from a `~/dev/mzSpecLib` clone and skips it when absent, so the
metabolomics fixture gap is untested by default; **(f)** unchanged, still
@mobiusklein's to give. Three rows were added on 2026-10-23, on the release side
rather than the research side, because the review pass that produced 0.1.0 left
them implicit: **(g)** the author record was inconsistent between `DESCRIPTION`
and the generated `\author{}` fields — answered on 2026-10-23, sole author Helge
Hecht (Masaryk University), and applied to `DESCRIPTION`, to the thirteen `@author`
tags and their Rd output, to the licence and to this report's header, so the
invented name occurs nowhere in the tree except the row above, which quotes the
answer; **(h)** closed with it — the package is MIT, `LICENSE` is the licence text
with `Copyright (c) 2026 Helge Hecht`, and the check NOTE that had been the whole
of `Status: 1 NOTE` is gone, since `MIT + file LICENSE` is the form `R CMD check`
accepts; **(i)** answered "no", the tree stays un-versioned by decision rather
than by oversight. These three were the only questions in this section that the
user could settle by answering rather than by measuring, and all three are
settled; a–f still need the people named there.

---

## 9. Appendix: evidence index

### Measured on this machine (R 4.3.3)

**Reproducibility caveat, stated plainly (updated 2026-10-22).** The report was
measured in three throwaway environments; two are still **gone from this
machine**, and the third was rebuilt and re-used the same day:

- **Spectra 1.12.0** (Bioc 3.18) lived in `/tmp/rlib`; only `data.table` survives
  there. So §4.1, §4.2's generous scenario, §4.4 and the backend-class census must
  be re-installed to repeat — they are not covered by a checked-in script.
- **The python oracle** `/tmp/mzvenv` **exists again**: rebuilt 2026-10-22 with
  `mzspeclib` 1.0.7, `psims` 1.4.0, `mzpaf` 0.2.0b0 (`/tmp/mzvenv/bin/pip list`),
  and everything that depends on it has since been re-executed against it from
  checked-in scripts — §4.3's agreement table (`oracle_counts.py`; the agreement
  is 30 of 36 cells, not the "36/36" this section's evidence row still carried
  until the present revision corrected it), §4.11 rows 1–3, §3.3
  (`oracle_probes.py`) and §4.15 (`oracle_defects.py`, `viol_inventory.py`). It
  is still a `/tmp` location — one purge loses it again, and the scripts that
  need it say so in their headers.
- **`/tmp/rpkgs`** (local clones behind the §4.6 backend census) is empty too.

Everything else in this table re-runs today from `analysis/` with base R +
`jsonlite` + `data.table`; the §4.3, §4.11 and §4.15 rows additionally need the
rebuilt `/tmp/mzvenv`, and two of them also `pkgload` the package itself — the
reproduction list at the end of this section marks which is which. Two scripts
need network: `cv_label_audit.py` (OLS
responses cached in `analysis/cv_label_audit_cache.json`, so it re-runs offline)
and `db_absence_probe.py` (EBI Search + MassIVE; no cache, because a cached negative
is exactly the thing this section warns about).
Timings are **load-sensitive
on this machine**: a re-run of `bench2.R` while background jobs were running gave
`fromJSON(simplifyVector=TRUE)` = 4.21 s where the §4.7 median was 1.91 s. Treat
absolute times as ±2× and read only orders of magnitude and ratios.

| Fact | How |
|---|---|
| 11.8 % / 15.7 % / 29.0 % occurrence-level mappability; 88.2 % gap; **72 distinct terms → 8 mapped / 64 unmapped strictly, 50 unmappable even in the generous scenario** | `analysis/mapping_gap.R` (the two "unmappable" numbers answer different questions: strict 19-variable mapping vs. mapping after allowing 16 extra custom columns — §4.2 quotes both) |
| 127-line reader parses 6 real libraries; **30 of 36 count cells agree with the python reference implementation** (the six exceptions are the attribute-set column, two defensible quantities differing predictably — §4.3) | `analysis/proto_reader.R` + `analysis/oracle_counts.py` against the §9 oracle |
| 15.2 MB text: `readLines` 0.52 s · CV parse 1.57 s · `strsplit` peaks 1.54 s · **`fread` peaks 0.14 s** · grouped split 0.58 s; 13.5 MB JSON: `fromJSON(TRUE)` 1.91 s vs **`fromJSON(FALSE)` 0.36 s**; materialise peaks 0.46 s (medians of 3, §4.7) | `analysis/bench_gen.R` then `analysis/bench2.R` |
| `simplifyVector=TRUE` makes `length(spectra)` return the **column count (6)** where the library has **21** spectra; ratio TRUE/FALSE = 2.7–5.7× on 3 corpora | `analysis/json_modes.R` |
| `metadata` slot but not exported | `"metadata" %in% getNamespaceExports("Spectra")` → FALSE |
| no `backendRegister` / `supportedBackends` / `supportedSpectraVariables` / `filterSpectraRanges` | `exists(..., asNamespace("Spectra"))` |
| backend compliance suite ships (`test_peaks_variables.R`, `test_spectra_subsetting.R`, `test_spectra_variables.R`) | `system.file("test_backends", package="Spectra")` |
| Suggests-only backend class fails to install | `cext` probe, `R CMD INSTALL` |
| JSON schema lacks `interpretations`, `additionalProperties:false`, cluster = attributes only | `mzSpecLib_json.schema.json` vs shipped examples |
| rules: `all.json` MUST 3 / SHOULD 7 / MAY 89 vs `base.json` MUST 5 / SHOULD 3 / MAY 2; 5 predicates | `validate/rules/*.json`, `Counter` |
| `load_rule_set('all')` → `KeyError: 'level'`; base/gold/silver/single/consensus/peptide load fine | `/tmp/mzvenv`, reference loader |
| `validate -p gold` exits **0** on a file with 12 MUST violations, and on a file with the MUST `library format version` attribute deleted | `python -m mzspeclib.tools.cli validate`, `$?` |
| real examples fail MUST under `gold`: spice 12, broad_tcga 20 | same, all 7 unique files |
| grammar vs `mzpaf` accept different ion series (`a x b y c z` vs `[axbyczdwv]` + `da/db/wa/wb`) | `annotation.lark:33` vs `mzpaf/annotation.py:32` |
| `mzpaf` = 1 288-line `annotation.py`, one 1 063-char `re.X` pattern, 13 alternations | PyPI sdist `mzpaf-0.2.0b0` |
| backend classes: 18 classes / 13 packages (4 in Spectra; 6 of 12 external hosts in Bioc 3.18) | Spectra README parse + Bioc 3.18 `src/contrib/PACKAGES` (2 216 pkgs) |
| `MarcIsak/MSLibrarian` 14 stars, pushed 2022-08-25, not on CRAN/Bioc | GitHub API + package indexes |
| examples carry 0 clusters; python's JSON writer never populates `cluster_attribute_sets` | all 9 mzSpecLib examples; `json.py:362-374` |
| tests: 7 files / 269 LOC against ~13 252 LOC package code | `find tests -name 'test_*.py' \| xargs wc -l` |
| python import closure needs sqlalchemy+pyteomics+psims | `__init__.py`, `analyte.py:5`, `index/sql.py`, `backends/base.py:13` |
| `annotation.py` = 1 line, `msp.py` = 2 557 LOC | `wc -l` |
| zero CRAN packages for PSI-MS CV / spectral libraries (25 235 scanned) | `PACKAGES` scan |
| no conda package for R Spectra stack | anaconda.org API |
| `mzR` has no Spectra dependency; Spectra `Suggests` mzR ≥ 2.19.6 | Bioconductor 3.18 `PACKAGES`, DESCRIPTION line 37 |
| **`mzspeclib-rs` is a full streaming *reader*, not "text-writer only"** (my first evidence row said the opposite and was wrong): `parse.rs` 28 493 B with `read_header()`/`read_next()`/`build_index()`; the writer is the 863 B `MzSpecLibTextWriter`; **no license file anywhere in the tree** (`license: null`), not on crates.io, no JSON codec | GitHub API tree + raw `src/*.rs` |
| `extendr` absent from CRAN (HTTP 404; no `extendr`/`extendrmacro` in `PACKAGES`) → Rust glue needs `SystemRequirements: cargo` | `curl -I cloud.r-project.org/web/packages/extendr/`, `PACKAGES` scan |
| rule provenance `terms.xlsx` → `excel_terms_to_json_rules.py` → `all.json`; `generate_metadata_docs.py` hardcodes a path under `implementations/python/…`, is invoked by nothing, `docs.yml` runs only `sphinx-build` | spec + python repos, `grep -rn generate_metadata_docs` |
| rules diff: accessions 97 ↔ 97 exact, **0** typing mismatches, **0** repeatable mismatches; **3** level conflicts vs `all.json`, **5** vs `base.json` (incl. `MS:1003062` MUST-vs-MAY); 3 base-only accessions; 3 `/Library/Cluster` rules with no doc scope | §4.8 diff, re-derivable from the two repos |
| `metadata-rules.md` lines 41–42 cite `MS:1003205` for **two different terms**; psi-ms 4.2.6 separates them (`MS:1003204` constituent identification file / `MS:1003205` constituent library file), 4.1.57 has neither; `rules/all.json` repeats the error in `has_constituent_identification_file` | `sed -n '41,42p'` + `analysis/oracle_probes.py` (probe 5) + accession counts in the rule JSONs |
| **ratified 2025-08-07** (psidev.info + PDF "Status of this document") while the PDF cover still prints `Status: DRAFT` and the spec README says "hoped to be complete at the end of 2024" | psidev.info, `pdftotext` of the v1.0 PDF |
| shipped JSON schema rejects its own shipped examples: 4 876 / 3 328 errors; `peak_annotations` declared array→array→array vs flat array of strings = **4 443** of them; `aggregations` 1 474; `interpretations` forbidden 21/20; `cv_param_group`/`analyte.id` integer-vs-string 391/21; unresolvable remote `$ref` | `jsonschema` Draft7 + `network=False` |
| **`RforMassSpectrometry/MsBackendMzSpecLib` exists** (RfMS org); its own `inst/txt/mzSpecLib-mapping.txt` maps **10.7 %** of rows onto real Spectra spectraVariables — 44.2 % onto invented columns, 45.1 % onto nothing | GitHub raw + local classification |
| that mapping's `required` flags agree with the normative levels **98/98** | same |
| Zenodo **10.5281/zenodo.13685813** = 99.0 GB of real mzSpecLib text (4 archives; `nine-species-balanced.zip` = 5 531 428 474 B) | Zenodo API + `curl -I` (`content-length`, `last-modified: Tue, 09 Dec 2025 19:50:30 GMT`) |
| its producer writes `<mzSpecLib 1.0>` (`MGFUtils.java:97`), `.mzlib.txt` (`:55`), **0** `MS:1003186`, **0** `<AttributeSet>`, and only **11** distinct CV terms — 5 of them absent from the normative 97-term table, 3 of 11 reaching a real Spectra variable through the RfMS mapping | `curl` raw `MGFUtils.java` + `grep -c` |
| Galaxy merged native mzSpecLib datatypes for **both** serializations **2026-09-11T18:01:35Z** — PR #22888, `merged=true`, 5 files, title *"Add mzSpecLib datatype support (JSON and text formats) for proteomics spectral libraries"* | GitHub API |
| **four** file-extension spellings coexist: `.mzSpecLib.txt` (spec), `.mzspeclib.txt` (Galaxy/py/mzcore/tims), `.mzlib.txt` (Noble), `.mzspeclib` (matchms test data); `mzcore/data/` holds 6 of the first and 2 of the second, incl. `fetal_brain_tiny.mzspeclib.txt` | `mzcore/contents/data` API listing; `MGFUtils.java:55`; `save_as_mzspeclib.py` + `tests/testdata/` |
| `matchms` support is **write-only**: #752/#757 export merged (`matchms/exporting/save_as_mzspeclib.py`), #751/#758 import closed **`not_planned`** | GitHub search API + issue states + raw source |
| ProteoWizard/Carafe throws: `LibraryOutputs.cs:69` `throw new NotSupportedException("-lf_type mzSpecLib is not supported by CarafeSharp")`, doc comment `:32` "`mzSpecLib` is not ported", asserted in `CommandLineErrorTest.cs:96` | raw source fetch |
| OpenMS #10172 *"Add mzSpecLib … read/write support"* (open, 2026-09-17) and #10175 *"Support satellite ions (d, v, w) — currently an mzPAF v1.0 conformance gap"* (open) | GitHub API, titles verbatim |
| normative table label audit: **90/97 exact** OLS preferred-label matches, 1 synonym, **7 mismatches**, of which 2 cite an accession naming a different term (`MS:1000034` = charge deconvolution used for "intensity unit"; `MS:1002875` = TSQ Quantis used for "inverse reduced ion mobility") | `analysis/cv_label_audit.py` + OLS4 API (cached in-repo) |
| **`spxtacular` implements mzSpecLib independently of `mzspeclib-py`** and keeps unmapped metadata as CV: own `CvParam/Analyte/Interpretation/LibraryEntry/SpectralLibrary`, own mzPAF (`paftacular`) + ProForma (`peptacular`) parsers, `read_mzspeclib()` (whole) + `MzSpecLibReader` (streaming), *"every attribute without a field keeps its CV form in an `attributes` tuple"*, *"Writing never emits attribute sets"* | raw `src/spxtacular/mzspeclib.py` (docstring + imports) |
| four tools touch the format in code: `sage-plus` 14 hits, `timsbuktoolkit` 44 (`rust/timsquery/src/serde/mzspeclib_io.rs`), `msspeculator` 17 (`rust/inference/src/mzspeclib.rs`), `spxtacular` 16 | GitHub code-search API per repo |
| `MsBackendMzR` exists in Spectra (30 code hits) — precedent for "thin backend over a standalone format package" | GitHub code-search API |
| **MassIVE: 0 mentions of `mzspeclib`/`mzspec`/`mzpaf`/`mzlib` across all 20 428 dataset-metadata records** (56.4 MB, 21 pages); controls `mzxml` 550, `mzml` 168, `blib` 10, `.msp` 2; `row_data` has no filename list → metadata-scope negative only | `analysis/db_absence_probe.py --massive` |
| **EBI Search: MetaboLights 0 and PRIDE 0** for `mzSpecLib`; controls glycerol 938 / mzML 344 / "spectral library" 561 and 2 171 / 790 / 2 200 | `analysis/db_absence_probe.py` |
| known-broken endpoints, avoided: `metabolights/ws/studies?keyword=X` ignores `keyword`; MassIVE `query=` is filtered client-side (`table_ss.js`, `value.indexOf(search_value)`), so the full paginated dump ≡ the site's own search box | measured |
| FragPipe: **0** issues matching `mzspec` (`repo:Nesvilab/FragPipe`), control `"spectral library"` → **329**; `orgs/FragPipe` → 404 (real tracker `Nesvilab/FragPipe`); `fragpipe.nesvilab.org` 200, `docs.nesvilab.org` NXDOMAIN | GitHub search API + DNS-over-HTTPS + HTTP |
| Spectronaut: `biognosys.net` **unregistered** (DoH `Status: 3` at Google *and* Cloudflare, RDAP 404); live site `biognosys.com/software/spectronaut/` = 445 591 B, 0 hits for `mzspeclib\|mzpaf` → *no mention on a fetchable page*, **not** "no support" | DoH + RDAP + HTTP + grep |
| "DIAlect" as an mzSpecLib consumer: **withdrawn**, no such proteomics repository locatable (GitHub repo/code search, EPMC, Crossref, OpenAlex, bio.tools, bioconda — per the research pass, none re-verified as a positive) | no claim made |
| the same filename holds **two different libraries**: `mzspeclib-rs/test/data/fetal_brain_tiny.mzSpecLib.txt` 148 670 B / 5 347 lines (`md5 171c1984…`) vs `mzSpecLib/examples/SpectraST/fetal_brain_tiny.mzSpecLib.txt` 165 046 B / 5 600 lines (`md5 5486d815…`) | fetched both, `md5sum` + `wc -l` (§4.11 row 11) |
| R→python interoperability counts (reference reader over R-written files): IARPA3 head **634 / 20 / 1 474 / 20 / 20 — cell-for-cell identical to the original** in text; same four spectrum-scope quantities in JSON, header doubled to 1 268 = 2 × 634 by the reference's own append-defect | `analysis/oracle_defects.py` probe 6 (§4.15 item 1) |
| gold-profile violation inventories: original vs R-written **text IDENTICAL** (2 SHOULD example, 21 SHOULD IARPA3); R JSON adds only value-type MUSTs (+15 example, +34 IARPA3, 0 removed); **all eight runs exit 0**, including the 34-MUST one | `analysis/viol_inventory.py` |
| the CLI prints every violation **twice to STDERR, nothing to stdout**, each line stamped `[HH:MM:SS]` (raw-vs-dedup: 4 lines/2 violations, 42/21) — naive counts double, cross-run diffs are timestamp-contaminated | `analysis/viol_inventory.py` (prints raw and normalised side by side; §4.15 item 3) |
| executed reference defects (1.0.7): JSON `read_header()` appends (634→1 268, 15→30; text idempotent 15/15/15); python's own string ids → **0** "does not match its key" warnings vs schema-conformant integer ids → **40** warnings/20 analytes; schema-optional `value` → `KeyError: 'value'` (`json.py:133`); numericising 3 version terms adds **exactly 3** MUSTs (15→18), exit still 0 | `analysis/oracle_defects.py` probes 1–4 (§4.15 item 2) |
| comments: leading comment → `read_header()` `False` + `ValueError: Could not locate valid header` (`base.py:522`); comment inside the header → `ValueError: Malformed attribute line` (`text.py:577`); 8/8 spec `.txt` examples start with `<mzSpecLib>` — and so does the package's shipped example since 2026-10-22 (0 comment lines), while 12 of its 13 fixtures still carry provenance comments in front of the magic line | `analysis/oracle_defects.py` probe 5; `readLines` + `grep -c "^#"` on `inst/extdata/` and `tests/testthat/files/`; §4.1.1/§4.1.18 text via `pdftotext` |
| **spectrum names: the reference implementation loses data over a term nothing requires** (mzspeclib 1.0.7) — mid-file an unnamed `<Spectrum>` raises `ValueError: No spectrum name` (`text.py:690`), at end of file the `if spectrum_name:` guard in front of `index.add(...)` (`text.py:736`) drops it silently; comment-stripped over all 13 fixtures: 8 raise, 1 (`canonical`) reads **1 spectrum/3 peaks** where this package and a raw scan of the file read **2/5**, 1 dies on its deliberate `<Spectrum=x>` (`invalid literal for int() with base 10: 'x'`), 3 agree (1/2, 2/0, 1/76); no rule set the tool can load has an `MS:1003061` rule (`gold`, `base`, `silver`, `consensus`, `single`, `peptide` 0 each; only `all.json` has 1 and the CLI's profile `Choice` does not offer it, `tools/cli.py:196-198`), and the file name is no constraint (`probe.txt`, an extension-less copy and `probe.mzlib.txt` all read) | `mzspeclib.SpectrumLibrary(filename=…, index_type=MemoryIndex)` over comment-stripped tempfile copies vs `read_mzspeclib()` + `spectraPeaks()`, 2026-10-22 |
| whole-tree counting over the spec repo (`MS:1000045`): `grep -rc`, python `os.walk` and `find -exec grep -o` all → **200**; ugrep absent and **no `rg` executable** (`type -P rg` empty — the interactive `rg` is a wrapper function); split 115 txt + 84 json + 1 docs, `accession\|name` concatenation → 115; **0 compressed files in the tree** | `bash analysis/count_tool_sweep.sh` (§4.15 item 4) |
| PSI-MS on this machine: **6 files in 4 versions** — 4.1.57 (3 096 `[Term]`, python package's pin), 4.1.104 (3 366), 4.1.258 (4 114, psims's vendored network-fallback), 4.2.6 (6 082, twice, md5-identical); the spec repo carries **no** ontology file | `grep -m1 '^data-version:'` + `grep -c '^\[Term\]'` + `md5sum` per copy (§4.15 item 5) |
| the shipped example is an **excerpt** of `fetal_brain_tiny_consensus_td`: 556/556 non-blank non-comment lines byte-identical to the original's prefix; 3 of 10 spectra, 392 of 1 242 peak rows ≈ 32 %, header attributes 15 = 15 — the header is complete, not a third | line-by-line prefix comparison (`python3`) + `oracle_defects.py` probe 6 |
| `mzspeclib-r` 0.1.0 after the review pass and the §8.2 g–i decisions: `R/` 2 814 LOC in 10 files, `tests/testthat/*.R` 4 818 LOC (15 test files + helper, 26 fixtures = 13 text + 13 JSON), `Imports: jsonlite` alone (`utils` dropped 2026-10-22), no `data.table`/`fread` use, sole author `Authors@R` and `License: MIT + file LICENSE` (`DESCRIPTION:4-7`, `DESCRIPTION:23`); source-tree suite `[ FAIL 0 \| WARN 0 \| SKIP 3 \| PASS 3340 ]` offline and `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 3382 ]` with the oracle reachable; `R CMD build` + `R CMD check --no-manual` → **`Status: OK`**, tests inside the check `[ FAIL 0 \| WARN 0 \| SKIP 4 \| PASS 3338 ]` | `cat R/*.R \| wc -l`, `cat tests/testthat/*.R \| wc -l`, `ls tests/testthat/files`; `DESCRIPTION:25`; `grep -rn "fread\|data.table" R/` empty and `grep -rn "utils::" R/` down to the single comment line that explains the helper (`R/utils.R:13`); `testthat::test_local()` with and without `MZSPECLIB_PYTHON`, 2026-10-22; build + check with tests run 2026-10-23. The tarball run skips one test the source tree runs and therefore reports 3338 rather than 3340: `test-spec-examples.R:121-122` reads `reports/analysis/cv_label_audit_cache.json`, which `.Rbuildignore` keeps out of the package — the skip names itself ("the term name audit is not there"), so the two counts are the same suite seen from two roots, not two different suites |
| the differential test file itself: 42 expectations — per-library spectra/peak counts through both readers, `gold` inventories **equal** for 7 original↔R-written pairs (8, 9, 6, 50, 9, 47 and 11 unique `level: message` entries), and the 9 refusals of item 2 pinned by file *and* reason; one python process for 32 files, a fresh validator chain per file (a chain's error log cannot be cleared: its setter discards the value, `validate/validator.py:502`), memoized CV load; whole file gated on `MZSPECLIB_PYTHON`, 6.7 s when psims serves its bundled CVs and 55 s when `purl.obolibrary.org` answers | `tests/testthat/test-reference-python.R`; `MZSPECLIB_PYTHON=/tmp/mzvenv/bin/python Rscript -e 'testthat::test_local(filter = "reference-python")'` |

### Key upstream references

- `RforMassSpectrometry/Spectra` — `R/MsBackend.R` (fat virtual class, method
  contract), `R/MsBackendDataFrame-functions.R` (`.SPECTRA_DATA_COLUMNS`),
  `R/MsBackendMemory.R` (`peaksDataFrame`), `vignettes/MsBackend.Rmd` (backend
  authoring guide), `inst/test_backends/README.md` (compliance suite).
- `RforMassSpectrometry/ProtGenerics` (branch `master`) — `peaksData`,
  `peaksVariables`, `backendInitialize`, `backendMerge` live here, not in Spectra.
- `HUPO-PSI/mzSpecLib` — `specification/mzSpecLib_specification_v1.0.pdf`
  (§3.4 serializations/sidecar indexes, §4.1 text format, §4.2 JSON, §4.3
  announced binary), `specification/mzSpecLib_json.schema.json`,
  `specification/peak-annotation-format/annotation.lark`,
  `docs/metadata-rules.md`, `docs/guidelines/{mz,mass}_terms.csv`,
  `examples/*` (8 text + 2 JSON libraries).
- `HUPO-PSI/mzspeclib-py` — the reference implementation: `mzspeclib/validate/rules/
  {base,gold,silver,all}.json` (+ `tmp/terms.xlsx`,
  `tmp/excel_terms_to_json_rules.py`, `tmp/convert_to_xlsx.py`,
  `validator-rules-schema.json`), `mzspeclib/backends/`, `mzpaf/annotation.py`
  (a second, wider mzPAF grammar than the spec's `.lark`).
- `RforMassSpectrometry/MsBackendMzSpecLib` — **the backend this report's Option B
  describes, already started.** Read `inst/txt/mzSpecLib-mapping.txt` before
  designing any mapping of your own (§4.12).
- `mobiusklein/mzspeclib-rs` (streaming Rust reader, **unlicensed**) and
  `rusteomics/mzcore` / `mzannotate` (reader + writer, the implementation
  psidev.info lists under "Implementations"; `data/` carries all three filename
  conventions).
- psidev.info mzSpecLib page — ratification date, "Implementations" list,
  tool registry. Release paper: *Anal. Chem.* **97**(2), 2025,
  `10.1021/acs.analchem.4c04091`.
- Zenodo **10.5281/zenodo.13685813** + `Noble-Lab/multi-species-benchmark`
  (`MGFUtils.java`) — the only large real mzSpecLib corpus and its producer
  (§4.13, §8 Q5). Related: *Sci Data* 2024, `10.1038/s41597-024-04068-4`.
- HUPO-PSI issues: #13 HDF, #74 Avro, #48 unimplemented features, #7 CV
  refinement (mzSpecLib); #3 interpretation/precursor placement (mzspeclib-py);
  OpenMS #10172 (mzSpecLib support), #10175 (mzPAF conformance); Galaxy PR #22888.
- `tacular-omics/spxtacular` — `src/spxtacular/mzspeclib.py` is the most useful
  single file in this survey for the architecture question: a third-party,
  non-HUPO-PSI mzSpecLib 1.0 model sitting **under** a Spectra-like spectrum class,
  with CV carry-through for everything the flat record cannot hold (§4.13 c).
  Also relevant: `paftacular` (their mzPAF parser) and `peptacular` (ProForma).
- Adoption evidence, all fetched directly: `matchms/matchms`
  (`matchms/exporting/save_as_mzspeclib.py`, issues #751/#752/#757/#758),
  `ProteoWizard/pwiz` (`pwiz_tools/CarafeSharp/CarafeSharp.Proteome/LibraryOutputs.cs`,
  `CarafeSharp.Test/CommandLineErrorTest.cs`), `galaxyproject/galaxy` PR #22888,
  `OpenMS/OpenMS` issues #10172/#10175.
- **OLS4 API** (`www.ebi.ac.uk/ols4/api/ontologies/ms/terms?iri=…`) — the authority
  used by `analysis/cv_label_audit.py` to audit the normative table's labels.

### Reproducing the measurements

```sh
cd reports
Rscript analysis/mapping_gap.R     # metadata census vs Spectra's spectraVariables
Rscript analysis/proto_reader.R    # 127-line reader over the spec examples
Rscript analysis/loss_experiment.R # single-spectrum walk into Spectra
Rscript analysis/bench_gen.R       # writes the 15.2 MB / 13.5 MB bench corpus
Rscript analysis/bench2.R          # parse timings over that corpus + the real examples
Rscript analysis/json_modes.R      # simplifyVector TRUE/FALSE: timing AND the length() trap
python3 analysis/cv_label_audit.py # normative-table labels vs PSI-MS in OLS4 (§3.3)
python3 analysis/db_absence_probe.py            # EBI Search negatives + controls (§4.14)
python3 analysis/db_absence_probe.py --massive  # + the 20 428-record MassIVE sweep (~1 min)

# The four scripts that need the python oracle of §9 (mzspeclib 1.0.7 in
# /tmp/mzvenv); the two newest additionally drive R via pkgload, so the package
# itself must load:
/tmp/mzvenv/bin/python analysis/oracle_probes.py  # §3.3 accession errors, §4.11 rows
                                     # 13–14 (offline)
/tmp/mzvenv/bin/python analysis/oracle_counts.py  # the §4.3 three-way comparison
/tmp/mzvenv/bin/python analysis/oracle_defects.py # the six §4.15 probes; probe 4 runs
                                     # the CLI twice
/tmp/mzvenv/bin/python analysis/viol_inventory.py # normalised gold inventories;
                                     # ~1 min/file cold — the CLI loads the PSI-MS
                                     # ontology per run (network first, psims's
                                     # vendored 4.1.258 copy offline)
bash analysis/count_tool_sweep.sh    # §4.15 item 4; spec-repo clone only

# The package's own test suite. The first is offline and is what R CMD check
# runs; the second additionally runs the differential against the oracle (the
# file skips unless MZSPECLIB_PYTHON names an interpreter, because the oracle
# fetches its ontologies over the network in every process):
Rscript -e 'testthat::test_local(".")'
MZSPECLIB_PYTHON=/tmp/mzvenv/bin/python \
  Rscript -e 'testthat::test_local(".")'

# Every verbatim quotation from the specification in §3.2/§3.3/§4.13/§8.1 is a quote
# from this one command's output (no script; the PDF is not redistributed here):
pdftotext -layout ~/dev/mzSpecLib/specification/mzSpecLib_specification_v1.0.pdf - | less
```

`mapping_gap.R`, `proto_reader.R` and `json_modes.R` need only base R +
`jsonlite`; they read `~/dev/mzSpecLib/examples/` through hard-coded absolute
paths, so edit the file vectors at the top of each script if your spec clone lives
somewhere else. `bench2.R` needs `data.table` and expects
`/tmp/work/data/bench.mzSpecLib.{txt,json}`; generate them with `bench_gen.R`
first (fixed seed, so the corpus is byte-identical across machines). The
Spectra-dependent claims in §4.1/§4.2-generous/§4.4 have no script here — see the
reproducibility caveat above for what to install.
