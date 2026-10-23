## Controlled vocabulary parameters: the one grammar the whole format is
## built on, plus the small helpers that read and write it.
##
## Grammar (mzSpecLib v1.0, section 4.1.2):
##
##     [group]MS:1000894|retention time=42.5
##     [2]MS:1000044|dissociation method=MS:1000422|beam-type CID
##     NCBITaxon:9606|taxonomy: scientific name=Homo sapiens
##     MS:1001200|confidence=
##
## i.e. an optional integer group designator in square brackets, a subject
## "accession|name", a first "=" (the subject never contains one), and an
## object which is either a free value or, when the subject has no data type,
## another "accession|name" term.

## Regexes are kept at package level: they are used for every line of every
## file and compiling them once is measurably worth it.
.re_group <- "^\\[([0-9]+)\\][ \t]*"
## A CV-valued object: "MS:1000422|name", "UO:0000266|name",
## "NCBITaxon:9606|name". USI values ("mzspec:PXD000561:...:scan:1") must NOT
## match, hence the requirement of digits directly after the colon.
.re_cv_value <- "^[A-Za-z][A-Za-z0-9]*:[0-9]+\\|"

## Parse one CV line. Returns a named character vector (one row) or NULL when
## the line is not a CV parameter.
cv_parse_line <- function(line) {
    group <- NA_character_
    if (grepl(.re_group, line)) {
        group <- sub("^\\[([0-9]+)\\].*$", "\\1", line)
        line <- sub(.re_group, "", line)
    }
    bar <- regexpr("|", line, fixed = TRUE)
    if (bar < 0L)
        return(NULL)
    accession <- substring(line, 1L, bar - 1L)
    rest <- substring(line, bar + 1L)
    if (!nzchar(accession) || !grepl(":", accession, fixed = TRUE))
        return(NULL)
    ## Names that contain "=" must be quoted (section 4.1.2); such a name is
    ## read up to its closing quote so that the first "=" *outside* the quotes
    ## remains the subject/object delimiter.
    if (startsWith(rest, "\"")) {
        close <- regexpr("\"", substring(rest, 2L), fixed = TRUE)
        if (close < 0L)
            return(NULL)
        close <- close + 1L
        name <- substring(rest, 1L, close)
        if (substring(rest, close + 1L, close + 1L) != "=")
            return(NULL)
        value <- substring(rest, close + 2L)
    }
    else {
        eq <- regexpr("=", rest, fixed = TRUE)
        if (eq < 0L)
            return(NULL)
        name <- substring(rest, 1L, eq - 1L)
        value <- substring(rest, eq + 1L)
    }
    value_accession <- NA_character_
    if (grepl(.re_cv_value, value)) {
        vb <- regexpr("|", value, fixed = TRUE)
        value_accession <- substring(value, 1L, vb - 1L)
        value <- substring(value, vb + 1L)
    }
    c(group = group, accession = accession, name = name,
      value = value, value_accession = value_accession)
}

## Parse many CV lines, dropping the ones that are not parameters and
## reporting them.
cv_parse_lines <- function(lines, state = NULL, where = "section") {
    rows <- lapply(lines, cv_parse_line)
    ok <- vapply(rows, function(x) !is.null(x), logical(1))
    if (!all(ok))
        .issue(state, "ignoring ", sum(!ok), " unparsable line(s) in ", where,
            ": ", paste(.first(lines[!ok], 3L), collapse = " | "))
    rows <- rows[ok]
    if (!length(rows))
        return(.empty_df(cv_columns()))
    res <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
    res[, cv_columns(), drop = FALSE]
}

## Re-render one CV row the way the text serialization wants it. Inverse of
## cv_parse_line() by construction, which is what makes a read/write round
## trip byte-stable for metadata.
cv_format_row <- function(row) {
    ## A term without a value is written with an empty object
    ## ("MS:1001200|confidence="), never with the text "NA": the JSON
    ## serialization has no empty string to lose on the way, so this is where
    ## an absent value has to turn back into an empty one. The name is
    ## required by the grammar, but a document can lack it.
    value <- row[["value"]]
    if (is.na(value))
        value <- ""
    name <- row[["name"]]
    if (is.na(name))
        name <- ""
    va <- row[["value_accession"]]
    if (!is.na(va))
        value <- paste0(va, "|", value)
    head <- if (is.na(row[["group"]]))
        "" else paste0("[", row[["group"]], "]")
    paste0(head, row[["accession"]], "|", row[["name"]], "=", value)
}

cv_format_rows <- function(table) {
    if (!nrow(table))
        return(character())
    vapply(seq_len(nrow(table)),
        function(i) cv_format_row(table[i, , drop = FALSE]), character(1))
}

#' Read a Single Controlled Vocabulary Value
#'
#' `cvParameter()` extracts the value(s) of one controlled vocabulary term
#' from a CV parameter table as returned by [libraryCv()], [spectraCv()] or
#' [attributeSets()]. It matches on the accession alone, never on the term
#' name, because the same accession can legitimately appear with different
#' names in real files.
#'
#' @param cv `data.frame` with the CV parameter columns `group`, `accession`,
#'   `name`, `value` and `value_accession`.
#' @param accession `character(1)` accession to look up, e.g.
#'   `"MS:1000043"`. Terms from any ontology (`MS:`, `UO:`, `NCBITaxon:`, ...)
#'   are supported.
#' @param value `logical(1)` whether to return the value (`TRUE`, the
#'   default) or the name of the CV term the value points to. For terms whose
#'   object is not a CV term this returns `NA_character_` if `value = FALSE`.
#' @param all `logical(1)` whether to return every instance of a repeatable
#'   term or only the last one, which is the instance that takes precedence
#'   according to the specification (section 4.1.11). The default is `FALSE`,
#'   because a caller that asks for one term usually wants the value that
#'   counts; `all = TRUE` is for the rare term that is genuinely repeated.
#'
#' @return `character` with the value(s), or `character(0)` if the term is
#'   absent.
#'
#' @author Helge Hecht
#'
#' @examples
#' cv <- data.frame(group = c(NA, "1"),
#'     accession = c("MS:1000043", "UO:0000000"),
#'     name = c("intensity unit", "unit"),
#'     value = c("percent of base peak times 100", "electronvolt"),
#'     value_accession = c("MS:1000905", "UO:0000266"),
#'     stringsAsFactors = FALSE)
#' cvParameter(cv, "MS:1000043")
#' cvParameter(cv, "MS:1000043", value = FALSE)
#' cvParameter(cv, "MS:1000123")
#'
#' @export
cvParameter <- function(cv, accession, value = TRUE, all = FALSE) {
    if (is.null(cv) || !nrow(cv))
        return(character())
    if (!is.character(accession) || length(accession) != 1L)
        stop("'accession' must be a single string", call. = FALSE)
    idx <- which(cv[["accession"]] == accession)
    if (!length(idx))
        return(character())
    if (!all)
        idx <- idx[length(idx)]
    res <- if (value) cv[["value"]][idx] else cv[["value_accession"]][idx]
    as.character(res)
}
