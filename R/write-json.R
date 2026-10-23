## The JSON serialization writer (mzSpecLib v1.0, section 4.2).
##
## Like the text writer this is a renderer of the object, not a copy of the
## input: the library attributes, the attribute set definitions, the clusters
## and the spectra are written from what the object holds, and inheritance is
## not expanded into the spectra. The members are written in the order of the
## schema, the keys of an object in the order the object lists them (the
## reference python writer sorts them, which turns analyte 10 into the neighbour
## of analyte 1 rather than of analyte 11).

write_json <- function(object, file, digits = 15L, warn = TRUE) {
    if (warn && !length(cvParameter(object$header, "MS:1003186")))
        warning("the header has no MS:1003186|library format version, ",
            "which the specification requires (section 4.1.1)",
            call. = FALSE)
    keys <- spectraIds(object)
    if (warn && any(is.na(keys)))
        warning(sum(is.na(keys)), " spectrum(s) have no library spectrum ",
            "key; the JSON serialization has no section keys, so their ",
            "identity is only their position in the document", call. = FALSE)
    ## Losing the key of a cluster is not the library's fault but the format's:
    ## see .json_payload() below. Saying it once is cheaper than letting the
    ## reader find the keys missing after a round trip.
    clusterKeys <- vapply(object$clusters, function(cl) cl$id, integer(1))
    if (warn && length(clusterKeys) && any(!is.na(clusterKeys)))
        warning(sum(!is.na(clusterKeys)), " cluster(s) have a key, which the ",
            "JSON serialization cannot store: a cluster object of the schema ",
            "has no member but 'attributes'. The keys are not in the written ",
            "file (section 4.2)", call. = FALSE)
    payload <- .json_payload(object, keys = keys)
    txt <- jsonlite::toJSON(payload, auto_unbox = TRUE, na = "null",
        pretty = TRUE, digits = I(digits))
    con <- if (grepl("\\.gz$", file, ignore.case = TRUE))
        gzfile(file, "w") else file(file, "w")
    on.exit(close(con))
    writeLines(as.character(txt), con)
    invisible(file)
}

.json_payload <- function(object, keys = spectraIds(object)) {
    c(list(attributes = .cv_to_json(object$header)),
        .attribute_sets_to_json(object$attributeSets),
        ## A cluster is written with its attributes alone: the 'cluster'
        ## definition of the schema has no other member and allows no other,
        ## so the key of a <Cluster=N> section has nowhere to go in a JSON
        ## document (see "JSON serialization" in ?mzspeclib-package).
        list(clusters = lapply(object$clusters, function(cl)
            list(attributes = .cv_to_json(cl$cv)))),
        list(spectra = I(lapply(seq_along(object$spectra), function(k)
            .spectrum_to_json(object$spectra[[k]], k,
                key = keys[[k]])))),
        list(format_version = "1.0"))
}

## A CV parameter table as an array of cvparam objects. The two optional
## members which are not a value - 'value_accession' and 'cv_param_group' - are
## left out when they have nothing to say, because the schema makes them
## optional and gives no notation for "this term is not CV valued".
.cv_to_json <- function(cv) {
    cv <- .as_cv(cv)
    if (!nrow(cv))
        return(list())
    group <- .json_values(cv$group)
    value <- .json_values(cv$value)
    valueAccession <- .json_values(cv$value_accession)
    accession <- cv$accession
    name <- cv$name
    lapply(seq_len(nrow(cv)), function(j) {
        res <- list(accession = .json_string(accession[[j]]),
            name = .json_string(name[[j]]))
        ## The value is always written, as the empty string when the term has
        ## no value: the schema makes the member optional, but the reader of
        ## the reference implementation reads it unguarded, and the text
        ## serialization writes such a term with an empty object anyway.
        res$value <- if (is.na(value[[j]])) "" else value[[j]]
        if (!is.na(valueAccession[[j]]))
            res$value_accession <- valueAccession[[j]]
        if (!is.na(group[[j]]))
            res$cv_param_group <- group[[j]]
        res
    })
}

.json_string <- function(x) if (is.na(x)) "" else x

## The text serialization carries no types, the JSON serialization does, and the
## rule applied here is that a value is typed only where typing is reversible: it
## becomes a JSON number or boolean exactly when reading the document back
## yields the very text that stood in the file. "0.17" and "570" are numbers and
## "TRUE" is a boolean for that reason, while "1e-07" stays text because it
## would come back as "0.0000001", an integer with more digits than the type
## holds stays text instead of silently losing precision, and NaN and Inf stay
## text because a JSON document has no notation for them at all.
##
## A writer that does not consult the controlled vocabulary gets that far, and
## no further. In the reference implementation it is the range a term declares
## that decides whether its value is written as a number or as a string -
## xsd:float for MS:1000045|collision energy, xsd:string for
## MS:1003186|library format version - and that range lives in the ontology, not
## in the file: a text library holds both values as the text "39.0" and "1.0",
## and no property of those texts tells them apart. A JSON number cannot carry
## the trailing fraction of "39.0" either, so a value of that shape stays a
## string here, and the validation rules of the format then report the term's
## declared numeric range as violated ("the value type of
## MS:1000045|collision energy must be a value of type xsd:float, but got str").
## Guessing instead - typing every value that parses as a number - writes the
## version terms as 1 and 6 and violates just as many rules of the same level,
## besides destroying the value a version term holds. The text is kept, and the
## remaining complaints are documented under "JSON serialization" in
## ?mzspeclib-package.
.json_values <- function(x) {
    if (!is.character(x))
        x <- as.character(x)
    lapply(x, function(v) {
        if (is.na(v) || !nzchar(v))
            return(NA)
        if (v %in% c("TRUE", "FALSE"))
            return(v == "TRUE")
        if (grepl("^-?[0-9]+$", v)) {
            num <- suppressWarnings(as.integer(v))
            if (!is.na(num))
                return(num)
        }
        num <- suppressWarnings(as.numeric(v))
        if (is.na(num) || !is.finite(num) ||
            !identical(format_number(num), v))
            v
        else
            num
    })
}

