## Accessors. Two views of the same data, on purpose:
##
## * the *long* "Cv" views ([libraryCv()], [spectraCv()], ...) reproduce the
##   file: one row per CV line, group designators intact, repeated attributes
##   kept as separate rows. Nothing is lost, nothing is inferred.
## * the *wide* "Table" views ([libraryTable()], [spectraTable()], ...) have
##   one row per entity and one column per controlled vocabulary term. Those
##   are what tabular consumers want - MsBackendMzSpecLib being the intended
##   one - and they are by construction lossy for groups and repeated
##   attributes, which is documented on each of them and reported by
##   [cvLosses()].

## ---------------------------------------------------------------- structures

#' The Spectra of a Library
#'
#' `spectra()` returns the spectrum objects of a [mzspeclib()] object,
#' `spectraIds()` their library spectrum keys.
#'
#' @param object A [mzspeclib()] object.
#' @param i `integer` or `NULL` (all). Indices *within the library*, not
#'   library spectrum keys - use [spectraIds()] to map between the two.
#'
#' @return `spectra()` returns a `list` of [spectrum()] objects,
#'   `spectraIds()` an `integer` vector of the keys read from the
#'   `<Spectrum=N>` lines (`NA` where the file provided no key).
#'
#' @author Helge Hecht
#'
#' @examples
#' lib <- read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",
#'     package = "mzspeclib"))
#' length(spectra(lib))
#' spectraIds(lib)
#'
#' @export
spectra <- function(object, i = NULL) {
    .check_library(object)
    if (is.null(i))
        return(object$spectra)
    object$spectra[i]
}

#' @rdname spectra
#' @export
spectraIds <- function(object) {
    .check_library(object)
    vapply(object$spectra, function(sp) sp$id, integer(1))
}

.check_library <- function(object) {
    if (!inherits(object, "mzspeclib_library"))
        stop("'object' must be a 'mzspeclib_library'", call. = FALSE)
    invisible(TRUE)
}

## Normalise `i` into valid spectrum positions.
.spectrum_index <- function(object, i = NULL) {
    n <- length(object$spectra)
    if (is.null(i))
        return(seq_len(n))
    i <- if (is.logical(i)) which(i) else as.integer(i)
    if (any(i > n | i < 1L | is.na(i)))
        stop("'i' contains out of range indices", call. = FALSE)
    i
}

## ------------------------------------------------------------- library level

#' Library Attributes
#'
#' `libraryCv()` returns the library-level controlled vocabulary parameters -
#' the lines between `<mzSpecLib>` and the first section line.
#' `libraryTable()` returns the same information as a one row wide table.
#'
#' @param object A [mzspeclib()] object.
#' @param useAccession `logical(1)`: name the columns of the wide table by
#'   CV accession (`MS:1000894`, the default and unambiguous) or by CV term
#'   name (`retention time`, duplicated names get a numeric suffix).
#' @param columns `character` of accessions (or names, with
#'   `useAccession = FALSE`) to restrict the wide table to. `NULL` (default)
#'   keeps all.
#' @param collapse `character(1)` used to join the values of a repeatable
#'   attribute, or `NA` to keep only the last instance, which is the one the
#'   specification says takes precedence (section 4.1.11).
#' @param coerce `logical(1)` whether to convert columns that are entirely
#'   numeric or entirely `TRUE`/`FALSE` into `integer`/`double`/`logical`.
#'   The conversion looks at the values only and never at a controlled
#'   vocabulary, so it is a heuristic; the default is `FALSE`, i.e.
#'   everything stays `character` exactly as written in the file.
#'
#' @return `libraryCv()` a `data.frame` with the columns `group`,
#'   `accession`, `name`, `value` and `value_accession`.
#'   `libraryTable()` a one row `data.frame`; its `cvName` attribute maps
#'   column name to CV term name (`useAccession = TRUE`) or to accession
#'   (`useAccession = FALSE`).
#'
#' @author Helge Hecht
#'
#' @examples
#' lib <- read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",
#'     package = "mzspeclib"))
#' libraryCv(lib)
#' libraryTable(lib)
#' cvParameter(libraryCv(lib), "MS:1003188")
#'
#' @export
libraryCv <- function(object) {
    .check_library(object)
    object$header
}

