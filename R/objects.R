## The object graph. Deliberately plain lists and data.frames with S3
## classes: the format is a tree of sections, and a class hierarchy would add
## nothing to reading or writing it (see the survey report, section 6,
## "Package shape"). Every element is also directly usable without this
## package, which is what makes the object a safe argument for a downstream
## backend.

## Columns of the attribute set definition table.
attribute_set_columns <- function()
    c("type", "set", cv_columns())

## A set which is declared but empty is recorded by one row with empty CV
## columns, so that claiming it is not mistaken for claiming an undefined set
## (see attributeSets()).
.empty_set_row <- function(type, set)
    data.frame(type = type, set = set, group = NA_character_,
        accession = NA_character_, name = NA_character_,
        value = NA_character_, value_accession = NA_character_,
        stringsAsFactors = FALSE)

## Columns of a peak table.
peaks_columns <- function() c("mz", "intensity")

#' Create an mzSpecLib Library Object
#'
#' `mzspeclib()` creates the object [read_mzspeclib()] returns and that
#' [write_mzspeclib()] writes. It is exported for completeness (to assemble a
#' library programmatically and hand it to `write_mzspeclib()`) and for
#' tests; reading and writing files does not require calling it.
#'
#' The object is a plain list with S3 class `"mzspeclib_library"` and five
#' elements:
#'
#' - `file`: `character(1)`, the file it was read from (`NA` if assembled in
#'   memory).
#' - `header`: `data.frame` with the library-level controlled vocabulary
#'   parameters (see [libraryCv()] for the columns).
#' - `attributeSets`: `data.frame` with the attribute set *definitions* of
#'   the header (see [attributeSets()]).
#' - `clusters`: `list` of spectrum clusters, each a `list` with elements
#'   `id` (`integer(1)`) and `cv` (a CV parameter table).
#' - `spectra`: `list` of spectrum objects (see [spectrum()]).
#' - `issues`: `character` with everything the reader had to complain about.
#'   A non-empty `issues` never means the read failed - the offending lines
#'   are reported, not dropped silently.
#'
#' @param header,spectra,attributeSets,clusters as described above. `NULL`
#'   (the default) gives an empty table or list.
#' @param file,issues `character(1)` respectively `character`.
#'
#' @return A list of class `"mzspeclib_library"`.
#'
#' @author Helge Hecht
#'
#' @seealso [spectrum()], [read_mzspeclib()], [write_mzspeclib()]
#'
#' @examples
#' mzspeclib()
#' mzspeclib(header = data.frame(
#'     group = NA_character_, accession = "MS:1003186",
#'     name = "library format version", value = "1.0",
#'     value_accession = NA_character_, stringsAsFactors = FALSE))
#'
#' @export
mzspeclib <- function(header = NULL, spectra = list(), attributeSets = NULL,
    clusters = list(), file = NA_character_, issues = character()) {
    header <- .as_cv(header)
    if (is.null(attributeSets))
        attributeSets <- .empty_df(attribute_set_columns())
    if (!is.data.frame(attributeSets))
        stop("'attributeSets' must be a data.frame", call. = FALSE)
    spectra <- .as_spectra(spectra)
    clusters <- .as_clusters(clusters)
    structure(list(
        file = .check_file_arg(file),
        header = header,
        attributeSets = attributeSets[, attribute_set_columns(), drop = FALSE],
        clusters = clusters,
        spectra = spectra,
        issues = as.character(issues %||% character())),
        class = "mzspeclib_library")
}

.check_file_arg <- function(file) {
    if (is.null(file) || !length(file))
        return(NA_character_)
    as.character(file)[1L]
}

## Coerce NULL / a bare data.frame into a CV table with the right columns.
.as_cv <- function(cv) {
    if (is.null(cv))
        return(.empty_df(cv_columns()))
    if (!is.data.frame(cv))
        stop("controlled vocabulary parameters must be a data.frame",
            call. = FALSE)
    missing <- setdiff(cv_columns(), colnames(cv))
    if (length(missing))
        stop("missing CV column(s): ", paste(missing, collapse = ", "),
            call. = FALSE)
    cv[, cv_columns(), drop = FALSE]
}

.as_spectra <- function(spectra) {
    if (is.null(spectra) || !length(spectra))
        return(list())
    if (!is.list(spectra))
        stop("'spectra' must be a list", call. = FALSE)
    if (!all(vapply(spectra, is_spectrum, logical(1))))
        stop("'spectra' must only contain objects created by 'spectrum()'",
            call. = FALSE)
    spectra
}

.as_clusters <- function(clusters) {
    if (is.null(clusters))
        return(list())
    if (!is.list(clusters))
        stop("'clusters' must be a list", call. = FALSE)
    lapply(clusters, function(cl) {
        if (is.data.frame(cl))
            cl <- list(id = NA_integer_, cv = cl)
        if (!is.list(cl) || is.null(cl$cv))
            stop("a cluster must be a list with elements 'id' and 'cv'",
                call. = FALSE)
        list(id = .as_key(cl$id), cv = .as_cv(cl$cv))
    })
}

## A section key: positive integer, or NA when the file did not provide one.
.as_key <- function(x) {
    if (is.null(x))
        return(NA_integer_)
    res <- suppressWarnings(as.integer(x)[1L])
    res
}

