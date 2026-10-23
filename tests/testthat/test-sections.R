## The section structure of the text serialization (mzSpecLib v1.0, sections
## 4.1.1, 4.1.3 and 4.1.7 to 4.1.10): which section line owns which lines,
## which sections may appear where, and what a section line that the
## specification does not define does to the file.

## One file, written for these tests, that puts every section kind of the
## format into a place the specification does not intend for it. The terms are
## copied verbatim from inst/extdata/example.mzSpecLib.txt.
section_lines <- c(
    "# a comment before everything",
    "MS:1003186|library format version=1.0",
    "<mzSpecLib>",
    "MS:1003187|library identifier=mzspec:PXL000001:sections",
    "",
    "<Cluster=1>",
    "MS:1003320|spectrum cluster size=6",
    "<Spectrum=1>",
    "MS:1000511|ms level=2",
    "<Peaks>",
    "# a comment among the peak rows",
    "100.0000\t1000.0\t y1",
    "101.0000\t500.0",
    "<Analyte=1>",
    "MS:1003270|proforma peptidoform ion notation=FAC[Carbamidomethyl]HSASLTVR/3",
    "<Peaks>",
    "102.0000\t10.0",
    "<InterpretationMember=1>",
    "MS:1003164|member spectrum USI=mzspec:PXL000001:x:key:1",
    "<Cluster=2>",
    "MS:1003320|spectrum cluster size=2",
    "<spectrum=2>",
    "MS:1000511|ms level=2",
    "<Spectrum = 3 >",
    "MS:1000511|ms level=2")

## The same lines in a file of their own.
section_file <- function(lines = section_lines, name = ".mzSpecLib.txt") {
    file <- tempfile(fileext = name)
    writeLines(lines, file)
    file
}

test_that("a section line owns every line up to the next section line", {
    rg <- mzspeclib:::.text_regions(section_lines)
    expect_named(rg, c("lines", "name", "qualifier", "type", "value",
        "start", "end"))
    expect_identical(rg$name, c("mzSpecLib", "Cluster", "Spectrum", "Peaks",
        "Analyte", "Peaks", "InterpretationMember", "Cluster", "spectrum",
        "Spectrum"))
    ## A region ends on the line before the next section line, and the last
    ## region ends on the last line of the file.
    expect_identical(rg$start, c(3L, 6L, 8L, 10L, 14L, 16L, 18L, 20L, 22L,
        24L))
    expect_identical(rg$end, c(5L, 7L, 9L, 13L, 15L, 17L, 19L, 21L, 23L,
        length(section_lines)))
    ## The key of a section is what stands behind the equal sign, spaces
    ## around it included in the file but not in the key.
    expect_identical(rg$qualifier[[2L]], "1")
    expect_identical(rg$qualifier[[10L]], "3")
    expect_identical(rg$qualifier[[1L]], "")
    ## An attribute set is the only section with a second word.
    sets <- mzspeclib:::.text_regions(c("<AttributeSet Spectrum=all>",
        "MS:1000511|ms level=2"))
    expect_identical(sets$name, "AttributeSet")
    expect_identical(sets$type, "Spectrum")
    expect_identical(sets$value, "all")
    expect_identical(sets$qualifier, "")
    ## Nothing to split into regions.
    expect_length(mzspeclib:::.text_regions(character())$name, 0L)
    expect_identical(mzspeclib:::.text_regions(c("a", "b"))$start,
        integer())
})

test_that("the library section is what the header belongs to", {
    lib <- read_mzspeclib(section_file())
    ## The line in front of <mzSpecLib> is read as a library attribute, but
    ## is reported as the deviation it is.
    expect_identical(nrow(libraryCv(lib)), 2L)
    expect_identical(libraryCv(lib)$accession, c("MS:1003186", "MS:1003187"))
    expect_issue(lib, "1 line\\(s\\) before the first section line were read")
    ## A cluster attribute does not become a library attribute, and neither
    ## does an attribute of a spectrum.
    expect_false("MS:1003320" %in% libraryCv(lib)$accession)
    expect_false("MS:1000511" %in% libraryCv(lib)$accession)
    ## The lines before the first section line are read even when the required
    ## section line is missing altogether; the issue then names what was found.
    orphan <- read_mzspeclib(section_file(c("MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1000511|ms level=2")))
    expect_length(orphan, 1L)
    expect_identical(nrow(libraryCv(orphan)), 1L)
})