#' @rdname libraryCv
#' @export
libraryTable <- function(object, useAccession = TRUE, columns = NULL,
    collapse = ";", coerce = FALSE) {
    .check_library(object)
    .wide_table(object$header, id_columns = character(),
        useAccession = useAccession, columns = columns,
        collapse = collapse, coerce = coerce)
}

## ------------------------------------------------------------- spectra: long

#' Spectrum Attributes
#'
#' `spectraCv()` returns the controlled vocabulary parameters of the
#' spectra, one row per parameter, exactly as the file states them -
#' including the group designator, which the wide [spectraTable()] view
#' cannot express. `analyteCv()`, `interpretationCv()`,
#' `interpretationMemberCv()` and `clusterCv()` do the same for the other
#' sections of the data model.
#'
#' @param object A [mzspeclib()] object.
#' @param i `integer` or `NULL` (all spectra).
#' @param inherit `logical(1)` whether to include the attributes the section
#'   inherits from the attribute sets it claims (and from the `"all"` set),
#'   in addition to the ones written in the section itself. Defaults to
#'   `TRUE`; inherited rows come first. See [attributeSets()] for the
#'   definitions themselves and mzSpecLib sections 4.1.4/4.1.11 for the
#'   precedence rules that are applied.
#'
#' @return A `data.frame` with an identifying column per level (for
#'   `spectraCv()` that is `spectrum`, the position within the library, and
#'   `spectrum_key`, the library spectrum key) followed by the CV columns
#'   `group`, `accession`, `name`, `value` and `value_accession`. With
#'   `inherit = TRUE`, `spectraCv()` also has a `inherited` logical column
#'   telling the two layers apart.
#'
#' @author Helge Hecht
#'
#' @examples
#' lib <- read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",
#'     package = "mzspeclib"))
#' spectraCv(lib)
#' spectraCv(lib, i = 1L, inherit = FALSE)
#'
#' @export
spectraCv <- function(object, i = NULL, inherit = TRUE) {
    .check_library(object)
    i <- .spectrum_index(object, i)
    rows <- lapply(i, function(k) {
        sp <- object$spectra[[k]]
        cv <- .inherit_table(sp$cv, object$attributeSets, "Spectrum",
            inherit)
        .id_cbind(data.frame(spectrum = k, spectrum_key = sp$id,
            stringsAsFactors = FALSE), cv)
    })
    rbind_rows(rows, c("spectrum", "spectrum_key", cv_columns(),
        "inherited"))
}

## The identifying columns in front of the CV table of a section. A section
## MAY hold no CV parameter at all, and then its table has no rows either -
## but it is still the table of that section, so its columns are there.
.id_cbind <- function(id, cv) {
    if (!nrow(cv))
        id <- id[0L, , drop = FALSE]
    cbind(id, cv)
}

## Attach the inherited rows (marked) in front of the local ones (also
## marked), or return the local table untouched.
.inherit_table <- function(cv, sets, type, inherit) {
    if (!inherit) {
        ## A data.frame without rows takes only a value of length 0, not the
        ## recycled length 1 that an empty section would otherwise get.
        cv$inherited <- if (nrow(cv)) FALSE else logical(0)
        return(cv)
    }
    resolved <- resolve_cv(cv, sets, type)
    if (!nrow(resolved)) {
        cv$inherited <- logical(0)
        return(cv)
    }
    ## A row is local when the section states the same term in the same group
    ## itself; the group belongs to the context (see resolve_cv()).
    local <- .context_key(cv$accession, cv$group)
    resolved$inherited <- !(
        .context_key(resolved$accession, resolved$group) %in% local)
    ## Keep the file's own rows last: they are the ones that win.
    resolved[order(resolved$inherited, decreasing = TRUE), , drop = FALSE]
}

#' @rdname spectraCv
#' @export
analyteCv <- function(object, i = NULL, inherit = TRUE) {
    .graph_table(object, i = i, inherit = inherit, what = "analyte")
}

#' @rdname spectraCv
#' @export
interpretationCv <- function(object, i = NULL, inherit = TRUE) {
    .graph_table(object, i = i, inherit = inherit, what = "interpretation")
}

#' @rdname spectraCv
#' @export
interpretationMemberCv <- function(object, i = NULL, inherit = TRUE) {
    .graph_table(object, i = i, inherit = inherit, what = "member")
}

