## The JSON serialization of section 4.2: what a JSON library reads into, and
## what the writer makes of a library.

## The JSON counterpart of the example library, with a cluster, attribute sets
## of two kinds and one declared but empty set.
json_lib <- function()
    read_fixture("json-library.mzSpecLib.json")

test_that("a JSON library reads into the same object as a text library", {
    lib <- json_lib()
    expect_s3_class(lib, "mzspeclib_library")
    expect_length(lib$issues, 0L)
    expect_identical(length(lib), 2L)
    expect_identical(spectraIds(lib), c(1L, 2L))
    expect_identical(nrow(libraryCv(lib)), 5L)
    expect_identical(cvParameter(libraryCv(lib), "MS:1003186"), "1.0")
    expect_identical(nrow(attributeSets(lib)), 7L)
    expect_length(clusters(lib), 1L)
    ## A JSON file keeps its numbers where the text file has text: a CV value
    ## that JSON stores as a number comes back as the text of that number.
    expect_identical(cvParameter(attributeSets(lib), "MS:1000511"), "2")
    expect_identical(cvParameter(libraryCv(lib), "MS:1003188"),
        "fetal_brain_tiny_consensus_td")
    ## The peak tables.
    one <- spectraPeaks(lib, i = 1L)
    expect_identical(names(one), c("mz", "intensity", "annotation",
        "MS:1003279"))
    expect_identical(nrow(one), 3L)
    expect_identical(one$mz, c(103.0541, 110.0711, 115.0863))
    expect_identical(one$intensity, c(102.5, 1329.4, 110.9))
    expect_identical(one$annotation[[2L]], "IC[Carbamidomethyl]/-0.0008")
    expect_identical(one[["MS:1003279"]], c("0.6", "1", "0.8"))
    ## A peak with more than one annotation is one string, as in the text
    ## serialization.
    two <- spectraPeaks(lib, i = 2L)
    expect_identical(two$annotation[[1L]], "?,y1/-0.0005")
    expect_identical(two[["MS:1003279"]], c("1.000", NA_character_))
    ## The file the object came from is remembered.
    expect_identical(basename(lib$file), "json-library.mzSpecLib.json")
})

test_that("a JSON cluster and its attributes are read", {
    lib <- json_lib()
    expect_identical(clusters(lib)[[1L]]$id, 1L)
    cv <- clusterCv(lib)
    expect_identical(cv$cluster_key, c(1L, 1L))
    expect_identical(cv$accession, c("MS:1003320", "MS:1003268"))
    expect_identical(cv$value, c("6", "1,6,23,63,89"))
})

test_that("the key of a cluster has nowhere to go in the JSON serialization", {
    ## Not a defect of the writer but of the format: the 'cluster' definition
    ## of mzSpecLib_json.schema.json lists the single property 'attributes' and
    ## sets additionalProperties to false, so a cluster object cannot carry an
    ## id, and no CV term exists that would stand for one. The writer says so
    ## rather than losing the key quietly, and the attributes survive.
    lib <- read_fixture("spec-4-1-5-cluster.mzSpecLib.txt")
    expect_identical(vapply(clusters(lib), function(x) x$id, integer(1)),
        c(1L, 2L))
    out <- tempfile(fileext = ".mzSpecLib.json")
    expect_warning(write_mzspeclib(lib, out),
        "2 cluster\\(s\\) have a key, which the JSON serialization cannot")
    doc <- jsonlite::fromJSON(out, simplifyVector = FALSE)
    expect_length(doc$clusters, 2L)
    expect_identical(names(doc$clusters[[1L]]), "attributes")
    back <- suppressWarnings(read_mzspeclib(out))
    expect_identical(vapply(clusters(back), function(x) x$id, integer(1)),
        c(NA_integer_, NA_integer_))
    ## Only the key is lost: the parameters of the clusters are the same, in
    ## the same order, and clusterCv() still numbers the sections.
    expect_identical(unique(clusterCv(back)$cluster), c(1L, 2L))
    cvCols <- c("group", "accession", "name", "value", "value_accession")
    expect_identical(reset_rows(clusterCv(back)[, cvCols]),
        reset_rows(clusterCv(lib)[, cvCols]))
    ## A library without clusters says nothing about cluster keys.
    noClusters <- read_fixture("spec-4-1-6-spectrum.mzSpecLib.txt")
    expect_length(clusters(noClusters), 0L)
    expect_false(any(grepl("cluster",
        capture_warnings(write_mzspeclib(noClusters, out)))))
})

