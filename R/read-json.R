## The JSON serialization reader (mzSpecLib v1.0, section 4.2).
##
## The JSON serialization is defined by `mzSpecLib_json.schema.json` in the
## specification. Two things became apparent when that schema was compared with
## the example files of the same repository, and both are handled here the way
## the *files* do it rather than the way the schema does:
##
## - The `spectrum` object of the schema has `additionalProperties: false` and
##   no `interpretations` property, although the very same schema defines
##   `interpretation` and `interpretation_member`, and although every spectrum
##   of `examples/SpectraST/fetal_brain_tiny.mzSpecLib.json` and of
##   `examples/NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.json` carries
##   interpretations. The reader therefore reads interpretations, and says
##   nothing about it.
## - The schema wants the per-peak annotations to be an array of arrays, while
##   both example files - and the writer of the reference python
##   implementation - write one string per peak. Both forms are accepted.
##
## The reader does not validate documents against the schema (that would need a
## JSON schema validator as a dependency); it reads what is there, and reports
## in `issues` every member it had to ignore, because a member the schema does
## not know is a member whose content cannot be represented in the object.

#' Read an mzSpecLib JSON Document
#'
#' `parse_json()` is the JSON counterpart of the text reader. It is not
#' exported: use [read_mzspeclib()], which chooses the serialization for you.
#' It is documented here because the section "JSON serialization" of
#' [mzspeclib-package] explains what is translated and what is kept verbatim.
#'
#' @param file `character(1)` the document to read.
#' @param encoding `character(1)` passed to [readLines()].
#'
#' @noRd
parse_json <- function(file, encoding = "UTF-8") {
    state <- .issue_state()
    txt <- paste(.open_lines(file, encoding), collapse = "\n")
    payload <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE),
        error = function(e) {
            .issue(state, "the file is not a JSON document: ",
                conditionMessage(e))
            NULL
        })
    if (!is.list(payload) || is.null(names(payload))) {
        if (!length(state$issues))
            .issue(state, "the JSON document is not an object; a library is ",
                "a single object with the members 'attributes' and ",
                "'spectra', not an array")
        return(mzspeclib(file = file, issues = state$issues))
    }
    known <- c("attributes", "spectrum_attribute_sets",
        "analyte_attribute_sets", "interpretation_attribute_sets",
        "cluster_attribute_sets", "clusters", "spectra", "format_version")
    unknown <- setdiff(names(payload), known)
    if (length(unknown))
        .issue(state, "the JSON document has the member(s) ",
            paste0("'", unknown, "'", collapse = ", "), ", which the ",
            "specification does not define; their content is not in the ",
            "returned object")
    version <- .json_text(payload$format_version)
    if (is.na(version))
        .issue(state, "the JSON document has no 'format_version' member, ",
            "which the schema requires")
    else if (!identical(version, "1.0"))
        .issue(state, "the document declares format version '", version,
            "'; this package implements version 1.0")
    header <- .cv_from_json(payload$attributes, state, "the library header")
    sets <- .attribute_sets_from_json(payload, state)
    clusters <- lapply(payload$clusters %||% list(), function(cl)
        list(id = .as_key(cl$id),
            cv = .cv_from_json(cl$attributes, state, "a cluster")))
    spectra <- lapply(seq_along(payload$spectra %||% list()), function(k)
        .spectrum_from_json(payload$spectra[[k]], k, state))
    dropped <- vapply(spectra, is.null, logical(1))
    if (any(dropped))
        .issue(state, sum(dropped), " spectrum object(s) were not objects ",
            "and were dropped")
    spectra <- spectra[!dropped]
    mzspeclib(header = header, spectra = spectra, attributeSets = sets,
        clusters = clusters, file = file, issues = state$issues)
}

## One spectrum. `k` is its position in the document, used only to make the
## complaints identifiable.
.spectrum_from_json <- function(sp, k, state) {
    where <- paste0("spectrum ", k)
    if (!is.list(sp) || is.null(names(sp))) {
        .issue(state, where, " is not an object")
        return(NULL)
    }
    known <- c("attributes", "analytes", "interpretations", "mzs",
        "intensities", "peak_annotations", "aggregations")
    unknown <- setdiff(names(sp), known)
    if (length(unknown))
        .issue_once(state, "spectrum-members", "spectrum object(s) have the ",
            "undefined member(s) ", paste0("'", unique(unknown), "'",
            collapse = ", "), "; their content is not in the returned object")
    cv <- .cv_from_json(sp$attributes, state, where)
    ## The JSON serialization has no section keys, so the identity of a
    ## spectrum is its MS:1003237|library spectrum key.
    key <- .as_key(cvParameter(cv, "MS:1003237")[1L])
    if (is.na(key))
        .issue(state, where, " has no MS:1003237|library spectrum key")
    spectrum(id = key, cv = cv,
        analytes = .nodes_from_json(sp$analytes, "analyte", state, where),
        interpretations = .nodes_from_json(sp$interpretations,
            "interpretation", state, where, members = TRUE),
        peaks = .peaks_from_json(sp, state, where))
}

