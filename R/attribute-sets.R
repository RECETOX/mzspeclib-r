## Attribute set inheritance (mzSpecLib v1.0, sections 4.1.4 and 4.1.11).
##
## An attribute set is a named bundle of CV parameters defined in the library
## header. A spectrum/analyte/interpretation claims one by carrying
## "MS:1003212|library attribute set name" whose value is the set name. The
## name "all" applies to every entry of that type.
##
## The precedence rules the specification states, implemented literally:
##
## 1. "all" is inherited by every entry, then the named sets in the order the
##    entry claims them.
## 2. If several claimed sets define the same term, the *last-referenced* set
##    prevails, and the earlier instances are discarded rather than
##    accumulated (section 4.1.11: "are not accumulative").
## 3. Any instance defined by the entry itself shadows the inherited ones for
##    that accession, whatever the value.
## 4. All instances of a repeated term within one context are an inseparable
##    group: they are inherited or overridden together. That falls out of 2
##    and 3 for free, because the unit being replaced is "all rows of one
##    accession within one context".
## 5. A context is an accession *and* the attribute group it is stated in. A
##    set claimed inside a group is inherited into that group, and neither
##    shadows nor is shadowed by the same term in another group of the same
##    section (section 4.1.12, Example 3).

## The claim attribute. The label is spelled exactly as in the PSI-MS CV;
## matching happens on the accession only.
ATTRIBUTE_SET_ACCESSION <- "MS:1003212"

## The claims of one section, as the (set, group) pairs it references them in.
## A claim may carry a group designator, and then the attributes of the set are
## inherited *into that group* (section 4.1.12, Example 3); a claim of the same
## set in two groups therefore inherits it twice, into two contexts. The
## implicitly claimed "all" comes first and belongs to the whole section, never
## into a group (section 4.1.12: "one MAY NOT inherit the 'all' attribute set
## into any group automatically").
.reference_order <- function(cv) {
    idx <- which(cv[["accession"]] == ATTRIBUTE_SET_ACCESSION)
    claimed <- data.frame(set = cv[["value"]][idx], group = cv[["group"]][idx],
        stringsAsFactors = FALSE)
    claimed <- claimed[!is.na(claimed[["set"]]) & nzchar(claimed[["set"]]) &
        claimed[["set"]] != "all", , drop = FALSE]
    ## A set that is claimed twice in the same group is one reference, and the
    ## *last* of those mentions is the one that counts (section 4.1.11).
    if (nrow(claimed)) {
        pair <- paste(claimed[["set"]], claimed[["group"]], sep = "\r")
        claimed <- claimed[!duplicated(pair, fromLast = TRUE), , drop = FALSE]
    }
    rbind(data.frame(set = "all", group = NA_character_,
        stringsAsFactors = FALSE), claimed)
}

## The context a resolved attribute belongs to: its accession and the group it
## is stated in. Section 4.1.11 makes "the same context" the unit which is
## repeated, inherited and overridden together, and Example 3 of section 4.1.12
## shows that two groups of one section are two contexts of one accession.
.context_key <- function(accession, group)
    paste(accession, ifelse(is.na(group), "", group), sep = "\r")