test_that("attribute sets of every kind come from the JSON members", {
    lib <- json_lib()
    sets <- attributeSets(lib)
    expect_setequal(unique(paste(sets$type, sets$set)),
        c("Spectrum all", "Spectrum DECOY", "Analyte HUMAN_TRYPTIC",
            "Analyte EMPTY_SET"))
    ## A declared but empty set is the row of NA values it is in the text
    ## serialization too.
    empty <- which(sets$set == "EMPTY_SET")
    expect_length(empty, 1L)
    expect_true(is.na(sets$accession[[empty]]))
    ## The peak attribute declaration keeps its group designator.
    decl <- which(sets$accession == "MS:1003254")
    expect_length(decl, 1L)
    expect_identical(sets$group[[decl]], "2")
    expect_identical(sets$value_accession[[decl]], "MS:1003279")
    ## A spectrum that claims a set inherits from it the usual way.
    expect_identical(cvParameter(spectraCv(lib, i = 1L), "MS:1000511"), "2")
    expect_true(any(spectraCv(lib, i = 1L)$inherited))
    ## A claim of a set that was never defined warns, and one of a declared
    ## empty set does not.
    claims <- read_fixture("json-attribute-set-claims.mzSpecLib.json")
    expect_warning(analyteCv(claims, i = 1L),
        "claims of undefined Analyte attribute set\\(s\\): alsoNeverDefined")
    expect_warning(cv <- spectraCv(claims, i = 1L),
        "claims of undefined Spectrum attribute set\\(s\\): neverDefined")
    ## The warning changes nothing about the rows: the two claims are there,
    ## and the one inherited value on top of them.
    expect_identical(cv$accession, c("MS:1000511", "MS:1003237", "MS:1003212",
        "MS:1003212"))
    expect_identical(cv$inherited, c(TRUE, rep(FALSE, 3L)))
    expect_length(claims$issues, 0L)
})

test_that("analyte keys are used in numeric order, not as strings", {
    ## JSON objects have no order, so the analyte keys of a spectrum have to be
    ## sorted as numbers: "10" comes after "9", not after "1".
    lib <- read_fixture("json-eleven-analytes.mzSpecLib.json")
    tab <- analyteTable(lib)
    expect_identical(nrow(tab), 11L)
    expect_identical(tab$analyte_key, 1:11)
    expect_identical(tab$analyte, 1:11)
    expect_identical(unique(analyteCv(lib)$spectrum_key), 1L)
})

test_that("a key and an id member that disagree are reported", {
    lib <- read_fixture("json-key-id-mismatch.mzSpecLib.json")
    expect_length(lib, 1L)
    expect_issue(lib, "spectrum 1: an analyte keyed 5 declares id 9; the key ")
    expect_length(lib$issues, 1L)
    ## The key won: the analyte is still the second of the two, in the numeric
    ## order of the keys 1 and 5, and its id member was ignored.
    tab <- analyteTable(lib)
    expect_identical(tab$analyte_key, c(1L, 5L))
    expect_identical(tab$analyte, c(1L, 2L))
    expect_identical(tab[["MS:1003270"]], c("KYLYEIAR/2", "DLGEENFK/2"))
})

test_that("a document which is not a library says so and reads as nothing", {
    for (name in c("json-array", "json-scalar")) {
        lib <- read_fixture(paste0(name, ".mzSpecLib.json"))
        expect_length(lib, 0L)
        expect_issue(lib, "the JSON document is not an object")
        expect_identical(nrow(libraryCv(lib)), 0L)
    }
    ## An empty file is not a JSON document at all; the parse error is passed
    ## on rather than swallowed.
    empty <- read_fixture("json-empty.mzSpecLib.json")
    expect_length(empty, 0L)
    expect_issue(empty, "the file is not a JSON document")
    ## A text file dictated to be read as JSON ends up in the same branch.
    text <- read_mzspeclib(example_path(), format = "json")
    expect_length(text, 0L)
    expect_issue(text, "the file is not a JSON document")
})

