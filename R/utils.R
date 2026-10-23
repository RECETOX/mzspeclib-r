## Internal helpers. Nothing here is exported.

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L ||
    (length(x) == 1L && is.na(x))) y else x

## Name a vector without pulling in stats::setNames().
set_names <- function(x, nm) {
    names(x) <- nm
    x
}

## The first n elements, for the messages that quote a few offending lines and
## would otherwise need utils::head() - and with it a second Imports entry.
.first <- function(x, n) x[seq_len(min(n, length(x)))]

## Empty data.frame with the given column names and character storage.
.empty_df <- function(columns) {
    res <- data.frame(matrix(character(), nrow = 0L,
        ncol = length(columns),
        dimnames = list(NULL, columns)))
    res
}

## Columns of a controlled vocabulary parameter table (long form). Every CV
## section of a file (`<mzSpecLib>`, `<Spectrum>`, `<Analyte>`, ...) is
## represented with exactly these columns.
cv_columns <- function()
    c("group", "accession", "name", "value", "value_accession")

## Rows of a CV table as an unnamed list of characters, for building wide
## tables without repeated `[` subsetting.
cv_unname <- function(x) unname(as.list(x))

## Bind a list of one-row data.frames into a table with a fixed column set.
## `extra` columns are appended to the front (e.g. the section id columns).
rbind_rows <- function(rows, columns) {
    if (!length(rows))
        return(.empty_df(columns))
    res <- do.call(rbind, rows)
    res <- res[, columns, drop = FALSE]
    rownames(res) <- NULL
    res
}

## Append rows to a table, ignoring empty input.
add_rows <- function(table, rows) {
    if (length(rows) == 0L)
        return(table)
    res <- if (!nrow(table)) do.call(rbind, rows) else
        rbind(table, do.call(rbind, rows))
    rownames(res) <- NULL
    res
}

## Column bind that keeps row count consistent.
safe_cbind <- function(...) {
    args <- list(...)
    lengths <- vapply(args, function(x) nrow(x) %||% length(x), integer(1))
    if (length(unique(lengths)) > 1L)
        stop("incompatible number of rows in 'cbind'", call. = FALSE)
    do.call(cbind, args)
}

## Type-guessing for the wide *Table() accessors. Deliberately naive: it
## looks only at the values, never at a controlled vocabulary, so that
## results never depend on which ontology copy is available (see the
## package's "Design decisions" documentation).
coerce_values <- function(x) {
    if (!is.character(x))
        return(x)
    not_na <- !is.na(x) & nzchar(x)
    if (!any(not_na))
        return(x)
    val <- x[not_na]
    if (all(val %in% c("TRUE", "FALSE")))
        return(as.logical(x))
    num <- suppressWarnings(as.numeric(val))
    if (all(!is.na(num))) {
        if (all(grepl("^-?[0-9]+$", val)))
            return(suppressWarnings(as.integer(x)))
        return(num[match(x, val)])
    }
    x
}

## Collapse repeated values of one attribute within one entity.
collapse_values <- function(x, collapse = ";") {
    if (is.na(collapse))
        return(x[length(x)])
    paste(x, collapse = collapse)
}

## Ensure 'x' is a non-empty single file name.
.check_file <- function(file, what = "file") {
    if (!is.character(file) || length(file) != 1L || is.na(file) ||
        !nzchar(file))
        stop("'", what, "' must be a single file name", call. = FALSE)
    file
}

## A file name ending in .gz is read through a connection.
.open_lines <- function(file, encoding = "UTF-8") {
    con <- if (grepl("\\.gz$", file, ignore.case = TRUE))
        gzfile(file, "r") else file(file, "r")
    on.exit(close(con))
    readLines(con, encoding = encoding, warn = FALSE)
}

## The collection of parse problems of one read.
##
## This is an environment, not a list, and that is load-bearing: the readers
## hand the state to every helper they call, and R passes a list by value, so an
## addendum made deep down would vanish again with the local copy. An
## environment is the one mutable object a helper can add to without the readers
## having to thread a return value through every level of the call graph.
.issue_state <- function() {
    state <- new.env(parent = emptyenv())
    state$issues <- character()
    state$reported <- character()
    state
}

## Report a parse problem. Kept in one place so the reader can collect
## problems instead of failing on the first one. A missing state is tolerated:
## a helper may also be called from a context that has no interest in the
## complaints.
.issue <- function(state, ...) {
    if (is.null(state))
        return(invisible(NULL))
    state$issues <- c(state$issues, paste0(...))
    invisible(NULL)
}
