## Peak rows: the tab separated tables of section 4.1.13 to 4.1.16, the only
## part of a library whose values become numbers.

## The fixture of section 4.1.16, four spectra with the same three peak
## attribute declarations and four different peak tables.
peak_fixture <- function()
    read_fixture("spec-4-1-16-peak-attributes.mzSpecLib.txt")

test_that("a peak row is m/z, intensity, annotation, then the attributes", {
    lib <- peak_fixture()
    pk <- spectraPeaks(lib, i = 1L)
    expect_s3_class(pk, "data.frame")
    expect_identical(names(pk), c("mz", "intensity", "annotation",
        "MS:1003279", "MS:1003285", "MS:1003286"))
    expect_identical(nrow(pk), 2L)
    ## Only these two columns are numbers, and they are doubles.
    expect_type(pk$mz, "double")
    expect_type(pk$intensity, "double")
    expect_identical(pk$mz, c(110.0405, 110.3405))
    expect_identical(pk$intensity, c(12342, 12342))
    ## Everything else is text, exactly as the row wrote it.
    expect_type(pk$annotation, "character")
    expect_identical(pk$annotation, c("IH", "?"))
    expect_identical(pk[["MS:1003279"]], c("10", "3"))
    expect_identical(pk[["MS:1003285"]], c("52.34", "522.34"))
    ## The column number in the file is the column number in the table.
    expect_identical(peakColumns(lib)$column, rep(4:6, 4L))
})

test_that("a peak table is per spectrum, not per library", {
    lib <- peak_fixture()
    ## Spectrum 2 of the section declares the same three attributes but writes
    ## three column rows, so its table has three columns.
    two <- spectraPeaks(lib, i = 2L)
    expect_identical(names(two), c("mz", "intensity", "annotation"))
    expect_identical(nrow(two), 2L)
    ## The declaration of an attribute does not invent a column.
    expect_identical(nrow(peakColumns(lib, i = 2L)), 3L)
    ## Spectrum 3 has the columns but no annotation.
    three <- spectraPeaks(lib, i = 3L)
    expect_identical(names(three), names(spectraPeaks(lib, i = 1L)))
    expect_identical(three$annotation, rep(NA_character_, 2L))
    expect_identical(three$mz, c(110.0405, 110.3405))
    ## Spectrum 4 has holes in the attribute columns.
    four <- spectraPeaks(lib, i = 4L)
    expect_identical(four[["MS:1003285"]], c(NA_character_, "522.34"))
    expect_identical(four[["MS:1003279"]], c("10", NA_character_))
    expect_identical(four$annotation, c("IH", "?"))
})

test_that("peak attribute columns are named by the declaration, or not", {
    lib <- peak_fixture()
    cols <- peakColumns(lib)
    expect_identical(colnames(cols), c("spectrum", "column", "accession",
        "name"))
    expect_identical(nrow(cols), 12L)
    expect_identical(unique(cols$accession), c("MS:1003279", "MS:1003285",
        "MS:1003286"))
    expect_identical(cols$column, rep(4:6, 4L))
    expect_identical(cols$name[[1L]], "observation frequency of peak")
    ## The generic names of the reader are available for a caller who wants
    ## the file's columns and nothing else.
    raw <- spectraPeaks(lib, i = 1L, peakColumns = FALSE)
    expect_identical(names(raw), c("mz", "intensity", "annotation", "X4",
        "X5", "X6"))
    expect_identical(unname(raw[3:6]),
        unname(spectraPeaks(lib, i = 1L)[3:6]))
    ## A library without any declaration gives an empty table with the four
    ## columns, and no error.
    none <- peakColumns(mzspeclib())
    expect_identical(dim(none), c(0L, 4L))
    ragged <- read_fixture("peaks-ragged.mzSpecLib.txt")
    expect_identical(dim(peakColumns(ragged, i = c(1L, 4L))), c(0L, 4L))
    ## Only the spectra that declare something contribute rows.
    expect_identical(peakColumns(ragged)$spectrum, c(3L, 3L, 5L))
    expect_identical(peakColumns(ragged)$column, c(4L, 5L, 4L))
})

