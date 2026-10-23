## Prototype: minimal but REAL mzSpecLib text reader, pure R, no dependencies.
`%||%` <- function(a, b) if (is.null(a) || is.na(a)) b else a
## Purpose: measure how much code the format core actually needs, and find the
## places where the spec is ambiguous enough that an implementer must guess.

## ---- CV parameter parsing ---------------------------------------------------
## Grammar per spec 4.1.2:  [group]MS:acc|term name=value
##   value may itself be a CV term: MS:x|name=MS:y|other name
##   lists are comma separated; unit terms are UO:
.parseCvLine <- function(line) {
  gsub_ <- sub
  grp <- NA_character_
  if (grepl("^\\[[0-9]+\\]", line)) {
    grp <- sub("^\\[([0-9]+)\\].*$", "\\1", line)
    line <- sub("^\\[[0-9]+\\]", "", line)
  }
  eq <- regexpr("=", line, fixed = TRUE)
  if (eq < 0) return(NULL)
  key <- substring(line, 1, eq - 1)
  val <- substring(line, eq + 1)
  bar <- regexpr("|", key, fixed = TRUE)
  if (bar < 0) return(NULL)                       # AMBIGUITY: line is not a cvparam
  acc <- substring(key, 1, bar - 1)
  nm  <- substring(key, bar + 1)
  valCv <- NA_character_
  if (grepl("^MS:[0-9]+\\||^UO:[0-9]+\\||^NCBITaxon:[0-9]+", val)) {
    vb <- regexpr("|", val, fixed = TRUE)
    if (vb > 0) { acc_v <- substring(val, 1, vb - 1); valCv <- val; val <- substring(val, vb + 1)
    } else { valCv <- val; val <- NA_character_ }
  }
  list(group = grp, accession = acc, name = nm, value = val, value_cv = valCv)
}

## ---- library reader --------------------------------------------------------
read_mzspeclib_txt <- function(file, max_spectra = Inf) {
  ln <- readLines(file)
  if (!length(ln) || ln[[1]] != "<mzSpecLib>")
    stop("missing <mzSpecLib> magic line")

  ## classify lines
  isSection <- grepl("^<[^>]+>$", ln)
  ## "<AttributeSet Spectrum=all>" has a SPACE before the type qualifier, so the
  ## name is the first token only; "^<([^>=]+)…>$" would swallow "AttributeSet Spectrum".
  secName   <- ifelse(isSection, sub("^<([^>=[:space:]]+)([[:space:]=].*)?>$", "\\1", ln), NA_character_)
  secIdx    <- ifelse(isSection, suppressWarnings(as.integer(sub("^<[^>=]+=?([^>]*)>$", "\\1", ln))), NA_integer_)
  isPeak    <- !isSection & grepl("^[0-9]", ln) & !grepl("=", ln)   # <-- FRAGILE, see notes
  isComment <- startsWith(ln, "#")
  isCv      <- !isSection & !isPeak & !isComment & grepl("=", ln)

  ## forward-fill section membership
  secIdx[is.na(secIdx)] <- ""
  cur <- ifelse(isSection, paste0(secName[isSection]), NA_character_)
  curKey <- ifelse(isSection,
                   paste0(secName, "=", secIdx), NA_character_)
  fill <- function(x) { i <- which(!is.na(x)); if (!length(i)) return(rep(NA_character_, length(x))); c(NA_character_, x[i])[findInterval(seq_along(x), i + 1L) + 1L] }
  memberOf <- fill(curKey)
  memberTyp <- fill(secName)
  ## peak rows live inside <Peaks>, which has no index: they must be attributed to
  ## the enclosing <Spectrum=N>. Without this, a naive section model loses all peaks.
  specOf <- fill(ifelse(!is.na(secIdx) & secName == "Spectrum",
                        paste0("Spectrum=", secIdx), NA_character_))
  memberOf[isPeak] <- specOf[isPeak]
  memberTyp[isPeak] <- "Spectrum"

  ## header
  hdrIdx <- which(memberTyp == "mzSpecLib" & isCv)
  header <- lapply(ln[hdrIdx], .parseCvLine)
  header <- header[!vapply(header, is.null, logical(1))]

  ## spectra
  specIds <- unique(memberOf[!is.na(memberTyp) & memberTyp == "Spectrum"])
  specIds <- specIds[!is.na(specIds)]
  n <- min(length(specIds), max_spectra)
  out <- vector("list", n)
  for (i in seq_len(n)) {
    key <- specIds[[i]]
    idx <- which(memberOf == key)
    cv <- lapply(ln[idx[isCv[idx]]], .parseCvLine)
    cv <- cv[!vapply(cv, is.null, logical(1))]
    pkLines <- ln[idx[isPeak[idx]]]
    sp <- strsplit(pkLines, "\t", fixed = TRUE)
    ncols <- vapply(sp, length, integer(1))
    peaks <- if (length(sp)) {
      mat <- do.call(rbind, lapply(sp, function(x) { length(x) <- max(ncols); x }))
      list(mz = as.numeric(mat[, 1]),
           intensity = as.numeric(mat[, 2]),
           annotation = if (ncol(mat) >= 3) mat[, 3] else NA_character_,
           extra = if (ncol(mat) >= 4) mat[, 4:ncol(mat), drop = FALSE] else NULL)
    } else NULL
    out[[i]] <- list(key = as.integer(sub("^Spectrum=", "", key)),
                     cv = cv, peaks = peaks)
  }
  ## Count SECTIONS, not the CV lines attributed to them. Counting lines instead is
  ## the single easiest way to fool yourself here: fetal_brain_tiny reports 280
  ## "analytes" that way when it has exactly 21 <Analyte> blocks.
  nsections <- function(want) sum(isSection & !is.na(secName) & secName == want)
  list(header = header, spectra = out,
       n_lines = length(ln),
       analyte_sections = nsections("Analyte"),
       interpretation_sections = nsections("Interpretation"),
       attribute_sets = nsections("AttributeSet"))
}