## A CV parameter table from an array of cvparam objects.
.cv_from_json <- function(attributes, state, where) {
    if (is.null(attributes))
        return(.empty_df(cv_columns()))
    if (!is.list(attributes) || (length(attributes) &&
        !is.null(names(attributes)))) {
        .issue(state, where, ": the attributes are not an array of ",
            "controlled vocabulary parameters; they were dropped")
        return(.empty_df(cv_columns()))
    }
    rows <- lapply(attributes, function(at) {
        if (!is.list(at) || is.null(names(at))) {
            .issue(state, where, ": an attribute which is not an object was ",
                "dropped")
            return(NULL)
        }
        accession <- .json_text(at$accession)
        if (is.na(accession) || !nzchar(accession)) {
            .issue(state, where, ": an attribute without an accession was ",
                "dropped")
            return(NULL)
        }
        extra <- setdiff(names(at), c("accession", "name", "value",
            "value_accession", "cv_param_group"))
        if (length(extra))
            .issue_once(state, "cvparam-members", where, ": attribute(s) ",
                "with the undefined member(s) ",
                paste0("'", unique(extra), "'", collapse = ", "), "; their ",
                "content is not in the returned object")
        data.frame(group = .json_text(at$cv_param_group),
            accession = accession, name = .json_text(at$name),
            value = .json_text(at$value),
            value_accession = .json_text(at$value_accession),
            stringsAsFactors = FALSE)
    })
    rows <- rows[!vapply(rows, is.null, logical(1))]
    rbind_rows(rows, cv_columns())
}

## The four "*_attribute_sets" members of the document, in the order of the
## specification, as the long attribute set definition table.
.attribute_sets_from_json <- function(payload, state) {
    members <- c(spectrum_attribute_sets = "Spectrum",
        analyte_attribute_sets = "Analyte",
        interpretation_attribute_sets = "Interpretation",
        cluster_attribute_sets = "Cluster")
    rows <- list()
    for (member in names(members)) {
        block <- payload[[member]]
        if (is.null(block) || !length(block))
            next
        ## An empty object is the same as no member at all; an empty *array*
        ## is what a writer produces when it mistakes the object for a list.
        if (!is.list(block) || is.null(names(block))) {
            .issue(state, "'", member, "' is not an object of set names to ",
                "attributes; it was ignored")
            next
        }
        type <- members[[member]]
        for (label in names(block)) {
            cv <- .cv_from_json(block[[label]], state,
                paste0("the ", type, " attribute set '", label, "'"))
            if (!nrow(cv)) {
                rows <- c(rows, list(.empty_set_row(type, label)))
                next
            }
            rows <- c(rows, list(cbind(data.frame(type = type, set = label,
                stringsAsFactors = FALSE), cv)))
        }
    }
    if (!length(rows))
        return(.empty_df(attribute_set_columns()))
    res <- do.call(rbind, rows)[, attribute_set_columns(), drop = FALSE]
    rownames(res) <- NULL
    res
}

## Analytes, interpretations and interpretation members are JSON objects keyed
## by their id. The keys win over a (possibly inconsistent) 'id' member, as in
## the reference implementation, but the entries are sorted by their *numeric*
## key: a writer that sorts the keys of an object lexically - which the python
## writer does - would otherwise read back as 1, 10, 11, 2.
.nodes_from_json <- function(nodes, what, state, where, members = FALSE) {
    if (is.null(nodes) || !length(nodes))
        return(list())
    if (!is.list(nodes) || is.null(names(nodes))) {
        .issue(state, where, ": the ", what, "s are not an object keyed by ",
            "id; they were dropped")
        return(list())
    }
    keys <- suppressWarnings(as.integer(names(nodes)))
    if (all(is.na(keys)))
        keys <- vapply(nodes, function(nd) .as_key(nd$id), integer(1))
    res <- lapply(order(keys, na.last = TRUE), function(j) {
        node <- nodes[[j]]
        if (!is.list(node) || is.null(names(node))) {
            .issue(state, where, ": an ", what, " which is not an object was ",
                "dropped")
            return(NULL)
        }
        id <- keys[[j]]
        declared <- .as_key(node$id)
        if (!is.na(declared) && !is.na(id) && declared != id)
            .issue(state, where, ": an ", what, " keyed ", id, " declares ",
                "id ", declared, "; the key is used")
        res <- list(id = id, cv = .cv_from_json(node$attributes, state,
            paste0(where, ", ", what, " ", id %||% "?")))
        if (members)
            res$members <- .nodes_from_json(node$member_interpretations,
                "interpretation member", state,
                paste0(where, ", interpretation ", id %||% "?"))
        res
    })
    res[!vapply(res, is.null, logical(1))]
}