test_that("a peak row belongs to the spectrum, not to the <Peaks> line", {
    lib <- read_mzspeclib(section_file())
    ## Two <Peaks> sections in one spectrum are one peak table.
    pk <- spectraPeaks(lib, i = 1L)
    expect_identical(nrow(pk), 3L)
    expect_identical(pk$mz, c(100, 101, 102))
    expect_identical(pk$annotation[[1L]], " y1")
    expect_identical(pk$annotation[-1L], rep(NA_character_, 2L))
    ## A comment between peak rows is a comment, not a row and not an
    ## unparsable attribute line.
    expect_length(lib$issues, 3L)
    ## A spectrum that follows without a <Peaks> section of its own has no
    ## peaks; the rows above did not stay with it.
    empty <- spectraPeaks(lib, i = 2L)
    expect_identical(nrow(empty), 0L)
    expect_null(lib$spectra[[2L]]$peaks)
    ## The <Analyte> section in the middle of a spectrum neither ends it nor
    ## takes the peak rows with it.
    expect_identical(nrow(analyteCv(lib, i = 1L, inherit = FALSE)), 1L)
    expect_identical(spectraIds(lib), c(1L, 3L))
})

test_that("section names are exactly the ones the specification defines", {
    lib <- read_mzspeclib(section_file())
    ## "<spectrum=2>" is not "<Spectrum=2>": the whole section is unknown, its
    ## line count is reported and its content is dropped.
    expect_issue(lib, "unknown section '<spectrum=2>' at line 22")
    expect_length(spectra(lib), 2L)
    expect_false(2L %in% spectraIds(lib))
    ## A section line is a section line only on its own.
    mixed <- read_mzspeclib(section_file(c("<mzSpecLib>",
        "MS:1003186|library format version=1.0", "<Spectrum=1>extra",
        "MS:1000511|ms level=2")))
    expect_length(mixed, 0L)
    expect_issue(mixed, "ignoring 1 unparsable line\\(s\\) in the library header: <Spectrum=1>extra")
    expect_length(mixed$issues, 1L)
    ## A commented out section line stays a comment.
    commented <- read_mzspeclib(section_file(c("<mzSpecLib>",
        "#<Spectrum=1>", "MS:1003186|library format version=1.0")))
    expect_length(commented, 0L)
    expect_length(commented$issues, 0L)
    expect_identical(attr(commented, "comments"), 1L)
})

test_that("nested sections need the spectrum they nest in", {
    ## Section 4.1.7 to 4.1.9 nest a spectrum, so without one their lines have
    ## nowhere to go, and the reader says so instead of guessing.
    lines <- c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Analyte=1>", "MS:1003270|proforma peptidoform ion notation=PEP/2",
        "<Interpretation=1>", "MS:1003163|number of interpretation members=1",
        "<InterpretationMember=1>",
        "MS:1003164|member spectrum USI=mzspec:PXL000001:x:key:1",
        "<Peaks>", "100.0\t1000.0")
    lib <- read_mzspeclib(section_file(lines))
    expect_length(lib, 0L)
    expect_length(lib$issues, 4L)
    expect_issue(lib, "'Analyte' section without a preceding <Spectrum>")
    expect_issue(lib, "'Interpretation' section without a preceding <Spectrum>")
    expect_issue(lib, "'InterpretationMember' section without a preceding")
    expect_issue(lib, "'<Peaks>' without a preceding <Spectrum> section; 1")
    expect_identical(attr(lib, "comments"), 0L)
    ## An <InterpretationMember> inside a spectrum but before any
    ## <Interpretation> is likewise lost (section 4.1.9).
    lib2 <- read_mzspeclib(section_file(c(section_lines[1:9],
        section_lines[18:19], "<mzSpecLib>", "MS:1003187|library identifier=x")))
    expect_issue(lib2, "<InterpretationMember> without an <Interpretation>")
    expect_identical(nrow(interpretationCv(lib2, i = 1L, inherit = FALSE)),
        0L)
})