test_that("a JSON document with wrong members still yields what it can", {
    lib <- read_fixture("json-ragged.mzSpecLib.json")
    expect_identical(length(lib), 2L)
    expect_length(lib$issues, 9L)
    expect_issue(lib, "the library header: an attribute which is not an object")
    expect_issue(lib, "the library header: an attribute without an accession")
    expect_issue(lib, "spectrum 1: an attribute which is not an object")
    expect_issue(lib, "spectrum 1: 3 m/z value\\(s\\) but 1 intensity ")
    expect_issue(lib, "the shorter array was padded with NA")
    expect_issue(lib, "spectrum 1: 1 peak annotation\\(s\\) for 3 peak\\(s\\)")
    expect_issue(lib, "spectrum 2: the analytes are not an object keyed by id")
    expect_issue(lib, "spectrum 3 is not an object")
    expect_issue(lib, "1 spectrum object\\(s\\) were not objects and were ")
    ## Padding, not truncation: the longer array decides the number of peaks.
    one <- spectraPeaks(lib, i = 1L)
    expect_identical(nrow(one), 3L)
    expect_identical(one$mz, c(103.0541, 110.0711, 115.0863))
    expect_true(is.na(one$intensity[[2L]]))
    expect_true(is.na(one$annotation[[2L]]))
    ## The spectrum whose analytes were dropped is still a spectrum.
    expect_length(lib$spectra[[2L]]$analytes, 0L)
    expect_identical(spectraIds(lib), c(1L, 2L))
})

test_that("peak annotations and aggregations may be arrays or single values", {
    lib <- read_fixture("json-peak-annotation-forms.mzSpecLib.json")
    expect_identical(length(lib), 3L)
    ## One string per peak, an array of strings per peak, and an array that is
    ## joined because a peak can carry more than one annotation.
    expect_identical(spectraPeaks(lib, i = 1L)$annotation,
        c("?", "IC[Carbamidomethyl]/-0.0008", "y3/-0.0011"))
    two <- spectraPeaks(lib, i = 2L)
    expect_identical(two$annotation[[1L]], "?")
    expect_identical(two$annotation[[2L]],
        "a1/-0.0003,y2-H2O-NH3^2/0.0017")
    expect_identical(two$annotation[[3L]], NA_character_)
    ## A single string where an array was expected is one annotation.
    three <- spectraPeaks(lib, i = 3L)
    expect_identical(three$annotation[[1L]], "not an array but a single string")
    expect_identical(three$annotation[-1L], rep(NA_character_, 2L))
    expect_length(lib$issues, 1L)
    ## Aggregations become one column per declared peak attribute.
    agg <- read_fixture("json-aggregations.mzSpecLib.json")
    expect_identical(names(spectraPeaks(agg, i = 1L)), c("mz", "intensity",
        "annotation", "MS:1003279", "MS:1003285"))
    ## A spectrum without aggregations has the columns of its own declarations
    ## only.
    expect_identical(names(spectraPeaks(agg, i = 2L)), c("mz", "intensity",
        "MS:1003279"))
})

test_that("a missing or foreign format version is reported once", {
    v2 <- read_fixture("json-format-version-2.mzSpecLib.json")
    expect_issue(v2, "declares format version '2.0'")
    expect_length(v2$issues, 1L)
    ## Reading it did not stop: the library is there.
    expect_length(v2, 1L)
    missing <- read_fixture("json-format-version-missing.mzSpecLib.json")
    expect_issue(missing, "no 'format_version' member")
    expect_length(missing$issues, 1L)
    ## The text serialization has no member to look at, only the CV line, and
    ## the reader accepts whatever that line says: a foreign version is the
    ## writer's business, where it is a warning. A line which is not there at
    ## all is a deviation of the file, and the reader collects it (section
    ## 4.1.1 makes the term mandatory).
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=2.0"),
        file)
    expect_length(read_mzspeclib(file)$issues, 0L)
    writeLines(c("<mzSpecLib>", "MS:1003187|library identifier=x"), file)
    noVersion <- read_mzspeclib(file)
    expect_issue(noVersion, "no MS:1003186\\|library format version, which ")
    expect_length(noVersion$issues, 1L)
    out <- tempfile(fileext = ".mzSpecLib.txt")
    expect_warning(write_mzspeclib(read_mzspeclib(file), out),
        "the header has no MS:1003186\\|library format version")
})

test_that("an empty library is written as an empty document of either kind", {
    ## Both serializations of nothing at all, so that a caller can round trip
    ## an empty result without an error.
    txt <- tempfile(fileext = ".mzSpecLib.txt")
    expect_warning(write_mzspeclib(mzspeclib(), txt),
        "the header has no MS:1003186")
    expect_identical(readLines(txt), "<mzSpecLib>")
    json <- tempfile(fileext = ".mzSpecLib.json")
    expect_warning(write_mzspeclib(mzspeclib(), json),
        "the header has no MS:1003186")
    doc <- jsonlite::fromJSON(json, simplifyVector = FALSE)
    expect_identical(names(doc), c("attributes", "spectrum_attribute_sets",
        "analyte_attribute_sets", "interpretation_attribute_sets",
        "cluster_attribute_sets", "clusters", "spectra", "format_version"))
    expect_identical(doc$format_version, "1.0")
    back <- suppressWarnings(read_mzspeclib(json))
    expect_length(back, 0L)
    expect_identical(nrow(libraryCv(back)), 0L)
})