#' @rdname spectraCv
#' @export
clusterCv <- function(object, inherit = TRUE) {
    .check_library(object)
    rows <- lapply(seq_along(object$clusters), function(k) {
        cl <- object$clusters[[k]]
        cv <- .inherit_table(cl$cv, object$attributeSets, "Cluster",
            inherit)
        .id_cbind(data.frame(cluster = k, cluster_key = cl$id,
            stringsAsFactors = FALSE), cv)
    })
    rbind_rows(rows, c("cluster", "cluster_key", cv_columns(), "inherited"))
}

## The columns which identify a node of the analyte/interpretation/member
## graph, in addition to the spectrum it belongs to. The position in the file
## and the key the section declares are both kept, because a member key is
## only unique within its interpretation (section 4.1.10).
.graph_columns <- function(what) switch(what,
    analyte = c("analyte", "analyte_key"),
    interpretation = c("interpretation", "interpretation_key"),
    member = c("interpretation", "interpretation_key", "member",
        "member_key"),
    stop("unknown section: ", what, call. = FALSE))

.graph_table <- function(object, i = NULL, inherit = TRUE, what = "analyte") {
    .check_library(object)
    i <- .spectrum_index(object, i)
    field <- switch(what, analyte = "analytes", interpretation =
        "interpretations", member = "members",
        stop("unknown section: ", what, call. = FALSE))
    type <- switch(what, analyte = "Analyte",
        interpretation = "Interpretation", member = "Interpretation",
        stop("unknown section: ", what, call. = FALSE))
    rows <- list()
    for (k in i) {
        sp <- object$spectra[[k]]
        for (nd in .graph_nodes(sp, field, what)) {
            cv <- .inherit_table(nd$node$cv, object$attributeSets, type,
                inherit)
            id <- c(list(spectrum = k, spectrum_key = sp$id), nd$id)
            rows <- c(rows, list(.id_cbind(
                as.data.frame(id, stringsAsFactors = FALSE), cv)))
        }
    }
    rbind_rows(rows, c("spectrum", "spectrum_key", .graph_columns(what),
        cv_columns(), "inherited"))
}

## The nodes of one spectrum of one level, each with the identifying columns
## of its level already filled in. An interpretation member is listed under
## its interpretation, whose position and key are part of the member's
## identity.
.graph_nodes <- function(sp, field, what) {
    if (what != "member")
        return(lapply(seq_along(sp[[field]]), function(j) {
            node <- sp[[field]][[j]]
            ## the two names of the level: its position and its key
            list(node = node,
                id = set_names(list(j, node$id), .graph_columns(what)))
        }))
    res <- list()
    for (it in seq_along(sp$interpretations)) {
        interp <- sp$interpretations[[it]]
        for (m in seq_along(interp$members %||% list())) {
            member <- interp$members[[m]]
            res <- c(res, list(list(node = member,
                id = list(interpretation = it,
                    interpretation_key = interp$id, member = m,
                    member_key = member$id))))
        }
    }
    res
}

## The entities of a level, whether or not they state a CV parameter of their
## own. A wide table has one row per entity of this list, so that a spectrum
## without a single attribute still occupies its row: a table with fewer rows
## than the library has spectra would lose spectra without saying so, and a
## tabular consumer such as MsBackendMzSpecLib has no way to notice.
.spectrum_ids <- function(object, i) {
    data.frame(spectrum = i,
        spectrum_key = vapply(object$spectra[i], function(sp) sp$id,
            integer(1)), stringsAsFactors = FALSE)
}

.graph_ids <- function(object, i, what) {
    field <- switch(what, analyte = "analytes", interpretation =
        "interpretations", member = "members",
        stop("unknown section: ", what, call. = FALSE))
    rows <- lapply(i, function(k) {
        sp <- object$spectra[[k]]
        nodes <- .graph_nodes(sp, field, what)
        lapply(nodes, function(nd) as.data.frame(c(list(spectrum = k,
            spectrum_key = sp$id), nd$id), stringsAsFactors = FALSE))
    })
    rows <- unlist(rows, recursive = FALSE)
    cols <- c("spectrum", "spectrum_key", .graph_columns(what))
    if (!length(rows))
        return(.empty_df(cols))
    res <- do.call(rbind, rows)[, cols, drop = FALSE]
    rownames(res) <- NULL
    res
}

