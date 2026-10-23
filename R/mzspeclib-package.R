#' mzspeclib: Read and Write HUPO-PSI mzSpecLib Spectral Libraries
#'
#' mzSpecLib is the HUPO-PSI exchange format for spectral libraries. A library
#' file describes a spectral library with controlled vocabulary (PSI-MS)
#' parameters on four levels - the library itself, its spectra, the analytes
#' and interpretations of a spectrum - plus, for every spectrum, a peak list.
#' Version 1.0 of the specification defines two normative serializations of
#' that model, a line oriented plain text format and a JSON format, and this
#' package reads and writes both.
#'
#' @section Getting started:
#' [read_mzspeclib()] reads a file and returns a [mzspeclib()] object;
#' [write_mzspeclib()] writes such an object again. Everything else in the
#' package are accessors for the object: [libraryCv()] and [libraryTable()] for
#' the library header, [spectraCv()] and [spectraTable()] for the spectra,
#' [spectraPeaks()] for the peak lists as data.frames,
#' [analyteCv()]/[analyteTable()], [interpretationCv()]/[interpretationTable()],
#' [clusterCv()]/[clusterTable()], [attributeSets()] for the attribute set
#' definitions, [cvParameter()] to pick single parameters out of a CV table, and
#' [peakColumns()] for the meaning of the additional peak columns.
#'
#' @section Two views on the metadata:
#' Every level of the model is offered twice, because the two forms are needed
#' by different consumers.
#'
#' The `*Cv()` accessors return the parameters *as written*, one row per
#' parameter, with nothing merged, reordered or dropped. That is the faithful
#' view, and the one to use when a file has to be understood or reproduced.
#'
#' The `*Table()` accessors return one row per entity - one row per spectrum -
#' and one column per parameter, with repeated parameters collapsed into one
#' cell. That is the form a data.frame consumer wants: [spectraTable()] gives a
#' `data.frame` with a column per spectrum attribute, ready to be joined with
#' the peak matrices of [spectraPeaks()]. `*Table()` accessors inherit the
#' attribute sets a spectrum claims (see [attributeSets()]), which the `*Cv()`
#' accessors do not.
#'
#' @section Design decisions:
#' - **Plain lists and data.frames, with S3 classes only for printing and
#'   subsetting.** The format is a tree of sections; a class hierarchy would
#'   add nothing to reading or writing it, and a plain object can be inspected
#'   with `str()` and passed to a downstream package without that package
#'   having to import a class definition.
#' - **No ontology lookups, and no type conversion based on the ontology.**
#'   Nothing in this package asks a PSI-MS copy what a term means. Values are
#'   kept exactly as the file wrote them, as `character`, and only peak `mz`
#'   and `intensity` are converted to `double`. That keeps a result - and a
#'   publication that quotes one - independent of which ontology version
#'   happens to be installed. The `coerce` argument of the `*Table()` accessors
#'   offers type guessing from the *values* alone, on request.
#' - **Nothing is dropped because the package does not know a term.** An
#'   unknown accession, an unknown peak attribute and even an unknown section
#'   type are read into the object; deviations that do cost something (a
#'   section without a key, a JSON member the specification does not define)
#'   are collected in the object's `issues` element instead of failing the read.
#' - **Columns are named by accession, not by term name.** The PSI-MS names of
#'   two accessions have changed over time, accessions have been merged, and
#'   two terms can share a name; the accession cannot. Use `useAccession =
#'   FALSE` on a `*Table()` accessor to get the term names instead, and
#'   [cvParameter()] when writing code that has to survive a rename.
#' - **`spectraPeaks()`, not `peaksData()`.** The peak accessor is named after
#'   what it returns rather than reusing the `peaksData()` generic of
#'   ProtGenerics, so that this package has no dependency on the naming
#'   decisions of the mass spectrometry infrastructure and a caller can use it
#'   without attaching anything.
#'
#' @section JSON serialization:
#' The two serializations describe the same model, and the object holds that
#' model, not the file. Where they correspond is stated in the specification;
#' where they do not, this package behaves as follows.
#'
#' | text serialization | JSON serialization |
#' | --- | --- |
#' | `<mzSpecLib>` section | `attributes` |
#' | `<AttributeSet Spectrum=name>` | `spectrum_attribute_sets` (and the three other scopes) |
#' | `<Cluster=N>` | `clusters`, without its key (see below) |
#' | `<Spectrum=N>` | `spectra` (no key: the identity is the `MS:1003237` attribute) |
#' | `<Analyte=N>` / `<Interpretation=M>` | `analytes` / `interpretations`, objects keyed by that number |
#' | `<InterpretationMember=N>` | `member_interpretations` of the interpretation |
#' | `accession|name=value` with a group designator in brackets | `{"accession", "name", "value"}` plus `"cv_param_group"` |
#' | `accession|name=ACC|value` | `"value_accession": "ACC"` |
#' | columns 1 and 2 of a peak row | `mzs`, `intensities` |
#' | column 3 of a peak row | `peak_annotations`, `"?"` for an unannotated peak |
#' | columns 4+ of a peak row | `aggregations` |
#'
#' Reading is permissive: a string, a list of strings or a list of structured
#' mzPAF annotation objects is accepted as the annotation of a peak. The first
#' two become the `annotation` column of the peak table; structured mzPAF
#' annotation *objects* are kept as their JSON text, because this package does
#' not implement the mzPAF annotation grammar, and are written back as objects
#' by [write_mzspeclib()] when the target is JSON.
#'
#' Two deviations of the format itself are worth knowing, because both make a
#' strictly schema-validating reader fail on the specification's own examples.
#' The `spectrum` object of `mzSpecLib_json.schema.json` allows no
#' `interpretations` member, although the same schema defines the
#' `interpretation` object and although every spectrum of the example libraries
#' has interpretations; and the schema wants the per-peak annotations to be an
#' array of arrays, while the example libraries - and the writer of the
#' reference python implementation - write one string per peak. Both forms are
#' read. This package does not validate documents against the schema.
#'
#' Two limitations of the *writer* follow from the same schema and from the
#' decision to know no ontology, and both are stated rather than hidden:
#'
#' - A JSON document types its values, a text file does not, and in the
#'   reference implementation it is the range a CV term declares in the
#'   ontology - `xsd:float` for `MS:1000045|collision energy`, `xsd:string` for
#'   `MS:1003186|library format version` - that decides whether a value is
#'   written as a number or as a string. That range is not in the file: a text
#'   library holds both as the text `"39.0"` and `"1.0"`, and no property of
#'   those texts tells them apart. This package therefore types a value only
#'   where typing is *reversible*, i.e. where reading the document back yields
#'   exactly the text that stood in the file, and keeps the text otherwise. A
#'   value such as `"39.0"` consequently stays a string, and the validation
#'   rules of the format report the term's declared numeric range as violated.
#'   Typing every value that parses as a number instead would write the version
#'   terms as `1` and `6` - which violates just as many rules of the same level
#'   and destroys the value a version term holds.
#' - A `<Cluster=N>` key cannot be written to JSON at all: the `cluster` object
#'   of the schema has `attributes` as its only property and allows no other,
#'   and no CV term stands for a cluster key. [write_mzspeclib()] warns about
#'   it, because the key of the library's clusters is then not in the file it
#'   writes. The attributes of the clusters survive unchanged.
#'
#' @section Round trips:
#' Reading and writing a text library reproduces its metadata byte for byte;
#' peak numbers are re-rendered with `digits` significant digits, so they are
#' guaranteed numerically equal rather than identical. Reading and writing a
#' JSON library reproduces the metadata and the peak numbers as JSON numbers.
#' Three things cannot survive a change of serialization: the key of a
#' `<Cluster>` section, which [write_mzspeclib()] warns about, the *order* of a
#' file that interleaved clusters and spectra, and comments (the specification
#' says comments are "generally NOT transcribed to other serializations"; the
#' reader counts them and keeps the count in the `comments` attribute of the
#' object it returns, so a caller can see that something was left out).
#'
#' @section The example file:
#' `system.file("extdata", "example.mzSpecLib.txt", package = "mzspeclib")` is
#' a byte identical excerpt of `fetal_brain_tiny_consensus_td.mzSpecLib.txt`
#' from the `examples/SpectraST/` directory of the HUPO-PSI mzSpecLib
#' specification repository, (c) HUPO-PSI, Apache License 2.0 - the library
#' header and the first three spectra, with nothing modified. It is the file the
#' examples of this manual page and of every accessor use. It exercises three
#' attribute sets, analytes, interpretations with member interpretations, mzPAF
#' peak annotations and peak rows with additional attribute columns; spectrum 3
#' is a consensus spectrum whose peak rows carry the three additional peak
#' attributes the header declares.
#'
#' The file carries no comment lines, because section 4.1.1 requires a text
#' library to begin with its `<mzSpecLib>` line - a provenance comment in front
#' of it makes the file invalid - so the attribution lives here instead.
#'
#' @section Licence:
#' The code of this package is MIT licensed, see the `LICENSE` file. The example
#' library above is not: it stays a separate component under the specification
#' repository's Apache License 2.0, and that is stated both here and in the
#' README.
#'
#' @name mzspeclib-package
#'
#' @seealso [read_mzspeclib()], [mzspeclib()]
NULL
