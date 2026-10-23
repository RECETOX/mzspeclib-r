## The controlled vocabulary parameter grammar of mzSpecLib v1.0, section
## 4.1.2, and the single-value accessor cvParameter() built on the resulting
## table.
##
## The example lines of the first test are transcribed verbatim from section
## 4.1.2 of mzSpecLib_specification_v1.0.pdf (HUPO-PSI, Apache License 2.0);
## the remaining ones are copied from inst/extdata/example.mzSpecLib.txt, so
## that every accession and term name in this file comes from a real file.

## The example block of section 4.1.2.
spec_lines <- c(
    "MS:1000888|stripped peptide sequence=DSDDVPMVLVGNKCDLAAR",
    "MS:1001112|n-terminal flanking residue=K",
    "MS:1000044|dissociation method=MS:1002472|trap-type collision-induced dissociation",
    "MS:1003208|experimental monoisotopic precursor m/z=880.8902",
    "[1]MS:1003209|monoisotopic m/z deviation=0.333",
    "[1]UO:0000000|unit=UO:0000169|parts per million")

## Every parsed line has these columns, in this order.
cv_names <- c("group", "accession", "name", "value", "value_accession")

test_that("the examples of section 4.1.2 parse into the five columns", {
    for (line in spec_lines) {
        res <- mzspeclib:::cv_parse_line(line)
        expect_identical(names(res), cv_names)
        expect_false(is.na(res[["accession"]]))
        expect_false(is.na(res[["name"]]))
    }
    res <- mzspeclib:::cv_parse_line(spec_lines[[1]])
    expect_identical(res[["accession"]], "MS:1000888")
    expect_identical(res[["name"]], "stripped peptide sequence")
    expect_identical(res[["value"]], "DSDDVPMVLVGNKCDLAAR")
    expect_identical(res[["value_accession"]], NA_character_)
    ## An m/z with a slash and a decimal point is an ordinary free value.
    res <- mzspeclib:::cv_parse_line(spec_lines[[4]])
    expect_identical(res[["name"]], "experimental monoisotopic precursor m/z")
    expect_identical(res[["value"]], "880.8902")
})

test_that("a group designator becomes the group, not the whole line", {
    ## The regression this guards: "[1]" used to end up in the accession, or
    ## the group column to hold the whole "[1]" prefix instead of "1".
    res <- mzspeclib:::cv_parse_line(spec_lines[[5]])
    expect_identical(res[["group"]], "1")
    expect_identical(res[["accession"]], "MS:1003209")
    expect_identical(res[["value"]], "0.333")
    res <- mzspeclib:::cv_parse_line("[1]MS:1003207|library creation software=MS:1001477|SpectraST")
    expect_identical(res[["group"]], "1")
    expect_identical(res[["accession"]], "MS:1003207")
    ## More than one digit, and no designator at all.
    expect_identical(mzspeclib:::cv_parse_line("[12]MS:1000511|ms level=2")[["group"]],
        "12")
    expect_identical(mzspeclib:::cv_parse_line("[108]MS:1000511|ms level=2")[["group"]],
        "108")
    expect_identical(mzspeclib:::cv_parse_line("MS:1000511|ms level=2")[["group"]],
        NA_character_)
    ## The space the specification's examples put after the bracket is part of
    ## the designator, not of the accession.
    res <- mzspeclib:::cv_parse_line("[1] MS:1000885|protein accession=sp|HUMAN|xxxx")
    expect_identical(res[["group"]], "1")
    expect_identical(res[["accession"]], "MS:1000885")
    expect_identical(res[["value"]], "sp|HUMAN|xxxx")
    ## A non numeric designator is not a designator, and the line is simply
    ## what it is: a term whose accession column carries the brackets.
    expect_identical(mzspeclib:::cv_parse_line("[x]MS:1000511|ms level=2")[["group"]],
        NA_character_)
})

