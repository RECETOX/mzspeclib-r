# mzspeclib

mzspeclib reads and writes spectral libraries in mzSpecLib, the HUPO-PSI
exchange format for spectral libraries, at version 1.0 of the specification.
Both normative serializations are supported in both directions: the
line-oriented plain text format (`.mzSpecLib.txt`) and the JSON format
(`.json`). A file is read once into a plain `list` - library attributes,
attribute set definitions, clusters and spectra, with analytes,
interpretations and peak lists hanging off each spectrum - and accessors
present parts of that object as `data.frame`s, so that no class has to be
understood in order to use the data. Controlled vocabulary values are kept
exactly as the file wrote them, as `character`, and only peak `mz` and
`intensity` are converted to `double`, so a result does not depend on which
copy of the PSI-MS ontology happens to be installed. The only dependency is
`jsonlite`: the package neither uses Spectra nor resolves terms against an
ontology.

## Install

mzspeclib is not on CRAN. This source tree is the package root, so:

    R CMD INSTALL .

`jsonlite` is the only package that has to be present to install it.

## Quick start

`read_mzspeclib()` chooses the serialization from the file extension, and
`write_mzspeclib()` does the same; `format = "text"` or `format = "json"`
overrides that choice, and a file ending in `.gz` is streamed through a
connection either way. The package ships a small library to try things on:
the header and the first three spectra of a HUPO-PSI example library.

```r
library(mzspeclib)

lib <- read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",
    package = "mzspeclib"))
lib
#> mzSpecLib library [example.mzSpecLib.txt]
#>   name: fetal_brain_tiny_consensus_td
#>   spectra: 3
#>   clusters: 0
#>   attribute sets: 3
#>   library CV parameters: 15
```

`spectraTable()` gives the per-spectrum metadata as a `data.frame`, one row
per spectrum and one column per controlled vocabulary term. Restricting the
columns with `columns` is usually the way to look at a library for the first
time; without it, every term the spectra and their attribute sets carry
becomes a column.

```r
spectraTable(lib, columns = c("MS:1000511", "MS:1000894", "MS:1003065"))
#>   spectrum spectrum_key MS:1000511 MS:1000894         MS:1003065
#> 1        1            1          2     1189.6 singleton spectrum
#> 2        2            2          2     1189.6 singleton spectrum
#> 3        3            3          2     2622.1 consensus spectrum
```

`spectraPeaks()` gives the peak lists. A peak table has `mz` and `intensity`
as `double`, the mzPAF fragment ion annotation of section 4.1.14 of the
specification as an opaque `character` column, and, where the library defines
them, one column per additional peak attribute - named by accession, as
reported by `peakColumns()`.

```r
head(spectraPeaks(lib, 1L), 3L)
#>        mz intensity                  annotation
#> 1 103.0541     102.5                           ?
#> 2 110.0711    1329.4 IC[Carbamidomethyl]/-0.0008
#> 3 115.0863     110.9                           ?
```

Single parameters are picked out of any of the long CV tables with
`cvParameter()`, which matches on the accession alone:

```r
cvParameter(spectraCv(lib, i = 1L), "MS:1000894")
#> [1] "1189.6"
```

Writing renders the object again; here the same library leaves as JSON and
comes back with the same three spectra.

```r
out <- tempfile(fileext = ".mzSpecLib.json")
write_mzspeclib(lib, out)
length(read_mzspeclib(out))
#> [1] 3
```

## Two views on the metadata

Every level of the model - library, spectrum, analyte, interpretation,
interpretation member, cluster - is offered twice, because the two forms are
needed by different consumers.

The `*Cv()` accessors (`libraryCv()`, `spectraCv()`, `analyteCv()`,
`interpretationCv()`, `interpretationMemberCv()`, `clusterCv()`) return the
parameters *as the file states them*: one row per parameter, in the columns
`group`, `accession`, `name`, `value` and `value_accession`, with the designator
of a line such as `[1]MS:1000045|collision energy=39.0` kept in `group` and
with repeated attributes kept as separate rows. Nothing is merged, reordered
or dropped. This is the view to read when a file has to be understood or
reproduced.

