## The example libraries of the specification itself. Everything below comes
## from the files tests/testthat/files/spec-*.mzSpecLib.txt, which are
## transcriptions of the examples of the HUPO-PSI mzSpecLib specification
## version 1.0 (see the header of each of those files for the section it came
## from, the source and the license). What is tested here is the pair of things
## only those files can give: that the transcription says where it came from and
## parses, and that the reader arrives at the values the specification lists
## next to the example.

## The seven transcriptions, with the section each one is from.
spec_examples <- function() {
    files <- list.files(fixture(""), "^spec-.*[.]mzSpecLib[.]txt$",
        full.names = FALSE)
    section <- gsub("-", ".", sub("^spec-(4-1-[0-9]+)-.*$", "\\1", files))
    data.frame(file = files, section = section, stringsAsFactors = FALSE)
}

test_that("every transcription of an example says where it came from", {
    ex <- spec_examples()
    expect_identical(ex$section, c("4.1.10", "4.1.12", "4.1.12", "4.1.16",
        "4.1.17", "4.1.5", "4.1.6"))
    for (k in seq_len(nrow(ex))) {
        lines <- readLines(fixture(ex$file[[k]]))
        ## A comment in the very first line, as section 4.1.18 allows for a
        ## comment line, and the words that make the attribution worth having.
        expect_true(startsWith(lines[[1L]], "#"), info = ex$file[[k]])
        header <- paste(lines[startsWith(lines, "#")], collapse = " ")
        expect_true(startsWith(header, "# Transcribed"), info = ex$file[[k]])
        for (phrase in c("HUPO-PSI mzSpecLib specification", "version", "1.0",
                "Apache License 2.0", "http://psidev.info/mzSpecLib",
                "copied verbatim"))
            expect_true(grepl(phrase, header, fixed = TRUE),
                info = paste(ex$file[[k]], ":", phrase))
        ## The section it claims, and only that section.
        expect_true(grepl(paste0("section ", ex$section[[k]]), header,
            fixed = TRUE), info = ex$file[[k]])
        ## The first section line is the library one, and the first CV term of
        ## the header is the format version, which section 4.1.1 makes
        ## mandatory ("The first CV term MUST be the mzSpecLib format
        ## specification version number").
        content <- lines[!startsWith(lines, "#") & nzchar(lines)]
        expect_identical(content[[1L]], "<mzSpecLib>", info = ex$file[[k]])
        expect_identical(content[[2L]],
            "MS:1003186|library format version=1.0", info = ex$file[[k]])
    }
})

test_that("an example reads as it was written, and the comments are kept apart",
    {
    ex <- spec_examples()
    for (k in seq_len(nrow(ex))) {
        lib <- read_fixture(ex$file[[k]])
        ## Nothing about an example of the format is a deviation from it.
        expect_length(lib$issues, 0L)
        ## The comment lines are counted and are nowhere in the data.
        lines <- readLines(fixture(ex$file[[k]]))
        expect_identical(attr(lib, "comments"),
            sum(startsWith(lines, "#")), info = ex$file[[k]])
        tables <- list(libraryCv(lib), attributeSets(lib))
        for (k in seq_along(lib))
            ## A spectrum section of the examples sometimes states nothing of
            ## its own; its table is empty and cannot say anything (see the
            ## skip about it in test-accessors-long.R).
            if (nrow(lib$spectra[[k]]$cv))
                tables[[length(tables) + 1L]] <- suppressWarnings(
                    spectraCv(lib, i = k, inherit = FALSE))
        for (cv in tables)
            expect_false(any(grepl("^#", cv$name, fixed = TRUE)))
        ## The library is not empty and the format version is where it belongs.
        expect_identical(cvParameter(libraryCv(lib), "MS:1003186"), "1.0",
            info = ex$file[[k]])
    }
})