test_that("a JSON document with a ragged aggregation array is readable", {
    ## The reader promises to pad a shorter array (see the issues it writes for
    ## m/z and intensity), and the same has to hold for aggregations.
    lib <- try(read_fixture("json-ragged-aggregations.mzSpecLib.json"),
        silent = TRUE)
        expect_false(inherits(lib, "try-error"))
    expect_identical(nrow(spectraPeaks(lib, i = 1L)), 3L)
})

test_that("the serialization is chosen by the file, and can be dictated", {
    expect_identical(mzspeclib:::.detect_format(
        fixture("json-library.mzSpecLib.json"), "UTF-8"), "json")
    expect_identical(mzspeclib:::.detect_format(example_path(), "UTF-8"),
        "text")
    ## A JSON document in a file named .txt is still read as JSON.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    file.copy(fixture("json-library.mzSpecLib.json"), file)
    expect_identical(mzspeclib:::.detect_format(file, "UTF-8"), "json")
    expect_length(read_mzspeclib(file), 2L)
    ## A JSON file dictated to be text gets the text reader's complaint.
    forced <- read_mzspeclib(fixture("json-library.mzSpecLib.json"),
        format = "text")
    expect_length(forced, 0L)
    expect_issue(forced, "does not start with the required '<mzSpecLib>' line")
})

test_that("the writer decides the JSON type of a value by its text", {
    ## The schema has no type information about a CV value, so the writer
    ## looks at the text: a value written "1.0" has to come back as "1.0".
    file <- tempfile(fileext = ".mzSpecLib.txt")
    vals <- c("1.0", "39.0", "6.0", "1e-07", "0.17", "0.333", "570", "-12",
        "2", "TRUE", "FALSE", "100000000000000000000", "", "NaN", "Inf")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1000511|ms level=2",
        paste0("MS:1003275|other attribute name=", vals), "<Peaks>",
        "100.0\t1\t?"), file)
    lib <- read_mzspeclib(file)
    out <- tempfile(fileext = ".mzSpecLib.json")
    write_mzspeclib(lib, out)
    doc <- jsonlite::fromJSON(out, simplifyVector = FALSE)
    written <- vapply(doc$spectra[[1L]]$attributes, function(a)
        class(a$value)[[1L]], character(1))
    ## The attributes of the section in the order of the file, and the added
    ## spectrum key last.
    expect_identical(written, c("integer", "character", "character",
        "character", "character", "numeric", "numeric", "integer", "integer",
        "integer", "logical", "logical", "numeric", "character", "character",
        "character", "integer"))
    ## A value with a trailing zero, an exponent, a logical word, an empty
    ## value, NaN and Inf all stay text; plain integers, decimals and big
    ## numbers become JSON numbers.
    values <- vapply(doc$spectra[[1L]]$attributes, function(a)
        as.character(a$value), character(1))
    expect_identical(values[[2L]], "1.0")
    expect_identical(values[[5L]], "1e-07")
    expect_identical(values[[8L]], "570")
    expect_identical(values[[11L]], "TRUE")
    expect_identical(values[[12L]], "FALSE")
    ## A number too big for an integer is written in exponential form, but it
    ## is read back as the same text it had in the file.
    expect_identical(values[[13L]], "1e+20")
    ## An empty value is written as the empty string, which is what the schema
    ## allows and what the text serialization writes.
    expect_identical(values[[14L]], "")
    back <- read_mzspeclib(out)
    text <- cvParameter(spectraCv(back, i = 1L, inherit = FALSE),
        "MS:1003275", all = TRUE)
    expect_length(text, 15L)
    expect_identical(text[[1L]], "1.0")
    expect_identical(text[[4L]], "1e-07")
    expect_identical(text[[7L]], "570")
    expect_identical(text[[10L]], "TRUE")
    expect_identical(text[[12L]], "100000000000000000000")
    expect_identical(text[[15L]], "Inf")
    expect_identical(cvParameter(spectraCv(back, i = 1L, inherit = FALSE),
        "MS:1000511"), "2")
    ## An empty value comes back as a missing value, not as the empty text:
    ## the one place where the JSON round trip is not the identity.
    expect_identical(text[[13L]], NA_character_)
    ## Nothing was reported on the way back.
    expect_length(back$issues, 0L)
})