The `*Table()` accessors (`libraryTable()`, `spectraTable()`,
`analyteTable()`, `interpretationTable()`, `clusterTable()`) flatten the same
parameters into one row per entity and one column per term, joining the
values of a term that occurs more than once for one entity with `collapse`.
That is the shape a tabular consumer wants, and it is lossy by construction:
a wide table has nowhere to put a group designator, and a group is precisely
how the format binds attributes that must be read together - a collision
energy and its unit, or the ordered declaration of the additional peak
columns. `cvLosses()` counts, per level, how many rows of a library carry a
group or repeat a term, so the loss can be measured before it is relied on.

Two views rather than one because each loses what the other exists to keep:
the faithful view costs a reshape before use, the wide view costs
relationships. Both are available without an option, and neither is the
"real" representation - the object is that, and it holds the model rather
than either file.

Columns are keyed by accession (`MS:1000894`) rather than by term name
(`retention time`), because the accession is the stable identifier: PSI-MS
term names have changed over time, accessions have been merged, and two
terms can share a name. `useAccession = FALSE` asks for the term names
instead (duplicated names get a numeric suffix), the `cvName` attribute of
every wide table carries the mapping in whichever direction was not chosen,
and `cvParameter()` - which matches accessions only - is what code that has
to survive a rename should use.

## For authors of a Spectra backend

