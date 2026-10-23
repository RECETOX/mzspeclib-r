## The differential test against the reference implementation of the format:
## the python package mzspeclib, which reads the libraries of the specification
## repository and validates them against the same profiles the specification
## names. No test of this package alone can establish what is compared here,
## because both sides of the comparison would be this package's own reading of
## the format: the counts a reader of the reference implementation gets from a
## library, and the violations its validator reports for a library this package
## wrote.
##
## WHY NOTHING HERE RUNS UNLESS MZSPECLIB_PYTHON IS SET
##
## The reference implementation resolves every CV term against the PSI-MS and
## the unit ontology, and it fetches both from purl.obolibrary.org in every
## fresh process, because the on-disk cache of psims is switched off in it:
## measured 33.5 s for the PSI-MS ontology and 49.9 s for both together, before
## any file is read. Which ontology answers also decides the wording of a
## violation, so a run of it is neither fast nor reproducible. Nothing here is
## therefore attempted on a guess, and in particular not on a default path,
## unless the variable names an interpreter:
##
##     MZSPECLIB_PYTHON=/path/to/venv/bin/python \
##         Rscript -e 'testthat::test_local(filter = "reference-python")'
##
## One python process is asked about every library of the comparison, since a
## second process would pay for the ontologies again, and they are the whole
## runtime of these tests: about a minute for the 32 files of the comparison,
## against a measured 2 min 12 s that the console script needs for one of them.
## The script is dirname(python)/mzspeclib; the package cannot be run as a
## module ("python -m mzspeclib" says that mzspeclib has no __main__), which is
## why the driver below calls the library the script itself calls.
##
## The violation inventories are compared as sets of messages measured in the
## same process, never against wording written down here, for the reason above:
## the term names in a message come from whatever ontology the server served.

## The driver of the python half, as the python source it has to be. It is
## spelled out here rather than shipped as a file of the package because it is
## part of the documentation of these tests: it says which entry point of the
## reference implementation is compared against, and what it reports.
python_driver_source <- function()
    c('#!/usr/bin/env python3',
        '"""The python half of the differential test in the R file of this',
        'name.',
        '',
        '    driver.py <library> ...',
        '',
        'For every library it prints, tab separated, the numbers a user of the',
        'reference implementation gets from the file',
        '',
        '    COUNTS  <library>  <spectra>  <peaks>',
        '',
        'and the violations of the validator chain that the console script',
        'builds for "mzspeclib validate -p gold" (mzspeclib/tools/cli.py)',
        '',
        '    BEGIN      <library>',
        '    VIOLATION  <library>  <level>  <message>',
        '    END        <library>',
        '',
        'or, for a file the reference implementation does not read at all,',
        '',
        '    ERROR      <library>  <Exception>: <message>',
        '',
        'The chain is built anew for every library although the libraries are',
        'read in one process, because the error log of a chain cannot be',
        'emptied again: the setter of it in mzspeclib/validate/validator.py',
        'discards the value it is given, so a chain that was used once would',
        'report the violations of every earlier library as well.',
        '"""',
        'import sys',
        '',
        '## A tab without a backslash, so that these lines stay readable in',
        '## the R file that holds them.',
        'SEP = chr(9)',
        '_cv_cache = {}',
        '',
        '',
        'def emit(tag, path, *rest):',
        '    print(SEP.join([tag, path] + [str(x) for x in rest]), flush=True)',
        '',
        '',
        'def memoize_cv():',
        '    """Load every controlled vocabulary at most once per process.',
        '',
        '    load_cv of mzspeclib.ontology caches per validator, and the chain',
        '    is built per library, so without this every library would fetch',
        '    the ontologies again. The vocabularies are only read by the',
        '    validators, never modified by them.',
        '    """',
        '    from mzspeclib import ontology',
        '',
        '    fetch = ontology._VocabularyResolverMixin.load_cv',
        '',
        '    def load_cv(self, name):',
        '        if name not in _cv_cache:',
        '            _cv_cache[name] = fetch(self, name)',
        '        self.controlled_vocabularies[name] = _cv_cache[name]',
        '        return _cv_cache[name]',
        '',
        '    ontology._VocabularyResolverMixin.load_cv = load_cv',
        '',
        '',
        'def load(path):',
        '    """A library, the way the console script opens one."""',
        '    from mzspeclib import MemoryIndex, SpectrumLibrary',
        '',
        '    return SpectrumLibrary(filename=path, index_type=MemoryIndex)',
        '',
        '',
        'def counts(path):',
        '    """What len() of the library and its spectra report."""',
        '    lib = load(path)',
        '    emit("COUNTS", path, len(lib), sum(len(s.peak_list) for s in lib))',
        '',
        '',
        'def violations(path):',
        '    """The gold profile violations, as the console script prints them.',
        '',
        '    The script logs them at WARN and MAY ones at DEBUG, which is why',
        '    they do not all appear on its stderr; the error log of the chain',
        '    holds all of them and deduplicates them itself.',
        '    """',
        '    from mzspeclib.validate import get_validator_for',
        '    from mzspeclib.validate import load_default_validator',
        '',
        '    chain = load_default_validator()',
        '    chain |= get_validator_for("gold")',
        '    emit("BEGIN", path)',
        '    chain.validate_library(load(path))',
        '    for error in chain.error_log:',
        '        emit("VIOLATION", path, error.requirement_level.name,',
        '             error.message)',
        '    emit("END", path)',
        '',
        '',
        'def main(paths):',
        '    memoize_cv()',
        '    for path in paths:',
        '        try:',
        '            counts(path)',
        '            violations(path)',
        '        except Exception as err:',
        '            emit("ERROR", path, "%s: %s" % (type(err).__name__, err))',
        '    emit("DONE", "reference-python")',
        '',
        '',
        'main(sys.argv[1:])')