test_that("a CV valued object is split into its accession and its name", {
    res <- mzspeclib:::cv_parse_line("MS:1000044|dissociation method=MS:1000422|beam-type collision induced dissociation")
    expect_identical(res[["accession"]], "MS:1000044")
    expect_identical(res[["name"]], "dissociation method")
    expect_identical(res[["value_accession"]], "MS:1000422")
    expect_identical(res[["value"]], "beam-type collision induced dissociation")
    ## Terms of other ontologies are CV terms as well (section 4.1.2 names the
    ## Unit Ontology and NCBITaxon explicitly).
    res <- mzspeclib:::cv_parse_line("[1]UO:0000000|unit=UO:0000266|electronvolt")
    expect_identical(res[["accession"]], "UO:0000000")
    expect_identical(res[["value_accession"]], "UO:0000266")
    expect_identical(res[["value"]], "electronvolt")
    res <- mzspeclib:::cv_parse_line("NCBITaxon:9606|taxonomy: scientific name=Homo sapiens")
    expect_identical(res[["accession"]], "NCBITaxon:9606")
    expect_identical(res[["value_accession"]], NA_character_)
    expect_identical(res[["value"]], "Homo sapiens")
})

test_that("a USI value is a value and not a CV term", {
    ## "mzspec:" is followed by characters, not by digits, so the value must
    ## stay one piece. This is the one place where a purely syntactic split of
    ## "accession|name" would invent a value accession.
    usi <- c(
        "MS:1003203|constituent spectrum file=mzspec:PXD000561:Fetal_Brain_Gel_Velos_16_f16",
        "MS:1003299|contributing replicate spectrum USI=mzspec:PXL000001:fetal_brain_tiny:key:1",
        "MS:1003204|constituent identification file=file://data/interact.pep.xml")
    values <- c("mzspec:PXD000561:Fetal_Brain_Gel_Velos_16_f16",
        "mzspec:PXL000001:fetal_brain_tiny:key:1", "file://data/interact.pep.xml")
    for (k in seq_along(usi)) {
        res <- mzspeclib:::cv_parse_line(usi[[k]])
        expect_identical(res[["value"]], values[[k]])
        expect_identical(res[["value_accession"]], NA_character_)
    }
})

test_that("a quoted name keeps its quotes and its own equal signs", {
    ## Section 4.1.2: "If the exact name of the CV term contains an =
    ## character (e.g., for regular expressions of proteases), then the name
    ## MUST be enclosed in double quotation characters". No term of that kind
    ## occurs in the libraries of this repository, so the quotation itself is
    ## exercised with a term name copied verbatim from
    ## inst/extdata/example.mzSpecLib.txt.
    res <- mzspeclib:::cv_parse_line("MS:1001467|\"taxonomy: NCBI TaxID\"=9606")
    expect_identical(res[["accession"]], "MS:1001467")
    expect_identical(res[["name"]], "\"taxonomy: NCBI TaxID\"")
    expect_identical(res[["value"]], "9606")
    ## An unterminated quote and a quote that does not end right before the
    ## delimiter are not parsable names.
    expect_null(mzspeclib:::cv_parse_line("MS:1001467|\"taxonomy: NCBI TaxID=9606"))
    expect_null(mzspeclib:::cv_parse_line("MS:1001467|\"taxonomy\"x=9606"))
    ## Quotes inside the *value* are part of the value (section 4.1.2: "all
    ## quotation marks are to be interpreted as part of the string"), and so
    ## are equal signs, as the delimiter is the FIRST equal sign. Both lines
    ## are copied verbatim from inst/extdata/example.mzSpecLib.txt.
    line <- "[1]MS:1003206|library creation log=COMPILE FROM /data/fetal_brain_tiny_consensus.splib\"  [DECOY;c=TRUE;y=1;DPS=FALSE;I=]"
    res <- mzspeclib:::cv_parse_line(line)
    expect_identical(res[["name"]], "library creation log")
    expect_identical(res[["value"]],
        "COMPILE FROM /data/fetal_brain_tiny_consensus.splib\"  [DECOY;c=TRUE;y=1;DPS=FALSE;I=]")
    expect_identical(mzspeclib:::cv_format_row(res), line)
})

test_that("an empty object is allowed", {
    res <- mzspeclib:::cv_parse_line("MS:1001200|confidence=")
    expect_identical(res[["value"]], "")
    expect_false(is.na(res[["value"]]))
    expect_identical(res[["value_accession"]], NA_character_)
    expect_identical(mzspeclib:::cv_format_row(res), "MS:1001200|confidence=")
})

