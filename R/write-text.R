## Writers. The text writer is deliberately a *renderer* of the object graph,
## not a copy of the input file: what it writes is what the object holds, in
## the canonical section order (library attributes, attribute set
## definitions, clusters, spectra). Controlled vocabulary values are written
## exactly as they were read, so a read/write round trip is byte-stable for
## everything except the formatting of peak numbers.

#' Write an mzSpecLib File
#'
#' `write_mzspeclib()` writes a [mzspeclib()] object in the plain text or the
#' JSON serialization.
#'
#' @section What is written, and in which order:
#' The file is rendered from the object: library attributes, then the
#' attribute set definitions, then the clusters, then the spectra with their
#' analytes, interpretations, interpretation members and peak lists. A file
#' that interleaved `<Cluster>` and `<Spectrum>` sections therefore comes back
#' with the clusters grouped in front, which the specification explicitly
#' allows (section 4.1.5). Only the attributes a section *itself* defines are
#' written into it; attributes inherited from an attribute set stay in the
#' set, so a read/write round trip does not expand inheritance into every
#' spectrum.
#'
#' @section Numbers:
#' Values of controlled vocabulary parameters are written verbatim. Peak `mz`
#' and `intensity` are `double` and are rendered with [format()] at `digits`
#' significant digits and never in scientific notation. Because of that a
#' round trip of peak values is only guaranteed to be numerically equal, not
#' byte-identical, unless the input was itself written with the same
#' precision.
#'
#' @param object A [mzspeclib()] object.
#' @param file `character(1)` where to write.
#' @param format `character(1)`: `"auto"` (default, by file extension),
#'   `"text"` or `"json"`.
#' @param digits `integer(1)` significant digits used for peak `mz` and
#'   `intensity`.
#' @param gzip `logical(1)` whether to compress the text serialization with
#'   [gzfile()]. Ignored for JSON.
#' @param warn `logical(1)` whether to warn about violations of the
#'   specification that the object nevertheless allows (no `MS:1003186|library
#'   format version` in the header, spectra without a library spectrum key).
#'
#' @return `file`, invisibly.
#'
#' @author Helge Hecht
#'
#' @seealso [read_mzspeclib()], [mzspeclib()]
#'
#' @examples
#' lib <- read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",
#'     package = "mzspeclib"))
#' out <- tempfile(fileext = ".mzSpecLib.txt")
#' write_mzspeclib(lib, out)
#' identical(spectraIds(read_mzspeclib(out)), spectraIds(lib))
#'
#' @export
write_mzspeclib <- function(object, file, format = c("auto", "text", "json"),
    digits = 15L, gzip = FALSE, warn = TRUE) {
    .check_library(object)
    .check_file(file)
    format <- match.arg(format)
    if (format == "auto")
        format <- if (grepl("\\.json$", file, ignore.case = TRUE))
            "json" else "text"
    if (format == "json")
        return(write_json(object, file, digits = digits, warn = warn))
    lines <- format_text(object, digits = digits, warn = warn)
    con <- if (gzip || grepl("\\.gz$", file, ignore.case = TRUE))
        gzfile(file, "w") else file(file, "w")
    on.exit(close(con))
    writeLines(lines, con)
    invisible(file)
}

## The text renderer, split out so tests can look at the lines without a file.
format_text <- function(object, digits = 15L, warn = TRUE) {
    if (warn && !length(cvParameter(object$header, "MS:1003186")))
        warning("the header has no MS:1003186|library format version, ",
            "which the specification requires (section 4.1.1)",
            call. = FALSE)
    lines <- c("<mzSpecLib>", cv_format_rows(object$header))
    lines <- c(lines, .format_attribute_sets(object$attributeSets))
    lines <- c(lines, .format_clusters(object$clusters))
    keys <- spectraIds(object)
    if (warn && any(is.na(keys)))
        warning(sum(is.na(keys)), " spectrum(s) have no library spectrum ",
            "key; sequential keys are written instead", call. = FALSE)
    keys[is.na(keys)] <- which(is.na(keys))
    for (k in seq_along(object$spectra)) {
        sp <- object$spectra[[k]]
        lines <- c(lines, paste0("<Spectrum=", keys[[k]], ">"),
            cv_format_rows(sp$cv))
        for (an in sp$analytes)
            lines <- c(lines, .format_node(an, "Analyte"))
        for (it in sp$interpretations) {
            lines <- c(lines, .format_node(it, "Interpretation"))
            for (mm in it$members %||% list())
                lines <- c(lines, .format_node(mm, "InterpretationMember"))
        }
        lines <- c(lines, .format_peaks(sp$peaks, digits = digits))
    }
    lines
}

.format_node <- function(node, name) {
    c(if (is.na(node$id)) paste0("<", name, ">")
      else paste0("<", name, "=", node$id, ">"),
      cv_format_rows(node$cv))
}

.format_attribute_sets <- function(sets) {
    if (!nrow(sets))
        return(character())
    out <- character()
    ## One section per (type, set) pair, in the order the file defined them.
    ids <- unique(sets[, c("type", "set"), drop = FALSE])
    for (j in seq_len(nrow(ids))) {
        rows <- sets[sets$type == ids$type[[j]] &
            sets$set == ids$set[[j]] & !is.na(sets$accession), ,
            drop = FALSE]
        out <- c(out, paste0("<AttributeSet ", ids$type[[j]], "=",
            ids$set[[j]], ">"),
            cv_format_rows(rows[, cv_columns(), drop = FALSE]))
    }
    out
}

.format_clusters <- function(clusters) {
    out <- character()
    for (cl in clusters)
        out <- c(out, if (is.na(cl$id)) "<Cluster>"
            else paste0("<Cluster=", cl$id, ">"), cv_format_rows(cl$cv))
    out
}

## Peak rows (section 4.1.13): mz, intensity, annotation, then the additional
## peak attributes. Column 3 is dropped only when there are no additional
## columns and no annotation at all, because the format requires it to be
## present (possibly empty) as soon as a fourth column exists.
.format_peaks <- function(peaks, digits = 15L) {
    if (is.null(peaks) || !nrow(peaks))
        return(character())
    columns <- c("mz", "intensity")
    hasAnnotation <- "annotation" %in% colnames(peaks)
    extra <- setdiff(colnames(peaks), c("mz", "intensity", "annotation"))
    if (hasAnnotation || length(extra))
        columns <- c(columns, "annotation")
    columns <- c(columns, extra)
    rendered <- lapply(columns, function(cn) {
        x <- peaks[[cn]]
        if (is.numeric(x))
            format_number(x, digits)
        else {
            x <- as.character(x)
            x[is.na(x)] <- ""
            x
        }
    })
    body <- do.call(paste, c(rendered, sep = "\t"))
    c("<Peaks>", body)
}

## One number per element: format() over a whole vector would pad everything
## to the width of the widest value.
format_number <- function(x, digits = 15L) {
    vapply(x, function(v) if (is.na(v))
        "" else format(v, digits = digits, trim = TRUE,
            scientific = FALSE), character(1), USE.NAMES = FALSE)
}