## The driver in a tempfile, since python wants to read it from a file.
python_driver <- function() {
    file <- tempfile(fileext = ".py")
    writeLines(python_driver_source(), file)
    normalizePath(file)
}

## What the one run of the reference implementation answered, kept between the
## tests of this file. See ref_run() for why there is only ever one run.
ref_cache <- new.env(parent = emptyenv())

## The exit status of a system2() run. The status attribute is only there when
## the command did not end well, so its absence means 0.
ref_status <- function(out) {
    status <- attr(out, "status")
    if (is.null(status)) 0L else as.integer(status)
}

## Run the reference implementation with these arguments. The arguments are
## quoted by hand because system2() passes them to the shell as they are, and
## a python one-liner with a quote in it does not survive that.
ref_system2 <- function(python, args) {
    suppressWarnings(system2(python, shQuote(args), stdout = TRUE,
        stderr = TRUE))
}

## The reference implementation, or a skip that says what is missing. Every
## test of this file goes through here, so the whole file skips at once. The
## version is asked for because it is part of any answer about a violation:
## which term names a message holds depends on the implementation and on the
## ontology it resolved.
python_or_skip <- function() {
    py <- Sys.getenv("MZSPECLIB_PYTHON", "")
    skip_if_not(nzchar(py), paste0("set MZSPECLIB_PYTHON to the reference ",
        "implementation's python to run the differential tests"))
    skip_if_not(file.exists(py) || nzchar(Sys.which(py)),
        paste("MZSPECLIB_PYTHON is not an executable that is there:", py))
    code <- paste("import importlib.metadata as md;",
        "print(md.version('mzspeclib'))")
    out <- ref_system2(py, c("-c", code))
    skip_if_not(identical(ref_status(out), 0L), paste(
        "MZSPECLIB_PYTHON does not import mzspeclib:", py, "|",
        paste(out, collapse = " | ")))
    res <- list(python = py, version = if (length(out)) out[[length(out)]]
        else NA_character_)
    if (!isTRUE(ref_cache$announced)) {
        message("reference implementation: mzspeclib ", res$version, " at ",
            py)
        ref_cache$announced <- TRUE
    }
    res
}

