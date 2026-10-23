## The wide tables: libraryTable(), spectraTable(), analyteTable(),
## interpretationTable() and clusterTable(), and the cvLosses() report about
## what they cannot express.

test_that("spectraTable() has one row per spectrum and one column per term", {
    lib <- example_library()
    tab <- spectraTable(lib)
    expect_s3_class(tab, "data.frame")
    expect_identical(dim(tab), c(3L, 36L))
    expect_identical(names(tab)[1:2], c("spectrum", "spectrum_key"))
    expect_identical(tab$spectrum, 1:3)
    expect_identical(tab$spectrum_key, 1:3)
    ## The key column is the <Spectrum=N> number, the position column is not
    ## the same thing when the file numbers differently.
    spec <- read_fixture("spec-4-1-6-spectrum.mzSpecLib.txt")
    wide <- spectraTable(spec)
    expect_identical(wide$spectrum, 1:3)
    expect_identical(wide$spectrum_key, c(1L, 234L, 235L))
    ## A term that is used in two groups is still ONE column, and both of its
    ## values are in it (see the @section of ?spectraTable).
    expect_identical(sum(names(tab) == "MS:1003275"), 1L)
    expect_identical(unique(tab[["MS:1003275"]]), "Status;BinaryFileOffset")
    ## The group designator is gone, which is exactly what cvLosses() counts.
    expect_false("group" %in% names(tab))
    ## Subsetting spectra keeps the positions of the selection.
    expect_identical(dim(spectraTable(lib, i = 2:3)), c(2L, 36L))
    expect_identical(spectraTable(lib, i = 2:3)$spectrum_key, 2:3)
})

test_that("the cvName attribute maps column names to term names", {
    lib <- example_library()
    tab <- spectraTable(lib)
    name <- attr(tab, "cvName")
    expect_length(name, ncol(tab) - 2L)
    expect_identical(name[["MS:1000511"]], "ms level")
    expect_identical(name[["MS:1000045"]], "collision energy")
    expect_identical(name[["UO:0000000"]], "unit")
    ## With useAccession = FALSE the map runs the other way, and the columns
    ## themselves carry the term names.
    byName <- spectraTable(lib, useAccession = FALSE)
    expect_identical(ncol(byName), ncol(tab))
    expect_false(any(grepl("^MS:", names(byName))))
    expect_true("ms level" %in% names(byName))
    expect_identical(attr(byName, "cvName")[["ms level"]], "MS:1000511")
    ## Every column of a table is in the map, and the map is what makes the
    ## two views of the same library reconcilable.
    expect_setequal(names(attr(byName, "cvName")), names(byName)[-c(1L, 2L)])
})

test_that("a term used twice in one section is joined, not dropped", {
    lib <- example_library()
    ## The header of spectrum 1 declares two other attribute names.
    expect_length(cvParameter(spectraCv(lib, i = 1L), "MS:1003275",
        all = TRUE), 2L)
    tab <- spectraTable(lib)
    expect_identical(tab[["MS:1003275"]][[1L]], "Status;BinaryFileOffset")
    ## A caller who wants the last instance, which is the one that would win
    ## as an inherited value, asks for collapse = NA.
    expect_identical(spectraTable(lib, columns = "MS:1003275",
        collapse = NA)[["MS:1003275"]][[1L]], "BinaryFileOffset")
    ## Any other separator is the caller's.
    expect_identical(spectraTable(lib, columns = "MS:1003275",
        collapse = " / ")[["MS:1003275"]][[1L]], "Status / BinaryFileOffset")
    ## The related spectrum keys of section 4.1.6 are three instances of one
    ## term in one spectrum, in the order of the file and with their groups.
    spec <- read_fixture("spec-4-1-6-spectrum.mzSpecLib.txt")
    expect_identical(spectraTable(spec, columns = "MS:1003259")[["MS:1003259"]][[1L]],
        "1234;567;1083")
    expect_identical(spectraTable(spec, columns = "MS:1003259",
        collapse = NA)[["MS:1003259"]][[1L]], "1083")
})

