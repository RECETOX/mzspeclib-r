## The objects themselves: mzspeclib(), spectrum(), the subsetting operators
## and the two ways a library describes itself on the console.

test_that("mzspeclib() builds an empty library with every element in place", {
    lib <- mzspeclib()
    expect_s3_class(lib, "mzspeclib_library")
    expect_identical(names(lib), c("file", "header", "attributeSets",
        "clusters", "spectra", "issues"))
    expect_identical(dim(lib$header), c(0L, 5L))
    expect_identical(colnames(lib$header), c("group", "accession", "name",
        "value", "value_accession"))
    expect_identical(dim(lib$attributeSets), c(0L, 7L))
    expect_identical(colnames(lib$attributeSets), c("type", "set", "group",
        "accession", "name", "value", "value_accession"))
    expect_identical(lib$clusters, list())
    expect_identical(lib$spectra, list())
    expect_identical(lib$issues, character())
    expect_true(is.na(lib$file))
    expect_length(lib, 0L)
    ## An empty library is a library: every accessor works on it (see
    ## test-accessors-long.R for the tables, test-errors.R for the checks).
    expect_identical(spectraIds(lib), integer())
    expect_length(spectra(lib), 0L)
})

test_that("a CV table is coerced to the five columns, or refused", {
    ## A data.frame with the five columns is taken as it is, in that order.
    cv <- data.frame(value = "2", accession = "MS:1000511",
        group = NA_character_, name = "ms level",
        value_accession = NA_character_, stringsAsFactors = FALSE)
    expect_identical(colnames(mzspeclib(header = cv)$header),
        c("group", "accession", "name", "value", "value_accession"))
    expect_identical(mzspeclib(header = cv)$header$accession, "MS:1000511")
    ## A sixth column is not the reader's business and is left out; a missing
    ## one is named in the error.
    cv$extra <- "x"
    expect_identical(ncol(mzspeclib(header = cv)$header), 5L)
    cv$value <- NULL
    expect_error(mzspeclib(header = cv), "missing CV column\\(s\\): value")
    expect_error(mzspeclib(header = data.frame(a = 1)),
        "missing CV column\\(s\\): group, accession, name, value, ")
    expect_error(mzspeclib(header = "MS:1000511|ms level=2"),
        "controlled vocabulary parameters must be a data.frame")
    expect_error(mzspeclib(header = 1),
        "controlled vocabulary parameters must be a data.frame")
    ## NULL is the empty table, not an error.
    expect_identical(nrow(mzspeclib(header = NULL)$header), 0L)
    ## The same rules hold for the CV of a spectrum.
    expect_error(spectrum(cv = data.frame(a = 1)), "missing CV column\\(s\\)")
    expect_identical(dim(spectrum()$cv), c(0L, 5L))
})

test_that("spectrum() holds what a spectrum section holds", {
    sp <- spectrum()
    expect_s3_class(sp, "mzspeclib_spectrum")
    expect_identical(names(sp), c("id", "cv", "analytes", "interpretations",
        "peaks"))
    expect_true(is.na(sp$id))
    expect_identical(sp$analytes, list())
    expect_identical(sp$interpretations, list())
    expect_null(sp$peaks)
    ## The key is an integer: a number that is not one is truncated without a
    ## sound, and a negative or zero key is accepted because the format does
    ## not forbid it.
    expect_identical(spectrum(id = 7L)$id, 7L)
    expect_identical(spectrum(id = 7)$id, 7L)
    expect_identical(spectrum(id = "7")$id, 7L)
    expect_identical(spectrum(id = 1.7)$id, 1L)
    expect_identical(spectrum(id = -3L)$id, -3L)
    expect_identical(spectrum(id = 0L)$id, 0L)
    ## A peak table needs its two number columns; everything else is the
    ## caller's.
    expect_error(spectrum(peaks = data.frame(a = 1)),
        "'peaks' must have columns 'mz' and 'intensity'")
    pk <- data.frame(mz = c(103.0541, 110.0711), intensity = c(102.5, 1329.4))
    expect_identical(nrow(spectrum(peaks = pk)$peaks), 2L)
    ## A spectrum built here is a spectrum the accessors accept.
    lib <- mzspeclib(spectra = list(spectrum(id = 1L, peaks = pk)))
    expect_length(lib, 1L)
    expect_identical(spectraIds(lib), 1L)
    expect_identical(spectraPeaks(lib, i = 1L)$mz, pk$mz)
    ## Anything else in the list is refused.
    expect_error(mzspeclib(spectra = list(1)),
        "'spectra' must only contain objects created by 'spectrum\\(\\)'")
    expect_error(mzspeclib(spectra = "spectrum"), "'spectra' must be a list")
    ## NULL and an empty list are the empty library, which is also the default.
    expect_length(mzspeclib(spectra = NULL), 0L)
    expect_length(mzspeclib(spectra = list()), 0L)
    expect_length(mzspeclib(), 0L)
})

