## The arguments: what the functions refuse, what they say when they refuse, and
## the few places where they accept something they could have objected to.

test_that("the file argument is one name of a file that exists", {
    ## The name is checked before anything is read, and it is the name the
    ## library is given back (?read_mzspeclib).
    expect_identical(mzspeclib:::.check_file(example_path()), example_path())
    for (bad in list(NULL, character(), c("a", "b"), 1, list(), TRUE))
        expect_error(read_mzspeclib(bad),
            "'file' must be a single file name")
    for (bad in list(NULL, character(), c("a", "b")))
        expect_error(mzspeclib:::.check_file(bad),
            "'file' must be a single file name")
    ## A name without a file behind it is named in the error, as it was given.
    missing <- file.path(tempdir(), "there-is-no-such-library.mzSpecLib.txt")
    expect_false(file.exists(missing))
    expect_error(read_mzspeclib(missing), paste0("file does not exist: ",
        missing), fixed = TRUE)
    expect_error(read_mzspeclib("nope.mzSpecLib.txt"),
        "file does not exist: nope\\.mzSpecLib\\.txt")
    ## A directory is a name that exists, and the operating system is the one
    ## that says no: the error comes from file() and not from the package, so
    ## what can be relied on is only that nothing is read.
    dir <- file.path(tempdir(), "a-directory.mzSpecLib.txt")
    dir.create(dir, showWarnings = FALSE)
    expect_error(suppressWarnings(read_mzspeclib(dir)),
        "cannot open the connection")
    ## An empty file and a file of nothing but bytes R cannot decode are files:
    ## they are read as a library without anything in it, with the one thing
    ## that is missing named (?read_mzspeclib).
    empty <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(character(), empty)
    lib <- read_mzspeclib(empty)
    expect_length(lib, 0L)
    expect_identical(nrow(libraryCv(lib)), 0L)
    expect_issue(lib, "the file does not start with the required ")
    expect_true(any(grepl("no section line at all", lib$issues)))
    bin <- tempfile(fileext = ".mzSpecLib.txt")
    writeBin(as.raw(c(0L, 10L, 77L, 83L, 58L, 49L, 10L)), bin)
    expect_length(read_mzspeclib(bin), 0L)
})

test_that("the format argument is matched, not guessed at", {
    file <- example_path()
    ## The three choices, and the abbreviation of the first two.
    expect_length(read_mzspeclib(file, format = "auto"), 3L)
    expect_length(read_mzspeclib(file, format = "text"), 3L)
    expect_length(read_mzspeclib(file, format = "t"), 3L)
    ## The abbreviation reaches the JSON reader as well, which for a text file
    ## means: the text is parsed as JSON and nothing is found.
    expect_identical(read_mzspeclib(file, format = "j"),
        read_mzspeclib(file, format = "json"))
    expect_length(read_mzspeclib(file, format = "json"), 0L)
    ## Nothing is matched case insensitively or with NULL standing for a
    ## format of its own: NULL is the automatic choice.
    expect_error(read_mzspeclib(file, format = "TEXT"), "should be one of")
    expect_error(read_mzspeclib(file, format = "xml"), "should be one of")
    expect_error(read_mzspeclib(file, format = NA),
        "must be NULL or a character vector")
    expect_length(read_mzspeclib(file, format = NULL), 3L)
    ## The JSON reader is reachable through the argument even when the name of
    ## the file says otherwise (the opposite case, a text file named .json, is
    ## in test-write-round-trip.R).
    json <- tempfile(fileext = ".mzSpecLib.txt")
    suppressWarnings(write_mzspeclib(example_library(), json,
        format = "json"))
    expect_length(read_mzspeclib(json), 3L)
    expect_length(read_mzspeclib(json, format = "json"), 3L)
    expect_length(read_mzspeclib(json, format = "text"), 0L)
})

test_that("an object that is not a library is refused by every accessor", {
    ## The check is the same one for all of them, so one message says it all.
    lib <- example_library()
    for (fun in c("libraryCv", "libraryTable", "spectra", "spectraIds",
            "spectraCv", "analyteCv", "interpretationCv",
            "interpretationMemberCv", "clusterCv", "clusters", "attributeSets",
            "spectraTable", "analyteTable", "interpretationTable",
            "spectraPeaks", "peakColumns", "cvLosses"))
        expect_error(suppressWarnings(get(fun)("not a library")),
            "'object' must be a 'mzspeclib_library'", info = fun)
    expect_error(mzspeclib:::.check_library(spectrum()),
        "'object' must be a 'mzspeclib_library'")
    expect_error(mzspeclib:::.check_library(NULL),
        "'object' must be a 'mzspeclib_library'")
    ## An empty library is a library, and the check says so and hands back
    ## TRUE invisibly.
    expect_true(mzspeclib:::.check_library(mzspeclib()))
    expect_true(mzspeclib:::.check_library(lib))
    expect_error(write_mzspeclib("not a library",
        tempfile(fileext = ".mzSpecLib.txt")),
        "'object' must be a 'mzspeclib_library'")
    expect_error(write_mzspeclib(lib[[1L]], tempfile(fileext = ".txt")),
        "'object' must be a 'mzspeclib_library'")
    ## length(), format() and [] belong to the class as much as the accessors
    ## do, but they are methods and are not reached with a plain string.
    expect_error(length("x"), NA)
})

