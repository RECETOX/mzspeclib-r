## The long accessors: libraryCv(), spectraCv(), analyteCv(),
## interpretationCv(), interpretationMemberCv() and clusterCv(). One row per
## CV parameter, the group designator kept, nothing dropped.

## The five columns every CV table has, and the columns that identify the
## section a row came from.
cv_cols <- c("group", "accession", "name", "value", "value_accession")

## The identifying columns of every long table, in front of the CV columns.
## Each level names its own sections - a member row carries its interpretation
## as well as its own key - and the spectrum a row belongs to travels with it.
key_cols <- list(spectraCv = c("spectrum", "spectrum_key"),
    analyteCv = c("spectrum", "spectrum_key", "analyte", "analyte_key"),
    interpretationCv = c("spectrum", "spectrum_key", "interpretation",
        "interpretation_key"),
    interpretationMemberCv = c("spectrum", "spectrum_key", "interpretation",
        "interpretation_key", "member", "member_key"),
    clusterCv = c("cluster", "cluster_key"))

test_that("every long table has the same CV columns after its keys", {
    lib <- example_library()
    expect_identical(colnames(libraryCv(lib)), cv_cols)
    for (fun in names(key_cols))
        expect_identical(colnames(get(fun)(lib)),
            c(key_cols[[fun]], cv_cols, "inherited"), info = fun)
    ## An empty library returns the same columns, not NULL and not a shorter
    ## table.
    for (fun in names(key_cols))
        expect_identical(colnames(get(fun)(mzspeclib())),
            c(key_cols[[fun]], cv_cols, "inherited"), info = fun)
    expect_identical(colnames(libraryCv(mzspeclib())), cv_cols)
    expect_identical(nrow(spectraCv(mzspeclib())), 0L)
})

test_that("libraryCv() is the header of the file and nothing else", {
    lib <- example_library()
    expect_identical(libraryCv(lib), lib$header)
    expect_identical(nrow(libraryCv(lib)), 15L)
    ## The five CV columns only: no key column, no inherited column, because
    ## a library has nothing to inherit from.
    expect_false(any(c("spectrum", "inherited") %in% colnames(libraryCv(lib))))
    ## Nothing but text; the header of a file is text.
    expect_identical(unique(vapply(libraryCv(lib), function(x) class(x)[[1L]],
        character(1))), "character")
    ## The group designator of the creation software lines survived.
    expect_identical(unique(libraryCv(lib)$group), c(NA, "1"))
})

test_that("spectraCv() has one row per parameter, inherited rows first", {
    lib <- example_library()
    cv <- spectraCv(lib)
    expect_identical(nrow(cv), 100L)
    expect_identical(sum(cv$inherited), 42L)
    expect_identical(sort(unique(cv$spectrum)), seq_len(length(lib)))
    ## The rows of one spectrum: the set's rows first, the section's own last.
    one <- spectraCv(lib, i = 1L)
    expect_identical(nrow(one), 29L)
    expect_identical(one$inherited, c(rep(TRUE, 14L), rep(FALSE, 15L)))
    expect_identical(one$spectrum, rep(1L, 29L))
    expect_identical(one$spectrum_key, rep(1L, 29L))
    ## Without inheritance the same rows minus the inherited ones.
    local <- spectraCv(lib, i = 1L, inherit = FALSE)
    expect_identical(nrow(local), 15L)
    expect_false(any(local$inherited))
    expect_identical(local$accession, one$accession[!one$inherited])
    ## The whole table is the four spectra's own rows plus what they inherit.
    expect_identical(nrow(spectraCv(lib, inherit = FALSE)), 58L)
    ## A repeated attribute keeps its rows; nothing was collapsed on the way.
    expect_true(any(duplicated(cv[, c("spectrum", "accession")])))
})

test_that("the group designator survives into the long tables", {
    lib <- example_library()
    cv <- spectraCv(lib, i = 1L)
    ## The collision energy of the "all" set and its unit form one group.
    rows <- which(cv$accession %in% c("MS:1000045", "UO:0000000"))
    expect_length(rows, 2L)
    expect_identical(cv$group[rows], c("1", "1"))
    ## A group designator stays text, and most lines carry none at all.
    expect_type(cv$group, "character")
    expect_true(any(is.na(cv$group)))
    ## The whole library uses five groups: the creation software of the header
    ## and the four bracketed definitions of the spectra.
    expect_identical(sort(unique(spectraCv(lib)$group, na.last = NA)),
        as.character(1:5))
    expect_identical(sort(unique(libraryCv(lib)$group, na.last = NA)), "1")
    ## The wide view loses this, which is what cvLosses() is for.
    losses <- cvLosses(lib)
    expect_identical(losses$level, c("library", "spectrum", "analyte",
        "interpretation", "cluster"))
    expect_true(losses$grouped[[2L]] > 0L)
})