## The libraries of the comparison: every text fixture of the package, the
## library the package ships and, when the repository of the specification is
## there, the two smallest of its real libraries. Those two are the ones of the
## seven examples that the reference implementation reads in well under a
## second and that are not transcriptions of an example of the specification,
## so that a library of a real producer is part of the comparison as well; the
## larger ones add runtime and nothing else. See ref_run() for why every one of
## them is asked in a single python process.
ref_libraries <- function() {
    fixtures <- list.files(fixture(""), "^.*[.]mzSpecLib[.]txt$",
        full.names = TRUE)
    extra <- character()
    if (dir.exists(spec_repo()))
        extra <- reference_path(c("spice.mzSpecLib.txt",
            "DIA-NN/phl004_canonical_sall_pv_plasma.head.diann.mzSpecLib.txt"))
    extra <- extra[file.exists(extra)]
    data.frame(file = normalizePath(c(fixtures, example_path(), extra)),
        kind = c(rep("fixture", length(fixtures)), "example",
            rep("reference", length(extra))), stringsAsFactors = FALSE)
}

## The file as the reference implementation can be given it, which a fixture
## with provenance comments in front of its <mzSpecLib> line cannot be. Its
## text backend treats a line as an attribute line and not as a comment: a '#'
## line inside the header raises "ValueError: Malformed attribute line ..." in
## _parse_header_from_stream of mzspeclib/backends/text.py, and comment lines
## in front of the <mzSpecLib> line leave the header empty, which stops the
## validator with StopIteration. Section 4.1.18 of the specification permits a
## comment line in the text serialization, so this is a limit of the reference
## implementation, and the comments stay where they are: they are the
## provenance of a transcription and another test of this package reads them.
## The copy is named *.mzSpecLib.txt because that is what it is; reading it
## does not depend on the name.
ref_stripped <- function(file) {
    lines <- readLines(file, encoding = "UTF-8", warn = FALSE)
    lines <- sub("\r$", "", lines)
    out <- tempfile(fileext = ".mzSpecLib.txt")
    writeLines(lines[!startsWith(lines, "#")], out)
    normalizePath(out)
}

## The libraries of the comparison with, for each of them, the file as the
## package holds it, the copy without comment lines and the file this package
## writes from what it read, together with the counts this package's accessors
## report for it.
ref_subjects <- function() {
    one <- function(file, kind) {
        lib <- suppressWarnings(read_mzspeclib(file))
        out <- tempfile(fileext = ".mzSpecLib.txt")
        ## The one thing the writer has to say about these libraries is for
        ## the fixture whose spectra carry no library spectrum key, and
        ## test-write-round-trip.R is where that warning is tested.
        suppressWarnings(write_mzspeclib(lib, out))
        data.frame(file = normalizePath(file), kind = kind,
            stripped = ref_stripped(file), written = normalizePath(out),
            spectra = length(lib),
            peaks = sum(vapply(all_peaks(lib), nrow, integer(1))),
            stringsAsFactors = FALSE)
    }
    lib <- ref_libraries()
    res <- do.call(rbind, Map(one, lib$file, lib$kind))
    rownames(res) <- NULL
    res
}

## What the driver answered. Lines that are not of the protocol stay in $out so
## that a failure can be read from the report of the test alone.
ref_parse <- function(out) {
    rows <- strsplit(out, "\t", fixed = TRUE)
    tag <- vapply(rows, function(r) if (length(r) >= 2L) r[[1L]] else "",
        character(1))
    ## A list rather than a named character vector, so that a lookup of a file
    ## that is not in it gives NULL instead of an error.
    counts <- list()
    errors <- list()
    violations <- list()
    done <- logical(0)
    for (r in rows[tag == "COUNTS"])
        counts[[r[[2L]]]] <- c(as.integer(r[[3L]]), as.integer(r[[4L]]))
    for (r in rows[tag == "ERROR"])
        errors[[r[[2L]]]] <- r[[3L]]
    for (r in rows[tag == "VIOLATION"]) {
        ## Only the first three fields are protocol; what follows is the
        ## message, which is free text and may hold a tab of its own.
        message <- if (length(r) > 4L)
            paste(r[seq(4L, length(r))], collapse = "\t") else r[[4L]]
        key <- paste(r[[3L]], message, sep = ": ")
        violations[[r[[2L]]]] <- c(violations[[r[[2L]]]], key)
    }
    if (any(tag == "DONE"))
        done <- TRUE
    list(counts = counts, errors = errors, violations = violations,
        done = isTRUE(done))
}