test_that("the spectrum selection is checked, and where it is not", {
    lib <- example_library()
    ## The CV accessors and the peak accessor share one normaliser: a position
    ## has to be inside the library, which is said once and in the same words.
    for (fun in c("spectraCv", "analyteCv", "interpretationCv",
            "interpretationMemberCv", "spectraPeaks"))
        for (i in list(0L, 99L, -1L, NA_integer_, "a", c(1L, NA), c(1L, 99L)))
            expect_error(suppressWarnings(get(fun)(lib, i = i)),
                "'i' contains out of range indices", info = fun)
    ## What is accepted: a logical vector, a real number that is truncated, and
    ## an empty selection, which is the empty table and not an error.
    expect_identical(nrow(spectraCv(lib, i = character())), 0L)
    expect_identical(nrow(spectraCv(lib, i = logical())), 0L)
    ## A single TRUE is the first spectrum and not "all": the normaliser asks
    ## which() and never recycles the vector to the length of the library.
    expect_identical(spectraCv(lib, i = TRUE), spectraCv(lib, i = 1L))
    expect_identical(spectraCv(lib, i = c(TRUE, FALSE, TRUE)),
        spectraCv(lib, i = c(1L, 3L)))
    expect_identical(spectraCv(lib, i = 1.7), spectraCv(lib, i = 1L))
    ## spectra() is the one accessor that indexes the list itself, so a
    ## position outside the library is not an error there but a NULL element -
    ## in contrast to every accessor above and to the documented return value,
    ## "a list of spectrum() objects". It is recorded as it is because the
    ## difference is only visible to a caller who does not look.
    expect_length(spectra(lib, i = 99L), 1L)
    expect_null(spectra(lib, i = 99L)[[1L]])
    expect_length(spectra(lib, i = "a"), 1L)
    expect_length(spectra(lib, i = character()), 0L)
    expect_length(spectra(lib, i = c(1L, 99L)), 2L)
    ## clusterCv() is the one CV accessor without an 'i' at all: it always
    ## reports every cluster of the library. It is worth saying here because
    ## the shared help page ?spectraCv documents an 'i' for the family, so an
    ## 'i' given to clusterCv() is not an error but R's partial matching of the
    ## one argument it does have, 'inherit' - which is why the two calls below
    ## both report all eleven rows of the fixture.
    clus <- read_fixture("spec-4-1-5-cluster.mzSpecLib.txt")
    expect_identical(nrow(clusterCv(clus)), 11L)
    expect_identical(clusterCv(clus, i = 1L), clusterCv(clus))
    expect_identical(unique(clusterCv(clus, i = 1L)$cluster), 1:2)
    ## The second argument is inherit, whatever it is called by the caller.
    expect_identical(clusterCv(clus, FALSE), clusterCv(clus, inherit = FALSE))
    expect_error(clusterCv(clus, i = NULL), "invalid argument type")
})

test_that("the writing arguments are checked before a file is touched", {
    lib <- example_library()
    out <- tempfile(fileext = ".mzSpecLib.txt")
    ## The same file check as for reading, and before anything is opened.
    expect_error(write_mzspeclib(lib, NULL),
        "'file' must be a single file name")
    expect_error(write_mzspeclib(lib, character()),
        "'file' must be a single file name")
    expect_false(file.exists(out))
    ## A name in a directory that does not exist is not created on the way, and
    ## the error is again the one file() gives.
    expect_error(suppressWarnings(write_mzspeclib(lib,
        file.path(tempdir(), "no-such-directory", "lib.mzSpecLib.txt"))),
        "cannot open the connection")
    ## The format argument is the same match.arg() call, and a file that is
    ## refused is not left behind half written.
    expect_error(write_mzspeclib(lib, out, format = "yaml"),
        "should be one of")
    expect_false(file.exists(out))
    ## digits goes to formatC(), so it complains with formatC()'s own words.
    expect_error(write_mzspeclib(lib, out, digits = 0),
        "invalid value 0 for 'digits'")
    expect_error(write_mzspeclib(lib, out, digits = -1),
        "invalid value -1 for 'digits'")
    ## What is accepted without objection: a character count, more than one
    ## count, and NULL, which leaves the numbers to R.
    expect_identical(write_mzspeclib(lib, out, digits = "3"), out)
    expect_identical(write_mzspeclib(lib, out, digits = c(3, 4)), out)
    expect_identical(write_mzspeclib(lib, out, digits = NULL), out)
    ## A count that is not a number is NA by the time it is looked at, and NA
    ## reaches formatC() as its most negative integer, which is what the
    ## message then says.
    expect_error(suppressWarnings(write_mzspeclib(lib, out, digits = "x")),
        "invalid value -2147483648 for 'digits'")
    ## A file that exists is overwritten, whatever it holds.
    writeLines("somebody else's content", out)
    expect_identical(write_mzspeclib(lib, out), out)
    expect_identical(readLines(out, n = 1L), "<mzSpecLib>")
})