test_that("'i' is a position in the library, never a spectrum key", {
    ## The example of section 4.1.6 numbers its spectra 1, 234 and 235, which
    ## is exactly the case a reader must not confuse.
    lib <- read_fixture("spec-4-1-6-spectrum.mzSpecLib.txt")
    expect_identical(spectraIds(lib), c(1L, 234L, 235L))
    expect_identical(unique(spectraCv(lib, i = 2L)$spectrum_key), 234L)
    expect_identical(unique(spectraCv(lib, i = 2L)$spectrum), 2L)
    expect_identical(length(spectra(lib, i = 3L)), 1L)
    expect_identical(spectra(lib, i = 3L)[[1L]]$id, 235L)
    ## The order of the result is the order of 'i'.
    expect_identical(unique(spectraCv(lib, i = c(3L, 1L))$spectrum), c(3L, 1L))
    ## The same 'i' means the same thing for the nested sections: it selects
    ## spectra, not analytes.
    s10 <- read_fixture("spec-4-1-10-analytes.mzSpecLib.txt")
    expect_identical(unique(analyteCv(s10, i = 2L)$spectrum), 2L)
    expect_true(all(analyteCv(s10, i = 2L)$value %in%
        analyteCv(s10)$value))
    ## A logical vector is the positions it marks.
    expect_identical(spectraCv(lib, i = c(TRUE, FALSE, TRUE)),
        spectraCv(lib, i = c(1L, 3L)))
    ## Nothing selected is an empty table with all columns.
    expect_identical(nrow(spectraCv(lib, i = integer())), 0L)
    expect_identical(colnames(spectraCv(lib, i = integer())),
        colnames(spectraCv(lib)))
    ## A missing value selects nothing rather than the whole library or an
    ## error; a value out of range is an error.
    expect_identical(nrow(spectraCv(lib, i = NA)), 0L)
    expect_error(spectraCv(lib, i = 4L), "'i' contains out of range indices")
    expect_error(spectraCv(lib, i = 0L), "'i' contains out of range indices")
    expect_error(spectraCv(lib, i = -1L), "'i' contains out of range indices")
    expect_error(spectraCv(lib, i = c(1L, 4L)), "'i' contains out of range")
    ## Not a library is not a library.
    for (fun in c("libraryCv", "libraryTable", "spectraCv", "spectraTable",
            "analyteCv", "analyteTable", "interpretationCv", "clusterCv",
            "spectraPeaks", "peakColumns", "cvLosses", "attributeSets",
            "clusters", "spectra", "spectraIds"))
        expect_error(get(fun)(list()), "'object' must be a", info = fun)
})

test_that("analyte and interpretation tables hold what the sections held", {
    ## Section 4.1.10 of the specification has four spectra, nine analytes,
    ## nine interpretations and three interpretation members.
    lib <- read_fixture("spec-4-1-10-analytes.mzSpecLib.txt")
    expect_length(lib, 4L)
    expect_identical(nrow(analyteCv(lib)), 9L)
    expect_identical(nrow(interpretationCv(lib)), 9L)
    expect_identical(nrow(interpretationMemberCv(lib)), 3L)
    ## Only spectrum 3 of that example gives its members an intensity
    ## fraction, and it has three of them.
    expect_identical(unique(interpretationMemberCv(lib)$spectrum), 3L)
    expect_identical(interpretationMemberCv(lib)$accession,
        rep("MS:1003166", 3L))
    expect_identical(interpretationMemberCv(lib)$value,
        c("0.287", "0.423", "0.512"))
    ## A spectrum without an <Analyte> section simply contributes no rows.
    expect_identical(nrow(analyteCv(lib, i = 1L)), 1L)
    expect_setequal(unique(analyteCv(lib)$spectrum), c(1L, 2L, 3L, 4L))
    ## The example library's three spectra share their analyte terms with the
    ## library's "all" set, which is where the 50 - 37 inherited rows come
    ## from.
    ex <- example_library()
    expect_identical(nrow(analyteCv(ex)), 50L)
    expect_identical(nrow(analyteCv(ex, inherit = FALSE)), 37L)
    expect_identical(nrow(interpretationCv(ex)), 17L)
    expect_identical(nrow(interpretationMemberCv(ex)), 0L)
    ## An empty table is still a table.
    expect_identical(nrow(interpretationMemberCv(ex, i = 1L)), 0L)
    expect_identical(colnames(interpretationMemberCv(ex, i = 1L)),
        colnames(interpretationMemberCv(ex)))
})

test_that("the nested tables should say which analyte a row came from", {
    ## A chimeric spectrum (section 4.1.7) holds more than one analyte, so the
    ## position of a row inside the spectrum is not enough to say which analyte
    ## it came from. The wide analyteTable() has the analyte and analyte_key
    ## columns; the long table is supposed to have them as well (see the
    ## @return section of ?spectraCv: "an identifying column per level").
    lib <- read_fixture("spec-4-1-17-chimeric.mzSpecLib.txt")
    expect_length(lib$spectra[[1L]]$analytes, 2L)
    cv <- analyteCv(lib)
    expect_identical(nrow(cv), 4L)
    expect_identical(unique(cv$spectrum), 1L)
    tab <- analyteTable(lib)
    expect_identical(nrow(tab), 2L)
    expect_identical(tab$analyte, c(1L, 2L))
    expect_identical(tab$analyte_key, c(1L, 2L))
    ## The two analytes of the spectrum are named in the file, and the long
    ## table cannot say which of its rows belongs to which of them.
        expect_true(all(c("analyte", "analyte_key") %in% colnames(cv)))
    expect_identical(cv$analyte, c(1L, 1L, 2L, 2L))
    expect_identical(cv$analyte_key, c(1L, 1L, 2L, 2L))
})