test_that("every term of an example is a term of the format", {
    ## The names in the fixtures were copied, not written: the check here is
    ## that a line is a CV parameter line at all, and that an accession is
    ## either an MS: or a UO: term of seven digits. What the name of an
    ## accession is cannot be checked here without the CV itself, so the pairs
    ## are checked against the two in repository sources of them: the example
    ## library the package ships and the audit of the term names in
    ## reports/analysis/. The handful of pairs neither of them knows are named
    ## below, and only there, because they are known from the specification
    ## alone.
    ex <- spec_examples()
    lines <- unlist(lapply(ex$file, function(f) {
        l <- readLines(fixture(f))
        l[!startsWith(l, "#")]
    }))
    ## A CV parameter line, optionally with a group designator in front of it.
    ## Peak rows are not CV parameter lines and never start with a group
    ## designator, so the lines that start with a digit are left out.
    pattern <- "^ *\\[?[0-9]*\\]? *([^|=]+)\\|([^=]+)=.*$"
    cv_lines <- function(lines) {
        lines <- lines[!startsWith(lines, "#")]
        lines <- lines[nzchar(lines) & !startsWith(lines, "<")]
        lines[!grepl("^[0-9]", lines)]
    }
    parse_pairs <- function(lines) {
        lines <- cv_lines(lines)
        data.frame(accession = trimws(sub(pattern, "\\1", lines)),
            name = trimws(sub(pattern, "\\2", lines)),
            parses = grepl(pattern, lines), stringsAsFactors = FALSE)
    }
    all_lines <- unlist(lapply(ex$file, function(f)
        readLines(fixture(f))))
    parsed <- parse_pairs(all_lines)
    expect_identical(sum(parsed$parses), nrow(parsed),
        info = paste(cv_lines(all_lines)[!parsed$parses], collapse = " | "))
    expect_identical(sum(grepl("^(MS|UO):[0-9]{7}$", parsed$accession)),
        nrow(parsed),
        info = paste(unique(parsed$accession[!grepl("^(MS|UO):[0-9]{7}$",
            parsed$accession)]), collapse = " | "))
    expect_identical(sum(nzchar(parsed$name)), nrow(parsed))
    pairs <- unique(parsed[, c("accession", "name")])
    ## The pairs the package's own example library uses, parsed the same way.
    example <- parse_pairs(readLines(example_path()))
    documented <- function(a, n)
        any(example$accession == a & example$name == n)
    audit <- file.path("..", "..", "reports", "analysis",
        "cv_label_audit_cache.json")
    skip_if_not(file.exists(audit), "the term name audit is not there")
    labels <- jsonlite::fromJSON(audit, simplifyVector = FALSE)
    ## Only the pairs whose accession the audit of this package covers, and
    ## whose name is the label or one of the synonyms it recorded.
    attested <- function(a, n)
        !is.null(labels[[a]]) && n %in% trimws(unlist(c(labels[[a]]$label,
            labels[[a]]$synonyms)))
    ## The pairs the specification is the only source of in this repository.
    ## The pair MS:1003212|data processing action is the line of Example 2 the
    ## specification itself writes with the accession of the claim term and the
    ## name of the data processing action; the fixture copies it (see the
    ## Example 2 test below).
    only_spec <- data.frame(accession = c("MS:1003047", "MS:1003163",
        "MS:1003166", "MS:1003212", "MS:1003268", "MS:1003297",
        "MS:1003304", "MS:1003320", "MS:1003321", "MS:1003322"),
        name = c("protein sequence offset", "analyte mixture members",
            "assigned intensity fraction", "data processing action",
            "spectrum cluster member keys",
            "contributing replicate spectrum keys", "spectral dot product",
            "spectrum cluster size",
            "summary statistics of clustered spectra",
            "spectrum cluster best representative"), stringsAsFactors = FALSE)
    exempt <- function(a, n) any(only_spec$accession == a &
        only_spec$name == n)
    unknown <- mapply(function(a, n) !(documented(a, n) || attested(a, n) ||
        exempt(a, n)), pairs$accession, pairs$name)
    expect_false(any(unknown), info = paste(paste(pairs$accession[unknown],
        pairs$name[unknown], sep = "|"), collapse = " | "))
    ## The exemption list is exact, so a new term cannot hide in it unnoticed.
    unaccounted <- mapply(function(a, n) !(documented(a, n) ||
        attested(a, n)), pairs$accession, pairs$name)
    expect_identical(nrow(pairs[unaccounted, ]), nrow(only_spec))
})

