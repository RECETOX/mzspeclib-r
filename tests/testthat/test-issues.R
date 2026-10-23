## The issues an mzSpecLib file can raise: what the reader collects, how it
## says it, and what strict = TRUE makes of the collection.

## The hand written fixture of deviations, one per line where it matters.
issues_lib <- function()
    read_fixture("issues.mzSpecLib.txt")

test_that("a file of deviations is still read, and says everything it saw", {
    lib <- issues_lib()
    ## Twelve complaints, in the order the reader came across them.
    expect_length(lib$issues, 12L)
    ## The missing '<mzSpecLib>' line of the fixture comes first, because the
    ## reader looks for it before it reads anything else, and it says which
    ## section line it found instead; the two complaints of the file's end come
    ## in the order the reader met them, the leading lines last.
    expect_identical(lib$issues[[1L]], paste0("the file does not start with ",
        "the required '<mzSpecLib>' line (found '<Cluster=1>')"))
    expect_identical(grep("before the first section line", lib$issues), 11L)
    expect_identical(grep("unknown section", lib$issues), 10L)
    ## The library is there despite all of it.
    expect_length(lib, 4L)
    expect_identical(nrow(libraryCv(lib)), 2L)
    expect_identical(spectraIds(lib), c(1L, 1L, NA_integer_, NA_integer_))
    expect_identical(nrow(attributeSets(lib)), 1L)
    expect_length(clusters(lib), 1L)
    ## Nothing was added by the accessors, and reading the tables twice gives
    ## the same complaints and no new ones.
    for (fun in c("libraryCv", "spectraCv", "analyteCv", "interpretationCv",
            "clusterCv", "attributeSets", "spectraIds", "peakColumns",
            "cvLosses"))
        suppressWarnings(get(fun)(lib))
    expect_length(lib$issues, 12L)
    expect_identical(lib$issues, issues_lib()$issues)
})

test_that("every deviation has its own issue, worded the same way every time", {
    lib <- issues_lib()
    expect_issue(lib, "the file does not start with the required ")
    expect_issue(lib, "'Analyte' section without a preceding <Spectrum> ")
    expect_issue(lib, "'InterpretationMember' section without a preceding")
    expect_issue(lib, "'<Peaks>' without a preceding <Spectrum> section; 1 ")
    expect_issue(lib, "duplicated library spectrum key 1 \\(section 4\\.1\\.6 ")
    expect_issue(lib, "non-numeric key 'x' in <Spectrum>")
    expect_issue(lib, "<Spectrum> section without a key")
    expect_issue(lib, "attribute set 'LATE' is defined after the first ")
    expect_issue(lib, "ignoring malformed attribute set line '<AttributeSet Spectrum>'")
    expect_issue(lib, "unknown section '<Bogus=1>' at line 44; its 1 content ")
    expect_issue(lib, "ignoring 1 unparsable line\\(s\\) in <Spectrum=1>: this ")
    ## One issue per deviation: the duplicated key is reported once per
    ## offending section, the unknown section once, the unparsable line once.
    expect_length(grep("duplicated", lib$issues), 1L)
    expect_length(grep("unknown section", lib$issues), 1L)
    expect_length(grep("unparsable", lib$issues), 1L)
    ## An attribute set that is defined too late is still read, which is what
    ## its issue says; it is only never inherited, because no spectrum claims
    ## it (section 4.1.4).
    expect_identical(attributeSets(lib)$set, "LATE")
    expect_identical(attributeSets(lib)$accession, "MS:1000511")
    expect_length(suppressWarnings(cvParameter(spectraCv(lib),
        "MS:1000511")), 0L)
})

test_that("a file without the required section line names what it found", {
    write <- function(lines) {
        file <- tempfile(fileext = ".mzSpecLib.txt")
        writeLines(lines, file)
        read_mzspeclib(file)
    }
    ## Nothing but CV lines: no section line at all, and the message says so.
    lib <- write(c("MS:1003186|library format version=1.0"))
    expect_identical(lib$issues, paste0("the file does not start with the ",
        "required '<mzSpecLib>' line (no section line at all)"))
    expect_length(lib, 0L)
    ## Without a single section line there is no section the lines could belong
    ## to, so nothing is read; the file with at least one section line does
    ## read its leading lines as library attributes (test-sections.R).
    expect_identical(nrow(libraryCv(lib)), 0L)
    ## A section line is there, only not the required one: the message has to
    ## name the section that was found, and nothing else.
    cluster <- write(c("<Cluster=1>",
        "MS:1003320|spectrum cluster size=6"))
    expect_length(cluster$issues, 1L)
    expect_identical(cluster$issues, paste0("the file does not start with ",
        "the required '<mzSpecLib>' line (found '<Cluster=1>')"))
})

test_that("one malformed line is one issue", {
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<AttributeSet Spectrum>", "MS:1000511|ms level=2", "<Spectrum=1>",
        "MS:1003061|library spectrum name=one"), file)
    lib <- read_mzspeclib(file)
    expect_length(lib$issues, 1L)
    expect_identical(lib$issues[[1L]],
        "ignoring malformed attribute set line '<AttributeSet Spectrum>'")
    file2 <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1003061|library spectrum name=one",
        "<AttributeSet Spectrum>", "MS:1000511|ms level=2"), file2)
    late <- read_mzspeclib(file2)
        expect_length(late$issues, 1L)
})