files <- c(
  "/home/hechth/dev/mzSpecLib/examples/spice.mzSpecLib.txt",
  "/home/hechth/dev/mzSpecLib/examples/NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.txt",
  "/home/hechth/dev/mzSpecLib/examples/SpectraST/fetal_brain_tiny.mzSpecLib.txt",
  "/home/hechth/dev/mzSpecLib/examples/NIST-CPTAC/broad_tcga_nonphospho_consensus_rec.head.mzSpecLib.txt",
  "/home/hechth/dev/mzSpecLib/examples/DIA-NN/phl004_canonical_sall_pv_plasma.head.diann.mzSpecLib.txt",
  "/home/hechth/dev/mzSpecLib/examples/Spectronaut/human_serum.head.spectronaut.mzSpecLib.txt"
)
for (f in files) {
  r <- tryCatch(read_mzspeclib_txt(f), error = function(e) { cat("ERROR", basename(f), ":", conditionMessage(e), "\n"); NULL })
  if (is.null(r)) next
  np <- vapply(r$spectra, function(s) length(s$peaks$mz), integer(1))
  cat(sprintf("%-58s hdr=%3d spectra=%3d peaks/spec=%5.0f analytes=%3d interpretations=%2d attrsets=%d\n",
              basename(f), length(r$header), length(r$spectra),
              if (length(np)) mean(np) else 0,
              r$analyte_sections, r$interpretation_sections, r$attribute_sets))
}

cat("\n--- first spectrum of the small-molecule example, as parsed ---\n")
r <- read_mzspeclib_txt(files[[1]], max_spectra = 1)
s <- r$spectra[[1]]
cat("key:", s$key, " peaks:", length(s$peaks$mz), "\n")
for (p in s$cv) cat(sprintf("  [%s] %s | %s = %s  (value_cv: %s)\n",
                            p$group %||% "-", p$accession, p$name, p$value, p$value_cv %||% "-"))