#' Create a Spectrum Object
#'
#' `spectrum()` creates one element of the `spectra` list of a
#' [mzspeclib()] object. Like [mzspeclib()] it is exported for assembling
#' libraries in memory; reading files does not require it.
#'
#' A spectrum is a plain list with S3 class `"mzspeclib_spectrum"` and five
#' elements: `id` (`integer(1)`, the library spectrum key `MS:1003237` from
#' the `<Spectrum=N>` line, `NA` if the file omitted it), `cv` (CV parameters
#' of the spectrum itself), `analytes` and `interpretations` (lists of
#' `list`s with an `id` and a `cv` table; interpretations additionally have
#' `members`), and `peaks` (a `data.frame` with columns `mz` and `intensity`
#' plus, when present, `annotation` and the additional peak attribute
#' columns, or `NULL` when the file has no `<Peaks>` section).
#'
#' @param id `integer(1)` library spectrum key.
#' @param cv `data.frame` of CV parameters.
#' @param analytes,interpretations `list`s of analyte/interpretation objects.
#' @param peaks `data.frame` or `NULL`.
#'
#' @return A list of class `"mzspeclib_spectrum"`.
#'
#' @author Helge Hecht
#'
#' @examples
#' spectrum(id = 1L, peaks = data.frame(mz = c(110.04, 120.08),
#'     intensity = c(12342, 5321)))
#'
#' @export
spectrum <- function(id = NA_integer_, cv = NULL, analytes = list(),
    interpretations = list(), peaks = NULL) {
    if (!is.list(analytes))
        stop("'analytes' must be a list", call. = FALSE)
    if (!is.list(interpretations))
        stop("'interpretations' must be a list", call. = FALSE)
    structure(list(
        id = .as_key(id),
        cv = .as_cv(cv),
        analytes = lapply(analytes, .as_graph_node, "analyte"),
        interpretations = lapply(interpretations, .as_graph_node,
            "interpretation"),
        peaks = .as_peaks(peaks)),
        class = "mzspeclib_spectrum")
}

.as_graph_node <- function(node, what) {
    if (is.data.frame(node))
        node <- list(id = NA_integer_, cv = node)
    if (!is.list(node) || is.null(node$cv))
        stop("an ", what, " must be a list with element 'cv'", call. = FALSE)
    res <- list(id = .as_key(node$id), cv = .as_cv(node$cv))
    if (!is.null(node$members))
        res$members <- lapply(node$members, .as_graph_node,
            "interpretation member")
    res
}

## Peaks keep the file's own column order; extra peak attribute columns stay
## character (they are the file's text, and typing them would invent
## information the format does not carry).
.as_peaks <- function(peaks) {
    if (is.null(peaks))
        return(NULL)
    if (!is.data.frame(peaks))
        stop("'peaks' must be a data.frame or NULL", call. = FALSE)
    if (!all(c("mz", "intensity") %in% colnames(peaks)))
        stop("'peaks' must have columns 'mz' and 'intensity'", call. = FALSE)
    peaks$mz <- as.numeric(peaks$mz)
    peaks$intensity <- as.numeric(peaks$intensity)
    cols <- c("mz", "intensity", setdiff(colnames(peaks), c("mz", "intensity")))
    peaks[, cols, drop = FALSE]
}

is_spectrum <- function(x) inherits(x, "mzspeclib_spectrum")

#' @export
print.mzspeclib_library <- function(x, ...) {
    cat(format(x), sep = "\n")
    invisible(x)
}

#' @export
format.mzspeclib_library <- function(x, ...) {
    name <- cvParameter(x$header, "MS:1003188")
    c(paste0("mzSpecLib library",
        if (!is.na(x$file)) paste0(" [", basename(x$file), "]") else ""),
      if (length(name)) paste0("  name: ", name[1L]),
      paste0("  spectra: ", length(x$spectra)),
      paste0("  clusters: ", length(x$clusters)),
      paste0("  attribute sets: ", n_sets(x$attributeSets)),
      paste0("  library CV parameters: ", nrow(x$header)),
      if (length(x$issues))
          paste0("  ", length(x$issues), " issue(s) - see $issues"))
}

## The number of attribute sets a definition table declares. A set is its
## kind and its name together (section 4.1.4 defines four kinds and reserves
## the name "all" for each of them), so "all" once per kind is not one set but
## as many as there are kinds.
n_sets <- function(sets) {
    if (!is.data.frame(sets) || !nrow(sets))
        return(0L)
    nrow(unique(sets[, c("type", "set"), drop = FALSE]))
}

## length() is the number of spectra, so that seq_along()/seq_len() work on a
## library without knowing the accessor names.
#' @export
length.mzspeclib_library <- function(x) length(x$spectra)

## Subsetting a library subsets its spectra; attribute sets, clusters and the
## header come along because they are library-level.
#' @export
`[.mzspeclib_library` <- function(x, i, ...) {
    x$spectra <- .as_spectra(x$spectra[i])
    x
}

#' @export
`[[.mzspeclib_library` <- function(x, i, ...) x$spectra[[i]]

#' @export
print.mzspeclib_spectrum <- function(x, ...) {
    cat(format(x), sep = "\n")
    invisible(x)
}

#' @export
format.mzspeclib_spectrum <- function(x, ...) {
    npeaks <- if (is.null(x$peaks)) 0L else nrow(x$peaks)
    c(paste0("spectrum", if (!is.na(x$id)) paste0(" ", x$id) else ""),
      paste0("  CV parameters: ", nrow(x$cv)),
      paste0("  analytes: ", length(x$analytes)),
      paste0("  interpretations: ", length(x$interpretations)),
      paste0("  peaks: ", npeaks))
}