test_that("section 4.1.5: a cluster is a group of spectra and nothing else", {
    lib <- read_fixture("spec-4-1-5-cluster.mzSpecLib.txt")
    expect_length(clusters(lib), 2L)
    cv <- clusterCv(lib)
    ## The two clusters keep their own keys, and the key of a cluster has
    ## nothing to do with the key of a spectrum ("shared Cluster and Spectrum
    ## key numbers MUST NOT be assumed to be related").
    expect_identical(unique(cv$cluster), 1:2)
    expect_identical(unique(cv$cluster_key), c(1L, 2L))
    expect_identical(spectraIds(lib), c(1L, 2L))
    ## Cluster 1 is the example of the specification, line by line.
    one <- cv[cv$cluster == 1L, ]
    expect_identical(one$accession, c("MS:1003320", "MS:1003268",
        "MS:1003269", "MS:1003321", "MS:1003176", "MS:1003321",
        "MS:1003176", "MS:1003177", "MS:1003322"))
    expect_identical(one$value[[1L]], "6")
    expect_identical(one$value[[2L]], "1,6,23,63,89")
    expect_true(startsWith(one$value[[3L]], "mzspec:PXD000561:"))
    expect_identical(one$value[[4L]], "spectral dot product")
    expect_identical(one$value[[6L]],
        "experimental precursor monoisotopic m/z")
    expect_identical(one$value[[7L]], "1029.05")
    expect_identical(one$value[[9L]], "63")
    ## The attribute groups of the example are the two summary statistics, and
    ## an ungrouped line is a line of the cluster itself.
    expect_identical(one$group, c(NA, NA, NA, "1", "1", "2", "2", "2", NA))
    ## Cluster 2 stands for the '<Cluster=N+1>' of the example, and it has only
    ## the two lines it writes; the best representative it does not have is
    ## simply not there.
    two <- cv[cv$cluster == 2L, ]
    expect_identical(two$accession, c("MS:1003320", "MS:1003268"))
    expect_identical(two$value, c("2", "2,4"))
    expect_length(cvParameter(two, "MS:1003322"), 0L)
    ## "Since a cluster represents a group of spectra, there MUST NOT be
    ## Analyte or Interpretation sections within <Cluster>": the reader keeps
    ## what it reads inside a cluster inside the cluster, and the identification
    ## of a member belongs to the <Spectrum> section of that member, which is
    ## what the two spectra of this library are.
    expect_false(any(cv$accession %in% c("MS:1003270", "MS:1002357")))
    expect_identical(nrow(suppressWarnings(analyteCv(lib))), 0L)
    expect_identical(nrow(suppressWarnings(interpretationCv(lib))), 0L)
    expect_length(lib$spectra[[1L]]$analytes, 0L)
    expect_length(lib$spectra[[2L]]$interpretations, 0L)
    ## A cluster inherits from the Cluster attribute sets like every other
    ## section, and this library has none, so nothing is inherited anywhere.
    expect_false(any(cv$inherited))
    expect_identical(clusterCv(lib, inherit = FALSE), cv)
    expect_identical(nrow(attributeSets(lib)), 0L)
})

