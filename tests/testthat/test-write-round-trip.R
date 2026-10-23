## Round trips: what write_mzspeclib() makes of an object, and what comes back
## when that file is read again.

## Read a file, write it, read the written file.
round_trip <- function(file, format = NULL, ...) {
    lib <- read_mzspeclib(file)
    out <- tempfile(fileext = if (is.null(format))
        if (grepl("\\.json$", file)) ".mzSpecLib.json" else ".mzSpecLib.txt"
        else if (format == "json") ".mzSpecLib.json" else ".mzSpecLib.txt")
    args <- list(lib, out, ...)
    if (!is.null(format))
        args$format <- format
    suppressWarnings(do.call(write_mzspeclib, args))
    list(lib = lib, file = out, written = readLines(out),
        back = suppressWarnings(read_mzspeclib(out)))
}

test_that("a file the writer itself could have written comes back byte by byte", {
    ## The canonical fixture has no comments, no blank lines and no
    ## interleaving, which is exactly what the writer produces: reading it,
    ## writing it and comparing the lines is the identity.
    res <- round_trip(fixture("canonical.mzSpecLib.txt"))
    expect_identical(res$written, readLines(fixture("canonical.mzSpecLib.txt")))
    expect_length(res$back$issues, 0L)
    expect_identical(res$back$header, res$lib$header)
    expect_identical(mzspeclib:::format_text(res$lib, warn = FALSE),
        res$written)
    ## Writing the object that came back gives the same file again, so the
    ## writer is at a fixed point after one pass.
    again <- tempfile(fileext = ".mzSpecLib.txt")
    write_mzspeclib(res$back, again)
    expect_identical(readLines(again), res$written)
})

test_that("the example library survives a text round trip in content", {
    res <- round_trip(example_path())
    lib <- res$lib
    back <- res$back
    ## Every CV table, every attribute set, every peak list.
    expect_identical(libraryCv(back), libraryCv(lib))
    expect_identical(spectraCv(back, inherit = FALSE),
        spectraCv(lib, inherit = FALSE))
    expect_identical(analyteCv(back, inherit = FALSE),
        analyteCv(lib, inherit = FALSE))
    expect_identical(interpretationCv(back, inherit = FALSE),
        interpretationCv(lib, inherit = FALSE))
    expect_identical(interpretationMemberCv(back), interpretationMemberCv(lib))
    expect_identical(attributeSets(back), attributeSets(lib))
    expect_identical(peakColumns(back), peakColumns(lib))
    expect_identical(all_peaks(back), all_peaks(lib))
    expect_identical(spectraIds(back), spectraIds(lib))
    expect_length(back$issues, 0L)
    ## The object as a whole, with the two things that cannot be the same:
    ## where it came from, and the comments the reader counted.
    same <- back
    same$file <- lib$file
    attr(same, "comments") <- attr(lib, "comments")
    expect_identical(same, lib)
})

test_that("what a text round trip does not keep is what it says it drops", {
    res <- round_trip(example_path())
    ## The example has no comments to lose, and a library that has them loses
    ## them (see ?read_mzspeclib, "Comments and other things that are not
    ## kept", and section 4.1.18 of the specification).
    expect_identical(attr(res$lib, "comments"), 0L)
    expect_identical(attr(res$back, "comments"), 0L)
    withComments <- round_trip(fixture("spec-4-1-12-groups.mzSpecLib.txt"))
    expect_true(attr(withComments$lib, "comments") > 0L)
    expect_identical(attr(withComments$back, "comments"), 0L)
    expect_false(any(grepl("^#", res$written)))
    expect_identical(length(res$written), 556L)
    ## Blank lines are not written either.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("", "<mzSpecLib>", "",
        "MS:1003186|library format version=1.0", "", "<Spectrum=1>", "",
        "MS:1000511|ms level=2", ""), file)
    out <- tempfile(fileext = ".mzSpecLib.txt")
    write_mzspeclib(read_mzspeclib(file), out)
    expect_identical(readLines(out), c("<mzSpecLib>",
        "MS:1003186|library format version=1.0", "<Spectrum=1>",
        "MS:1000511|ms level=2"))
    ## A byte order mark and CRLF line endings are read and written as plain
    ## UTF-8 with LF.
    bom <- tempfile(fileext = ".mzSpecLib.txt")
    con <- file(bom, "wb")
    writeBin(charToRaw(paste0("\ufeff<mzSpecLib>\r",
        "MS:1003186|library format version=1.0\r", "<Spectrum=1>\r",
        "MS:1000511|ms level=2\r")), con)
    close(con)
    out2 <- tempfile(fileext = ".mzSpecLib.txt")
    write_mzspeclib(read_mzspeclib(bom), out2)
    first <- readBin(out2, "raw", 1L)
    expect_identical(first, as.raw(60L))
    expect_false(any(grepl("\r", readLines(out2))))
    ## Several <Peaks> sections of one spectrum come back as one, written
    ## without the second header line.
    two <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1000511|ms level=2", "<Peaks>",
        "100.0\t1\ta1", "<Peaks>", "101.0\t2\tb1"), two)
    out3 <- tempfile(fileext = ".mzSpecLib.txt")
    write_mzspeclib(read_mzspeclib(two), out3)
    lines <- readLines(out3)
    expect_identical(sum(lines == "<Peaks>"), 1L)
    expect_identical(lines[grep("^[0-9]", lines)], c("100\t1\ta1", "101\t2\tb1"))
})