test_that("clusterCv() keys the clusters by position and by key", {
    lib <- read_fixture("spec-4-1-5-cluster.mzSpecLib.txt")
    cv <- clusterCv(lib)
    expect_identical(nrow(cv), 11L)
    ## One row per parameter: nine parameters of the first cluster, two of the
    ## second, positions and keys side by side.
    expect_identical(cv$cluster, c(rep(1L, 9L), rep(2L, 2L)))
    expect_identical(cv$cluster_key, c(rep(1L, 9L), rep(2L, 2L)))
    expect_false(any(is.na(cv$cluster_key)))
    ## A cluster is not a spectrum: no spectrum columns here.
    expect_false(any(c("spectrum", "spectrum_key") %in% colnames(cv)))
    ## clusterTable() agrees with it, row for row.
    expect_identical(nrow(clusterTable(lib)), length(clusters(lib)))
    ## Nothing inherited, because the example defines no cluster attribute
    ## sets.
    expect_false(any(clusterCv(lib)$inherited))
    expect_identical(clusterCv(lib, inherit = FALSE), clusterCv(lib))
})

test_that("the long tables are what cvParameter() reads", {
    lib <- example_library()
    ## Every long table has the five CV columns, so one function reads them
    ## all; a table without them is refused.
    for (tab in list(libraryCv(lib), spectraCv(lib), analyteCv(lib),
            interpretationCv(lib)))
        expect_true(all(cv_cols %in% colnames(tab)))
    expect_identical(cvParameter(spectraCv(lib, i = 1L), "MS:1003061"),
        "FAC[Carbamidomethyl]HSASLTVR/3 (HCD)")
    expect_identical(cvParameter(analyteCv(lib, i = 1L), "MS:1003270"),
        "FAC[Carbamidomethyl]HSASLTVR/3")
    ## A table that has none of them yields nothing instead of failing, like
    ## an absent term (see ?cvParameter).
    expect_identical(cvParameter(data.frame(a = 1), "MS:1000511"),
        character())
})

test_that("spectra(), spectraIds() and length() describe the same list", {
    lib <- example_library()
    expect_length(spectra(lib), length(lib))
    expect_identical(spectraIds(lib), vapply(spectra(lib), function(x) x$id,
        integer(1)))
    expect_identical(spectraIds(lib), 1:3)
    expect_s3_class(spectra(lib)[[1L]], "mzspeclib_spectrum")
    expect_named(spectra(lib)[[1L]], c("id", "cv", "analytes",
        "interpretations", "peaks"))
    ## A library read from an empty file has no spectra and no ids.
    expect_identical(spectraIds(mzspeclib()), integer())
    expect_length(clusters(lib), 0L)
})

test_that("a spectrum section without a single CV line still has a table", {
    ## A <Spectrum=N> section MAY hold no CV parameter at all: the analytes,
    ## the interpretations and the peaks of a spectrum are sections of their
    ## own, and the fixture of section 4.1.12 has two spectra that state
    ## nothing, one of them only because the set it claims gives it everything.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1000511|ms level=2", "<Spectrum=2>",
        "MS:1003061|library spectrum name=two", "<Spectrum=3>"), file)
    lib <- read_mzspeclib(file)
    expect_length(lib, 3L)
    expect_identical(nrow(lib$spectra[[3L]]$cv), 0L)
    ## An empty library answers a CV accessor with the empty table, and a
    ## library with a spectrum that has no CV line of its own cannot answer
    ## with less than that.
    empty <- spectraCv(mzspeclib())
    expect_identical(dim(empty), c(0L, 8L))
    ## The spectrum without a line of its own contributes no rows to the long
    ## table - it states no parameter - but it is a spectrum, and the wide
    ## table gives it its row with NA in every term column.
    expect_identical(dim(suppressWarnings(spectraCv(lib, i = 3L,
        inherit = FALSE))), c(0L, 8L))
    long <- suppressWarnings(spectraCv(lib, inherit = FALSE))
    expect_identical(dim(long), c(2L, 8L))
    expect_identical(colnames(long), colnames(empty))
    expect_identical(long$spectrum, c(1L, 2L))
    ## Nothing to inherit here, so the two layers of the table are the same.
    expect_identical(suppressWarnings(spectraCv(lib)), long)
    expect_identical(dim(suppressWarnings(cvLosses(lib))), c(5L, 4L))
    expect_identical(suppressWarnings(cvLosses(lib))$rows,
        c(1L, 2L, 0L, 0L, 0L))
    wide <- suppressWarnings(spectraTable(lib))
    expect_identical(nrow(wide), 3L)
    expect_identical(wide$spectrum, 1:3)
    expect_true(all(is.na(wide[3L, setdiff(colnames(wide),
        c("spectrum", "spectrum_key"))])))
})