test_that("section 4.1.5: clusters and spectra MAY be interleaved", {
    ## The section of a cluster ends with the next <Cluster=...> line or with
    ## the first <Spectrum=...> line, and a file MAY interleave the two kinds.
    ## The fixture of section 4.1.5 has its clusters first; here the same
    ## content comes between the spectra, and it has to read the same.
    before <- read_fixture("spec-4-1-5-cluster.mzSpecLib.txt")
    one <- c("<Cluster=1>", "MS:1003320|spectrum cluster size=6",
        "MS:1003268|spectrum cluster member keys=1,6,23,63,89",
        "MS:1003269|spectrum cluster member USI=mzspec:PXD000561:Adult_Frontalcortex_bRP_Elite_85_f09:scan:17555",
        "[1] MS:1003321|summary statistics of clustered spectra=MS:1003304|spectral dot product",
        "[1] MS:1003176|attribute mean=0.7",
        "[2] MS:1003321|summary statistics of clustered spectra=MS:1003208|experimental precursor monoisotopic m/z",
        "[2] MS:1003176|attribute mean=1029.05",
        "[2] MS:1003177|attribute standard deviation=0.41",
        "MS:1003322|spectrum cluster best representative=63")
    two <- c("<Cluster=2>", "MS:1003320|spectrum cluster size=2",
        "MS:1003268|spectrum cluster member keys=2,4")
    first <- c("<Spectrum=1>", "MS:1003061|library spectrum name=AILINFIDR/2",
        "MS:1000511|ms level=2")
    second <- c("<Spectrum=2>",
        "MS:1003061|library spectrum name=HLAEISLLEQSFVK/3",
        "MS:1000511|ms level=2")
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0", one,
        first, two, second), file)
    lib <- read_mzspeclib(file)
    expect_length(lib$issues, 0L)
    expect_length(clusters(lib), 2L)
    expect_identical(clusterCv(lib), clusterCv(before))
    expect_identical(spectraIds(lib), spectraIds(before))
    expect_identical(suppressWarnings(spectraCv(lib, inherit = FALSE)),
        suppressWarnings(spectraCv(before, inherit = FALSE)))
})

## The four resolved attributes the specification prints under "Then for this
## library spectrum, the following should apply after resolving conflicts".
test_that("section 4.1.12 Example 1: the first spectrum resolves as printed", {
    lib <- read_fixture("spec-4-1-12-attribute-sets.mzSpecLib.txt")
    expect_identical(nrow(attributeSets(lib)), 10L)
    expect_identical(unique(attributeSets(lib)$set),
        c("all", "ETD", "HCD", "Decoy"))
    cv <- spectraCv(lib, i = 1L)
    ## The spectrum itself claims the two sets and states one attribute, so
    ## three of its rows are its own and the rest are inherited.
    expect_identical(nrow(cv), 6L)
    local <- cv[!cv$inherited, ]
    expect_identical(local$accession, c("MS:1003212", "MS:1003212",
        "MS:1003072"))
    expect_identical(local$value, c("ETD", "Decoy",
        "precursor shift decoy spectrum"))
    inherited <- cv[cv$inherited, ]
    ## Exactly the three attributes the specification prints besides the local
    ## one, and with the values it prints: the polarity of "all", the
    ## instrument and the dissociation method of "ETD".
    expect_identical(inherited$accession, c("MS:1000465", "MS:1000031",
        "MS:1000044"))
    expect_identical(inherited$name, c("scan polarity", "instrument model",
        "dissociation method"))
    expect_identical(inherited$value, c("positive scan",
        "LTQ Orbitrap XL ETD", "electron transfer dissociation"))
    expect_identical(inherited$value_accession, c("MS:1000130",
        "MS:1000639", "MS:1000598"))
    ## The four resolutions of the example, in the words of the example:
    ## "all" gives the polarity without conflict, "ETD" overrides the
    ## dissociation method of "all", and the spectrum's own origin type
    ## overrides the one of "Decoy", which in turn overrides the one of "all".
    expect_identical(cvParameter(cv, "MS:1000465", value = FALSE),
        "MS:1000130")
    expect_identical(cvParameter(cv, "MS:1000044"),
        "electron transfer dissociation")
    expect_identical(cvParameter(cv, "MS:1000044", value = FALSE),
        "MS:1000598")
    expect_identical(cvParameter(cv, "MS:1003072"),
        "precursor shift decoy spectrum")
    ## Which is to say: neither of the two origin types that were overridden is
    ## anywhere in the resolved table.
    expect_false(any(cv$value == "shuffle and reposition decoy spectrum"))
    expect_false(any(cv$value == "observed spectrum"))
    expect_false(any(cv$value == "collision-induced dissociation"))
})