test_that("a gzip library is written and read through a connection", {
    gz <- tempfile(fileext = ".mzSpecLib.txt.gz")
    write_mzspeclib(example_library(), gz)
    expect_identical(readBin(gz, "raw", 2L), as.raw(c(0x1f, 0x8b)))
    back <- read_mzspeclib(gz)
    expect_identical(libraryCv(back), libraryCv(example_library()))
    expect_identical(all_peaks(back), all_peaks(example_library()))
    expect_length(back$issues, 0L)
    ## The gzip argument compresses whatever the file is called, and the JSON
    ## writer looks at the name only (see ?write_mzspeclib, "Ignored for
    ## JSON").
    plain <- tempfile(fileext = ".mzSpecLib.txt")
    suppressWarnings(write_mzspeclib(example_library(), plain, gzip = TRUE))
    expect_identical(readBin(plain, "raw", 2L), as.raw(c(0x1f, 0x8b)))
    json <- tempfile(fileext = ".mzSpecLib.json")
    suppressWarnings(write_mzspeclib(example_library(), json, gzip = TRUE))
    expect_identical(substr(readLines(json, n = 1L), 1L, 1L), "{")
    gzjson <- tempfile(fileext = ".mzSpecLib.json.gz")
    suppressWarnings(write_mzspeclib(example_library(), gzjson))
    expect_identical(readBin(gzjson, "raw", 2L), as.raw(c(0x1f, 0x8b)))
    expect_length(read_mzspeclib(gzjson), 3L)
})

test_that("the format argument decides the writing, the file name the reading", {
    ## Explicit JSON into a name that says text: the writer obeys the argument.
    json <- tempfile(fileext = ".mzSpecLib.txt")
    suppressWarnings(write_mzspeclib(example_library(), json, format = "json"))
    expect_identical(substr(readLines(json, n = 1L), 1L, 1L), "{")
    expect_length(read_mzspeclib(json), 3L)
    ## Explicit text into a name that says JSON: the writer again obeys, but
    ## the reader of the same package looks at the extension first
    ## (R/read-text.R:82), so the file it just wrote is no longer readable
    ## without the format argument. This asymmetry is a documented limitation
    ## of the round trip, not of the writer.
    txt <- tempfile(fileext = ".mzSpecLib.json")
    write_mzspeclib(example_library(), txt, format = "text")
    expect_identical(substr(readLines(txt, n = 1L), 1L, 1L), "<")
    expect_length(read_mzspeclib(txt), 0L)
    expect_length(read_mzspeclib(txt, format = "text"), 3L)
    ## An unknown format is refused before anything is written.
    missing <- tempfile(fileext = ".mzSpecLib.txt")
    expect_error(write_mzspeclib(example_library(), missing, format = "xml"),
        "'arg' should be one")
    expect_false(file.exists(missing))
})