test_that("a line which is not a CV parameter is NULL", {
    bad <- c("not a cv line", "", "MS:1000511 ms level=2", "|no accession=2",
        "MS:1000511|ms level", "MS:1000511|", "=", "  ",
        "MS:1003061|library spectrum name")
    for (line in bad)
        expect_null(mzspeclib:::cv_parse_line(line), info = line)
})

test_that("cv_format_row is the inverse of cv_parse_line", {
    lines <- c(spec_lines,
        "MS:1003186|library format version=1.0",
        "MS:1001200|confidence=",
        "MS:1001467|\"taxonomy: NCBI TaxID\"=9606",
        "[2]MS:1003254|peak attribute=MS:1003286|coefficient of variation of intensity of peak among replicates")
    for (line in lines)
        expect_identical(mzspeclib:::cv_format_row(mzspeclib:::cv_parse_line(line)),
            line, info = line)
    ## A term read from JSON has NA instead of the empty text of the text
    ## serialization, and is written back the way the grammar wants it.
    row <- mzspeclib:::cv_parse_line("MS:1001200|confidence=")
    row[["value"]] <- NA_character_
    expect_identical(mzspeclib:::cv_format_row(row), "MS:1001200|confidence=")
    expect_identical(mzspeclib:::cv_format_rows(mzspeclib:::.empty_df(cv_names)),
        character())
})

test_that("unparsable lines inside a section are reported, not fatal", {
    state <- mzspeclib:::.issue_state()
    res <- mzspeclib:::cv_parse_lines(c("MS:1000511|ms level=2", "nonsense",
        "also nonsense"), state, "<Spectrum=1>")
    expect_identical(dim(res), c(1L, 5L))
    expect_identical(colnames(res), cv_names)
    expect_length(state$issues, 1L)
    expect_match(state$issues[[1]], "ignoring 2 unparsable line\\(s\\) in <Spectrum=1>")
    expect_match(state$issues[[1]], "nonsense")
    ## Nothing to parse and no state to complain to.
    expect_identical(dim(mzspeclib:::cv_parse_lines(character())), c(0L, 5L))
    expect_silent(mzspeclib:::cv_parse_lines("nonsense"))
})

test_that("cvParameter matches on the accession and returns the last instance", {
    lib <- example_library()
    cv <- libraryCv(lib)
    expect_identical(cvParameter(cv, "MS:1003188"), "fetal_brain_tiny_consensus_td")
    expect_identical(cvParameter(cv, "MS:1003207"), "SpectraST")
    ## A term whose object is a CV term: the value or the name it points to.
    expect_identical(cvParameter(cv, "MS:1003207", value = FALSE), "MS:1001477")
    ## A free text value has no term to point to.
    expect_identical(cvParameter(cv, "MS:1003188", value = FALSE), NA_character_)
    ## Repeated terms: the last instance by default, all of them on request.
    expect_length(cvParameter(cv, "MS:1003206"), 1L)
    all <- cvParameter(cv, "MS:1003206", all = TRUE)
    expect_length(all, 4L)
    expect_identical(cvParameter(cv, "MS:1003206"), all[[4L]])
    ## Absent terms and empty tables give character(0), never NA and never an
    ## error.
    expect_identical(cvParameter(cv, "MS:9999999"), character())
    expect_identical(cvParameter(cv, "MS:9999999", all = TRUE), character())
    expect_identical(cvParameter(mzspeclib()$header, "MS:1003186"), character())
    expect_identical(cvParameter(NULL, "MS:1003186"), character())
    expect_error(cvParameter(cv, c("MS:1003186", "MS:1003188")),
        "'accession' must be a single string")
})

test_that("cvParameter finds terms of every ontology without knowing them", {
    lib <- example_library()
    cv <- spectraCv(lib, i = 1L)
    ## A Unit Ontology term and a PSI-MS term are looked up the same way, and
    ## the same accession may appear in an attribute set instead of the
    ## section.
    expect_identical(cvParameter(cv, "UO:0000000"), "second")
    expect_identical(cvParameter(cv, "UO:0000000", value = FALSE), "UO:0000010")
    expect_identical(cvParameter(cv, "MS:1000043"), "percent of base peak times 100")
    expect_identical(cvParameter(cv, "MS:1000511"), "2")
})
