## Reading the text serialization: what a file is turned into before any of
## the accessors looks at it. The section structure itself is the subject of
## test-sections.R, the deviations from the specification that of
## test-issues.R.

test_that("the example library is read with its header intact", {
    lib <- example_library()
    expect_s3_class(lib, "mzspeclib_library")
    expect_length(lib$issues, 0L)
    cv <- libraryCv(lib)
    expect_identical(colnames(cv), c("group", "accession", "name", "value",
        "value_accession"))
    expect_identical(nrow(cv), 15L)
    ## The header as written: fifteen lines, of which the first six and the
    ## last three are not grouped, and the six creation software lines carry
    ## the group.
    expect_identical(sum(is.na(cv$group)), 9L)
    expect_identical(unique(cv$group[!is.na(cv$group)]), "1")
    expect_identical(cv$accession[[1L]], "MS:1003186")
    expect_identical(cv$value[[1L]], "1.0")
    expect_identical(spectraIds(lib), 1:3)
    expect_length(spectra(lib), 3L)
    expect_length(clusters(lib), 0L)
    ## The whole header is kept as text; only the peak columns are numbers.
    expect_identical(unique(vapply(cv, function(x) class(x)[[1L]], character(1))),
        "character")
    expect_identical(lib$file, normalizePath(example_path(), mustWork = FALSE))
})

test_that("comments and empty lines are not content", {
    lib <- example_library()
    ## The example file has no comments: section 4.1.1 requires a text library
    ## to begin with its '<mzSpecLib>' line, so nothing may stand in front of
    ## it - not even the attribution of an excerpt, which is why it is in the
    ## manual instead of the file.
    lines <- readLines(example_path(), encoding = "UTF-8")
    expect_identical(attr(lib, "comments"), 0L)
    expect_identical(lines[[1L]], "<mzSpecLib>")
    ## The excerpt claim is checked rather than repeated: the file is the first
    ## lines of the reference library, byte for byte.
    reference <- reference_path(
        "SpectraST/fetal_brain_tiny_consensus_td.mzSpecLib.txt")
    skip_if_not(file.exists(reference),
        "the specification repository is not available")
    expect_identical(lines,
        readLines(reference, encoding = "UTF-8")[seq_along(lines)])
    ## A library that does carry comments counts them, and keeps them out of
    ## the content.
    named <- read_fixture("spec-4-1-12-groups.mzSpecLib.txt")
    namedLines <- readLines(fixture("spec-4-1-12-groups.mzSpecLib.txt"),
        encoding = "UTF-8")
    expect_identical(attr(named, "comments"),
        sum(startsWith(namedLines, "#")))
    expect_true(attr(named, "comments") > 0L)
    expect_length(named$issues, 0L)
    ## Neither a comment nor a blank line can end up as a CV parameter.
    expect_false(any(grepl("^#|^$", c(libraryCv(lib)$accession,
        libraryCv(lib)$name))))
    expect_false(any(grepl("^<", libraryCv(lib)$accession)))
    ## The fixture has blank lines between its sections, and the parser does
    ## not turn them into unparsable lines.
    spec <- read_fixture("spec-4-1-6-spectrum.mzSpecLib.txt")
    expect_length(spec$issues, 0L)
})

test_that("a UTF-8 byte order mark and CRLF line endings are tolerated", {
    lib <- read_fixture("crlf-bom.mzSpecLib.txt")
    expect_length(lib$issues, 0L)
    expect_identical(length(lib), 1L)
    expect_identical(spectraIds(lib), 1L)
    expect_identical(cvParameter(libraryCv(lib), "MS:1003186"), "1.0")
    expect_identical(cvParameter(libraryCv(lib), "MS:1003187"),
        "mzspec:PXL000001:mzSpecLib_v1_example")
    pk <- spectraPeaks(lib, 1L)
    expect_identical(pk$mz, c(110.0405, 110.3405))
    expect_identical(pk$annotation, c("IH", "?"))
    ## The byte order mark directly in front of the required section line.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    con <- file(file, "wb")
    writeBin(charToRaw(paste0("\ufeff<mzSpecLib>\r",
        "MS:1003186|library format version=1.0\r", "\r",
        "<Spectrum=1>\r", "MS:1000511|ms level=2\r")), con)
    close(con)
    bom <- read_mzspeclib(file)
    expect_length(bom$issues, 0L)
    expect_identical(length(bom), 1L)
    expect_identical(cvParameter(libraryCv(bom), "MS:1003186"), "1.0")
})

