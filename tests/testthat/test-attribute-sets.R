## Attribute sets: the definitions returned by attributeSets() and the four
## precedence rules of sections 4.1.4 and 4.1.11, as they apply to a spectrum
## that claims one or more sets.
##
## Two fixtures are used. "attribute-sets.mzSpecLib.txt" is written for these
## tests and holds one spectrum per precedence rule; "attribute-sets-groups.mzSpecLib.txt"
## holds the rule for a term that occurs more than once in the same context.
## Both use only accessions and term names copied verbatim from the example
## libraries of the HUPO-PSI mzSpecLib specification v1.0 (Apache License 2.0).

## The fixture with one spectrum per rule:
## 1 nothing claimed, 2 FIRST+SECOND, 3 SECOND+FIRST, 4 FIRST+SECOND+FIRST,
## 5 two local values (one of them equal to the inherited one), 6 a claim of a
## set that was never defined, 7 a claim of a set that defines nothing, 8 a
## local value reached through a set, 9 a local value in a group.
sets_lib <- function()
    read_fixture("attribute-sets.mzSpecLib.txt")

## Spectrum 1 of that fixture is the baseline: everything "all" gives, and
## nothing else.
baseline <- function() {
    lib <- sets_lib()
    spectraCv(lib, i = 1L)
}

test_that("attributeSets() returns the definitions, not the inheritance", {
    lib <- sets_lib()
    res <- attributeSets(lib)
    expect_identical(colnames(res), c("type", "set", "group", "accession",
        "name", "value", "value_accession"))
    expect_identical(nrow(res), 12L)
    ## The same set name in two kinds is two sets, and the table says so.
    expect_identical(n_sets(res), 6L)
    expect_identical(unique(res$type), c("Spectrum", "Analyte"))
    ## Nothing is resolved here: <Spectrum=1> claims no set, yet the "all"
    ## definition is in the table whether a spectrum uses it or not.
    expect_identical(res$set[res$type == "Analyte"], "all")
    expect_identical(attributeSets(lib, type = "Analyte"),
        res[res$type == "Analyte", , drop = FALSE])
    expect_identical(nrow(attributeSets(lib,
        type = c("Spectrum", "Interpretation"))), 11L)
    expect_error(attributeSets(lib, type = "Spectrun"), "'arg' should be one")
    expect_error(attributeSets(1), "'object' must be a 'mzspeclib_library'")
    ## A library without any definition.
    expect_identical(nrow(attributeSets(mzspeclib())), 0L)
    expect_identical(colnames(attributeSets(mzspeclib())), colnames(res))
})

test_that("a declared set without a single attribute is still declared", {
    lib <- sets_lib()
    res <- attributeSets(lib)
    empty <- which(res$set == "EMPTY_SET")
    expect_length(empty, 1L)
    expect_identical(res$type[[empty]], "Spectrum")
    expect_true(all(is.na(unlist(res[empty, c("group", "accession", "name",
        "value", "value_accession")]))))
    ## Spectrum 7 claims exactly that set, which is not an error, and gains
    ## nothing but the claim itself.
    cv <- suppressWarnings(spectraCv(lib, i = 7L))
    expect_identical(nrow(cv), 7L)
    expect_false(any(cv$inherited & cv$accession == "MS:1003212"))
    expect_identical(cvParameter(cv, "MS:1003212"), "EMPTY_SET")
    ## The JSON serialization writes the same thing as an empty list.
    json <- read_fixture("json-attribute-set-claims.mzSpecLib.json")
    jsonRow <- attributeSets(json)
    expect_true(any(is.na(jsonRow$accession) & jsonRow$set == "declaredEmpty"))
})