test_that("section 4.1.12 Example 1: the last claimed set wins", {
    lib <- read_fixture("spec-4-1-12-attribute-sets.mzSpecLib.txt")
    cv <- spectraCv(lib, i = 2L)
    ## This spectrum claims "HCD" first and "ETD" last, and states nothing of
    ## its own but the two claims, so all six attributes are inherited.
    expect_identical(sum(!cv$inherited), 2L)
    expect_identical(cv$accession[!cv$inherited], c("MS:1003212",
        "MS:1003212"))
    expect_identical(cv$value[!cv$inherited], c("HCD", "ETD"))
    inherited <- sort(cv$accession[cv$inherited])
    ## The six attributes of the specification's second list.
    expect_identical(inherited, sort(c("MS:1000031", "MS:1000044",
        "MS:1000138", "MS:1000419", "MS:1000465", "MS:1003072")))
    expect_identical(cvParameter(cv, "MS:1000031"), "LTQ Orbitrap XL ETD")
    expect_identical(cvParameter(cv, "MS:1000044"),
        "electron transfer dissociation")
    ## "But the ETD set does not specify the attributes of collision gas or
    ## normalized collision energy, so those attributes claimed from the HCD
    ## set still remain."
    expect_identical(cvParameter(cv, "MS:1000419"), "helium")
    expect_identical(cvParameter(cv, "MS:1000138"), "35")
    expect_identical(cvParameter(cv, "MS:1000465"), "positive scan")
    expect_identical(cvParameter(cv, "MS:1003072"), "observed spectrum")
    ## Nothing of the HCD set that the ETD set overrode is left behind.
    expect_false(any(cv$value == "Orbitrap Fusion"))
    expect_false(any(cv$value ==
        "beam-type collision-induced dissociation"))
    ## It is the order in which the sets are claimed that decides, not the
    ## order in which they are defined in the header: "HCD" is defined before
    ## "ETD", and claiming the two the other way round gives the HCD values.
    lines <- readLines(fixture("spec-4-1-12-attribute-sets.mzSpecLib.txt"))
    header <- lines[1L:(grep("^<Spectrum=1>", lines)[[1L]] - 1L)]
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c(header, "<Spectrum=1>",
        "MS:1003212|library attribute set name=ETD",
        "MS:1003212|library attribute set name=HCD"), file)
    other <- read_mzspeclib(file)
    other <- spectraCv(other, i = 1L)
    expect_identical(cvParameter(other, "MS:1000031"), "Orbitrap Fusion")
    expect_identical(cvParameter(other, "MS:1000044"),
        "beam-type collision-induced dissociation")
    expect_false(any(other$value == "LTQ Orbitrap XL ETD"))
    expect_false(any(other$value == "electron transfer dissociation"))
    ## The two attributes only "HCD" states are there in either order, because
    ## nothing claims them away.
    expect_identical(cvParameter(other, "MS:1000419"), "helium")
    expect_identical(cvParameter(cv, "MS:1000419"), "helium")
})