test_that("a .gz file is read through a connection", {
    lines <- readLines(example_path(), encoding = "UTF-8")
    file <- tempfile(fileext = ".mzSpecLib.txt.gz")
    con <- gzfile(file, "w")
    writeLines(lines, con)
    close(con)
    expect_true(grepl("\\.gz$", file))
    plain <- example_library()
    gz <- read_mzspeclib(file)
    expect_identical(mzspeclib:::.detect_format(file, "UTF-8"), "text")
    expect_identical(libraryCv(gz), libraryCv(plain))
    expect_identical(attributeSets(gz), attributeSets(plain))
    expect_identical(spectraIds(gz), spectraIds(plain))
    expect_identical(spectraCv(gz), spectraCv(plain))
    expect_identical(spectraPeaks(gz), spectraPeaks(plain))
    expect_length(gz$issues, 0L)
    ## Writing compresses by the same rule.
    out <- tempfile(fileext = ".mzSpecLib.txt.gz")
    write_mzspeclib(plain, out)
    con <- gzfile(out, "r")
    written <- readLines(con)
    close(con)
    expect_identical(written, mzspeclib:::format_text(plain))
    expect_length(read_mzspeclib(out), 3L)
})

test_that("the serialization is chosen by the file, and can be dictated", {
    lib <- example_library()
    expect_identical(mzspeclib:::.detect_format(example_path(), "UTF-8"), "text")
    expect_identical(mzspeclib:::.detect_format(fixture("json-library.mzSpecLib.json"),
        "UTF-8"), "json")
    ## A JSON document in a file that does not say so is still recognized.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    file.copy(fixture("json-library.mzSpecLib.json"), file)
    expect_identical(mzspeclib:::.detect_format(file, "UTF-8"), "json")
    expect_length(read_mzspeclib(file), 2L)
    ## Dictating the wrong serialization does not crash; the reader says what
    ## it could not read.
    text <- read_mzspeclib(fixture("json-library.mzSpecLib.json"),
        format = "text")
    expect_length(text, 0L)
    expect_issue(text, "does not start with the required '<mzSpecLib>' line")
    json <- read_mzspeclib(example_path(), format = "json")
    expect_length(json, 0L)
    expect_issue(json, "the file is not a JSON document")
    expect_error(read_mzspeclib(example_path(), format = "xml"),
        "'arg' should be one of")
})

test_that("values of CV parameters keep the text of the file", {
    lib <- example_library()
    cv <- libraryCv(lib)
    ## "1.0" is not 1, and a release date is not a date.
    expect_identical(cvParameter(cv, "MS:1003186"), "1.0")
    expect_identical(cvParameter(cv, "MS:1003190"), "1.0")
    expect_identical(cvParameter(cv, "MS:1001017"), "2023-05-06T00:00:00")
    expect_identical(cvParameter(cv, "MS:1003200"), "6.0")
    ## A value that parses as a number stays the text of the file, including
    ## its trailing zero, whether it was read from a section or inherited from
    ## an attribute set (the collision energy of the example library lives in
    ## <AttributeSet Spectrum=all>).
    expect_identical(cvParameter(spectraCv(lib, i = 1L), "MS:1000045"), "39.0")
    expect_identical(spectraTable(lib, columns = "MS:1000045")[[3L]][[1L]],
        "39.0")
    ## The ms level of the example of section 4.1.6 is "3", not 3L.
    spec <- read_fixture("spec-4-1-6-spectrum.mzSpecLib.txt")
    expect_identical(cvParameter(spectraCv(spec, i = 1L, inherit = FALSE),
        "MS:1000511"), "3")
    ## Only mz and intensity become double.
    pk <- spectraPeaks(read_fixture("spec-4-1-16-peak-attributes.mzSpecLib.txt"),
        i = 1L)
    expect_type(pk$mz, "double")
    expect_type(pk$intensity, "double")
    expect_type(pk[[4L]], "character")
})

test_that("a library without spectra and without attributes reads cleanly", {
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0"),
        file)
    lib <- read_mzspeclib(file)
    expect_length(lib, 0L)
    expect_length(lib$issues, 0L)
    expect_identical(nrow(libraryCv(lib)), 1L)
    expect_identical(nrow(attributeSets(lib)), 0L)
    ## The header line alone: still readable, but not clean, because section
    ## 4.1.1 makes MS:1003186|library format version mandatory.
    writeLines("<mzSpecLib>", file)
    noVersion <- read_mzspeclib(file)
    expect_issue(noVersion, "no MS:1003186\\|library format version")
    expect_length(noVersion$issues, 1L)
    expect_identical(nrow(libraryCv(noVersion)), 0L)
    ## An empty file is not a library, and says so.
    empty <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(character(), empty)
    nothing <- read_mzspeclib(empty)
    expect_length(nothing, 0L)
    expect_issue(nothing, "no section line at all")
})