test_that("columns restricts a table, and an unknown term yields no rows", {
    lib <- example_library()
    expect_identical(names(spectraTable(lib, columns = c("MS:1000511",
        "MS:1000045"))), c("spectrum", "spectrum_key", "MS:1000511",
        "MS:1000045"))
    ## The order of the columns is the order of the library, not of 'columns'.
    expect_identical(names(spectraTable(lib, columns = c("MS:1000045",
        "MS:1000511"))), c("spectrum", "spectrum_key", "MS:1000511",
        "MS:1000045"))
    ## Columns are matched on the accession, or on the name when the table is
    ## named by names.
    expect_identical(names(spectraTable(lib, useAccession = FALSE,
        columns = c("ms level", "collision energy"))), c("spectrum",
        "spectrum_key", "ms level", "collision energy"))
    ## A term the library does not use: the identification columns remain, the
    ## rows stay (a wide table has one row per spectrum, whichever columns were
    ## asked for), and there is no error to trip a loop over many files.
    none <- spectraTable(lib, columns = "MS:9999999")
    expect_identical(dim(none), c(length(spectra(lib)), 2L))
    expect_identical(names(none), c("spectrum", "spectrum_key"))
    expect_identical(dim(spectraTable(lib, columns = character())),
        c(length(spectra(lib)), 2L))
    expect_identical(nrow(spectraTable(mzspeclib())), 0L)
    expect_identical(dim(libraryTable(mzspeclib())), c(0L, 0L))
    expect_identical(names(analyteTable(mzspeclib())), c("spectrum",
        "spectrum_key", "analyte", "analyte_key"))
    expect_identical(names(interpretationTable(mzspeclib())), c("spectrum",
        "spectrum_key", "interpretation", "interpretation_key"))
    expect_identical(names(clusterTable(mzspeclib())), c("cluster",
        "cluster_key"))
})

test_that("a term whose object is a term can be read three ways", {
    lib <- example_library()
    ## MS:1000043|intensity unit=MS:1000905|percent of base peak times 100
    expect_identical(spectraTable(lib, columns = "MS:1000043")[["MS:1000043"]][[1L]],
        "percent of base peak times 100")
    expect_identical(spectraTable(lib, columns = "MS:1000043",
        cvValue = "accession")[["MS:1000043"]][[1L]], "MS:1000905")
    expect_identical(spectraTable(lib, columns = "MS:1000043",
        cvValue = "compound")[["MS:1000043"]][[1L]],
        "MS:1000905|percent of base peak times 100")
    expect_error(spectraTable(lib, cvValue = "term"), "'arg' should be one")
    ## A free text value has no term, so "accession" gives the value itself
    ## and "compound" does not invent a separator.
    free <- spectraTable(lib, columns = "MS:1003061", cvValue = "accession")
    expect_identical(free[["MS:1003061"]][[1L]],
        "FAC[Carbamidomethyl]HSASLTVR/3 (HCD)")
    expect_identical(spectraTable(lib, columns = "MS:1003061",
        cvValue = "compound")[["MS:1003061"]],
        spectraTable(lib, columns = "MS:1003061")[["MS:1003061"]])
})

test_that("coerce = TRUE is a heuristic over the values, not the terms", {
    lib <- example_library()
    ## By default everything stays exactly as written.
    plain <- spectraTable(lib)
    expect_identical(unique(vapply(plain, function(x) class(x)[[1L]],
        character(1))), c("integer", "character"))
    expect_identical(plain[["spectrum_key"]], 1:3)
    expect_identical(plain[["MS:1000511"]], c("2", "2", "2"))
    expect_identical(plain[["MS:1000045"]], c("39.0", "39.0", "39.0"))
    ## Coercing looks at the text of the values only.
    gone <- spectraTable(lib, coerce = TRUE)
    expect_identical(gone[["MS:1000511"]], c(2L, 2L, 2L))
    expect_identical(gone[["MS:1000045"]], c(39, 39, 39))
    expect_identical(gone[["MS:1003061"]], plain[["MS:1003061"]])
    ## A term whose values are all TRUE/FALSE becomes logical, and one whose
    ## values are decimal becomes double.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1000511|ms level=2",
        "MS:1003061|spectrum name=one",
        "MS:1003320|spectrum cluster size=TRUE",
        "MS:1000045|collision energy=39.5"), file)
    one <- spectraTable(read_mzspeclib(file), coerce = TRUE)
    expect_identical(one[["MS:1003320"]], TRUE)
    expect_identical(one[["MS:1000045"]], 39.5)
    expect_identical(one[["MS:1000511"]], 2L)
    ## The heuristic cannot know that a version number is not a number: "1.0"
    ## of the header becomes 1. This is why the default is FALSE.
    header <- libraryTable(read_mzspeclib(file), columns = "MS:1003186")
    expect_identical(header[["MS:1003186"]], "1.0")
    expect_identical(libraryTable(read_mzspeclib(file),
        columns = "MS:1003186", coerce = TRUE)[["MS:1003186"]], 1)
})

test_that("libraryTable() is the header as one row", {
    lib <- example_library()
    tab <- libraryTable(lib)
    expect_identical(dim(tab), c(1L, 12L))
    ## Fifteen lines, twelve distinct accessions: the four creation log lines
    ## of one accession arrive as one joined cell.
    expect_identical(nrow(libraryCv(lib)), 15L)
    expect_identical(length(unique(libraryCv(lib)$accession)), 12L)
    logs <- cvParameter(libraryCv(lib), "MS:1003206", all = TRUE)
    expect_length(logs, 4L)
    expect_identical(tab[["MS:1003206"]], paste(logs, collapse = ";"))
    expect_identical(substr(tab[["MS:1003206"]], 1L, 14L), "COMPILE FROM /")
    expect_identical(tab[["MS:1003186"]], "1.0")
    expect_identical(names(libraryTable(lib, columns = "MS:1003188")),
        "MS:1003188")
    expect_identical(libraryTable(lib, useAccession = FALSE)[["library name"]],
        "fetal_brain_tiny_consensus_td")
})

