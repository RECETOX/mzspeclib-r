## The text serialization reader (mzSpecLib v1.0, section 4.1).
##
## The parser works on *regions* rather than lines: the file is split at its
## section lines (`<Spectrum=1>` etc.) and the lines between two section lines
## belong to the section that opened them. That removes the two traps a naive
## line-by-line reader falls into (peak rows losing their spectrum, and the
## library scope silently running into the attribute set definitions), and it
## keeps the whole thing a single pass with vectorised line classification.

#' Read an mzSpecLib File
#'
#' `read_mzspeclib()` reads a spectral library in the mzSpecLib format
#' (HUPO-PSI mzSpecLib v1.0) in either of its two normative serializations:
#' the plain text format (`.mzSpecLib.txt`) and the JSON format (`.json`).
#' The returned [mzspeclib()] object holds the file as it was written:
#' controlled vocabulary parameters keep their accession, name, value and
#' group designator, and nothing is dropped because the package does not
#' know the term.
#'
#' The serialization is chosen by `format`; `"auto"` (the default) uses the
#' file extension and, failing that, whether the first line starts with `{`.
#' Files ending in `.gz` are read through a connection.
#'
#' @param file `character(1)`. The file to read.
#' @param format `character(1)`: `"auto"`, `"text"` or `"json"`.
#' @param encoding `character(1)` passed to [readLines()] for the text
#'   serialization.
#' @param strict `logical(1)` whether deviations from the specification that
#'   still leave the file readable (a missing `MS:1003186|library format
#'   version`, a duplicated spectrum key, an attribute set defined after the
#'   first spectrum) should be raised as a warning in addition to being
#'   collected in the object's `issues` element. Defaults to `FALSE`.
#'
#' @return A [mzspeclib()] object.
#'
#' @section Comments and other things that are not kept:
#' Comments (`#` in the first column) are ignored, as the specification
#' requires (section 4.1.18: they are "generally NOT transcribed to other
#' serializations"). Empty lines are ignored. A version tag beside the section
#' line - `<mzSpecLib 1.0>`, which some producers write although section 4.1.1
#' states the line as exactly `<mzSpecLib>` - is read as the library section all
#' the same and reported in `issues`, because [write_mzspeclib()] has only the
#' conformant line to write; the format version of a library is its
#' `MS:1003186` parameter, never the section line. The order of clusters and
#' spectra is preserved within each kind, but a file that interleaves
#' `<Cluster>` and `<Spectrum>` sections comes back with the clusters first;
#' [write_mzspeclib()] writes them in that canonical order too.
#'
#' @section Numbers:
#' Values of controlled vocabulary parameters are kept exactly as written, as
#' `character`. Only peak `mz` and `intensity` are converted to `double`;
#' a peak row whose m/z or intensity cannot be parsed is reported in
#' `issues` and its row is kept with `NA`. Nothing is type-converted on the
#' basis of the ontology, so results do not depend on which PSI-MS version is
#' installed (see `?mzspeclib-package`).
#'
#' @author Helge Hecht
#'
#' @seealso [mzspeclib()] for the object, [write_mzspeclib()] for writing,
#'   [spectraTable()] and [spectraPeaks()] for the tabular views.
#'
#' @examples
#' read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",
#'     package = "mzspeclib"))
#'
#' @export
read_mzspeclib <- function(file, format = c("auto", "text", "json"),
    encoding = "UTF-8", strict = FALSE) {
    .check_file(file)
    if (!file.exists(file))
        stop("file does not exist: ", file, call. = FALSE)
    format <- match.arg(format)
    if (format == "auto")
        format <- .detect_format(file, encoding)
    res <- if (format == "json")
        parse_json(file, encoding = encoding)
    else parse_text(.open_lines(file, encoding), file = file)
    res$file <- normalizePath(file, mustWork = FALSE)
    if (strict && length(res$issues))
        warning("read ", basename(file), " with ", length(res$issues),
            " issue(s): ", paste(.first(res$issues, 5L),
            collapse = " | "), call. = FALSE)
    res
}

.detect_format <- function(file, encoding) {
    if (grepl("\\.json$", file, ignore.case = TRUE))
        return("json")
    lines <- tryCatch(.open_lines(file, encoding), error = function(e)
        character())
    lines <- lines[nzchar(trimws(lines))]
    if (length(lines) && startsWith(trimws(lines[[1]]), "{"))
        return("json")
    "text"
}

