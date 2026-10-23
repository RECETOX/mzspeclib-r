## The libraries the specification repository holds: the six text examples of
## as many producers and the two JSON files, which are the JSON serializations
## of two of the text ones. Every test here skips when the repository is not
## there (helper-mzspeclib.R), because these files are not part of this package.
##
## What makes these libraries worth a test of their own is that they were
## written by other people's software: a count the reader agrees with itself
## about proves nothing, so the counts are compared against raw_counts(), which
## scans the file's lines without this package.

## The counts of a library as the accessors see them.
read_reference <- function(relative)
    suppressWarnings(reference_library(relative))

test_that("a real library is read whole, as a scan of its lines counts it", {
    for (relative in reference_text_libraries) {
        lib <- reference_library(relative)
        raw <- raw_counts(reference_path(relative))
        ## One spectrum per <Spectrum=N> line, with a key of its own.
        expect_length(lib, raw$spectra)
        expect_length(spectraIds(lib), raw$spectra)
        expect_identical(length(unique(spectraIds(lib))), raw$spectra)
        expect_false(any(is.na(spectraIds(lib))))
        ## The attribute lines of the header, which are the lines before the
        ## first section line of another kind.
        expect_identical(nrow(libraryCv(lib)), raw$header)
        ## One row of the wide table per analyte, interpretation and cluster
        ## section, whether or not the section states a parameter.
        expect_identical(nrow(analyteTable(lib)), raw$analytes)
        expect_identical(nrow(interpretationTable(lib)), raw$interpretations)
        expect_length(clusters(lib), raw$clusters)
        ## Every peak row of the file is a row of a peak table, and no row is
        ## counted twice or lost between the spectra.
        peaks <- vapply(seq_along(lib), function(k)
            nrow(spectraPeaks(lib, i = k)), integer(1))
        expect_identical(sum(peaks), raw$peaks)
        expect_identical(length(peaks), raw$spectra)
        ## A library of the format is a library of the format: the version
        ## term is there and says 1.0, and the reader had nothing to say.
        expect_identical(cvParameter(libraryCv(lib), "MS:1003186"), "1.0")
        expect_length(lib$issues, 0L)
    }
})

test_that("a real library says nothing it would have to explain", {
    for (relative in reference_text_libraries) {
        lib <- reference_library(relative)
        ## Nothing is inherited that was not claimed, so no accessor of a real
        ## library has a reason to warn (?attributeSets).
        for (fun in c("libraryCv", "libraryTable", "spectra", "spectraIds",
                "spectraCv", "analyteCv", "interpretationCv",
                "interpretationMemberCv", "clusterCv", "clusters",
                "attributeSets", "spectraTable", "analyteTable",
                "interpretationTable", "spectraPeaks", "peakColumns",
                "cvLosses")) {
            seen <- character()
            suppressWarnings(withCallingHandlers(get(fun)(lib),
                warning = function(w) {
                    seen <<- c(seen, conditionMessage(w))
                    invokeRestart("muffleWarning")
                }))
            expect_length(seen, 0L)
        }
        ## Reading a library a second time changes nothing about it.
        again <- reference_library(relative)
        expect_identical(lib$issues, again$issues)
        expect_identical(libraryCv(lib), libraryCv(again))
    }
})

test_that("the attribute sets of a real library are of the four kinds", {
    for (relative in reference_text_libraries) {
        lib <- reference_library(relative)
        sets <- attributeSets(lib)
        expect_identical(colnames(sets), c("type", "set", "group",
            "accession", "name", "value", "value_accession"))
        ## Section 4.1.4: Spectrum, Analyte, Interpretation and Cluster are the
        ## kinds a set may have, and a real library uses the first three.
        expect_true(all(sets$type %in% c("Spectrum", "Analyte",
            "Interpretation", "Cluster")))
        expect_true("Spectrum" %in% sets$type)
        ## A set is its kind and its name together, and the "all" set a library
        ## gives to every spectrum is there. A library may hold nothing else:
        ## the spice example defines exactly one set, its Spectrum/all.
        expect_gte(n_sets(sets), 1L)
        expect_true("all" %in% sets$set)
        expect_true(any(sets$type == "Spectrum" & sets$set == "all"))
        expect_false(any(is.na(sets$set)))
        expect_false(any(!nzchar(sets$set)))
        ## The set names are legal: alphanumeric with "-" and "_" allowed
        ## (section 4.1.4).
        expect_identical(sum(grepl("^[A-Za-z0-9_-]+$", sets$set)),
            nrow(sets), info = relative)
        ## Everything a spectrum claims is defined somewhere, which is the same
        ## statement the accessors make silently above.
        claims <- spectraCv(lib)
        claims <- claims[claims$accession == "MS:1003212", ]
        expect_true(all(claims$value %in% sets$set[sets$type == "Spectrum"]))
    }
})