.cluster_ids <- function(object) {
    cl <- object$clusters
    data.frame(cluster = seq_along(cl),
        cluster_key = vapply(cl, function(x) x$id, integer(1)),
        stringsAsFactors = FALSE)
}

## ------------------------------------------------------------ spectra: wide

#' Tabular Views of a Library
#'
#' These accessors flatten the controlled vocabulary parameters of one level
#' of the data model into a table with one row per entity and one column per
#' CV term. They are the interface intended for packages that want mzSpecLib
#' content as data.frames - in particular
#' [MsBackendMzSpecLib](https://github.com/RforMassSpectrometry/MsBackendMzSpecLib),
#' which maps CV terms onto the `spectraVariables` of a `Spectra` object.
#'
#' @inheritParams spectraCv
#' @param useAccession `logical(1)` whether columns are named by accession
#'   (default, unambiguous) or by CV term name.
#' @param columns `character` of accessions (or term names with
#'   `useAccession = FALSE`) restricting the result. `NULL` keeps all
#'   columns.
#' @param collapse `character(1)` joining the values of a term that appears
#'   more than once for one entity, or `NA` to keep only the last instance
#'   (the one that takes precedence per mzSpecLib section 4.1.11).
#' @param cvValue `character(1)` how to render a term whose object is itself
#'   a CV term (e.g. `MS:1000043|intensity unit=MS:1000905|percent of base
#'   peak times 100`): `"name"` (default) keeps
#'   `percent of base peak times 100`, `"accession"` keeps `MS:1000905` and
#'   `"compound"` keeps the whole `MS:1000905|percent of base peak times 100`
#'   as written in the file.
#' @param coerce `logical(1)` see [libraryTable()].
#'
#' @section What the wide tables cannot express:
#' A wide table has no place for the group designator, so attributes that
#' must be read as a group (a `collision energy` and its `unit`, or the
#' members of a `[n]MS:1003254|peak attribute` definition) arrive as
#'   ordinary columns. Repeatable attributes are joined with `collapse`. Both
#' are visible again in [spectraCv()], and [cvLosses()] reports how often
#' either occurs in a library - use it before trusting a wide table to be a
#' complete picture.
#'
#' @return A `data.frame`. `spectraTable()` has one row per spectrum,
#'   `analyteTable()` and `interpretationTable()` one row per analyte or
#'   interpretation (identified by `spectrum` plus `analyte`/`interpretation`
#'   position and key columns), `clusterTable()` one row per cluster. The
#'   rows are the entities of the library, not the rows of its CV table: an
#'   entity which states no parameter at all has its row, with `NA` in every
#'   term column, and restricting `columns` changes the columns of the table
#'   but never its number of rows. The first columns identify the entity, the
#'   rest are CV terms. The `cvName` attribute maps column names to CV term
#'   names or accessions.
#'
#' @author Helge Hecht
#'
#' @examples
#' lib <- read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",
#'     package = "mzspeclib"))
#' spectraTable(lib)
#' spectraTable(lib, columns = c("MS:1003208", "MS:1000043"))
#' spectraTable(lib, useAccession = FALSE)
#' analyteTable(lib)
#'
#' @export
spectraTable <- function(object, i = NULL, inherit = TRUE,
    useAccession = TRUE, columns = NULL, collapse = ";", cvValue = "name",
    coerce = FALSE) {
    .check_library(object)
    i <- .spectrum_index(object, i)
    long <- spectraCv(object, i = i, inherit = inherit)
    .wide_table(long, c("spectrum", "spectrum_key"), useAccession,
        columns, collapse, coerce, cvValue = cvValue,
        entities = .spectrum_ids(object, i))
}

#' @rdname spectraTable
#' @export
analyteTable <- function(object, i = NULL, inherit = TRUE,
    useAccession = TRUE, columns = NULL, collapse = ";",
    cvValue = "name", coerce = FALSE) {
    .check_library(object)
    i <- .spectrum_index(object, i)
    long <- .graph_table(object, i = i, inherit = inherit,
        what = "analyte")
    .wide_table(long, c("spectrum", "spectrum_key",
        .graph_columns("analyte")), useAccession, columns, collapse,
        coerce, cvValue = cvValue,
        entities = .graph_ids(object, i, "analyte"))
}