test_that("digits is about the peak numbers and nothing else", {
    lib <- example_library()
    ## The default keeps every m/z and intensity of the example.
    full <- tempfile(fileext = ".mzSpecLib.txt")
    write_mzspeclib(lib, full)
    expect_identical(all_peaks(read_mzspeclib(full)), all_peaks(lib))
    ## Three significant digits round the peak numbers; CV values are text and
    ## keep the text they had, so "39.0" is still "39.0" and the version is
    ## still "1.0".
    few <- tempfile(fileext = ".mzSpecLib.txt")
    write_mzspeclib(lib, few, digits = 3)
    rounded <- read_mzspeclib(few)
    expect_identical(spectraPeaks(rounded, i = 1L)$mz[[1L]], 103)
    expect_identical(spectraPeaks(rounded, i = 1L)$intensity[[1L]], 102)
    expect_identical(libraryCv(rounded), libraryCv(lib))
    expect_identical(spectraCv(rounded, inherit = FALSE),
        spectraCv(lib, inherit = FALSE))
    ## Seven digits are enough for this library's m/z values, and NULL leaves
    ## the numbers to R's own formatting.
    seven <- tempfile(fileext = ".mzSpecLib.txt")
    write_mzspeclib(lib, seven, digits = 7)
    expect_identical(all_peaks(read_mzspeclib(seven)), all_peaks(lib))
    expect_identical(nchar(mzspeclib:::format_text(lib, digits = NULL,
        warn = FALSE)),
        nchar(mzspeclib:::format_text(lib, digits = 15L, warn = FALSE)))
    expect_error(mzspeclib:::format_text(lib, digits = 0, warn = FALSE),
        "invalid value 0 for 'digits'")
})

test_that("the writer says what it had to invent, and can be told to be quiet",
    {
    ## A library without the required format version, and a spectrum without a
    ## key: both are writeable, both are worth a warning (?write_mzspeclib,
    ## @param warn).
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003187|library identifier=x",
        "<Spectrum>", "MS:1000511|ms level=2"), file)
    lib <- read_mzspeclib(file)
    out <- tempfile(fileext = ".mzSpecLib.txt")
    ## Both complaints at once, so they are collected rather than matched one
    ## by one (expect_warning() would treat the second as unexpected).
    seen <- character()
    suppressWarnings(withCallingHandlers(write_mzspeclib(lib, out),
        warning = function(w) {
            seen <<- c(seen, conditionMessage(w))
            invokeRestart("muffleWarning")
        }))
    expect_length(seen, 2L)
    expect_true(any(grepl(
        "the header has no MS:1003186\\|library format version", seen)))
    expect_true(any(grepl("1 spectrum\\(s\\) have no library spectrum key",
        seen)))
    expect_silent(write_mzspeclib(lib, out, warn = FALSE))
    expect_silent(write_mzspeclib(lib, tempfile(fileext = ".mzSpecLib.json"),
        warn = FALSE))
    ## A library that is in order writes without a sound.
    good <- tempfile(fileext = ".mzSpecLib.txt")
    expect_silent(write_mzspeclib(example_library(), good))
    expect_silent(write_mzspeclib(example_library(),
        tempfile(fileext = ".mzSpecLib.json")))
    ## And it hands back the name it wrote.
    expect_identical(write_mzspeclib(example_library(), good), good)
})

test_that("a text -> JSON -> text round trip keeps the library", {
    res <- round_trip(example_path(), format = "json")
    back <- res$back
    ## The header, the attribute sets and the peak tables are identical; the
    ## only difference is the one attribute the JSON serialization needs per
    ## spectrum (see the helper).
    expect_identical(drop_spectrum_key(libraryCv(back)), libraryCv(res$lib))
    expect_identical(attributeSets(back), attributeSets(res$lib))
    expect_identical(all_peaks(back), all_peaks(res$lib))
    expect_identical(peakColumns(back), peakColumns(res$lib))
    for (k in seq_along(res$lib)) {
        expect_identical(drop_spectrum_key(spectraCv(back, i = k)),
            spectraCv(res$lib, i = k))
        expect_identical(reset_rows(drop_spectrum_key(
            analyteCv(back, i = k, inherit = FALSE))),
            reset_rows(analyteCv(res$lib, i = k, inherit = FALSE)))
        expect_identical(reset_rows(drop_spectrum_key(
            interpretationCv(back, i = k, inherit = FALSE))),
            reset_rows(interpretationCv(res$lib, i = k, inherit = FALSE)))
    }
    expect_length(back$issues, 0L)
    expect_identical(spectraIds(back), spectraIds(res$lib))
})