## Resolve the CV parameters of one section against the library's attribute
## set definitions.
##
## cv    : CV table of the section itself
## sets  : the attribute set definition table (see attributeSets())
## type  : "Spectrum", "Analyte", "Interpretation" or "Cluster"
## warn  : whether to warn about claims of undefined sets
resolve_cv <- function(cv, sets, type = "Spectrum", warn = TRUE) {
    cv <- .as_cv(cv)
    if (!is.data.frame(sets) || !nrow(sets))
        return(cv)
    ## A set which is declared but defines no parameter is still declared, and
    ## is recorded as a row with empty CV columns (see attributeSets()); such a
    ## row must not be inherited, but it does make a claim of that set
    ## legitimate.
    declared <- unique(sets[["set"]])
    sets <- sets[sets[["type"]] == type & !is.na(sets[["accession"]]), ,
        drop = FALSE]
    claims <- .reference_order(cv)
    wanted <- claims[["set"]]
    ## "all" applies even if the entry does not mention it; a claim of a set
    ## that was never defined is reported and ignored.
    undefined <- setdiff(wanted, unique(c(declared, "all")))
    undefined <- setdiff(undefined, "all")
    if (length(undefined) && warn)
        warning("claims of undefined ", type, " attribute set(s): ",
            paste(undefined, collapse = ", "), call. = FALSE)
    inherited <- list()
    for (k in seq_along(wanted)) {
        nm <- claims[["set"]][[k]]
        rows <- sets[sets[["set"]] == nm, , drop = FALSE]
        if (!nrow(rows))
            next
        ## The group of the claim is the group the attributes are inherited
        ## into. Without a claim group the groups of the definition itself
        ## stand.
        group <- claims[["group"]][[k]]
        if (!is.na(group))
            rows[["group"]] <- group
        for (acc in unique(rows[["accession"]])) {
            block <- rows[rows[["accession"]] == acc, , drop = FALSE]
            for (ctx in .context_key(block[["accession"]], block[["group"]])) {
                ## A later set replaces what an earlier one contributed to the
                ## same context, and replaces it whole rather than adding to
                ## it (section 4.1.11: "are not accumulative").
                inherited[[ctx]] <- NULL
                inherited[[ctx]] <- block[
                    .context_key(block[["accession"]], block[["group"]]) ==
                        ctx, , drop = FALSE]
            }
        }
    }
    if (!length(inherited))
        return(cv)
    local <- .context_key(cv[["accession"]], cv[["group"]])
    inherited <- inherited[!names(inherited) %in% local]
    if (!length(inherited))
        return(cv)
    res <- do.call(rbind, c(lapply(inherited, function(rows)
        rows[, cv_columns(), drop = FALSE]), list(cv)))
    res <- res[, cv_columns(), drop = FALSE]
    ## The inherited frames carry the names of the rows they were built from,
    ## which as row *names* of the result would be a second, misleading index.
    rownames(res) <- NULL
    res
}

#' Attribute Set Definitions of a Library
#'
#' mzSpecLib libraries can define named bundles of attributes in their header
#' (`<AttributeSet Spectrum=all>` and friends) which the individual spectra,
#' analytes, interpretations or clusters then claim through
#' `MS:1003212|library attribute set name`. `attributeSets()` returns these
#' *definitions*. It does not apply them - the accessors that return
#' attributes of a single spectrum do that (see the `inherit` argument of
#' [spectraCv()], [spectraTable()], [analyteTable()] and
#' [interpretationTable()]), and [spectraCv()] shows both layers separately.
#'
#' @param object A [mzspeclib()] object.
#' @param type `character` restricting the result to one or more of
#'   `"Spectrum"`, `"Analyte"`, `"Interpretation"` and `"Cluster"`. `NULL`
#'   (the default) returns all of them.
#'
#' @return A `data.frame` with one row per attribute per set, and the columns
#'   `type`, `set`, `group`, `accession`, `name`, `value` and
#'   `value_accession`. `nrow() == 0` if the library defines no sets. A set
#'   which is declared but defines no attribute at all - `<AttributeSet
#'   Analyte=all>` followed by nothing, which real libraries do write - gets
#'   one row with `NA` in the six CV columns, because it is a set a section
#'   may claim without the claim being an error.
#'
#' @note Many real-world libraries put most of their spectrum-level metadata
#'   into the `"all"` set, so a reader that ignores attribute sets reports
#'   those spectra as having almost no metadata. [spectraTable()] and
#'   [spectraPeaks()] inherit by default for that reason.
#'
#' @author Helge Hecht
#'
#' @examples
#' lib <- mzspeclib(
#'     attributeSets = data.frame(
#'         type = c("Spectrum", "Spectrum"),
#'         set = c("all", "all"),
#'         group = c(NA_character_, NA_character_),
#'         accession = c("MS:1000511", "MS:1000043"),
#'         name = c("ms level", "intensity unit"),
#'         value = c("2", "percent of base peak times 100"),
#'         value_accession = c(NA_character_, "MS:1000905"),
#'         stringsAsFactors = FALSE))
#' attributeSets(lib)
#' attributeSets(lib, type = "Analyte")
#'
#' @export
attributeSets <- function(object, type = NULL) {
    if (!inherits(object, "mzspeclib_library"))
        stop("'object' must be a 'mzspeclib_library'", call. = FALSE)
    res <- object$attributeSets
    if (!is.null(type)) {
        type <- match.arg(type,
            c("Spectrum", "Analyte", "Interpretation", "Cluster"),
            several.ok = TRUE)
        res <- res[res[["type"]] %in% type, , drop = FALSE]
    }
    res
}