#' @rdname spectraTable
#' @export
interpretationTable <- function(object, i = NULL, inherit = TRUE,
    useAccession = TRUE, columns = NULL, collapse = ";",
    cvValue = "name", coerce = FALSE) {
    .check_library(object)
    i <- .spectrum_index(object, i)
    long <- .graph_table(object, i = i, inherit = inherit,
        what = "interpretation")
    .wide_table(long, c("spectrum", "spectrum_key",
        .graph_columns("interpretation")), useAccession, columns, collapse,
        coerce, cvValue = cvValue,
        entities = .graph_ids(object, i, "interpretation"))
}

#' @rdname spectraTable
#' @export
clusterTable <- function(object, inherit = TRUE, useAccession = TRUE,
    columns = NULL, collapse = ";", cvValue = "name", coerce = FALSE) {
    .check_library(object)
    long <- clusterCv(object, inherit = inherit)
    .wide_table(long, c("cluster", "cluster_key"), useAccession, columns,
        collapse, coerce, cvValue = cvValue,
        entities = .cluster_ids(object))
}

## The key of one row of an entity table: its identifying columns as one
## string, which is what matches a long row to the entity it belongs to.
.entity_keys <- function(x)
    do.call(paste, c(unname(lapply(x, as.character)), list(sep = "\r")))

## The identifying columns of the entities, or the empty table of a level
## which has neither entities nor a CV parameter.
.id_only <- function(entities, id_columns) {
    if (is.null(entities) || !nrow(entities))
        return(.empty_df(id_columns))
    res <- entities[, id_columns, drop = FALSE]
    rownames(res) <- NULL
    res
}

## Long CV table -> wide table. `id_columns` are kept as leading columns; the
## rows are `entities`, which may hold entities the long table has no row for.
.wide_table <- function(long, id_columns, useAccession = TRUE,
    columns = NULL, collapse = ";", coerce = FALSE,
    cvValue = c("name", "accession", "compound"), entities = NULL) {
    cvValue <- match.arg(cvValue)
    if (!is.null(entities))
        entities <- entities[, id_columns, drop = FALSE]
    ## Without a single CV line there is no term to make a column of, but the
    ## entities are still there and the table has their rows.
    if (!nrow(long)) {
        res <- .id_only(entities, id_columns)
        attr(res, "cvName") <- character()
        return(res)
    }
    ## accession -> column name
    keys <- unique(long$accession)
    labels <- vapply(keys, function(k)
        long$name[[which(long$accession == k)[1L]]], character(1))
    colnames <- if (useAccession) keys else make.unique(labels, sep = ".")
    names(colnames) <- keys
    if (!is.null(columns)) {
        wanted <- if (useAccession) keys %in% columns else labels %in%
            columns
        keys <- keys[wanted]
    }
    if (!length(keys)) {
        res <- .id_only(entities, id_columns)
        attr(res, "cvName") <- character()
        return(res)
    }
    value <- if (cvValue == "name") long$value
    else if (cvValue == "accession")
        ifelse(is.na(long$value_accession), long$value, long$value_accession)
    else if (cvValue == "compound")
        ifelse(is.na(long$value_accession), long$value,
            paste0(long$value_accession, "|", long$value))
    rowKeys <- if (length(id_columns))
        .entity_keys(long[, id_columns, drop = FALSE])
        else rep("1", nrow(long))
    ## The rows are the entities; a long table without a grid of its own
    ## defines them by its first row per entity.
    if (is.null(entities)) {
        ## A level without identifying columns has one entity, the library
        ## itself; the placeholder column of its row is dropped by .id_only().
        entities <- if (length(id_columns))
            long[!duplicated(rowKeys), id_columns, drop = FALSE]
        else data.frame(.entity = "1", stringsAsFactors = FALSE)
    } else if (!all(rowKeys %in% .entity_keys(entities))) {
        other <- long[!(rowKeys %in% .entity_keys(entities)), id_columns,
            drop = FALSE]
        entities <- rbind(entities,
            other[!duplicated(.entity_keys(other)), , drop = FALSE])
    }
    entity <- match(rowKeys, .entity_keys(entities))
    n <- nrow(entities)
    out <- vector("list", length(keys))
    names(out) <- colnames[keys]
    for (j in seq_along(keys)) {
        acc <- keys[[j]]
        sel <- which(long$accession == acc)
        col <- rep(NA_character_, n)
        ## Values of one entity are joined *within* that entity: the rows of
        ## one entity for one term are not necessarily adjacent in the file.
        byEntity <- split(value[sel], entity[sel])
        col[as.integer(names(byEntity))] <- vapply(byEntity,
            collapse_values, character(1), collapse = collapse)
        out[[j]] <- col
    }
    res <- do.call(data.frame, c(out,
        list(stringsAsFactors = FALSE, check.names = FALSE)))
    res <- cbind(.id_only(entities, id_columns), res)
    if (coerce)
        for (j in setdiff(colnames(res), id_columns))
            res[[j]] <- coerce_values(res[[j]])
    attr(res, "cvName") <- if (useAccession)
        set_names(labels[keys], keys)
    else set_names(keys, colnames[keys])
    rownames(res) <- NULL
    res
}