test_that("a declaration applies to the column by its order, groups first", {
    ## The group designator of a "MS:1003254|peak attribute" line is what
    ## orders the declarations; a declaration without one sorts last.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1000511|ms level=2",
        "MS:1003254|peak attribute=MS:1003279|observation frequency of peak",
        "[2]MS:1003254|peak attribute=MS:1003285|standard deviation of m/z values of peak among replicates",
        "<Peaks>", "100.0\t1\t?\t0.6\t1.2"), file)
    lib <- read_mzspeclib(file)
    cols <- peakColumns(lib)
    expect_identical(cols$accession, c("MS:1003285", "MS:1003279"))
    expect_identical(cols$column, 4:5)
    ## Which is to say: the column that the file wrote first is named after
    ## the grouped declaration. A file that mixes grouped and ungrouped
    ## declarations therefore has to be read with peakColumns = FALSE to see
    ## the file's own order.
    pk <- spectraPeaks(lib, i = 1L)
    expect_identical(names(pk), c("mz", "intensity", "annotation",
        "MS:1003285", "MS:1003279"))
    expect_identical(pk$`MS:1003285`, "0.6")
    ## The declarations a spectrum inherits from an attribute set count as
    ## well; that is how the example library's first two spectra, whose rows
    ## have three columns only, still report three declared attributes.
    ex <- example_library()
    expect_identical(unique(peakColumns(ex)$spectrum), 1:3)
    expect_identical(nrow(peakColumns(ex, i = 1L)), 3L)
    expect_identical(ncol(spectraPeaks(ex, i = 1L)), 3L)
})

test_that("rows of different widths are padded, not dropped", {
    lib <- read_fixture("peaks-ragged.mzSpecLib.txt")
    ## Spectrum 3 writes 5, 2 and 5 fields.
    pk <- spectraPeaks(lib, i = 3L)
    expect_identical(names(pk), c("mz", "intensity", "annotation",
        "MS:1003279", "MS:1003285"))
    expect_identical(nrow(pk), 3L)
    expect_identical(pk$mz, c(110.0405, 110.3405, 110.5405))
    expect_identical(pk$annotation, c("IH", NA, "?"))
    expect_identical(pk[["MS:1003279"]], c("10", NA, "3"))
    expect_identical(pk[["MS:1003285"]], c("52.34", NA, "22.43"))
    ## An empty field is a missing value, and so is a field that is not there.
    five <- spectraPeaks(lib, i = 5L)
    expect_identical(five$annotation, c(NA_character_, "?"))
    expect_identical(five[["MS:1003279"]], c("10", NA_character_))
    expect_identical(ncol(five), 4L)
})

test_that("a value that is not a number becomes NA and is reported", {
    lib <- read_fixture("peaks-ragged.mzSpecLib.txt")
    expect_length(lib$issues, 2L)
    expect_issue(lib, "spectrum 2: 2 peak row\\(s\\) with a non-numeric ")
    expect_issue(lib, "notANumber<TAB>12342<TAB>")
    ## The rows are kept, with NA where the number should have been.
    pk <- spectraPeaks(lib, i = 2L)
    expect_identical(nrow(pk), 3L)
    expect_identical(pk$mz, c(110.0405, NA, 110.3405))
    expect_identical(pk$intensity, c(12342, 12342, NA))
    ## The other spectra of the same file are unaffected, and one bad row does
    ## not make the reader complain about them.
    expect_length(lib$issues, 2L)
    expect_false(any(grepl("spectrum 3|spectrum 5", lib$issues)))
    ## Not every number a computer accepts is a peak: NaN is reported because
    ## it is missing, but an overflow to Inf passes as a number.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1000511|ms level=2", "<Peaks>",
        "1.100405e2\t1.5e3\ta1", "NaN\t5\tx", "Inf\t6\ty",
        "106.0\t1e999\tq", "1,000\t8\tw", "  105.0  \t9\tv"), file)
    odd <- read_mzspeclib(file)
    expect_issue(odd, "2 peak row\\(s\\) with a non-numeric m/z or intensity")
    pk <- spectraPeaks(odd, i = 1L)
    expect_identical(pk$mz[[1L]], 110.0405)
    expect_identical(pk$intensity[[1L]], 1500)
    expect_true(is.na(pk$mz[[2L]]))
    expect_identical(pk$mz[[3L]], Inf)
    expect_identical(pk$intensity[[4L]], Inf)
    expect_true(is.na(pk$mz[[5L]]))
    expect_identical(pk$intensity[[5L]], 8)
    ## Spaces around a number are not part of the number, spaces inside an
    ## annotation are part of the annotation.
    expect_identical(pk$mz[[6L]], 105)
    expect_identical(pk$annotation[[1L]], "a1")
})