test_that("\"all\" is inherited without being claimed", {
    lib <- sets_lib()
    one <- baseline()
    expect_identical(nrow(spectraCv(lib, i = 1L, inherit = FALSE)), 1L)
    expect_identical(nrow(one), 7L)
    expect_identical(sum(one$inherited), 6L)
    ## What the inherited rows are.
    expect_identical(cvParameter(one, "MS:1000511"), "2")
    expect_identical(cvParameter(one, "MS:1003072"), "observed spectrum")
    expect_identical(cvParameter(one, "MS:1000045"), "39.0")
    expect_identical(cvParameter(one, "UO:0000000"), "electronvolt")
    ## Without inheritance the same spectrum has one line and nothing else.
    local <- spectraCv(lib, i = 1L, inherit = FALSE)
    expect_identical(local$accession, "MS:1003061")
    expect_false(any(local$inherited))
    ## The column that says which layer a row came from is the only difference
    ## the accessor makes.
    plain <- one
    plain$inherited <- NULL
    local2 <- local
    local2$inherited <- NULL
    expect_identical(local2, reset_rows(plain[plain$accession ==
        "MS:1003061", , drop = FALSE]))
})

test_that("the last referenced set wins, and the earlier ones are dropped", {
    ## Section 4.1.11: claimed sets "are not accumulative", the last mention
    ## of an accession replaces what an earlier set contributed.
    lib <- sets_lib()
    ## FIRST defines the origin type as a decoy spectrum, SECOND as an
    ## observed one; "all" also says observed.
    expect_identical(cvParameter(spectraCv(lib, i = 1L), "MS:1003072"),
        "observed spectrum")
    expect_identical(cvParameter(spectraCv(lib, i = 2L), "MS:1003072"),
        "observed spectrum")
    expect_identical(cvParameter(spectraCv(lib, i = 3L), "MS:1003072"),
        "shuffle-and-reposition decoy spectrum")
    ## FIRST, SECOND, FIRST: the LAST mention of FIRST is what counts, so the
    ## second set loses even though it was named in between.
    expect_identical(cvParameter(spectraCv(lib, i = 4L), "MS:1003072"),
        "shuffle-and-reposition decoy spectrum")
    ## Replaced means replaced: exactly one row for the accession, never the
    ## two values of the two sets side by side.
    for (k in 2:4) {
        cv <- spectraCv(lib, i = k)
        expect_length(cvParameter(cv, "MS:1003072", all = TRUE), 1L)
    }
    ## A term only the winning set defines is gone from the winner's row set,
    ## and the claims themselves are kept as the section wrote them.
    expect_identical(cvParameter(spectraCv(lib, i = 2L), "MS:1000044"),
        "beam-type collision induced dissociation")
    expect_identical(cvParameter(spectraCv(lib, i = 4L), "MS:1003212",
        all = TRUE), c("FIRST", "SECOND", "FIRST"))
    ## The wide view collapses the same three claims into one cell. Spectrum 6
    ## of the fixture claims an undefined set, so the whole table warns.
    expect_warning(tab <- spectraTable(lib, columns = "MS:1003212"),
        "NEVER_DEFINED")
    expect_identical(tab[["MS:1003212"]][[4L]], "FIRST;SECOND;FIRST")
    expect_identical(tab[["MS:1003212"]][c(1L, 5L, 9L)],
        rep(NA_character_, 3L))
})