## Section line: "<name>" or "<name=qualifier>" or "<name qualifier>" or
## "<AttributeSet Spectrum=name>". group(1) is the section name, group(2)
## everything after it.
.re_section <- "^<([A-Za-z]+)[ \t]*([^>]*)>$"
## The qualifier of an attribute set, e.g. "Spectrum=all".
.re_set_qual <- "^([A-Za-z]+)[ \t]*=[ \t]*(.*)$"

## Split the file into regions: one entry per section line, with the lines it
## owns. Returns list(name, qualifier, type, start, end) as parallel vectors.
.text_regions <- function(lines) {
    if (length(lines))
        lines <- sub("^\ufeff", "", lines)
    lines <- sub("\r$", "", lines)
    isSection <- grepl(.re_section, lines) & !startsWith(lines, "#")
    pos <- which(isSection)
    if (!length(pos))
        return(list(lines = lines, name = character(), qualifier =
            character(), type = character(), value = character(),
            start = integer(), end = integer()))
    parsed <- regmatches(lines[pos], regexec(.re_section, lines[pos]))
    name <- vapply(parsed, function(x) x[[2L]], character(1))
    rest <- trimws(vapply(parsed, function(x) x[[3L]], character(1)))
    ## "<Spectrum=1>", "<Analyte=2>": qualifier after "=".
    qualifier <- ifelse(startsWith(rest, "="), trimws(sub("^=", "", rest)),
        "")
    ## "<AttributeSet Spectrum=all>": type and name of the set.
    hasType <- grepl(.re_set_qual, rest)
    type <- ifelse(hasType,
        sub(.re_set_qual, "\\1", rest), "")
    value <- ifelse(hasType, sub(.re_set_qual, "\\2", rest), "")
    ## The content of region k runs from its section line (exclusive) to the
    ## line before the next section line (inclusive).
    list(lines = lines, name = name, qualifier = qualifier, type = type,
        value = value, start = pos, end = c(pos[-1L] - 1L, length(lines)))
}

## Lines of a region that carry content: no blanks, no comments.
.region_content <- function(lines, from, to) {
    if (to < from)
        return(character())
    x <- lines[from:to]
    x <- x[nzchar(trimws(x)) & !startsWith(x, "#")]
    x
}