test_that("section 4.1.12 Example 2: instances of one term are one set", {
    lib <- read_fixture("spec-4-1-12-groups.mzSpecLib.txt")
    sets <- attributeSets(lib)
    ## The "all" set gives two instances of one term, which is what the example
    ## is about.
    expect_identical(nrow(sets), 5L)
    expect_identical(sum(sets$accession == "MS:1000543"), 2L)
    ## The example writes the overriding line of the spectrum with the
    ## accession MS:1003212|library attribute set name and the name and value
    ## of a data processing action; the fixture copies it as it stands, so the
    ## reader of the format sees a claim of a set called "square root
    ## transform" and says so.
    expect_warning(cv <- spectraCv(lib, i = 1L),
        "claims of undefined Spectrum attribute set\\(s\\): square root ")
    expect_identical(nrow(cv), 3L)
    expect_identical(cv$accession, c("MS:1000543", "MS:1000543",
        "MS:1003212"))
    expect_identical(cv$name[[3L]], "data processing action")
    expect_identical(cv$inherited, c(TRUE, TRUE, FALSE))
    ## What the example means is a spectrum that states the term itself. With
    ## the accession of the term, the one local instance replaces both
    ## inherited ones, which is the sentence "will override ALL the instances
    ## of the same term ... they are inherited or overridden as an inseparable
    ## set".
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<AttributeSet Spectrum=all>",
        "MS:1000543|data processing action=MS:1000033|deisotoping",
        "MS:1000543|data processing action=MS:1003242|rank transform",
        "<Spectrum=1>",
        "MS:1000543|data processing action=MS:1003241|square root transform"),
        file)
    one <- read_mzspeclib(file)
    cv <- spectraCv(one, i = 1L)
    expect_length(one$issues, 0L)
    expect_identical(nrow(cv), 1L)
    expect_false(cv$inherited)
    expect_identical(cvParameter(cv, "MS:1000543", all = TRUE),
        "square root transform")
    expect_false(any(cv$value == "deisotoping"))
    expect_false(any(cv$value == "rank transform"))
    ## Without the local line both instances are inherited together.
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<AttributeSet Spectrum=all>",
        "MS:1000543|data processing action=MS:1000033|deisotoping",
        "MS:1000543|data processing action=MS:1003242|rank transform",
        "<Spectrum=1>", "MS:1003061|library spectrum name=one"), file)
    both <- spectraCv(read_mzspeclib(file), i = 1L)
    both <- both[both$accession == "MS:1000543", ]
    expect_identical(nrow(both), 2L)
    expect_identical(both$value, c("deisotoping", "rank transform"))
    expect_identical(both$value_accession, c("MS:1000033", "MS:1003242"))
    expect_true(all(both$inherited))
})

test_that("section 4.1.12 Example 3: a set claimed from inside a group", {
    lib <- read_fixture("spec-4-1-12-groups.mzSpecLib.txt")
    cv <- analyteCv(lib, i = 2L)
    ## The analyte of the human tryptic peptide: nine lines of its own, three
    ## from the "human_tryptic" set.
    expect_identical(nrow(cv), 12L)
    expect_identical(sum(cv$inherited), 3L)
    expect_identical(sort(cv$accession[cv$inherited]),
        sort(c("MS:1001469", "MS:1001045", "MS:1003048")))
    expect_identical(cvParameter(cv, "MS:1001469"), "Homo sapiens")
    expect_identical(cvParameter(cv, "MS:1001045"), "Trypsin")
    expect_identical(cvParameter(cv, "MS:1003048"), "2")
    ## The three groups of the analyte are the m/z and its unit, the protein,
    ## and the claim of the set inside the protein group.
    expect_identical(unique(cv$group[!cv$inherited]), c(NA, "1", "2"))
    expect_identical(cv$group[!cv$inherited & cv$accession == "MS:1003212"],
        "2")
    ## The claim is what brings the three attributes in: without it the
    ## analyte has its own nine lines only.
    local <- analyteCv(lib, i = 2L, inherit = FALSE)
    expect_identical(nrow(local), 9L)
    expect_length(cvParameter(local, "MS:1001469"), 0L)
    ## "one MUST NOT inherit the all attribute set into any group
    ## automatically": the Analyte/all set does not exist in this library, and
    ## the Spectrum/all set is never inherited into an analyte section, so the
    ## analyte above has nothing of the data processing actions.
    expect_false(any(cv$accession == "MS:1000543"))
})

test_that("section 4.1.12 Example 3: two proteins of one peptide", {
    lib <- read_fixture("spec-4-1-12-groups.mzSpecLib.txt")
    cv <- analyteCv(lib, i = 3L)
    ## The peptide KYLYEIAR/2 maps to a human and a bovine protein, in the
    ## groups [2] and [3]. The human_tryptic set is claimed inside group [2],
    ## so its three attributes belong to the human protein, while group [3]
    ## states the bovine protein and one enzymatic terminus for itself. All
    ## seventeen local lines are there.
    expect_identical(nrow(analyteCv(lib, i = 3L, inherit = FALSE)), 17L)
    ## What the two groups do say is that the bovine protein states one
    ## enzymatic terminus and the human one the set's two.
    expect_identical(cvParameter(cv, "MS:1003048"), "1")
    ## That is the whole point of the example, and the point of claiming a set
    ## inside a group: the human protein of this spectrum keeps the attributes
    ## of the set it claims, whatever the bovine protein says.
        expect_identical(nrow(cv), 20L)
    expect_identical(sum(cv$inherited), 3L)
    expect_identical(cv$group[cv$inherited], rep("2", 3L))
    ## The human protein of the spectrum is then named twice, once by the
    ## analyte's own group [2] and once by the set it claims, and the two
    ## enzymatic termini of the two proteins stand side by side.
    expect_identical(cvParameter(cv, "MS:1001469", all = TRUE),
        c("Homo sapiens", "Bos taurus"))
    expect_identical(cvParameter(cv, "MS:1003048", all = TRUE), c("2", "1"))
})