test_that("an interpretation keeps its members in the order of the file", {
    ## Section 4.1.8/4.1.9: a spectrum holds interpretations, each of which
    ## holds members. Members of a second interpretation do not join the first.
    lines <- c("<mzSpecLib>", "MS:1003186|library format version=1.0", "",
        "<Spectrum=1>", "MS:1000511|ms level=2", "",
        "<Interpretation=1>", "MS:1003163|number of interpretation members=2",
        "<InterpretationMember=1>", "MS:1003237|library spectrum key=11",
        "<InterpretationMember=2>", "MS:1003237|library spectrum key=12",
        "<Interpretation=2>", "MS:1003163|number of interpretation members=1",
        "<InterpretationMember=1>", "MS:1003237|library spectrum key=13")
    lib <- read_mzspeclib(section_file(lines))
    expect_length(lib$issues, 0L)
    it <- lib$spectra[[1L]]$interpretations
    expect_length(it, 2L)
    expect_length(it[[1L]]$members, 2L)
    expect_length(it[[2L]]$members, 1L)
    expect_identical(vapply(it[[1L]]$members, function(x) x$id, integer(1)),
        c(1L, 2L))
    long <- interpretationMemberCv(lib)
    expect_identical(nrow(long), 3L)
    expect_identical(long$value, c("11", "12", "13"))
    ## Which interpretation a member row came from is in the long table too:
    ## the two members of the first interpretation carry its position and key,
    ## the third row carries those of the second, so the three rows of one
    ## spectrum can be split by interpretation without the object.
    expect_identical(long$interpretation, c(1L, 1L, 2L))
    expect_identical(long$interpretation_key, c(1L, 1L, 2L))
    expect_identical(long$member, c(1L, 2L, 1L))
    expect_identical(long$member_key, c(1L, 2L, 1L))
    tab <- interpretationTable(lib, columns = "MS:1003163")
    expect_identical(tab$interpretation, c(1L, 2L))
    expect_identical(tab$interpretation_key, c(1L, 2L))
    ## The interpretation a member belongs to is also visible in the wide
    ## view, which is where a reader looks for it.
    tab <- interpretationTable(lib, columns = "MS:1003163")
    expect_identical(tab[["MS:1003163"]], c("2", "1"))
})

test_that("clusters come before spectra, and both keep their own order", {
    lib <- read_mzspeclib(section_file())
    ## Interleaved in the file, separated in the object, in canonical order
    ## (see ?read_mzspeclib, "Comments and other things that are not kept").
    expect_identical(vapply(clusters(lib), function(x) x$id, integer(1)),
        c(1L, 2L))
    out <- tempfile(fileext = ".mzSpecLib.txt")
    write_mzspeclib(lib, out)
    written <- readLines(out)
    section <- grep("^<", written)
    kind <- sub("^<([A-Za-z]+).*", "\\1", written[section])
    expect_identical(kind, c("mzSpecLib", rep("Cluster", 2L), "Spectrum",
        "Analyte", "Peaks", "Spectrum"))
    ## The order within a kind is the order of the file, not the order of the
    ## keys.
    reversed <- read_mzspeclib(section_file(c("<mzSpecLib>",
        "MS:1003186|library format version=1.0",
        "<Cluster=7>", "MS:1003320|spectrum cluster size=1",
        "<Cluster=3>", "MS:1003320|spectrum cluster size=2",
        "<Spectrum=9>", "MS:1000511|ms level=2",
        "<Spectrum=4>", "MS:1000511|ms level=2")))
    expect_identical(vapply(clusters(reversed), function(x) x$id,
        integer(1)), c(7L, 3L))
    expect_identical(spectraIds(reversed), c(9L, 4L))
    expect_identical(clusterCv(reversed)$cluster, c(1L, 2L))
})

test_that("an attribute set section is neither a header nor a spectrum", {
    lines <- c("<mzSpecLib>", "MS:1003186|library format version=1.0", "",
        "<AttributeSet Spectrum=all>", "MS:1000511|ms level=2", "",
        "<Spectrum=1>", "MS:1003061|spectrum name=one")
    lib <- read_mzspeclib(section_file(lines))
    expect_length(lib$issues, 0L)
    expect_identical(nrow(libraryCv(lib)), 1L)
    expect_identical(nrow(spectraCv(lib, i = 1L, inherit = FALSE)), 1L)
    expect_identical(nrow(attributeSets(lib)), 1L)
    ## A malformed attribute set line names the set it could not read.
    bad <- read_mzspeclib(section_file(c("<mzSpecLib>",
        "MS:1003186|library format version=1.0", "<AttributeSet Spectrum>",
        "MS:1000511|ms level=2", "<AttributeSet>",
        "MS:1000511|ms level=2", "<Spectrum=1>", "MS:1003061|spectrum name=one")))
    expect_identical(nrow(attributeSets(bad)), 0L)
    expect_issue(bad, "ignoring malformed attribute set line '<AttributeSet Spectrum>'")
    expect_issue(bad, "ignoring malformed attribute set line '<AttributeSet>'")
    ## Two issues, one per line, and the attribute lines did not join the
    ## header.
    expect_length(bad$issues, 2L)
    expect_identical(nrow(libraryCv(bad)), 1L)
})