## The peak table: 'mzs' and 'intensities' are the numbers, 'peak_annotations'
## the third column and 'aggregations' the additional peak attributes, which is
## exactly how the text serialization lays a peak out (section 4.1.13).
.peaks_from_json <- function(sp, state, where) {
    mz <- .json_numbers(sp$mzs)
    intensity <- .json_numbers(sp$intensities)
    n <- max(length(mz), length(intensity))
    if (!n)
        return(NULL)
    if (length(mz) != length(intensity))
        .issue(state, where, ": ", length(mz), " m/z value(s) but ",
            length(intensity), " intensity value(s); the shorter array was ",
            "padded with NA")
    annotation <- .annotations_from_json(sp$peak_annotations, state, where)
    aggregation <- .aggregations_from_json(sp$aggregations)
    if (length(annotation) && length(annotation) != n)
        .issue(state, where, ": ", length(annotation), " peak annotation(s) ",
            "for ", n, " peak(s); the shorter array was padded")
    if (length(aggregation) && length(aggregation) != n)
        .issue(state, where, ": ", length(aggregation), " aggregation(s) for ",
            n, " peak(s); the shorter list was padded")
    ## One entry per peak, and so the list has to take the length of the peak
    ## table before any of its entries becomes a column: a document may hold
    ## fewer aggregations than m/z values, and a missing entry is a peak
    ## without additional attributes.
    length(aggregation) <- n
    res <- data.frame(mz = .pad(mz, n), intensity = .pad(intensity, n),
        stringsAsFactors = FALSE)
    if (length(annotation))
        res$annotation <- .pad(annotation, n, fill = NA_character_)
    width <- max(vapply(aggregation, length, integer(1)), 0L)
    for (j in seq_len(width))
        res[[paste0("X", j + 3L)]] <- vapply(aggregation,
            function(a) if (j <= length(a)) a[[j]] else NA_character_,
            character(1), USE.NAMES = FALSE)
    res
}

## One entry of the 'peak_annotations' array. A string is what every producer
## writes and is kept verbatim; a list of strings is the form the python writer
## chooses for several annotations of one peak and is joined with the comma it
## used; a list of structured mzPAF annotation objects keeps its JSON text,
## because this package does not implement the mzPAF annotation grammar (see
## "JSON serialization" in [mzspeclib-package]).
.annotation_from_json <- function(x) {
    if (is.null(x) || !length(x))
        return(NA_character_)
    if (!is.list(x))
        return(.json_text(x))
    if (any(vapply(x, function(e) is.list(e) && !is.null(names(e)),
        logical(1)))) {
        txt <- as.character(jsonlite::toJSON(x, auto_unbox = TRUE))
        if (length(txt) > 1L)
            txt <- paste(txt, collapse = "")
        return(txt)
    }
    flat <- vapply(x, .json_text, character(1), USE.NAMES = FALSE)
    flat <- flat[!is.na(flat) & nzchar(flat)]
    if (!length(flat))
        return(NA_character_)
    paste(flat, collapse = ",")
}

.annotations_from_json <- function(annotations, state, where) {
    if (is.null(annotations))
        return(NULL)
    if (!is.list(annotations))
        annotations <- list(annotations)
    if (!length(annotations))
        return(NULL)
    vapply(annotations, .annotation_from_json, character(1),
        USE.NAMES = FALSE)
}

## The 'aggregations' array: one entry per peak, each entry the additional peak
## attributes of that peak. Entries may be a single value instead of an array.
.aggregations_from_json <- function(aggregations) {
    if (is.null(aggregations) || !length(aggregations))
        return(list())
    if (!is.list(aggregations))
        return(list(.aggregation_from_json(aggregations)))
    lapply(aggregations, .aggregation_from_json)
}

.aggregation_from_json <- function(x) {
    if (is.null(x))
        return(character())
    if (!is.list(x))
        x <- list(x)
    res <- vapply(x, .json_text, character(1), USE.NAMES = FALSE)
    res[!is.na(res) & nzchar(res)]
}

## A JSON scalar as the text the text serialization would have carried. Numbers
## are rendered without an exponent, so that a document and a text file with
## the same content give the same CV table.
.json_text <- function(x) {
    if (is.null(x) || !length(x))
        return(NA_character_)
    if (is.list(x)) {
        txt <- as.character(jsonlite::toJSON(x, auto_unbox = TRUE))
        res <- paste(txt, collapse = "")
    } else {
        res <- if (is.double(x)) format_number(x) else as.character(x)[[1L]]
    }
    if (is.na(res) || !nzchar(res)) NA_character_ else res
}

.json_numbers <- function(x) {
    if (is.null(x))
        return(numeric())
    if (!is.list(x))
        return(suppressWarnings(as.numeric(x)))
    vapply(x, function(v) {
        res <- suppressWarnings(as.numeric(.json_text(v)))
        if (length(res)) res[[1L]] else NA_real_
    }, numeric(1), USE.NAMES = FALSE)
}

.pad <- function(x, n, fill = NA_real_) {
    length(x) <- n
    if (!is.na(fill))
        x[is.na(x)] <- fill
    x
}

## Report a problem of a kind once, instead of once per spectrum or per peak.
.issue_once <- function(state, id, ...) {
    reported <- state$reported %||% character()
    if (id %in% reported)
        return(invisible(NULL))
    state$reported <- c(reported, id)
    state$issues <- c(state$issues, paste0(...))
    invisible(NULL)
}