Nothing in this package imports Spectra, and the peak accessor is
deliberately named `spectraPeaks()` rather than being a `peaksData()` method,
so that the format core does not depend on the naming decisions of the mass
spectrometry infrastructure and a backend keeps ownership of the mapping
between the two conventions. The intended consumer of these accessors is
[MsBackendMzSpecLib](https://github.com/RforMassSpectrometry/MsBackendMzSpecLib);
this package contains no integration with it and makes no claim about its API.

What the accessors do is shaped for that kind of consumer:

- `spectraPeaks(lib, i)` returns a `data.frame` when `i` selects exactly one
  spectrum and a `list` of `data.frame`s otherwise - the convention
  `peaksData()` uses, so the result can be passed straight through.
- `spectraTable(lib)` returns one row per spectrum, with the identifying
  columns `spectrum` (the position within the library) and `spectrum_key`
  (the library spectrum key, read from the `<Spectrum=N>` line or, in JSON,
  from its `MS:1003237` attribute) in front of the CV columns, and
  `spectraPeaks()` in the same order, so the two can be joined by position.
  The rows are the spectra, not the CV lines: a spectrum that states no
  attribute at all still has its row (with `NA` in every term column), so
  `nrow(spectraTable(lib)) == length(spectra(lib))` holds and restricting
  `columns` cannot silently drop spectra.
- The wide views inherit the attribute sets a spectrum claims, and so does
  the naming of the additional peak columns. That default is deliberate:
  many libraries keep most of their spectrum-level metadata in the `all`
  set, and a reader that ignores attribute sets reports such spectra as
  nearly empty. `attributeSets()` returns the definitions, and `inherit =
  FALSE` on the long views returns only what a section itself defines.
- `peakColumns(lib)` reports which additional peak column corresponds to
  which declared `MS:1003254|peak attribute`, and
  `spectraPeaks(lib, peakColumns = FALSE)` keeps the positional `X4`, `X5`,
  ... names the reader assigns from the file's column numbers.

## Limitations

- **No CV ontology validation, and no term-driven typing.** Accessions are
  never looked up, values stay `character` exactly as the file has them, and
  a value is never converted because of what its term means. That is
  deliberate and is the reason results are reproducible across ontology
  versions; the reasoning is stated in `?mzspeclib-package`. On request,
  `coerce = TRUE` on a `*Table()` accessor converts columns that are
  entirely numeric or entirely `TRUE`/`FALSE`, judging by the values alone.
- **JSON documents are not validated against the published schema.** That
  would need a JSON schema validator as a dependency, and the schema
  disagrees with the specification's own example files in two places that a
  strictly validating reader would trip over (recorded under "JSON
  serialization" in `?mzspeclib-package`). A member a document has but the
  specification does not define does not reach the returned object - its
  content has no place in the model - but reading continues regardless.
- **Structured mzPAF annotation objects are kept as their JSON text.** When a
  JSON document carries a peak's annotation as mzPAF annotation objects
  rather than as a string, the `annotation` column holds the JSON text of
  those objects; the mzPAF annotation grammar is not implemented. Such an
  annotation is written back as objects when the target is JSON, so a JSON
  round trip keeps it structured.
- **JSON values are typed only where typing is reversible.** A JSON document
  types its values and a text file does not, and what decides the type in the
  reference implementation is the range the CV term declares in the ontology -
  which is not in the file. A value is therefore written as a number or a
  boolean only when reading it back yields exactly the text that stood in the
  file, and stays text otherwise; `39.0` stays `"39.0"`, and the validation
  rules of the format then report that term's declared range as violated.
  Guessing instead would write `MS:1003186|library format version` as `1`.
- **Three things cannot survive a change of serialization:** the key of a
  `<Cluster>` section, which the JSON schema has no place for and which
  `write_mzspeclib()` therefore warns about; the order of a file
  that interleaved `<Cluster>` and `<Spectrum>` sections, because both
  writers emit the clusters as one group in front; and comments, which the
  specification itself says are generally not transcribed.
- **A text round trip reproduces the metadata byte for byte, but not the
  peak text.** `mz` and `intensity` are re-rendered at `digits` significant
  digits, so they come back numerically equal rather than character
  identical; a value such as `10000.0` is written as `10000`.

## Tests

The suite is `testthat` and runs offline:
`Rscript -e 'testthat::test_local()'` from the repository root needs no network
and no other package beyond `testthat` itself.

One file is a deliberate exception.
`tests/testthat/test-reference-python.R` compares this package's reading of a
library — and the violations reported for a library this package wrote — against
the reference python implementation of the format, the software with which the
specification's own example libraries were produced. It is the only comparison
here that cannot be made against this package alone, and also the only one that
cannot run inside `R CMD check`: the reference implementation resolves every
controlled vocabulary term against the PSI-MS and the unit ontology and fetches
both from `purl.obolibrary.org` in every fresh process (measured: about 50
seconds before it reads a file), and which ontology happens to answer decides the
wording of a violation, so a run of it is neither fast nor reproducible. The file
therefore skips unless `MZSPECLIB_PYTHON` names an interpreter that has
`mzspeclib` installed:

    MZSPECLIB_PYTHON=/path/to/venv/bin/python \
        Rscript -e 'testthat::test_local(filter = "reference-python")'

about a minute for all of it, in a single python process.

## Rationale and licence

The design decisions behind all of this - a format core without a backend,
plain lists instead of a class hierarchy, the accession as column key, the
refusal to consult an ontology - are laid out in
`reports/2026-09-29-architecture-survey-mzspeclib-in-r.md`.

The code is released under the MIT License, see `LICENSE`.
`inst/extdata/example.mzSpecLib.txt` is an excerpt of
`fetal_brain_tiny_consensus_td.mzSpecLib.txt` from the `examples/SpectraST/`
directory of the HUPO-PSI mzSpecLib specification repository and remains under
that repository's Apache License 2.0. The file is a byte identical excerpt with
no comment lines of its own, because section 4.1.1 requires a text library to
begin with its `<mzSpecLib>` line; the attribution is part of the manual, under
"The example file" in `?mzspeclib-package`.