test_that("a JSON document is written again as it was read", {
    ## Read a JSON library, write it, write what came back again: the document
    ## does not change any more after the first pass.
    lib <- read_fixture("json-library.mzSpecLib.json")
    first <- tempfile(fileext = ".mzSpecLib.json")
    suppressWarnings(write_mzspeclib(lib, first))
    second <- tempfile(fileext = ".mzSpecLib.json")
    suppressWarnings(write_mzspeclib(read_mzspeclib(first), second))
    expect_identical(readLines(second), readLines(first))
    ## The written document is not byte identical to the fixture, because the
    ## writer always spells out every member of a spectrum object and the
    ## reference writer leaves empty optional members out; the library behind
    ## the two documents is the same.
    again <- read_mzspeclib(first)
    expect_identical(attributeSets(again), attributeSets(lib))
    expect_identical(libraryCv(again), libraryCv(lib))
    expect_identical(spectraIds(again), spectraIds(lib))
    expect_identical(nrow(clusterCv(again)), nrow(clusterCv(lib)))
    ## The peak tables, with one documented difference: a peak whose annotation
    ## was missing is written to JSON as the placeholder annotation "?", which
    ## is what the writer's own comment says it does for an unannotated peak
    ## (R/write-json.R:191-197). The text serialization writes an empty third
    ## column instead, so only the JSON round trip turns the missing value into
    ## that text.
    original <- all_peaks(lib)
    expect_identical(all_peaks(again), lapply(original, function(pk) {
            pk$annotation[is.na(pk$annotation)] <- "?"
            pk}))
    two <- spectraPeaks(again, i = 2L)
    expect_identical(two$annotation, c("?,y1/-0.0005", "?"))
    expect_identical(spectraPeaks(lib, i = 2L)$annotation,
        c("?,y1/-0.0005", NA_character_))
})

test_that("the JSON serialization of a text library is its own again", {
    ## text -> JSON -> text -> JSON: two round trips through both
    ## serializations leave the tables where they were.
    text <- example_path()
    json <- tempfile(fileext = ".mzSpecLib.json")
    suppressWarnings(write_mzspeclib(read_mzspeclib(text), json))
    back <- tempfile(fileext = ".mzSpecLib.txt")
    suppressWarnings(write_mzspeclib(read_mzspeclib(json), back))
    second <- tempfile(fileext = ".mzSpecLib.json")
    suppressWarnings(write_mzspeclib(read_mzspeclib(back), second))
    one <- read_mzspeclib(json)
    two <- read_mzspeclib(second)
    expect_identical(drop_spectrum_key(libraryCv(two)),
        drop_spectrum_key(libraryCv(one)))
    expect_identical(attributeSets(two), attributeSets(one))
    expect_identical(all_peaks(two), all_peaks(one))
    expect_identical(spectraIds(two), spectraIds(one))
    ## The empty library of either kind reads back as empty.
    txt <- tempfile(fileext = ".mzSpecLib.txt")
    suppressWarnings(write_mzspeclib(mzspeclib(), txt))
    expect_length(read_mzspeclib(txt), 0L)
    json2 <- tempfile(fileext = ".mzSpecLib.json")
    suppressWarnings(write_mzspeclib(mzspeclib(), json2))
    empty <- read_mzspeclib(json2)
    expect_length(empty, 0L)
    expect_identical(nrow(attributeSets(empty)), 0L)
})

test_that("a library written from an object built in R reads back", {
    ## Nothing was read from a file here, so this is the writer's behaviour on
    ## a hand built object.
    cv <- data.frame(group = c(NA_character_, "1"),
        accession = c("MS:1000511", "MS:1000045"),
        name = c("ms level", "collision energy"),
        value = c("2", "39.0"),
        value_accession = c(NA_character_, NA_character_),
        stringsAsFactors = FALSE)
    header <- data.frame(group = NA_character_,
        accession = "MS:1003186", name = "library format version",
        value = "1.0", value_accession = NA_character_,
        stringsAsFactors = FALSE)
    sp <- spectrum(id = 7L, cv = cv,
        peaks = data.frame(mz = c(103.0541, 110.0711),
            intensity = c(102.5, 1329.4)))
    lib <- mzspeclib(header = header, spectra = list(sp))
    expect_length(lib, 1L)
    out <- tempfile(fileext = ".mzSpecLib.txt")
    expect_silent(write_mzspeclib(lib, out))
    back <- read_mzspeclib(out)
    expect_identical(spectraIds(back), 7L)
    expect_identical(reset_rows(spectraCv(back, i = 1L, inherit = FALSE)[,
        c("group", "accession", "name", "value", "value_accession")]), cv)
    expect_identical(spectraPeaks(back, i = 1L)$mz, c(103.0541, 110.0711))
    expect_identical(libraryCv(back), header)
    ## The group designator came back, which is the thing the long tables keep
    ## and the wide ones do not.
    expect_identical(spectraCv(back, i = 1L)$group, c(NA, "1"))
    ## The same object as JSON.
    json <- tempfile(fileext = ".mzSpecLib.json")
    expect_silent(write_mzspeclib(lib, json))
    j <- read_mzspeclib(json)
    expect_identical(spectraIds(j), 7L)
    expect_identical(cvParameter(spectraCv(j, i = 1L, inherit = FALSE),
        "MS:1000045"), "39.0")
})