test_that("the two logical arguments are logicals", {
    lib <- example_library()
    ## strict is used in a condition, so a string is refused there and not
    ## where it is given; NA and a number are the two values R lets through.
    expect_error(read_mzspeclib(example_path(), strict = "x"),
        "invalid 'x' type in 'x && y'")
    expect_length(read_mzspeclib(example_path(), strict = NA), 3L)
    expect_length(read_mzspeclib(example_path(), strict = 1), 3L)
    ## inherit of the CV accessors is used in an if() as well.
    expect_error(analyteCv(lib, i = 1L, inherit = "x"),
        "invalid argument type")
    expect_error(spectraCv(lib, inherit = NA))
    ## encoding goes to file(), which knows its own names.
    expect_error(read_mzspeclib(example_path(), encoding = NULL),
        "invalid 'encoding' value")
    ## A name the connection layer does not know is refused, but a name it
    ## accepts is trusted without a sound, even when the file is plain UTF-8
    ## and the claim is wrong: the reader does not verify what it decoded. A
    ## made up name is not checked at all here, either.
    expect_length(read_mzspeclib(example_path(), encoding = "ISO-8859-1"), 3L)
    expect_length(read_mzspeclib(example_path(), encoding = "not-an-encoding"),
        3L)
})

test_that("cvParameter wants an accession and two logicals", {
    lib <- example_library()
    cv <- spectraCv(lib, i = 1L)
    expect_identical(cvParameter(cv, "MS:1000511"), "2")
    ## The term is looked for by its accession, and by nothing else: a term name
    ## finds no row, and the accession argument has to be exactly one string.
    expect_identical(cvParameter(cv, "ms level"), character())
    expect_error(cvParameter(cv), "argument \"accession\" is missing")
    expect_error(cvParameter(cv, 1), "'accession' must be a single string")
    expect_error(cvParameter(cv, c("MS:1000511", "MS:1000045")),
        "'accession' must be a single string")
    expect_error(cvParameter(cv, "MS:1000511", value = NA),
        "missing value where TRUE/FALSE needed")
    expect_error(cvParameter(cv, "MS:1000511", value = "x"),
        "argument is not interpretable as logical")
    ## A table that is not a CV table is not the caller's fault to find out.
    expect_error(cvParameter("MS:1000511|ms level=2", "MS:1000511"),
        "invalid argument type")
    ## Nothing matched is length zero text, with 'all' as with without it.
    expect_length(cvParameter(cv, "MS:1000512"), 0L)
    expect_length(cvParameter(cv, "MS:1000512", all = TRUE), 0L)
    expect_error(cvParameter(cv, "MS:1000511", all = "x"),
        "invalid argument type")
    ## A repeatable term: without 'all' the last instance wins, which is the
    ## instance the text serialization puts last and the precedence rules of
    ## section 4.1.4 give to the local definition; with 'all' every instance
    ## comes back in the order of the table.
    repeatable <- "MS:1003275"
    n <- sum(cv[["accession"]] == repeatable)
    expect_true(n > 1L)
    expect_length(cvParameter(cv, repeatable, all = TRUE), n)
    expect_identical(cvParameter(cv, repeatable),
        cvParameter(cv, repeatable, all = TRUE)[[n]])
    ## value = FALSE asks for the accession of the value instead of the value,
    ## which is NA for a term whose value is free text.
    expect_identical(cvParameter(cv, "MS:1000511", value = FALSE), NA_character_)
    withAccession <- which(!is.na(cv[["value_accession"]]))[[1L]]
    expect_identical(cvParameter(cv, cv[["accession"]][withAccession],
        value = FALSE), cv[["value_accession"]][withAccession])
    ## An empty table is answered with length zero text before the accession is
    ## even looked at.
    expect_identical(cvParameter(spectraCv(mzspeclib()), "MS:1000511"),
        character())
    expect_error(cvParameter(spectraCv(mzspeclib()), 1), NA)
})
