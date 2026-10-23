## Helpers shared by the test files. Nothing in here is a test.

## A fixture below tests/testthat/files/. Every hand written or transcribed
## library used by the tests lives there.
fixture <- function(name)
    test_path("files", name)

## A fixture read as a library.
read_fixture <- function(name, ...)
    read_mzspeclib(fixture(name), ...)

## The example library the package ships. system.file() is resolved by
## pkgload while the package is loaded from its source directory; the second
## branch is only there so that the tests also work when the package is
## installed in a library.
example_path <- function() {
    res <- system.file("extdata", "example.mzSpecLib.txt",
        package = "mzspeclib")
    if (!nzchar(res))
        res <- test_path("../../inst/extdata/example.mzSpecLib.txt")
    normalizePath(res, mustWork = TRUE)
}

example_library <- function(...)
    read_mzspeclib(example_path(), ...)

## The repository of the HUPO-PSI mzSpecLib specification, which holds the
## example libraries the format was developed against. It is not part of this
## package, so every test that uses it has to skip when it is not there.
spec_repo <- function()
    path.expand("~/dev/mzSpecLib")

reference_path <- function(relative)
    file.path(spec_repo(), "examples", relative)

## A reference library, or a skip.
reference_library <- function(relative, ...) {
    skip_if_not(dir.exists(spec_repo()),
        "the mzSpecLib specification repository is not available")
    file <- reference_path(relative)
    skip_if_not(file.exists(file),
        paste("reference library is not there:", relative))
    read_mzspeclib(file, ...)
}

## The example libraries of the specification repository, by text and JSON
## serialization. The two JSON files are the JSON counterparts of two of the
## text files. The library of the NIST directory is a byte identical copy of
## the one of the NIST-CPTAC directory, so the same library is read from two
## paths here; spice.mzSpecLib.txt, the small example at the top level of the
## examples directory, is the one of them that has no peak annotation column at
## all. The .tsv and .msp files of the same directory are the legacy formats of
## the section "legacy-formats" of that repository and are not libraries.
reference_text_libraries <- c(
    "DIA-NN/phl004_canonical_sall_pv_plasma.head.diann.mzSpecLib.txt",
    "NIST-CPTAC/broad_tcga_nonphospho_consensus_rec.head.mzSpecLib.txt",
    "NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.txt",
    "NIST/broad_tcga_nonphospho_consensus_rec.head.mzSpecLib.txt",
    "SpectraST/fetal_brain_tiny.mzSpecLib.txt",
    "SpectraST/fetal_brain_tiny_consensus_td.mzSpecLib.txt",
    "Spectronaut/human_serum.head.spectronaut.mzSpecLib.txt",
    "spice.mzSpecLib.txt")

reference_json_libraries <- c(
    "NIST" = "NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.json",
    "SpectraST" = "SpectraST/fetal_brain_tiny.mzSpecLib.json")

## Which text library a reference JSON library is the same library as.
reference_counterpart <- c(
    "NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.json" =
        "NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.txt",
    "SpectraST/fetal_brain_tiny.mzSpecLib.json" =
        "SpectraST/fetal_brain_tiny.mzSpecLib.txt")

## What a raw scan of a text library counts in it, without this package: the
## number of library attribute lines, of section lines of every kind and of
## peak rows. The tests of the real libraries compare the accessors against
## this, so that a wrong count in a reader cannot be confirmed by the same
## reader alone. A section line is one spectrum, one analyte, one
## interpretation, one interpretation member or one cluster, whether or not
## the section states a CV parameter of its own.
raw_counts <- function(file) {
    lines <- readLines(gzfile_if(file), encoding = "UTF-8", warn = FALSE)
    lines <- sub("\r$", "", lines)
    content <- nzchar(trimws(lines)) & !startsWith(lines, "#")
    line <- if (any(content)) lines[content] else character()
    section <- grepl("^<[A-Za-z]+[^>]*>$", line)
    name <- ifelse(section, sub("^<([A-Za-z]+).*", "\\1", line),
        NA_character_)
    peaks <- !is.na(name) & name == "Peaks"
    ## A peak row is any content line between a <Peaks> line and the next
    ## section line of the same or an outer kind.
    owner <- rep(NA_character_, length(line))
    current <- NA_character_
    for (k in seq_along(line)) {
        if (section[[k]])
            current <- name[[k]]
        owner[[k]] <- current
    }
    peakRows <- !section & !is.na(owner) & owner == "Peaks"
    spectra <- which(!is.na(name) & name == "Spectrum")
    list(
        header = sum(!section & !is.na(owner) & owner == "mzSpecLib"),
        spectra = length(spectra),
        analytes = sum(!is.na(name) & name == "Analyte"),
        interpretations = sum(!is.na(name) & name == "Interpretation"),
        members = sum(!is.na(name) & name == "InterpretationMember"),
        clusters = sum(!is.na(name) & name == "Cluster"),
        peaks = sum(peakRows))
}