## --------------------------------------------------------------- peak tables

#' Peak Lists of a Library
#'
#' `spectraPeaks()` returns the peak lists, `peakColumns()` the definition of
#' the additional peak columns.
#'
#' A peak table has the columns `mz` and `intensity` (`double`, converted
#' while reading), `annotation` (`character`, the mzPAF fragment ion
#' annotation of section 4.1.14, kept as the opaque string it is in the
#' file) and, when the file has them, one column per additional peak
#' attribute. Those columns stay `character`, because the file is the only
#' source of their type.
#'
#' The meaning of additional columns is defined by an ordered group of
#' `MS:1003254|peak attribute` attributes in the spectrum (or in an attribute
#' set it claims, section 4.1.16); `peakColumns()` resolves that and returns
#' it together with the column number it maps to. The specification does not
#' say what happens when a spectrum declares its columns in more than one
#' group; this package orders all declared attributes by group and then by
#' file order and assigns them to columns 4, 5, 6, ... in that sequence.
#'
#' @inheritParams spectraCv
#' @param peakColumns `logical(1)` whether the additional peak columns take
#'   the accession of their `MS:1003254|peak attribute` definition as their
#'   name (default, and unambiguous) or keep the generic `X4`, `X5`, ... names
#'   the reader assigns from the column number of the file. A library whose
#'   spectra declare different attributes in the same column position cannot
#'   be named by accession in one table; [peakColumns()] lists the definition
#'   of every spectrum either way.
#'
#' @return `spectraPeaks()` returns a `data.frame` if `i` selects exactly one
#'   spectrum and a `list` of `data.frame`s otherwise (the convention
#'   `peaksData()` of the \pkg{Spectra} package uses, so that a backend can
#'   pass the result through).
#'   `peakColumns()` returns a `data.frame` with columns `spectrum`,
#'   `column` (the 1-based column number in the peak table), `accession` and
#'   `name`.
#'
#' @author Helge Hecht
#'
#' @examples
#' lib <- read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",
#'     package = "mzspeclib"))
#' spectraPeaks(lib, 1L)
#' spectraPeaks(lib)
#' peakColumns(lib)
#'
#' @export
spectraPeaks <- function(object, i = NULL, peakColumns = TRUE) {
    .check_library(object)
    i <- .spectrum_index(object, i)
    defs <- if (peakColumns) .peak_column_map(object) else NULL
    one <- function(k) {
        peaks <- object$spectra[[k]]$peaks
        if (is.null(peaks))
            peaks <- data.frame(mz = numeric(0), intensity = numeric(0),
                stringsAsFactors = FALSE)
        map <- if (is.null(defs)) .empty_df(c("column", "accession",
            "name")) else defs[[k]]
        for (j in seq_len(nrow(map))) {
            from <- paste0("X", map$column[[j]])
            ## The column is named by the accession of the *declared* attribute
            ## (the value of MS:1003254), not by MS:1003254 itself. A library
            ## that declares a peak attribute as free text has no accession for
            ## it and gets that text instead; a name that is already taken is
            ## left alone rather than making the column names ambiguous.
            to <- if (is.na(map$accession[[j]])) map$name[[j]] else
                map$accession[[j]]
            if (!is.na(to) && nzchar(to) && from %in% colnames(peaks) &&
                !to %in% colnames(peaks))
                colnames(peaks)[colnames(peaks) == from] <- to
        }
        attr(peaks, "cvName") <- map$accession
        names(attr(peaks, "cvName")) <- map$name
        peaks
    }
    if (length(i) == 1L)
        return(one(i))
    lapply(i, one)
}