test_that("the peak tables of a real library hold what their files hold", {
    for (relative in reference_text_libraries) {
        lib <- reference_library(relative)
        raw <- raw_counts(reference_path(relative))
        peaks <- all_peaks(lib)
        ## The two number columns are numbers for every row of a real library,
        ## which is the difference between a peak table and a CV table.
        for (pk in peaks) {
            expect_type(pk$mz, "double")
            expect_type(pk$intensity, "double")
            expect_false(any(is.na(pk$mz)))
            expect_false(any(is.na(pk$intensity)))
            expect_false(any(pk$mz < 0))
            expect_true(all(c("mz", "intensity") %in% names(pk)))
        }
        ## A declared peak attribute column is a column of the table, and a
        ## spectrum without a declaration has the three columns of section
        ## 4.1.13 and nothing more.
        cols <- peakColumns(lib)
        expect_identical(colnames(cols), c("spectrum", "column", "accession",
            "name"))
        expect_true(all(cols$column > 3L))
        widths <- raw_peak_widths(reference_path(relative))
        expect_length(widths, length(lib))
        declared <- vapply(seq_along(lib), function(k)
            sum(cols$spectrum == k), integer(1))
        for (k in seq_along(lib)) {
            pk <- peaks[[k]]
            ## The table has as many columns as the rows of the spectrum have
            ## fields, no more and no less. Section 4.1.13 allows two, three or
            ## more ("Each line of peak data MUST be tab-separated values of 2,
            ## 3, or more columns", the third one "optional"), and section
            ## 4.1.16 lets a row stay shorter than the spectrum defines ("If a
            ## peak row has fewer columns than are defined, the missing values
            ## are to be interpreted as nulls"); peakColumns() still says what
            ## a column left out would have meant.
            expect_identical(ncol(pk), widths[[k]])
            expect_true(ncol(pk) >= 2L)
            expect_true(ncol(pk) <= 3L + declared[[k]])
            ## The columns are the m/z, the intensity and the annotation of
            ## section 4.1.13 in that order, and every further column is named
            ## by the accession that declares it, in the order declared.
            base <- c("mz", "intensity", "annotation")
            expect_identical(names(pk)[seq_len(min(3L, ncol(pk)))],
                base[seq_len(min(3L, ncol(pk)))])
            expect_identical(names(pk)[-c(1L, 2L, 3L)],
                cols$accession[cols$spectrum ==
                    k][seq_len(max(0L, ncol(pk) - 3L))])
        }
        ## Two of the eight libraries are unlike the rest in the shape of their
        ## peak rows, and only these two: the consensus library writes rows
        ## shorter than it defines peak attributes for, and the spice example
        ## has no annotation column at all.
        narrow <- which(declared > 0L & widths < 3L + declared)
        expect_identical(length(narrow) > 0L, relative ==
            "SpectraST/fetal_brain_tiny_consensus_td.mzSpecLib.txt")
        expect_identical(any(widths == 2L),
            relative == "spice.mzSpecLib.txt")
        ## The peak rows are in the order of the file.
        expect_identical(sum(vapply(peaks, nrow, integer(1))), raw$peaks)
    }
})

test_that("the JSON file of a library is the library of its text file", {
    for (name in names(reference_json_libraries)) {
        json <- read_reference(reference_json_libraries[[name]])
        text <- read_reference(reference_counterpart[[
            reference_json_libraries[[name]]]])
        ## What the two serializations have to agree on: how many spectra the
        ## library has, which keys they have, what the header says, and every
        ## peak of every spectrum.
        expect_length(json, length(text))
        expect_identical(spectraIds(json), spectraIds(text))
        expect_identical(nrow(libraryCv(json)), nrow(libraryCv(text)))
        expect_identical(sort(paste(libraryCv(json)$accession,
            libraryCv(json)$value, sep = "=")),
            sort(paste(libraryCv(text)$accession, libraryCv(text)$value,
                sep = "=")))
        expect_identical(all_peaks(json), all_peaks(text))
        expect_identical(n_sets(attributeSets(json)),
            n_sets(attributeSets(text)))
        expect_identical(colnames(attributeSets(json)),
            colnames(attributeSets(text)))
        expect_length(json$issues, 0L)
        ## The attribute sets are the same sets: the same (kind, name,
        ## accession, term name) key in both files, and the same value for
        ## every one of them once a number is read as a number. JSON writes
        ## 39 where the text file has 39.0, which is the same value and not
        ## the same text.
        fromJson <- attributeSets(json)
        fromText <- attributeSets(text)
        key <- function(x)
            paste(x$type, x$set, x$accession, x$name, sep = "/")
        expect_identical(anyDuplicated(key(fromJson)), 0L)
        expect_identical(sort(key(fromJson)), sort(key(fromText)))
        expect_identical(
            num_value(fromJson$value)[match(key(fromText), key(fromJson))],
            num_value(fromText$value))
        ## What the two serializations of a spectrum cannot agree about is its
        ## identity: the text file states it in the <Spectrum=N> line, the
        ## JSON document has no section lines and states it as an
        ## MS:1003237|library spectrum key attribute of the member.
        expect_identical(sum(spectraCv(json)$accession == "MS:1003237"),
            length(json))
        expect_identical(sum(spectraCv(text)$accession == "MS:1003237"), 0L)
        ## Everything a text spectrum states is also in its JSON member, with
        ## the same value; the JSON member may hold more, because the
        ## reference documents also carry the attributes of the "all" set in
        ## every member (renumbered into groups of their own), which the text
        ## file states once for the whole library.
        diff <- vapply(seq_along(text), function(k) {
            a <- spectraCv(json, i = k, inherit = FALSE)
            b <- spectraCv(text, i = k, inherit = FALSE)
            fa <- table(paste(a$accession, a$name, num_value(a$value)))
            fb <- table(paste(b$accession, b$name, num_value(b$value)))
            nm <- union(names(fa), names(fb))
            da <- ifelse(nm %in% names(fa), fa[nm], 0)
            db <- ifelse(nm %in% names(fb), fb[nm], 0)
            c(missing = sum(pmax(db - da, 0L)), extra = sum(da - db))
        }, numeric(2))
        expect_identical(sum(diff["missing", ]), 0)
        expect_true(all(diff["extra", ] >= 1))
    }
})