## Everything the reference implementation has to say about every library of
## the comparison, from exactly one python process, asked once per test run.
## The ontologies are what a run costs, not the libraries, so the three tests
## below share one answer instead of starting one process each.
ref_run <- function() {
    if (!is.null(ref_cache$run))
        return(ref_cache$run)
    ref <- python_or_skip()
    subject <- ref_subjects()
    ## The driver is not made executable, so the interpreter of the reference
    ## implementation runs it. The stripped copy and the file this package
    ## wrote from a library are asked one after the other, so that the two
    ## answers of a pair come from the same validator chain of the same process.
    files <- as.character(unlist(t(subject[, c("stripped", "written")])))
    args <- c(python_driver(), files)
    res <- ref_system2(ref$python, args)
    ref_cache$run <- c(list(ref = ref, subject = subject,
        cmd = paste(c(ref$python, shQuote(args)), collapse = " "),
        driver_cmd = paste(c(ref$python, shQuote(args[[1L]])),
            collapse = " "),
        status = ref_status(res), out = res), ref_parse(res))
    ref_cache$run
}

## The command that repeats the reference implementation's answer for one
## subject of the comparison. The whole run lists 32 tempfile names, which no
## reader of a failed test wants, while this names the file it is about.
ref_cmd <- function(run, s)
    paste(run$driver_cmd, shQuote(c(s$stripped, s$written)))

## The one thing every test here needs before it compares anything: that the
## python process answered its protocol to the end. It fails with the command,
## so that the run can be repeated by hand.
ref_expect_run <- function(run) {
    said <- paste(run$out[seq_len(min(40L, length(run$out)))],
        collapse = " || ")
    expect_identical(run$status, 0L, info = paste("the reference",
        "implementation failed; the command was:", run$cmd, "||", said))
    expect_true(run$done, info = paste("the reference implementation did",
        "not answer the protocol to the end; the command was:", run$cmd, "||",
        said))
}

## The files of the comparison the reference implementation does not read at
## all, with the exception it dies with. Both reasons are its own behaviour and
## not a deviation of this package from the format:
##
##   "No spectrum name" is raised by create_index of mzspeclib/backends/text.py
##   for a <Spectrum> section without MS:1003061|library spectrum name. The
##   specification makes that term optional - it occurs exactly once in
##   mzSpecLib_specification_v1.0.pdf, in an example - and the validator of the
##   reference implementation has no rule for it either. The transcriptions of
##   the examples of sections 4.1.6, 4.1.10, 4.1.12 and 4.1.16 are what they
##   are, and the hand written fixtures of attribute sets and of ragged peaks
##   follow them.
##
##   The other one is the fixture of deviations, which holds a <Spectrum=x>
##   line on purpose (section 4.1.6 requires the key to be a positive integer).
##   This package reads the file and says what is wrong with it, which is what
##   the next test after this one checks.
ref_refusals <- c(
    "attribute-sets.mzSpecLib.txt" = "ValueError: No spectrum name",
    "attribute-sets-groups.mzSpecLib.txt" = "ValueError: No spectrum name",
    "issues.mzSpecLib.txt" =
        "ValueError: invalid literal for int() with base 10: 'x'",
    "peaks-ragged.mzSpecLib.txt" = "ValueError: No spectrum name",
    "spec-4-1-10-analytes.mzSpecLib.txt" = "ValueError: No spectrum name",
    "spec-4-1-12-attribute-sets.mzSpecLib.txt" =
        "ValueError: No spectrum name",
    "spec-4-1-12-groups.mzSpecLib.txt" = "ValueError: No spectrum name",
    "spec-4-1-16-peak-attributes.mzSpecLib.txt" =
        "ValueError: No spectrum name",
    "spec-4-1-6-spectrum.mzSpecLib.txt" = "ValueError: No spectrum name")

