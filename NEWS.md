# mzspeclib 0.1.0

First version, 2026-10-22.

## New features

- `read_mzspeclib()` and `write_mzspeclib()` read and write mzSpecLib v1.0 in
  both of its normative serializations, the plain text format and the JSON
  format. The serialization is chosen from the file extension, or from the
  first line if the extension does not decide it, and a file ending in `.gz`
  is streamed through a connection.
- The whole data model is represented: library attributes, attribute sets and
  their inheritance, spectra, analytes, interpretations, interpretation
  members, clusters and peak lists, including mzPAF peak annotations and the
  additional peak attribute columns. It is returned as plain lists and
  `data.frame`s with S3 classes only for printing and subsetting, so the
  object can be inspected with `str()` and passed on without a class
  definition. Unknown accessions and unknown peak attributes are read rather
  than discarded, and a deviation that does cost content - a section without
  a key, a JSON member the specification does not define - does not fail the
  read.
- Two accessor families per level of the model. The long views `libraryCv()`,
  `spectraCv()`, `analyteCv()`, `interpretationCv()`,
  `interpretationMemberCv()` and `clusterCv()` return the parameters as
  written, one row per parameter with the group designator intact. The wide
  views `libraryTable()`, `spectraTable()`, `analyteTable()`,
  `interpretationTable()` and `clusterTable()` return one row per entity and
  one column per term, keyed by accession by default. `spectraPeaks()` and
  `peakColumns()` cover the peak lists, `attributeSets()` the set
  definitions, `cvParameter()` picks single terms out of a CV table,
  `cvLosses()` reports what a wide table cannot express, and `spectra()`,
  `spectraIds()` and `clusters()` reach the objects themselves.
- Attribute set inheritance is applied by the wide views and by the naming of
  the additional peak columns: the `all` set applies to every entry without
  being claimed, an attribute written in a section shadows the inherited ones
  for that term, and where more than one claimed set defines the same term the
  later one replaces the earlier rather than accumulating beside it. A context
  is a term *and* the attribute group it stands in, so a set claimed from
  inside a group is inherited into that group alone, as section 4.1.12
  demonstrates. `inherit = FALSE` returns only what a section itself defines,
  and the `inherited` column of the long views tells the two layers apart.
- Reading and writing a text library reproduces its metadata byte for byte;
  peak numbers are re-rendered at `digits` significant digits, so they are
  numerically equal rather than identical. A JSON round trip keeps the
  metadata and the peak numbers as JSON numbers, and keeps structured mzPAF
  annotations structured.
- Deviations from the specification are collected in the object's `issues`
  element and, with `strict = TRUE`, also raised as a warning: a file that does
  not begin with `<mzSpecLib>`, a header without the mandatory
  `MS:1003186|library format version`, a version tag beside the `<mzSpecLib>`
  section line - `<mzSpecLib 1.0>`, which producers write although section 4.1.1
  states the line without it, and which the reader reports because the writer
  has only the conformant line to give back - a duplicated library spectrum key,
  a section without a key, a peak row with a non-numeric m/z, a JSON member the
  specification does not define. `write_mzspeclib()` warns about what it cannot
  write, which includes the key of a cluster - the JSON schema has no place for
  it.
- `inst/extdata/example.mzSpecLib.txt` is a checked-in example library: the
  header and the first three spectra of
  `fetal_brain_tiny_consensus_td.mzSpecLib.txt` from the `examples/SpectraST/`
  directory of the HUPO-PSI mzSpecLib specification repository, unmodified and
  used under that repository's Apache License 2.0 (the code of this package is
  MIT licensed). It exercises three attribute sets, analytes,
  interpretations with member interpretations, mzPAF annotations and peak rows
  with three additional peak attributes.

## Known limitations

No CV ontology validation and no term-driven typing - deliberate, see
`?mzspeclib-package`. JSON documents are not validated against the published
schema. Structured mzPAF annotation objects are kept as their JSON text rather
than parsed. A JSON value is typed only where typing is reversible, so a value
whose declared range lives in the ontology - `39.0` for
`MS:1000045|collision energy` - stays a string there and is reported as
violating that range by the format's own validation rules. The key of a
`<Cluster>` section, the interleaving of clusters and spectra, and comments do
not survive a change of serialization; `inst/extdata/example.mzSpecLib.txt`
carries no comment lines of its own, because a text library has to begin with
its `<mzSpecLib>` line. The suite itself is offline and dependency-free except
for `testthat`; the one test file that compares against the reference python
implementation of the format (`tests/testthat/test-reference-python.R`) is
opt-in through `MZSPECLIB_PYTHON`, because that implementation fetches the PSI-MS
and unit ontologies over the network in every process and lets the version it
fetches decide the wording of a violation.