test_that("the nested wide tables identify their rows", {
    ## This is what the long tables of the same sections do not do.
    lib <- read_fixture("spec-4-1-10-analytes.mzSpecLib.txt")
    an <- analyteTable(lib)
    expect_identical(names(an)[1:4], c("spectrum", "spectrum_key", "analyte",
        "analyte_key"))
    expect_identical(nrow(an), 8L)
    ## The analyte position restarts at one in every spectrum.
    expect_identical(an$analyte, c(1L, 1L, 2L, 3L, 1L, 2L, 3L, 1L))
    expect_identical(an$analyte_key, c(1L, 1L, 2L, 3L, 1L, 2L, 3L, 1L))
    expect_identical(an$spectrum, c(1L, rep(2L, 3L), rep(3L, 3L), 4L))
    it <- interpretationTable(lib)
    expect_identical(names(it)[1:4], c("spectrum", "spectrum_key",
        "interpretation", "interpretation_key"))
    expect_identical(nrow(it), 5L)
    expect_identical(it$interpretation_key, c(1L, 1L, 2L, 1L, 2L))
    ## A chimeric spectrum keeps its two analytes apart here.
    chim <- read_fixture("spec-4-1-17-chimeric.mzSpecLib.txt")
    tab <- analyteTable(chim)
    expect_identical(nrow(tab), 2L)
    expect_identical(tab$analyte_key, c(1L, 2L))
    expect_identical(tab[["MS:1003270"]], c("AILINFIDR/2",
        "HLAEISLLEQSFVK/3"))
    ## inherit = FALSE leaves the set's terms out of the table entirely.
    ex <- example_library()
    expect_true("MS:1000008" %in% names(spectraTable(ex)))
    expect_false("MS:1000008" %in% names(spectraTable(ex, inherit = FALSE)))
    expect_identical(nrow(spectraTable(ex)), 3L)
})

test_that("clusterTable() has one row per cluster", {
    lib <- read_fixture("spec-4-1-5-cluster.mzSpecLib.txt")
    tab <- clusterTable(lib)
    expect_identical(dim(tab), c(2L, 9L))
    expect_identical(tab$cluster, 1:2)
    expect_identical(tab$cluster_key, 1:2)
    expect_identical(tab[["MS:1003320"]], c("6", "2"))
    expect_identical(clusterTable(lib, useAccession = FALSE)[["spectrum cluster size"]],
        c("6", "2"))
    ## coerce is offered here too, and turns the cluster size into a number.
    expect_identical(clusterTable(lib, columns = "MS:1003320",
        coerce = TRUE)[["MS:1003320"]], c(6L, 2L))
})

test_that("cvLosses() counts what the wide tables cannot express", {
    lib <- example_library()
    res <- cvLosses(lib)
    expect_s3_class(res, "data.frame")
    expect_identical(res$level, c("library", "spectrum", "analyte",
        "interpretation", "cluster"))
    expect_identical(names(res), c("level", "grouped", "repeated", "rows"))
    ## The numbers are the ones the long tables show: the rows counted are the
    ## rows without inheritance.
    long <- list(libraryCv(lib), spectraCv(lib, inherit = FALSE),
        analyteCv(lib, inherit = FALSE), interpretationCv(lib,
            inherit = FALSE), clusterCv(lib, inherit = FALSE))
    expect_identical(res$rows, vapply(long, nrow, integer(1)))
    ## Grouped lines and repeated terms exist at four of the five levels.
    expect_identical(res$grouped, c(6L, 41L, 19L, 3L, 0L))
    expect_identical(res$repeated, c(3L, 10L, 0L, 0L, 0L))
    expect_identical(sum(res$rows), 127L)
    ## An empty library reports zeros, not an error and not an empty table.
    empty <- cvLosses(mzspeclib())
    expect_identical(empty$rows, integer(5))
    expect_identical(empty$grouped, integer(5))
    ## A library of nothing but text lines has no losses to report either.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0"),
        file)
    expect_identical(cvLosses(read_mzspeclib(file))$rows,
        c(1L, 0L, 0L, 0L, 0L))
})

test_that("cvLosses() must count repeats per analyte, not per spectrum", {
    ## The chimeric example of section 4.1.7 has one spectrum with two
    ## analytes, each carrying MS:1003270 and MS:1001117. Within one analyte
    ## nothing is repeated, so "repeated" has to be 0 - the two analytes are
    ## two contexts, and analyteTable() does not merge them either.
    lib <- read_fixture("spec-4-1-17-chimeric.mzSpecLib.txt")
    expect_identical(nrow(analyteTable(lib)), 2L)
        expect_identical(cvLosses(lib)$repeated[[3L]], 0L)
})