## The four attribute set members. A type without a single definition is an
## empty object, not an empty array, because the schema defines these members
## as objects of set name to attributes.
.attribute_sets_to_json <- function(sets) {
    members <- c(spectrum_attribute_sets = "Spectrum",
        analyte_attribute_sets = "Analyte",
        interpretation_attribute_sets = "Interpretation",
        cluster_attribute_sets = "Cluster")
    res <- list()
    for (member in names(members)) {
        type <- members[[member]]
        declared <- sets[sets[["type"]] == type, , drop = FALSE]
        rows <- declared[!is.na(declared[["accession"]]), , drop = FALSE]
        ## A declared but empty set is written as an empty array, which the
        ## reader turns back into a declared but empty set.
        labels <- unique(declared[["set"]])
        res[[member]] <- if (!length(labels))
            set_names(list(), character(0))
        else set_names(lapply(labels, function(lb)
            .cv_to_json(rows[rows[["set"]] == lb, cv_columns(),
                drop = FALSE])), labels)
    }
    res
}

.spectrum_to_json <- function(sp, k, key = NA_integer_) {
    cv <- sp$cv
    ## A spectrum whose <Spectrum> line carried no key takes its position,
    ## which is what the text writer does with the same library.
    if (is.na(key))
        key <- k
    ## The identity of a spectrum in JSON is the library spectrum key
    ## attribute, so a library that carries it only as a section key (the text
    ## serialization) gets it written out as an attribute here.
    if (!length(cvParameter(cv, "MS:1003237")))
        cv <- rbind(cv, data.frame(group = NA_character_,
            accession = "MS:1003237", name = "library spectrum key",
            value = as.character(key), value_accession = NA_character_,
            stringsAsFactors = FALSE))
    peaks <- sp$peaks
    res <- list(attributes = .cv_to_json(cv),
        analytes = .nodes_to_json(sp$analytes, k, "analyte"),
        interpretations = .nodes_to_json(sp$interpretations, k,
            "interpretation", members = TRUE),
        mzs = I(if (is.null(peaks)) numeric() else peaks$mz),
        intensities = I(if (is.null(peaks)) numeric() else peaks$intensity))
    res$peak_annotations <- .annotations_to_json(peaks)
    extra <- .extra_peak_columns(peaks)
    if (length(extra))
        res$aggregations <- .aggregations_to_json(peaks, extra)
    res
}

## Analytes and interpretations as an object keyed by their id.
.nodes_to_json <- function(nodes, k, what, members = FALSE) {
    if (!length(nodes))
        return(set_names(list(), character(0)))
    ids <- vapply(nodes, function(nd) nd$id %||% NA_integer_, integer(1))
    ids[is.na(ids)] <- which(is.na(ids))
    labels <- as.character(ids)
    res <- set_names(lapply(seq_along(nodes), function(j) {
        nd <- nodes[[j]]
        out <- list(id = as.integer(ids[[j]]), attributes = .cv_to_json(nd$cv))
        if (members && length(nd$members))
            out$member_interpretations <- .nodes_to_json(nd$members, k,
                "interpretation member")
        out
    }), labels)
    res
}

## Peak annotations: the third column of the text serialization, with "?" for
## an unannotated peak, which is what both the text serialization and the
## reference writer use. An annotation that was read from a JSON document as
## structured mzPAF annotation objects is written back as those objects, so a
## JSON read/write round trip keeps them structured.
.annotations_to_json <- function(peaks) {
    if (is.null(peaks) || !nrow(peaks))
        return(I(character()))
    x <- if ("annotation" %in% colnames(peaks))
        as.character(peaks$annotation) else rep(NA_character_, nrow(peaks))
    x[is.na(x) | !nzchar(x)] <- "?"
    I(lapply(x, .annotation_to_json))
}

.annotation_to_json <- function(x) {
    if (grepl("^[{\\[]", x) && !is.null(
        tryCatch(jsonlite::fromJSON(x, simplifyVector = FALSE),
            error = function(e) NULL)))
        return(jsonlite::fromJSON(x, simplifyVector = FALSE))
    x
}

## The columns beyond mz, intensity and annotation, in the order of the peak
## table.
.extra_peak_columns <- function(peaks) {
    if (is.null(peaks))
        return(character())
    setdiff(colnames(peaks), c("mz", "intensity", "annotation"))
}

.aggregations_to_json <- function(peaks, columns) {
    typed <- lapply(columns, function(cn)
        .json_values(as.character(peaks[[cn]])))
    I(lapply(seq_len(nrow(peaks)), function(j)
        lapply(typed, function(column) column[[j]])))
}