test_that("a value of the section itself shadows the sets, whatever it is", {
    lib <- sets_lib()
    ## ms level "3" locally against "2" in "all", and a local origin type that
    ## is equal to the inherited value: one row either way, never two.
    five <- spectraCv(lib, i = 5L)
    expect_identical(nrow(spectraCv(lib, i = 5L, inherit = FALSE)), 2L)
    expect_length(cvParameter(five, "MS:1000511", all = TRUE), 1L)
    expect_length(cvParameter(five, "MS:1003072", all = TRUE), 1L)
    expect_identical(cvParameter(five, "MS:1000511"), "3")
    expect_identical(cvParameter(five, "MS:1003072"), "observed spectrum")
    expect_identical(sum(five$inherited), 4L)
    ## A local value in a group keeps the group: the collision energy is the
    ## section's own, its unit still comes from "all" with the designator.
    nine <- spectraCv(lib, i = 9L)
    expect_identical(cvParameter(nine, "MS:1000045"), "45.0")
    expect_identical(cvParameter(nine, "UO:0000000"), "electronvolt")
    group <- nine$group[nine$accession %in% c("MS:1000045", "UO:0000000")]
    inherited <- nine$inherited[nine$accession %in% c("MS:1000045",
        "UO:0000000")]
    expect_identical(group, c("1", "1"))
    expect_identical(sort(inherited), c(FALSE, TRUE))
    expect_true(nine$inherited[nine$accession == "UO:0000000"])
    expect_false(nine$inherited[nine$accession == "MS:1000045"])
    ## The shadowing is by accession, not by value: "all" contributes nothing
    ## for a term the section names, so an inherited value can never be told
    ## apart from a local one by looking at the value alone.
    expect_false(any(nine$inherited & nine$accession == "MS:1000045"))
})

test_that("a term repeated in one context is inherited as one group", {
    lib <- read_fixture("attribute-sets-groups.mzSpecLib.txt")
    expect_length(lib$issues, 0L)
    ## "all" and TWO both define the term twice, ONE once.
    all <- attributeSets(lib)
    expect_identical(sum(all$accession == "MS:1000543" & all$set == "all"), 2L)
    ## One local instance replaces BOTH inherited instances (4.1.11: the
    ## instances of one accession within one context are inseparable).
    one <- spectraCv(lib, i = 1L)
    expect_length(cvParameter(one, "MS:1000543", all = TRUE), 1L)
    expect_identical(cvParameter(one, "MS:1000543"), "square root transform")
    ## TWO then ONE: the winner defines one instance, so the spectrum has one.
    two <- spectraCv(lib, i = 2L)
    expect_length(cvParameter(two, "MS:1000543", all = TRUE), 1L)
    expect_identical(cvParameter(two, "MS:1000543"), "square root transform")
    ## ONE then TWO: the winner defines two, and both arrive together.
    three <- spectraCv(lib, i = 3L)
    expect_identical(cvParameter(three, "MS:1000543", all = TRUE),
        c("deisotoping", "rank transform"))
    ## The wide view of the two cases, without and with the separator.
    tab <- spectraTable(lib, columns = "MS:1000543")
    expect_identical(tab[[3L]], c("square root transform",
        "square root transform", "deisotoping;rank transform",
        "deisotoping;rank transform"))
    expect_identical(spectraTable(lib, columns = "MS:1000543",
        collapse = NA)[[3L]],
        c("square root transform", "square root transform",
        "rank transform", "rank transform"))
    ## Nothing but "all" claimed: both instances arrive.
    expect_length(cvParameter(spectraCv(lib, i = 4L), "MS:1000543",
        all = TRUE), 2L)
})

test_that("a claim of a set that was never defined warns and changes nothing", {
    lib <- sets_lib()
    six <- suppressWarnings(spectraCv(lib, i = 6L))
    expect_warning(cv <- spectraCv(lib, i = 6L),
        "claims of undefined Spectrum attribute set\\(s\\): NEVER_DEFINED")
    ## Everything "all" offers is still there, the claim is kept as written.
    expect_identical(cv, six)
    expect_identical(nrow(cv), 7L)
    expect_identical(cvParameter(cv, "MS:1003212"), "NEVER_DEFINED")
    expect_identical(cvParameter(cv, "MS:1000511"), "2")
    ## The warning comes from the resolver, not from the reader: reading the
    ## file is silent, and asking not to be warned is allowed.
    expect_silent(read_fixture("attribute-sets.mzSpecLib.txt"))
    expect_silent(mzspeclib:::resolve_cv(spectraCv(lib, i = 6L,
        inherit = FALSE), attributeSets(lib), warn = FALSE))
    ## The other spectra of the same fixture do not warn.
    expect_silent(spectraCv(lib, i = 7L))
    expect_silent(spectraTable(sets_lib(), i = 1:5))
})