test_that("a peak table the format cannot express is dropped, and said so", {
    lib <- read_fixture("peaks-ragged.mzSpecLib.txt")
    ## Spectrum 1 has one field per row: fewer than the two the format needs.
    expect_issue(lib, "<Peaks> of spectrum 1 has rows with fewer than 2 ")
    expect_issue(lib, "the peak table was dropped")
    expect_null(lib$spectra[[1L]]$peaks)
    ## The caller still gets a table, with the two columns and no rows.
    pk <- spectraPeaks(lib, i = 1L)
    expect_identical(names(pk), c("mz", "intensity"))
    expect_identical(nrow(pk), 0L)
    ## An empty <Peaks> section and a spectrum without one look the same.
    expect_null(lib$spectra[[4L]]$peaks)
    expect_null(lib$spectra[[6L]]$peaks)
    expect_identical(spectraPeaks(lib, i = 4L), spectraPeaks(lib, i = 6L))
    expect_length(lib$issues, 2L)
})

test_that("an annotation is text, spaces included, and empty is missing", {
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1000511|ms level=2", "<Peaks>",
        "100.0\t1\t b2/0.01", "101.0\t1\t", "102.0\t1\t?"), file)
    lib <- read_mzspeclib(file)
    pk <- spectraPeaks(lib, i = 1L)
    expect_identical(pk$annotation[[1L]], " b2/0.01")
    expect_identical(pk$annotation[[2L]], NA_character_)
    expect_identical(pk$annotation[[3L]], "?")
    ## A third column that is there is a column even when nothing is in it.
    expect_identical(ncol(pk), 3L)
    ## A trailing tab makes a fourth column of nothing at all: the row has
    ## four fields, the fourth one empty, so the table needs four columns.
    trail <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1000511|ms level=2", "<Peaks>",
        "100.0\t1\ta1\t", "101.0\t2\tb1\t"), trail)
    lines <- readLines(trail)
    expect_true(all(grepl("\t$", lines[6:7])))
    tp <- spectraPeaks(read_mzspeclib(trail), i = 1L)
        expect_identical(ncol(tp), 4L)
    expect_identical(names(tp)[[4L]], "X4")
    expect_identical(tp$X4, rep(NA_character_, 2L))
})

test_that("spectraPeaks() returns one table or a list of them", {
    ex <- example_library()
    ## More than one spectrum: a list, one data.frame per spectrum, in order.
    many <- spectraPeaks(ex)
    expect_false(is.data.frame(many))
    expect_length(many, length(ex))
    expect_identical(vapply(many, nrow, integer(1)), c(150L, 150L, 92L))
    expect_identical(lapply(seq_along(ex), function(k)
        spectraPeaks(ex, i = k)), many)
    ## Exactly one spectrum: the table itself, not a list of one.
    one <- read_fixture("crlf-bom.mzSpecLib.txt")
    expect_true(is.data.frame(spectraPeaks(one)))
    expect_identical(nrow(spectraPeaks(one)), 2L)
    ## The same rule for an explicit selection of one.
    expect_true(is.data.frame(spectraPeaks(ex, i = 1L)))
    expect_false(is.data.frame(spectraPeaks(ex, i = 1:2)))
    ## An empty library has nothing to list.
    expect_length(spectraPeaks(mzspeclib()), 0L)
    ## A library read without any spectra at all.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0"),
        file)
    expect_length(spectraPeaks(read_mzspeclib(file)), 0L)
})

test_that("the peak list of a real spectrum keeps its rows and its order", {
    ## The chimeric example of section 4.1.17: 76 rows of three columns,
    ## in the order of the file, with the annotation of the specification.
    lib <- read_fixture("spec-4-1-17-chimeric.mzSpecLib.txt")
    pk <- spectraPeaks(lib, i = 1L)
    expect_identical(nrow(pk), 76L)
    expect_identical(names(pk), c("mz", "intensity", "annotation"))
    expect_identical(pk$mz[[1L]], 84.0446)
    expect_identical(pk$intensity[[1L]], 11605.7)
    expect_identical(pk$annotation[[1L]], "IQ-NH3/2.5ppm")
    ## The m/z column of a real peak list is strictly ordered in the file, and
    ## the reader does not sort or otherwise move rows.
    expect_identical(pk$mz, sort(pk$mz))
    expect_false(any(is.na(pk$mz)))
    expect_false(any(is.na(pk$intensity)))
    ## The example library's consensus spectrum carries the three attribute
    ## columns its header declares.
    ex <- example_library()
    three <- spectraPeaks(ex, i = 3L)
    expect_identical(ncol(three), 6L)
    expect_identical(three[["MS:1003279"]][[1L]], "0.600")
    expect_identical(three[["MS:1003285"]][[1L]], "0.0000")
    ## The first two spectra of the same file have three columns only.
    expect_identical(ncol(spectraPeaks(ex, i = 1L)), 3L)
})