test_that("the writer adds the spectrum key the JSON schema needs", {
    ## The text serialization carries the key in the <Spectrum=N> line, the
    ## JSON serialization as an attribute, so a text -> JSON round trip adds
    ## exactly one attribute per spectrum.
    lib <- example_library()
    out <- tempfile(fileext = ".mzSpecLib.json")
    suppressWarnings(write_mzspeclib(lib, out))
    doc <- jsonlite::fromJSON(out, simplifyVector = FALSE)
    expect_length(doc$spectra, 3L)
    for (k in seq_along(doc$spectra)) {
        ## The attributes of the section keep their order; the key comes last,
        ## as the one thing the writer had to invent.
        last <- doc$spectra[[k]]$attributes[[length(doc$spectra[[k]]$attributes)]]
        expect_identical(last$accession, "MS:1003237")
        expect_identical(last$name, "library spectrum key")
        expect_identical(last$value, k)
    }
    ## The section key of the text serialization becomes the attribute of the
    ## JSON one, so a file that numbers its spectra 1, 234 and 235 keeps those
    ## numbers rather than their positions.
    spec <- read_fixture("spec-4-1-6-spectrum.mzSpecLib.txt")
    keyed <- tempfile(fileext = ".mzSpecLib.json")
    write_mzspeclib(spec, keyed)
    again <- read_mzspeclib(keyed)
    expect_identical(spectraIds(again), c(1L, 234L, 235L))
    d <- jsonlite::fromJSON(keyed, simplifyVector = FALSE)
    expect_identical(vapply(d$spectra, function(s)
        s$attributes[[length(s$attributes)]]$value, integer(1)),
        c(1L, 234L, 235L))
    ## Only a spectrum that has no key at all is left with its position, and
    ## the writer says so. The text writer does exactly that: the section line
    ## of the written file carries the position.
    file2 <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum>", "MS:1000511|ms level=2"), file2)
    keyless <- read_mzspeclib(file2)
    expect_issue(keyless, "<Spectrum> section without a key")
    out3 <- tempfile(fileext = ".mzSpecLib.txt")
    expect_warning(write_mzspeclib(keyless, out3),
        "1 spectrum\\(s\\) have no library spectrum key; sequential keys are ")
    expect_identical(spectraIds(read_mzspeclib(out3)), 1L)
    ## The JSON writer makes the same promise in its own words and then does
    ## not keep it.
    out2 <- tempfile(fileext = ".mzSpecLib.json")
    expect_warning(write_mzspeclib(keyless, out2),
        "1 spectrum\\(s\\) have no library spectrum key")
    back2 <- read_mzspeclib(out2)
        expect_identical(spectraIds(back2), 1L)
    expect_length(back2$issues, 0L)
    ## A library that already carries the term is not given a second one.
    expect_identical(sum(spectraCv(lib)$accession == "MS:1003237"), 0L)
    json <- read_mzspeclib(out)
    expect_identical(sum(spectraCv(json, inherit = FALSE)$accession ==
        "MS:1003237"), 3L)
    ## Nothing else was added or left out.
    expect_identical(nrow(spectraCv(json, inherit = FALSE)),
        nrow(spectraCv(lib, inherit = FALSE)) + 3L)
    expect_identical(names(doc$spectra[[1L]]), c("attributes", "analytes",
        "interpretations", "mzs", "intensities", "peak_annotations"))
    expect_identical(doc$format_version, "1.0")
})

test_that("peak numbers are written as JSON numbers with digits significant", {
    lib <- example_library()
    ## The default of fifteen digits keeps every peak of the example intact.
    full <- tempfile(fileext = ".mzSpecLib.json")
    write_mzspeclib(lib, full)
    expect_identical(spectraPeaks(read_mzspeclib(full), i = 1L),
        spectraPeaks(lib, i = 1L))
    ## Three digits do not, and the reader does not hide that.
    few <- tempfile(fileext = ".mzSpecLib.json")
    write_mzspeclib(lib, few, digits = 3)
    rounded <- spectraPeaks(read_mzspeclib(few), i = 1L)
    expect_identical(rounded$mz[[1L]], 103)
    expect_false(isTRUE(all.equal(rounded$mz, spectraPeaks(lib,
        i = 1L)$mz)))
    ## Seven digits are enough for the m/z values of this library.
    seven <- tempfile(fileext = ".mzSpecLib.json")
    write_mzspeclib(lib, seven, digits = 7)
    expect_identical(spectraPeaks(read_mzspeclib(seven), i = 1L)$mz,
        spectraPeaks(lib, i = 1L)$mz)
    ## The JSON document is written for a human to read.
    expect_true(grepl("\n", paste(readLines(full), collapse = "\n")))
    expect_identical(substr(readLines(full)[[1L]], 1L, 1L), "{")
})