test_that("sets of one kind never reach a section of another kind", {
    lib <- sets_lib()
    ## <AttributeSet Analyte=all> says the organism is human; the spectra do
    ## not inherit that, the analytes do.
    expect_false("MS:1001467" %in% spectraCv(lib, i = 1L)$accession)
    an <- analyteCv(lib, i = 1L)
    expect_true(any(an$accession == "MS:1001467" & an$inherited))
    expect_identical(cvParameter(an, "MS:1001467"), "9606")
    expect_identical(nrow(analyteCv(lib, i = 1L, inherit = FALSE)), 1L)
    ## The tables agree with the long form.
    expect_true(any(analyteTable(lib)[["MS:1001467"]] == "9606"))
    ## The resolver is told which kind of section it is resolving.
    expect_identical(nrow(mzspeclib:::resolve_cv(spectraCv(lib, i = 1L,
        inherit = FALSE), attributeSets(lib), type = "Analyte")), 2L)
})

test_that("the resolver works on a table that is not a whole library", {
    ## resolve_cv() is what spectraCv() calls; the four rules are checked
    ## against it directly, so that a broken accessor cannot hide a broken
    ## rule.
    sets <- data.frame(type = "Spectrum", set = c("all", "all", "B"),
        group = NA_character_, accession = c("MS:1000511", "MS:1003072",
            "MS:1000511"), name = c("ms level", "spectrum origin type",
            "ms level"), value = c("2", "observed spectrum", "1"),
        value_accession = c(NA_character_, "MS:1003073", NA_character_),
        stringsAsFactors = FALSE)
    cv <- mzspeclib:::cv_parse_lines(c(
        "MS:1003212|library attribute set name=B",
        "MS:1003061|spectrum name=one"))
    res <- mzspeclib:::resolve_cv(cv, sets)
    expect_identical(cvParameter(res, "MS:1000511"), "1")
    expect_identical(cvParameter(res, "MS:1003072"), "observed spectrum")
    ## No sets at all, and a section with no attributes at all.
    expect_identical(mzspeclib:::resolve_cv(cv, mzspeclib()$attributeSets), cv)
    ## A section with no attributes of its own still gets "all".
    expect_identical(nrow(mzspeclib:::resolve_cv(
        mzspeclib()$header, sets)), 2L)
    ## An empty value in the section still shadows the set.
    empty <- mzspeclib:::cv_parse_lines(c(
        "MS:1000511|ms level=",
        "MS:1003212|library attribute set name=B"))
    expect_identical(cvParameter(mzspeclib:::resolve_cv(empty, sets),
        "MS:1000511"), "")
})

test_that("clusters can claim attribute sets too", {
    ## Section 4.1.4 allows <AttributeSet Cluster=name> next to the three
    ## kinds of section a spectrum nests. The library of section 4.1.5 does
    ## not use them, so this is checked against an inline file whose terms are
    ## copied from inst/extdata/example.mzSpecLib.txt.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>",
        "MS:1003186|library format version=1.0",
        "",
        "<AttributeSet Cluster=all>",
        "MS:1003320|spectrum cluster size=6",
        "",
        "<Cluster=1>",
        "MS:1003268|spectrum cluster member keys=1,6,23,63,89",
        "",
        "<Spectrum=1>",
        "MS:1000511|ms level=2"), file)
    lib <- read_mzspeclib(file)
    expect_identical(attributeSets(lib)$type, "Cluster")
    expect_length(lib$issues, 0L)
    cv <- clusterCv(lib)
    expect_identical(cv$accession, c("MS:1003320", "MS:1003268"))
    expect_identical(cv$inherited, c(TRUE, FALSE))
    expect_identical(cvParameter(clusterCv(lib, inherit = FALSE),
        "MS:1003320"), character())
    ## A cluster is not a spectrum: the "all" of a Cluster set is not offered
    ## to spectra.
    expect_false("MS:1003320" %in% spectraCv(lib, i = 1L)$accession)
})