## Per spectrum: which additional peak columns are declared, in order.
.peak_column_map <- function(object) {
    lapply(seq_along(object$spectra), function(k) {
        cv <- resolve_cv(object$spectra[[k]]$cv, object$attributeSets,
            "Spectrum", warn = FALSE)
        cv <- cv[cv$accession == "MS:1003254", , drop = FALSE]
        if (!nrow(cv))
            return(.empty_df(c("column", "accession", "name")))
        ## Order by group designator, keeping the file's order within a group
        ## and the ungrouped declarations behind the grouped ones.
        cv <- cv[order(suppressWarnings(as.integer(cv$group)),
            na.last = TRUE), , drop = FALSE]
        data.frame(column = 3L + seq_len(nrow(cv)),
            accession = cv$value_accession,
            name = cv$value, stringsAsFactors = FALSE)
    })
}

#' @rdname spectraPeaks
#' @export
peakColumns <- function(object, i = NULL) {
    .check_library(object)
    i <- .spectrum_index(object, i)
    defs <- .peak_column_map(object)[i]
    rows <- lapply(seq_along(i), function(j) {
        d <- defs[[j]]
        if (!nrow(d))
            return(NULL)
        cbind(data.frame(spectrum = i[[j]], stringsAsFactors = FALSE), d)
    })
    rows <- rows[!vapply(rows, is.null, logical(1))]
    if (!length(rows))
        return(.empty_df(c("spectrum", "column", "accession", "name")))
    do.call(rbind, rows)
}

## -------------------------------------------------------------------- clusters

#' Clusters of a Library
#'
#' `clusters()` returns the spectrum clusters defined in the library header
#' as a list of `list`s with elements `id` and `cv`. mzSpecLib v1.0 example
#' libraries carry none, so expect an empty list unless the library is an
#' archive of related spectra.
#'
#' @param object A [mzspeclib()] object.
#'
#' @return A `list`.
#'
#' @author Helge Hecht
#'
#' @examples
#' clusters(read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",
#'     package = "mzspeclib")))
#'
#' @export
clusters <- function(object) {
    .check_library(object)
    object$clusters
}

## ------------------------------------------------------------------ diagnostics

#' What a Wide Table Lost
#'
#' `cvLosses()` counts, per level, the number of CV lines that a wide table
#' cannot represent: attributes carrying a group designator, and repeated
#' instances of one term within one entity. Use it to decide whether
#' [spectraTable()] is enough for an analysis or whether [spectraCv()] is
#' needed.
#'
#' @param object A [mzspeclib()] object.
#'
#' @return A `data.frame` with columns `level`, `grouped` (rows with a group
#'   designator), `repeated` (rows that are a second or later instance of the
#'   same term in the same section) and `rows` (all rows at that level).
#'
#' @author Helge Hecht
#'
#' @examples
#' lib <- read_mzspeclib(system.file("extdata", "example.mzSpecLib.txt",
#'     package = "mzspeclib"))
#' cvLosses(lib)
#'
#' @export
cvLosses <- function(object) {
    .check_library(object)
    levels <- list(library = libraryCv(object),
        spectrum = spectraCv(object, inherit = FALSE),
        analyte = analyteCv(object, inherit = FALSE),
        interpretation = interpretationCv(object, inherit = FALSE),
        cluster = clusterCv(object, inherit = FALSE))
    res <- lapply(names(levels), function(nm) {
        cv <- levels[[nm]]
        repeats <- 0L
        if (nrow(cv)) {
            ## A repeated parameter is one that appears twice *within one
            ## entity*, so the key of a row is the identifying columns of its
            ## level together, never one of them alone.
            ids <- setdiff(colnames(cv), c(cv_columns(), "inherited"))
            key <- do.call(paste,
                c(cv[c(ids, "accession")], list(sep = "\r")))
            repeats <- sum(duplicated(key))
        }
        data.frame(level = nm,
            grouped = sum(!is.na(cv$group)),
            repeated = repeats,
            rows = nrow(cv), stringsAsFactors = FALSE)
    })
    do.call(rbind, res)
}