test_that("attribute sets, clusters, the file name and the issues are taken", {
    sets <- data.frame(type = "Spectrum", set = "all", group = NA_character_,
        accession = "MS:1000511", name = "ms level", value = "2",
        value_accession = NA_character_, stringsAsFactors = FALSE)
    lib <- mzspeclib(attributeSets = sets)
    expect_identical(nrow(attributeSets(lib)), 1L)
    expect_identical(attributeSets(lib)$set, "all")
    ## Columns the package does not know are dropped, so a merged table does
    ## not break the accessors.
    expect_identical(ncol(mzspeclib(attributeSets = cbind(sets,
        extra = "x"))$attributeSets), 7L)
    expect_error(mzspeclib(attributeSets = "all"),
        "'attributeSets' must be a data.frame")
    ## The file name is a single string, and NULL or nothing at all is the
    ## missing value.
    expect_identical(mzspeclib(file = "/tmp/x.mzSpecLib.txt")$file,
        "/tmp/x.mzSpecLib.txt")
    expect_true(is.na(mzspeclib(file = NULL)$file))
    expect_true(is.na(mzspeclib(file = character())$file))
    expect_identical(mzspeclib(file = c("a", "b"))$file, "a")
    ## Issues are text, whatever they come as.
    expect_identical(mzspeclib(issues = "one")$issues, "one")
    expect_identical(mzspeclib(issues = 1)$issues, "1")
    expect_length(mzspeclib(issues = NULL)$issues, 0L)
    ## Clusters are only accepted as cluster objects; the reader builds them.
    expect_error(mzspeclib(clusters = "x"), "'clusters'",
        fixed = FALSE)
})

test_that("a subset of the spectra is still a library", {
    lib <- example_library()
    sub <- lib[2:3]
    expect_s3_class(sub, "mzspeclib_library")
    expect_length(sub, 2L)
    expect_identical(spectraIds(sub), 2:3)
    ## The positions of the subset start at one again: 'i' is always a
    ## position in the object that is being read.
    expect_identical(unique(spectraCv(sub)$spectrum), c(1L, 2L))
    ## The library level belongs to the library, not to the spectra, so it is
    ## unchanged: header, attribute sets, clusters and issues.
    expect_identical(libraryCv(sub), libraryCv(lib))
    expect_identical(attributeSets(sub), attributeSets(lib))
    expect_identical(sub$file, lib$file)
    expect_identical(attr(sub, "comments"), attr(lib, "comments"))
    ## The other index kinds, and the two ways out of range read differently.
    expect_identical(spectraIds(lib[-1]), 2:3)
    expect_identical(spectraIds(lib[c(TRUE, FALSE, TRUE)]), c(1L, 3L))
    expect_length(lib[integer()], 0L)
    expect_s3_class(lib[[2L]], "mzspeclib_spectrum")
    expect_identical(lib[[2L]]$id, 2L)
    expect_error(lib[[5L]], "subscript out of bounds")
    expect_error(lib[5L], "'spectra' must only contain objects")
    ## A library of one spectrum still answers length() with 1.
    one <- read_fixture("crlf-bom.mzSpecLib.txt")
    expect_length(one[1L], 1L)
    expect_s3_class(one[1L], "mzspeclib_library")
})