test_that("strict = TRUE turns the collection into one warning", {
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003186|library format version=1.0",
        "<Spectrum=1>", "MS:1000511|ms level=2", "<Spectrum=1>",
        "MS:1000511|ms level=2"), file)
    ## By default a reader that can read the file says nothing (?read_mzspeclib,
    ## @param strict).
    expect_silent(read_mzspeclib(file))
    lib <- read_mzspeclib(file)
    expect_length(lib$issues, 1L)
    ## With strict the same issues come as one warning, and the object is the
    ## same object.
    expect_warning(strict <- read_mzspeclib(file, strict = TRUE),
        "read .+ with 1 issue\\(s\\): duplicated library spectrum key 1")
    expect_identical(strict$issues, lib$issues)
    ## At most five of them are named, the count is the true one.
    lines <- c("<mzSpecLib>", "MS:1003186|library format version=1.0")
    for (k in 1:7)
        lines <- c(lines, "<Spectrum=1>", "MS:1000511|ms level=2")
    writeLines(lines, file)
    expect_warning(seven <- read_mzspeclib(file, strict = TRUE),
        "with 6 issue\\(s\\): ")
    expect_length(seven$issues, 6L)
    warn <- NULL
    suppressWarnings(withCallingHandlers(read_mzspeclib(file, strict = TRUE),
        warning = function(w) {
            warn <<- conditionMessage(w)
            invokeRestart("muffleWarning")
        }))
    expect_identical(length(gregexpr("duplicated library spectrum key",
        warn)[[1]]), 5L)
    ## A file without anything to complain about stays silent under strict.
    expect_silent(read_mzspeclib(example_path(), strict = TRUE))
    expect_silent(read_fixture("canonical.mzSpecLib.txt"))
})

test_that("a missing library format version is a deviation the reader survives",
    {
    ## Section 4.1.1: "The first CV term MUST be the mzSpecLib format
    ## specification version number", and ?read_mzspeclib names "a missing
    ## MS:1003186|library format version" among the deviations that are
    ## "collected in the object's issues element" when strict = TRUE. The
    ## reader is the one that sees the file.
    file <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(c("<mzSpecLib>", "MS:1003187|library identifier=x",
        "<Spectrum=1>", "MS:1000511|ms level=2"), file)
    lib <- read_mzspeclib(file)
        expect_issue(lib, "no MS:1003186\\|library format version")
    expect_warning(read_mzspeclib(file, strict = TRUE),
        "with 1 issue\\(s\\)")
    ## What is true today: the writer of the same library does warn, in both
    ## serializations, and says nothing when warn = FALSE.
    out <- tempfile(fileext = ".mzSpecLib.txt")
    expect_warning(write_mzspeclib(lib, out),
        "the header has no MS:1003186\\|library format version")
    expect_silent(write_mzspeclib(lib, out, warn = FALSE))
})

test_that("the issue collector concatenates and survives a missing state", {
    state <- mzspeclib:::.issue_state()
    expect_identical(state$issues, character())
    expect_identical(state$reported, character())
    ## The message is the concatenation of the arguments, which is how the
    ## reader writes its sentences.
    mzspeclib:::.issue(state, "unknown section '<Bogus=1>' at line ", 44L,
        "; its 1 content line(s) were dropped")
    expect_identical(state$issues,
        paste0("unknown section '<Bogus=1>' at line 44; its 1 content ",
            "line(s) were dropped"))
    mzspeclib:::.issue(state, "second complaint")
    expect_length(state$issues, 2L)
    ## A helper that is called without a state has nowhere to complain to and
    ## says so in no way at all.
    expect_null(mzspeclib:::.issue(NULL, "anyone there"))
})

test_that("a claim of an undefined attribute set warns, but is not an issue", {
    ## The precedence rules of section 4.1.4 can only be applied when the
    ## tables are read, so the complaint is a warning of the accessor and not
    ## something the reader knew while parsing (?attributeSets).
    lib <- read_fixture("attribute-sets.mzSpecLib.txt")
    expect_length(lib$issues, 0L)
    expect_warning(cv <- spectraCv(lib, i = 6L),
        "claims of undefined Spectrum attribute set\\(s\\): NEVER_DEFINED")
    expect_length(lib$issues, 0L)
    ## The warning changes nothing about the rows it came with.
    expect_identical(cv, suppressWarnings(spectraCv(lib, i = 6L)))
    ## warn = FALSE of the resolver itself is the silent form of the same call,
    ## and it is the same table (?attributeSets mentions the option).
    silent <- mzspeclib:::resolve_cv(spectraCv(lib, i = 6L, inherit = FALSE),
        attributeSets(lib), "Spectrum", warn = FALSE)
    expect_silent(silent)
    expect_identical(nrow(silent), nrow(cv))
})