## The files the reference implementation reads, but not whole, with the counts
## it reports for them. The next test says why one file is here and what the
## reference implementation does to lose a spectrum; it is a difference of the
## reference implementation and not of this package, so the count comparison
## above expects these numbers for these files instead of ours, and fails when
## the difference disappears upstream as much as when it grows.
## The first number is the spectra, the second the peaks.
ref_count_loss <- list("canonical.mzSpecLib.txt" = c(1L, 3L))

## The libraries the gold rule comparison of the last test can be made for,
## which are exactly the ones the reference implementation reads. Spelled out
## rather than derived, so that a reference implementation that stops reading
## one of them fails that test instead of quietly comparing one library less.
ref_readable <- c("canonical.mzSpecLib.txt", "crlf-bom.mzSpecLib.txt",
    "spec-4-1-5-cluster.mzSpecLib.txt", "spec-4-1-17-chimeric.mzSpecLib.txt",
    "example.mzSpecLib.txt")
ref_readable_reference <- c("spice.mzSpecLib.txt",
    "phl004_canonical_sall_pv_plasma.head.diann.mzSpecLib.txt")

test_that("the reference implementation counts a text library as we do", {
    run <- ref_run()
    ref_expect_run(run)
    ## The version belongs in the report, because the wording of every
    ## violation of the last test is the reference implementation's and its
    ## ontology's, not something this package fixes.
    expect_true(grepl("^[0-9]+([.][0-9]+)*$", run$ref$version),
        info = paste("the reference implementation at", run$ref$python,
            "reported an unexpected version:", run$ref$version))
    refused <- character()
    for (k in which(run$subject$kind == "fixture")) {
        s <- run$subject[k, ]
        name <- basename(s$file)
        ## A file the reference implementation does not read at all cannot say
        ## anything about counts; it is collected and compared as a set below.
        if (!is.null(run$errors[[s$stripped]])) {
            refused[[name]] <- run$errors[[s$stripped]]
            next
        }
        got <- run$counts[[s$stripped]]
        expect_false(is.null(got), info = paste("the reference",
            "implementation said nothing about", s$stripped,
            "; the command was:", ref_cmd(run, s)))
        ## The counts of the copy without comments, against what the accessors
        ## report for the fixture itself. Comments are not content (section
        ## 4.1.18), so the copy counts as the fixture does here. The files of
        ## ref_count_loss are the exception, and the next test is about them.
        loss <- ref_count_loss[[name]]
        want <- if (is.null(loss)) c(s$spectra, s$peaks) else loss
        expect_identical(got, want, info = paste("for", name, "the reference",
            "implementation reads", paste(got, collapse = " and "),
            "spectra and peaks, expected", paste(want, collapse = " and "),
            ", and this package reads", s$spectra, "and", s$peaks,
            "(ref_count_loss documents the files the reference",
            "implementation does not read whole); the command was:",
            ref_cmd(run, s)))
        ## The file this package wrote from the library has to read as the file
        ## it was written from, as far as the same reader is concerned.
        written <- run$counts[[s$written]]
        expect_identical(written, got, info = paste("for", name,
            "the file this package wrote from it reads differently from the",
            "file it was read from:", paste(written, collapse = "/"), "against",
            paste(got, collapse = "/"), "; the command was:",
            ref_cmd(run, s)))
    }
    ## What it refuses, exactly. A new refusal, a refusal that has gone away
    ## and a different reason all fail here.
    expect_identical(refused[sort(names(refused))],
        ref_refusals[sort(names(ref_refusals))], info = paste("the",
            "reference implementation refused other files, or for other",
            "reasons, than the ones documented in ref_refusals; the command",
            "was:", run$cmd))
    ## The one file it cannot open over a section key that is not a number is a
    ## file this package reads and reports, which is the difference between a
    ## reader and a crash (section 4.1.6: the key MUST be a positive integer).
    expect_issue(read_fixture("issues.mzSpecLib.txt"),
        "non-numeric key 'x' in <Spectrum>")
})