test_that("section 4.1.6: the metadata of a spectrum keeps its groups", {
    lib <- read_fixture("spec-4-1-6-spectrum.mzSpecLib.txt")
    expect_identical(spectraIds(lib), c(1L, 234L, 235L))
    cv <- spectraCv(lib, i = 1L, inherit = FALSE)
    expect_identical(cvParameter(cv, "MS:1000511"), "3")
    expect_identical(cvParameter(cv, "MS:1003072"), "observed spectrum")
    ## The aggregation type is stated twice, once ungrouped as the best
    ## replicate spectrum and once inside group [1] as a consensus spectrum;
    ## both stay, because they are statements of different contexts.
    agg <- cv[cv$accession == "MS:1003065", ]
    expect_identical(agg$value, c("best replicate spectrum",
        "consensus spectrum"))
    expect_identical(agg$group, c(NA, "1"))
    ## Group [1] is the replicate information, group [2] the similar spectrum
    ## and its dot product, groups [3] to [5] three related spectra.
    expect_identical(cv$group[cv$accession == "MS:1003070"], "1")
    expect_identical(cv$group[cv$accession == "MS:1003304"], "2")
    expect_identical(unique(cv$group[cv$accession == "MS:1003261"]),
        c("3", "4", "5"))
    expect_identical(cvParameter(cv, "MS:1003297"), "18,19,20")
    expect_identical(cvParameter(cv, "MS:1003304"), "0.89")
    ## A USI is a value and is never split at a colon.
    usi <- cvParameter(cv, "MS:1003264")
    expect_identical(usi, paste0("mzspec:PXD000561:Adult_Frontalcortex_",
        "bRP_Elite_85_f09:scan:17555"))
    ## A repeatable attribute keeps all three of its instances, in the order of
    ## the file, which is what the wide table has to collapse.
    ## The keys of the file are 234 and 235, but 'i' is a position within the
    ## library, which is what ?spectraCv says and what spectraIds() maps.
    charges <- spectraCv(lib, i = 2L, inherit = FALSE)
    expect_identical(spectraIds(lib)[[2L]], 234L)
    expect_identical(cvParameter(charges, "MS:1000633", all = TRUE),
        c("2", "3", "4"))
    expect_identical(cvParameter(charges, "MS:1000633"), "4")
    expect_identical(nrow(spectraTable(lib)), 3L)
    ## Two m/z values, each with its charge state, in two groups: the wide
    ## table can only keep one of them, the long one keeps both.
    two35 <- spectraCv(lib, i = 3L, inherit = FALSE)
    expect_identical(spectraIds(lib)[[3L]], 235L)
    expect_identical(two35$group, c("1", "1", "2", "2"))
    expect_identical(two35$value[c(two35$accession == "MS:1003208")],
        c("702.1033", "702.3078"))
    expect_identical(nrow(spectraTable(lib)), 3L)
})