## The text parser itself. `lines` is the content of the file, already read.
parse_text <- function(lines, file = NA_character_) {
    state <- .issue_state()
    rg <- .text_regions(lines)
    n <- length(rg$name)
    if (!n || rg$name[[1]] != "mzSpecLib")
        .issue(state, "the file does not start with the required ",
            "'<mzSpecLib>' line", if (n) paste0(" (found '<", rg$name[[1]],
            if (nzchar(rg$qualifier[[1]]))
                paste0("=", rg$qualifier[[1]]) else "", ">')") else
            " (no section line at all)")
    header <- list()
    attributeSets <- list()
    clusters <- list()
    spectra <- list()
    ## Indices of the region's content lines, resolved lazily per region.
    content <- function(k)
        .region_content(rg$lines, rg$start[[k]] + 1L, rg$end[[k]])
    currentSpectrum <- 0L
    seenSpectrum <- FALSE
    keys <- integer()
    for (k in seq_len(n)) {
        nm <- rg$name[[k]]
        qu <- rg$qualifier[[k]]
        cn <- content(k)
        if (nm == "mzSpecLib") {
            ## Section 4.1.1 states the line as exactly '<mzSpecLib>', and real
            ## producers write a version tag beside it anyway. The tag decides
            ## nothing here - the format version is the MS:1003186 parameter,
            ## not the section line - so the section is read as the header and
            ## the tag is reported rather than kept: the writer has only the
            ## conformant line to write.
            line <- trimws(rg$lines[[rg$start[[k]]]])
            ## Whitespace inside the brackets is typesetting, anything else is
            ## content the specification does not have.
            if (!identical(gsub("[[:space:]]", "", line), "<mzSpecLib>"))
                .issue(state, "the library section line '", line, "' states ",
                    "more than the '<mzSpecLib>' line of section 4.1.1; the ",
                    "section is read as the library header, and the writer ",
                    "emits '<mzSpecLib>'")
            header <- c(header, list(cn))
        }
        else if (nm == "AttributeSet") {
            ## A line which is not an attribute set definition at all is
            ## reported as that and nothing else, whether it comes before the
            ## first spectrum or after it.
            if (!nzchar(rg$type[[k]]) || !nzchar(rg$value[[k]])) {
                .issue(state, "ignoring malformed attribute set line '",
                    rg$lines[[rg$start[[k]]]], "'")
                next
            }
            if (seenSpectrum)
                .issue(state, "attribute set '", rg$value[[k]],
                    "' is defined after the first spectrum, which the ",
                    "specification forbids (section 4.1.4); it is read ",
                    "anyway")
            attributeSets <- c(attributeSets, list(list(
                type = rg$type[[k]], set = rg$value[[k]], lines = cn)))
        }
        else if (nm == "Cluster") {
            clusters <- c(clusters, list(list(id = .section_key(qu, k,
                "Cluster", state), lines = cn)))
        }
        else if (nm == "Spectrum") {
            seenSpectrum <- TRUE
            id <- .section_key(qu, k, "Spectrum", state)
            if (!is.na(id) && id %in% keys)
                .issue(state, "duplicated library spectrum key ", id,
                    " (section 4.1.6 requires unique keys)")
            keys <- c(keys, id)
            currentSpectrum <- currentSpectrum + 1L
            spectra[[currentSpectrum]] <- list(id = id, lines = list(cn),
                analytes = list(), interpretations = list(),
                peaks = character())
        }
        else if (nm %in% c("Analyte", "Interpretation",
                "InterpretationMember")) {
            if (!currentSpectrum) {
                .issue(state, "'", nm, "' section without a preceding ",
                    "<Spectrum> section; its ", length(cn), " line(s) ",
                    "were dropped")
                next
            }
            node <- list(id = .section_key(qu, k, nm, state), lines = cn)
            sp <- spectra[[currentSpectrum]]
            if (nm == "Analyte") {
                sp$analytes <- c(sp$analytes, list(node))
            }
            else if (nm == "Interpretation") {
                sp$interpretations <- c(sp$interpretations, list(node))
            }
            else {
                if (!length(sp$interpretations)) {
                    .issue(state, "<InterpretationMember> without an ",
                        "<Interpretation> section (invalid per section ",
                        "4.1.9); its lines were dropped")
                    next
                }
                li <- length(sp$interpretations)
                sp$interpretations[[li]]$members <-
                    c(sp$interpretations[[li]]$members, list(node))
            }
            spectra[[currentSpectrum]] <- sp
        }
        else if (nm == "Peaks") {
            if (!currentSpectrum) {
                .issue(state, "'<Peaks>' without a preceding <Spectrum> ",
                    "section; ", length(cn), " peak row(s) were dropped")
                next
            }
            sp <- spectra[[currentSpectrum]]
            sp$peaks <- c(sp$peaks, list(cn))
            spectra[[currentSpectrum]] <- sp
        }
        else {
            .issue(state, "unknown section '", rg$lines[[rg$start[[k]]]],
                "' at line ", rg$start[[k]], "; its ", length(cn),
                " content line(s) were dropped")
        }
    }
    ## Anything before the first section line.
    preamble <- if (length(rg$start) && rg$start[[1]] > 1L)
        .region_content(rg$lines, 1L, rg$start[[1]] - 1L)
    else character()
    if (length(preamble)) {
        .issue(state, length(preamble), " line(s) before the first ",
            "section line were read as library attributes")
        header <- c(list(preamble), header)
    }
    nComments <- sum(startsWith(rg$lines, "#"))
    headerCv <- cv_parse_lines(unlist(header, use.names = FALSE), state,
        "the library header")
    ## Section 4.1.1 makes the term mandatory, and its absence is one of the
    ## deviations read_mzspeclib() promises to collect in 'issues'. A file
    ## which does not even begin with '<mzSpecLib>' is already reported for
    ## that, and is not a library whose header could be missing a term.
    if (n && rg$name[[1]] == "mzSpecLib" &&
        !length(cvParameter(headerCv, "MS:1003186")))
        .issue(state, "the library header has no ",
            "MS:1003186|library format version, which the specification ",
            "requires (section 4.1.1)")
    sets <- .attribute_sets_table(attributeSets, state)
    clusters <- lapply(clusters, function(cl)
        list(id = cl$id, cv = cv_parse_lines(cl$lines, state,
            paste0("<Cluster=", cl$id, ">"))))
    spectra <- lapply(spectra, function(sp) {
        cv <- cv_parse_lines(unlist(sp$lines, use.names = FALSE), state,
            paste0("<Spectrum=", sp$id %||% "?", ">"))
        analytes <- lapply(sp$analytes, function(an) list(id = an$id,
            cv = cv_parse_lines(an$lines, state,
                paste0("<Analyte=", an$id %||% "?", ">"))))
        interpretations <- lapply(sp$interpretations, function(it) {
            members <- lapply(it$members %||% list(), function(mm)
                list(id = mm$id, cv = cv_parse_lines(mm$lines, state,
                    paste0("<InterpretationMember=", mm$id %||% "?",
                        ">"))))
            list(id = it$id,
                cv = cv_parse_lines(it$lines, state,
                    paste0("<Interpretation=", it$id %||% "?", ">")),
                members = members)
        })
        peaks <- .parse_peaks(unlist(sp$peaks, use.names = FALSE), state,
            sp$id)
        spectrum(id = sp$id, cv = cv, analytes = analytes,
            interpretations = interpretations, peaks = peaks)
    })
    res <- mzspeclib(header = headerCv, spectra = spectra,
        attributeSets = sets, clusters = clusters, file = file,
        issues = state$issues)
    attr(res, "comments") <- nComments
    res
}