test_that("the reference implementation loses a last spectrum without a name", {
    run <- ref_run()
    ref_expect_run(run)
    k <- which(basename(run$subject$file) == "canonical.mzSpecLib.txt")
    s <- run$subject[k, ]
    got <- run$counts[[s$stripped]]
    ## A scan of the lines of the file, without any reader: two spectra and
    ## five peak rows, which is also what the accessors report. So the two
    ## implementations do not disagree about a matter of interpretation.
    raw <- raw_counts(s$file)
    expect_identical(c(raw$spectra, raw$peaks), c(s$spectra, s$peaks))
    expect_identical(c(raw$spectra, raw$peaks), c(2L, 5L))
    ## The reference implementation reports one spectrum and its peak rows
    ## less. create_index of mzspeclib/backends/text.py raises "No spectrum
    ## name" for a <Spectrum> section without MS:1003061|library spectrum name
    ## when another section follows it, but at the end of the file the same
    ## entry is committed only if it does have a name, without any complaint.
    ## The last spectrum of this file has none, so it and its two peak rows are
    ## silently gone. That is a defect of the reference implementation, not of
    ## this package, and it is pinned here rather than smoothed over: when it
    ## is fixed upstream, these two expectations fail and the difference can be
    ## removed.
    expect_identical(got, ref_count_loss[["canonical.mzSpecLib.txt"]],
        info = paste("for", basename(s$file), "the reference implementation",
            "reads", paste(got, collapse = " and "), "spectra and peaks,",
            "which is not the documented loss of it either; the command was:",
            ref_cmd(run, s)))
    ## and it really is a loss: one spectrum and two peak rows of the file are
    ## in neither the index nor the spectra of the reference implementation.
    expect_identical(c(raw$spectra, raw$peaks) - got, c(1L, 2L))
    ## It is the last spectrum that is lost, and it is the one without a name:
    ## the first section of the file states MS:1003061, the second does not.
    lib <- suppressWarnings(read_fixture("canonical.mzSpecLib.txt"))
    named <- vapply(lib$spectra, function(sp)
        "MS:1003061" %in% sp$cv$accession, logical(1))
    expect_identical(named, c(TRUE, FALSE))
    ## The same spectrum earlier in a file is not lost but fatal, which is why
    ## eight of the fixtures are in ref_refusals above.
    k <- which(basename(run$subject$file) ==
        "spec-4-1-6-spectrum.mzSpecLib.txt")
    expect_identical(run$errors[[run$subject$stripped[[k]]]],
        ref_refusals[["spec-4-1-6-spectrum.mzSpecLib.txt"]], info = paste(
            "a <Spectrum> section without MS:1003061 in the middle of a file",
            "is no longer fatal for the reference implementation; the command",
            "was:", ref_cmd(run, run$subject[k, ])))
})

test_that("what we write breaks the same gold rules as what we read", {
    run <- ref_run()
    ref_expect_run(run)
    expected <- ref_readable
    if (any(run$subject$kind == "reference"))
        expected <- c(expected, ref_readable_reference)
    compared <- character()
    for (k in seq_len(nrow(run$subject))) {
        s <- run$subject[k, ]
        read <- run$violations[[s$stripped]]
        wrote <- run$violations[[s$written]]
        if (is.null(read) || is.null(wrote))
            next
        compared <- c(compared, basename(s$file))
        ## The set of messages, not their order and not how often the chain
        ## happened to log one: the chain of the reference implementation
        ## deduplicates on its own, and the console script that prints the same
        ## messages prints every one of them twice.
        expect_identical(sort(unique(read)), sort(unique(wrote)),
            info = paste("the gold violations of", basename(s$file), "and of",
                basename(s$written), "differ:",
                paste(setdiff(sort(unique(read)), sort(unique(wrote))),
                    collapse = " | "), "vs",
                paste(setdiff(sort(unique(wrote)), sort(unique(read))),
                    collapse = " | "), "; the command was:",
                ref_cmd(run, s)))
        ## A comparison of nothing would pass as well, so a library the
        ## reference implementation validates has to have something to say.
        expect_true(length(unique(read)) >= 1L, info = paste("the reference",
            "implementation found no violation at all in", basename(s$file),
            ", which cannot be compared to anything; the command was:",
            ref_cmd(run, s)))
    }
    ## Which libraries this compared, spelled out.
    expect_setequal(compared, expected)
})