test_that("a head of a real library survives being written again", {
    ## Three of the eight, so that the writer is measured against the shapes it
    ## has to get right and the files this writes stay small enough to look at:
    ## a DIA-NN head with plain three column peak rows, a consensus library
    ## with the three declared peak attribute columns of section 4.1.16, and
    ## the spice example, whose peak rows have no annotation column at all.
    for (relative in c("DIA-NN/phl004_canonical_sall_pv_plasma.head.diann.mzSpecLib.txt",
            "SpectraST/fetal_brain_tiny_consensus_td.mzSpecLib.txt",
            "spice.mzSpecLib.txt")) {
        lib <- reference_library(relative)
        out <- tempfile(fileext = ".mzSpecLib.txt")
        suppressWarnings(write_mzspeclib(lib, out))
        back <- suppressWarnings(read_mzspeclib(out))
        ## Nothing to complain about, and nothing lost.
        expect_length(back$issues, 0L)
        expect_identical(spectraIds(back), spectraIds(lib))
        expect_identical(libraryCv(back), libraryCv(lib))
        expect_identical(attributeSets(back), attributeSets(lib))
        expect_identical(spectraCv(back, inherit = FALSE),
            spectraCv(lib, inherit = FALSE))
        expect_identical(analyteCv(back, inherit = FALSE),
            analyteCv(lib, inherit = FALSE))
        expect_identical(interpretationCv(back, inherit = FALSE),
            interpretationCv(lib, inherit = FALSE))
        expect_identical(peakColumns(back), peakColumns(lib))
        expect_identical(all_peaks(back), all_peaks(lib))
        expect_identical(spectraTable(back), spectraTable(lib))
        expect_identical(analyteTable(back), analyteTable(lib))
        expect_identical(interpretationTable(back), interpretationTable(lib))
        ## The written file is a file of the format again, and a second
        ## writing changes it no more than the first one did.
        second <- tempfile(fileext = ".mzSpecLib.txt")
        suppressWarnings(write_mzspeclib(back, second))
        expect_identical(readLines(second), readLines(out))
        expect_identical(readLines(out, n = 1L), "<mzSpecLib>")
        ## The written file holds the same sections and the same peak rows as
        ## the file it was written from, counted without this package.
        expect_identical(raw_counts(out), raw_counts(reference_path(relative)))
        ## The same library as a JSON document: the same library, read back.
        json <- tempfile(fileext = ".mzSpecLib.json")
        suppressWarnings(write_mzspeclib(lib, json))
        j <- suppressWarnings(read_mzspeclib(json))
        expect_length(j$issues, 0L)
        expect_identical(spectraIds(j), spectraIds(lib))
        expect_identical(attributeSets(j), attributeSets(lib))
        expect_identical(drop_spectrum_key(libraryCv(j)), libraryCv(lib))
        expect_identical(peakColumns(j), peakColumns(lib))
        ## The m/z and the intensity of every peak survive, which is what a
        ## peak table is for.
        expect_identical(lapply(all_peaks(j), function(pk)
            pk[c("mz", "intensity")]),
            lapply(all_peaks(lib), function(pk) pk[c("mz", "intensity")]))
        ## A library that annotates its peaks comes back peak for peak,
        ## columns included. A library that does not, which section 4.1.13
        ## permits, comes back with an annotation column of its own: the JSON
        ## schema has a "peak_annotations" member and no way of leaving it out,
        ## so the writer fills it with "?" for a peak that has no annotation,
        ## the placeholder the peak rows of the example of section 4.1.16 use.
        ## The text writer leaves the field empty instead, which is why the
        ## text round trip above is the identity.
        if (all(vapply(all_peaks(lib), ncol, integer(1)) >= 3L)) {
            expect_identical(all_peaks(j), all_peaks(lib))
        } else {
            expect_true(all(vapply(all_peaks(j), function(pk)
                identical(pk$annotation, rep("?", nrow(pk))), logical(1))))
        }
    }
})