test_that("section 4.1.10: analytes, interpretations and their members", {
    lib <- read_fixture("spec-4-1-10-analytes.mzSpecLib.txt")
    expect_identical(spectraIds(lib), 1:4)
    ## The four examples of the section: one analyte and one interpretation,
    ## three analytes and two mixture interpretations, the same with the
    ## intensity fractions of the members, and one analyte with no
    ## interpretation at all.
    expect_identical(vapply(lib$spectra, function(sp) length(sp$analytes),
        integer(1)), c(1L, 3L, 3L, 1L))
    expect_identical(vapply(lib$spectra, function(sp)
        length(sp$interpretations), integer(1)), c(1L, 2L, 2L, 0L))
    ## The analytes of the second spectrum are the three peptides of the
    ## example, in the order of the file.
    expect_identical(cvParameter(analyteCv(lib, i = 2L, inherit = FALSE),
        "MS:1003270", all = TRUE)[[1L]],
        "DSDDVPM[Oxidation]VLVGNKCDLAAR/2")
    expect_identical(nrow(analyteCv(lib, i = 2L, inherit = FALSE)), 3L)
    ## An interpretation says which analytes it is about, by their keys, and
    ## how confident it is.
    ic <- interpretationCv(lib, i = 3L, inherit = FALSE)
    expect_identical(ic$accession, rep(c("MS:1003163", "MS:1002357"), 2L))
    expect_identical(ic$value, c("1,2", "0.974", "3", "0.937"))
    ## The members of the interpretations carry the assigned intensity
    ## fractions: two for the first interpretation, one for the second.
    mc <- interpretationMemberCv(lib, i = 3L)
    expect_identical(nrow(mc), 3L)
    expect_identical(mc$value, c("0.287", "0.423", "0.512"))
    expect_identical(mc$name, rep("assigned intensity fraction", 3L))
    expect_false(any(mc$inherited))
    ## The fourth spectrum has an analyte and no interpretation, which is a
    ## spectrum with a sequence assignment the library does not vouch for.
    expect_identical(nrow(analyteCv(lib, i = 4L, inherit = FALSE)), 2L)
    expect_identical(nrow(suppressWarnings(interpretationCv(lib, i = 4L))),
        0L)
    ## The wide tables hold one row per analyte and per interpretation.
    expect_identical(nrow(analyteTable(lib)), 8L)
    expect_identical(nrow(interpretationTable(lib)), 5L)
})

test_that("sections 4.1.16 and 4.1.17: the peak examples and the chimeric one",
    {
    ## The four peak list variants of section 4.1.16 are four spectra here,
    ## because one spectrum MUST have rows of one width; see test-peaks.R for
    ## what each of their tables holds.
    lib <- read_fixture("spec-4-1-16-peak-attributes.mzSpecLib.txt")
    expect_identical(length(lib), 4L)
    expect_identical(nrow(peakColumns(lib)), 12L)
    expect_identical(unique(peakColumns(lib)$accession),
        c("MS:1003279", "MS:1003285", "MS:1003286"))
    ## The chimeric spectrum of section 4.1.17 is one spectrum with two
    ## analytes and the peak list of both of them together.
    chim <- read_fixture("spec-4-1-17-chimeric.mzSpecLib.txt")
    expect_length(chim, 1L)
    expect_length(chim[[1L]]$analytes, 2L)
    expect_identical(cvParameter(spectraCv(chim, i = 1L, inherit = FALSE),
        "MS:1003061"), "AILINFIDR/2+HLAEISLLEQSFVK/3")
    ## Two analytes, each with its notation and its theoretical mass.
    expect_identical(nrow(analyteCv(chim, i = 1L, inherit = FALSE)), 4L)
    expect_identical(cvParameter(analyteCv(chim, i = 1L, inherit = FALSE),
        "MS:1001117", all = TRUE), c("1074.6306", "1613.8897"))
    expect_identical(cvParameter(analyteCv(chim, i = 1L, inherit = FALSE),
        "MS:1003270", all = TRUE), c("AILINFIDR/2", "HLAEISLLEQSFVK/3"))
    expect_identical(nrow(spectraPeaks(chim, i = 1L)), 76L)
    ## The name of the spectrum and the USI of the example are one and the
    ## same string of two peptides joined with a plus sign.
    usi <- cvParameter(spectraCv(chim, i = 1L, inherit = FALSE), "MS:1003063")
    expect_true(grepl("AILINFIDR/2\\+HLAEISLLEQSFVK/3$", usi))
})