## The number of tab separated fields of the peak rows of every spectrum, as a
## raw scan of the file counts them, and 0 for a spectrum without peak rows.
## Section 4.1.16 lets a peak row have fewer columns than the spectrum defines,
## so the peak tables of one and the same library need not be of one width, and
## only the file says how wide the rows of a spectrum are.
raw_peak_widths <- function(file) {
    lines <- readLines(gzfile_if(file), encoding = "UTF-8", warn = FALSE)
    lines <- sub("\r$", "", lines)
    content <- nzchar(trimws(lines)) & !startsWith(lines, "#")
    line <- if (any(content)) lines[content] else character()
    section <- grepl("^<[A-Za-z]+[^>]*>$", line)
    name <- ifelse(section, sub("^<([A-Za-z]+).*", "\\1", line),
        NA_character_)
    width <- integer()
    spectrum <- NA_integer_
    inPeaks <- FALSE
    for (k in seq_along(line)) {
        if (section[[k]]) {
            inPeaks <- identical(name[[k]], "Peaks")
            if (identical(name[[k]], "Spectrum")) {
                spectrum <- length(width) + 1L
                width <- c(width, 0L)
            }
        }
        if (inPeaks && !is.na(spectrum))
            width[[spectrum]] <- max(width[[spectrum]],
                length(strsplit(line[[k]], "\t", fixed = TRUE)[[1L]]))
    }
    width
}

## A .gz text library is read through a connection, like the package does.
gzfile_if <- function(file)
    if (grepl("\\.gz$", file)) gzfile(file, "r") else file

## The identity of a spectrum is the <Spectrum=N> line in the text
## serialization and the MS:1003237|library spectrum key attribute in the JSON
## serialization, so a text -> JSON round trip legitimately adds that one
## attribute per spectrum. Dropping it is what makes the two comparable.
drop_spectrum_key <- function(cv) {
    res <- cv[cv[["accession"]] != "MS:1003237", , drop = FALSE]
    rownames(res) <- NULL
    attr(res, "cvName") <- NULL
    res
}

## Same for a table that only differs in its row names, which happens as soon
## as rows were dropped from one of two otherwise equal tables.
reset_rows <- function(x) {
    rownames(x) <- NULL
    attr(x, "cvName") <- NULL
    x
}

## The CV values of a table as values rather than as text. The JSON
## serialization writes a number as a number, so the document holds 39 where
## the text file holds 39.0; both mean the same value, and only the second
## spelling is the one a user of the text format chose. Everything that is not
## written as a number is left as it stands.
num_value <- function(x) {
    is_num <- grepl("^-?[0-9]+(\\.[0-9]*)?([eE][-+]?[0-9]+)?$", x)
    x[is_num] <- sprintf("%.15g", as.numeric(x[is_num]))
    x
}

## The peak lists of all spectra as a plain list, also when the library has
## only one spectrum (spectraPeaks() returns the data.frame itself then).
all_peaks <- function(object)
    lapply(seq_along(object), function(k) spectraPeaks(object, i = k))

## The number of distinct (type, set) pairs of an attribute set table. The
## same set name can be used by two kinds, <AttributeSet Spectrum=all> and
## <AttributeSet Analyte=all>, and those are two sets.
n_sets <- function(sets)
    nrow(unique(sets[, c("type", "set"), drop = FALSE]))

## One issue message matching a pattern, or a failure that names the issues
## the reader did produce.
expect_issue <- function(object, pattern) {
    hits <- grep(pattern, object$issues)
    expect_true(length(hits) > 0L, info = paste0("issues were: ",
        paste(object$issues, collapse = " | ")))
    invisible(hits)
}