test_that("a spectrum key must be an integer, and must be unique", {
    lines <- c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=5>", "MS:1003061|spectrum name=five",
        "<Spectrum=5>", "MS:1003061|spectrum name=again",
        "<Spectrum=x>", "MS:1003061|spectrum name=letter",
        "<Spectrum>", "MS:1003061|spectrum name=nothing",
        "<Spectrum=+7>", "MS:1003061|spectrum name=plus")
    lib <- read_mzspeclib(section_file(lines))
    expect_identical(spectraIds(lib), c(5L, 5L, NA_integer_, NA_integer_, 7L))
    expect_length(lib, 5L)
    expect_issue(lib, "duplicated library spectrum key 5")
    expect_issue(lib, "non-numeric key 'x' in <Spectrum>")
    expect_issue(lib, "<Spectrum> section without a key")
    expect_length(grep("duplicated", lib$issues), 1L)
    ## A key that is not a key still identifies the spectrum for the accessors
    ## that work on positions, and the missing key does not stop the reader.
    expect_identical(cvParameter(spectraCv(lib, i = 3L, inherit = FALSE),
        "MS:1003061"), "letter")
    expect_identical(spectraTable(lib)[["spectrum_key"]][[3L]], NA_integer_)
    ## The same rules for the other keyed sections.
    ## "<Analyte >" has no equal sign at all, which is a section without a
    ## key; "<Analyte=y>" has a key that is not a number. Both give up the key
    ## and say why, and the wide table is where the key shows up.
    keyed <- read_mzspeclib(section_file(c("<mzSpecLib>",
        "MS:1003186|library format version=1.0", "<Spectrum=1>",
        "MS:1000511|ms level=2", "<Analyte >",
        "MS:1003270|proforma peptidoform ion notation=AILINFIDR/2",
        "<Analyte=y>",
        "MS:1003270|proforma peptidoform ion notation=HLAEISLLEQSFVK/3",
        "<Cluster>", "MS:1003320|spectrum cluster size=1")))
    expect_issue(keyed, "<Analyte> section without a key")
    expect_issue(keyed, "non-numeric key 'y' in <Analyte>")
    expect_issue(keyed, "<Cluster> section without a key")
    expect_length(keyed$issues, 3L)
    expect_identical(analyteTable(keyed)$analyte_key,
        c(NA_integer_, NA_integer_))
    expect_identical(analyteTable(keyed)$analyte, c(1L, 2L))
    expect_identical(clusterTable(keyed)$cluster_key, NA_integer_)
    ## The two analytes are still two analytes, key or no key.
    expect_length(keyed$spectra[[1L]]$analytes, 2L)
})

test_that("a version tag beside <mzSpecLib> is read and reported", {
    ## Section 4.1.1 states the line as exactly '<mzSpecLib>', but producers of
    ## real libraries write a version tag beside it. Nothing in the model comes
    ## from that tag - the format version is the MS:1003186 parameter - so the
    ## library is read whole and only the deviation is reported, which matters
    ## because the writer has only the conformant line to write.
    lib <- read_mzspeclib(section_file(c("<mzSpecLib 1.0>",
        "MS:1003186|library format version=1.0", "<Spectrum=1>",
        "MS:1000511|ms level=2", "<Peaks>", "100.0\t1000.0")))
    expect_length(lib$issues, 1L)
    expect_issue(lib, "states more than the '<mzSpecLib>' line")
    expect_length(lib, 1L)
    expect_identical(spectraIds(lib), 1L)
    expect_identical(cvParameter(libraryCv(lib), "MS:1003186"), "1.0")
    expect_identical(nrow(spectraPeaks(lib, 1L)), 1L)
    ## The line as the specification writes it is not a deviation, and neither
    ## is a space inside the brackets: typesetting is not content. Text *after*
    ## the closing bracket, though, keeps the line from being a section line at
    ## all, which is the stronger deviation and is reported as that (see
    ## "section names are exactly the ones the specification defines" above).
    versioned <- function(...)
        read_mzspeclib(section_file(c(...)))
    expect_length(versioned("<mzSpecLib>",
        "MS:1003186|library format version=1.0")$issues, 0L)
    expect_length(versioned("<mzSpecLib >",
        "MS:1003186|library format version=1.0")$issues, 0L)
    spaced <- versioned("<mzSpecLib > ",
        "MS:1003186|library format version=1.0")
    expect_length(spaced$issues, 1L)
    expect_issue(spaced, "does not start with the required '<mzSpecLib>' line")
    ## The tag is not in the object and not in the written file, which is the
    ## point of reporting it.
    out <- tempfile(fileext = ".mzSpecLib.txt")
    write_mzspeclib(lib, out)
    expect_identical(readLines(out)[[1L]], "<mzSpecLib>")
    expect_length(read_mzspeclib(out)$issues, 0L)
})