## A section key: "<Spectrum=12>". Non-numeric keys are kept as NA with an
## issue, because every accessor and the writer need integers.
.section_key <- function(qualifier, k, what, state) {
    if (!nzchar(qualifier)) {
        .issue(state, "<", what, "> section without a key")
        return(NA_integer_)
    }
    res <- suppressWarnings(as.integer(qualifier)[1L])
    if (is.na(res))
        .issue(state, "non-numeric key '", qualifier, "' in <", what,
            ">")
    res
}

## Attribute set definitions as one long table.
.attribute_sets_table <- function(sets, state) {
    if (!length(sets))
        return(.empty_df(attribute_set_columns()))
    out <- lapply(sets, function(set) {
        cv <- cv_parse_lines(set$lines, state,
            paste0("<AttributeSet ", set$type, "=", set$set, ">"))
        if (!nrow(cv))
            return(.empty_set_row(set$type, set$set))
        cbind(data.frame(type = set$type, set = set$set,
            stringsAsFactors = FALSE), cv)
    })
    out <- out[!vapply(out, is.null, logical(1))]
    if (!length(out))
        return(.empty_df(attribute_set_columns()))
    res <- do.call(rbind, out)[, attribute_set_columns(), drop = FALSE]
    rownames(res) <- NULL
    res
}

## Peak rows: tab separated, 2 or more columns (section 4.1.13/4.1.16).
## Column 3 is the annotation, columns 4+ additional peak attributes. The
## number of columns is per spectrum; short rows are padded with NA.
.parse_peaks <- function(rows, state, key) {
    if (!length(rows))
        return(NULL)
    parts <- strsplit(rows, "\t", fixed = TRUE)
    ## strsplit() drops a trailing empty field, so the number of fields of a
    ## row is the number of separators in it plus one - "100.0\t1\ta\t" is a
    ## row of four fields whose fourth is empty, and it has to be read as one.
    width <- max(vapply(rows, function(row)
        lengths(regmatches(row, gregexpr("\t", row, fixed = TRUE))) + 1L,
        integer(1)))
    if (width < 2L) {
        .issue(state, "<Peaks> of spectrum ", key %||% "?", " has rows ",
            "with fewer than 2 columns; the peak table was dropped")
        return(NULL)
    }
    pad <- function(x) {
        length(x) <- width
        x
    }
    mat <- vapply(parts, pad, character(width))
    mz <- suppressWarnings(as.numeric(mat[1L, ]))
    intensity <- suppressWarnings(as.numeric(mat[2L, ]))
    bad <- which(is.na(mz) | is.na(intensity))
    if (length(bad))
        .issue(state, spectrum_prefix(key), length(bad), " peak row(s) ",
            "with a non-numeric m/z or intensity; the row(s) are kept ",
            "with NA (first offending row: '",
            gsub("\t", "<TAB>", rows[[bad[[1L]]]]), "')")
    res <- data.frame(mz = mz, intensity = intensity,
        stringsAsFactors = FALSE)
    if (width >= 3L) {
        annotation <- mat[3L, ]
        annotation[!nzchar(annotation)] <- NA_character_
        res$annotation <- annotation
    }
    if (width >= 4L) {
        for (j in 4:width) {
            extra <- mat[j, ]
            extra[!nzchar(extra)] <- NA_character_
            res[[paste0("X", j)]] <- extra
        }
    }
    res
}

spectrum_prefix <- function(key)
    if (is.null(key) || is.na(key)) "" else paste0("spectrum ", key, ": ")