test_that("format() says what the library is, in one line per fact", {
    lib <- example_library()
    txt <- format(lib)
    expect_type(txt, "character")
    expect_identical(txt[[1L]], "mzSpecLib library [example.mzSpecLib.txt]")
    expect_identical(txt[[2L]], "  name: fetal_brain_tiny_consensus_td")
    expect_identical(txt[[3L]], "  spectra: 3")
    expect_identical(txt[[4L]], "  clusters: 0")
    expect_identical(txt[[5L]], "  attribute sets: 3")
    expect_identical(txt[[6L]], "  library CV parameters: 15")
    expect_length(txt, 6L)
    ## The name line is the MS:1003188|library name of the header, and it is
    ## left out when the header does not have the term; the file name is left
    ## out when the library was not read from a file.
    expect_identical(format(mzspeclib()),
        c("mzSpecLib library", "  spectra: 0", "  clusters: 0",
            "  attribute sets: 0", "  library CV parameters: 0"))
    noName <- format(read_fixture("spec-4-1-5-cluster.mzSpecLib.txt"))
    expect_identical(noName[[1L]],
        "mzSpecLib library [spec-4-1-5-cluster.mzSpecLib.txt]")
    expect_false(any(grepl("name:", noName)))
    expect_identical(noName[[2L]], "  spectra: 2")
    expect_identical(noName[[3L]], "  clusters: 2")
    ## print() writes exactly those lines and hands the library back
    ## invisibly, as an S3 print method should.
    expect_identical(capture.output(print(lib)), txt)
    printed <- capture.output(visible <- withVisible(print(lib)))
    expect_false(visible$visible)
    expect_identical(visible$value, lib)
})

test_that("format() describes a spectrum by its four counts", {
    lib <- example_library()
    txt <- format(lib[[1L]])
    expect_identical(txt[[1L]], "spectrum 1")
    expect_identical(txt, c("spectrum 1", "  CV parameters: 15",
        "  analytes: 1", "  interpretations: 1", "  peaks: 150"))
    ## The counts are the local ones and the number of peak rows, which is
    ## what the accessors of the same spectrum report.
    expect_identical(as.integer(sub(".*: ", "", txt[-1L])),
        c(nrow(spectraCv(lib, i = 1L, inherit = FALSE)),
            length(lib[[1L]]$analytes), length(lib[[1L]]$interpretations),
            nrow(spectraPeaks(lib, i = 1L))))
    expect_identical(format(spectrum()), c("spectrum", "  CV parameters: 0",
        "  analytes: 0", "  interpretations: 0", "  peaks: 0"))
    expect_identical(capture.output(print(lib[[2L]])), format(lib[[2L]]))
    ## A chimeric spectrum reports its two analytes (section 4.1.7).
    chim <- read_fixture("spec-4-1-17-chimeric.mzSpecLib.txt")
    expect_identical(format(chim)[[1L]],
        "mzSpecLib library [spec-4-1-17-chimeric.mzSpecLib.txt]")
    expect_identical(format(chim[[1L]])[[2L]],
        paste0("  CV parameters: ",
            nrow(spectraCv(chim, i = 1L, inherit = FALSE))))
    expect_identical(format(chim[[1L]])[[3L]], "  analytes: 2")
    expect_identical(format(chim[[1L]])[[5L]], "  peaks: 76")
})

test_that("the number of attribute sets format() reports is the number of sets",
    {
    ## The fixture defines Spectrum/all, Spectrum/FIRST, Spectrum/SECOND,
    ## Spectrum/EMPTY_SET, Spectrum/LOCAL_VALUE and Analyte/all: six sets,
    ## because a set is its kind and its name together (section 4.1.4: four
    ## kinds, "the name 'all' is reserved" per kind).
    lib <- read_fixture("attribute-sets.mzSpecLib.txt")
    sets <- attributeSets(lib)
    expect_identical(nrow(sets), 12L)
    expect_identical(n_sets(sets), 6L)
    expect_identical(length(unique(sets$set)), 5L)
    ## The JSON library is the easy case: four sets, four names.
    json <- read_fixture("json-library.mzSpecLib.json")
    expect_identical(n_sets(attributeSets(json)), 4L)
    expect_identical(format(json)[[5L]], "  attribute sets: 4")
        expect_identical(format(lib)[[5L]], "  attribute sets: 6")
})
