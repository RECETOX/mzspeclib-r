.libPaths(c("/tmp/rlib", .libPaths()))
suppressWarnings(suppressMessages({
  library(jsonlite); library(data.table)
}))
TXT <- "/tmp/work/data/bench.mzSpecLib.txt"
JSN <- "/tmp/work/data/bench.mzSpecLib.json"

tm <- function(label, expr) {
  g1 <- gc(reset = TRUE); on.exit(NULL)
  t <- system.time(res <- force(expr))
  gb <- sum(gc()[, 2]) / 1024
  cat(sprintf("%-46s user=%6.2f sys=%5.2f elapsed=%6.2f  heapMB~%6.0f  n=%s\n",
              label, t[[1]], t[[2]], t[[3]], gb,
              paste(format(dim(res))[1:2], collapse = "x")))
  invisible(res)
}

cat("sizes MB: text=", file.info(TXT)$size / 1e6, " json=", file.info(JSN)$size / 1e6, "\n\n")

## ---------------------------------------------------------------- 1. raw read
tm("readLines(all)",               readLines(TXT))
ln <- readLines(TXT)
isPeak <- grepl("^[0-9]", ln)
isHdr  <- grepl("^MS:|^\\[[0-9]+\\]MS:|^UO:|^<", ln)
cat("lines: total", length(ln), " peak", sum(isPeak), " header", sum(isHdr), "\n\n")

## ------------------------------------------- 2. header/CV parse (the real work)
tm("header CV parse: readLines+regmatches", {
  h <- ln[isHdr]
  m <- regmatches(h, regexec("^([^=]*)=(.*)$", h))
  key <- vapply(m, function(x) if (length(x) == 3) x[[2]] else NA_character_, character(1))
  val <- vapply(m, function(x) if (length(x) == 3) x[[3]] else NA_character_, character(1))
  key <- sub("^\\[[0-9]+\\]", "", key)
  acc <- sub("\\|.*$", "", key); nm <- sub("^[^|]*\\|", "", key)
  data.frame(section = h, accession = acc, name = nm, value = val,
             stringsAsFactors = FALSE)
})

## ------------------------------- 3. full text peak-list parse: base R strsplit
tm("peaks text parse: strsplit(vapply)", {
  p <- ln[isPeak]
  sp <- strsplit(p, "\t", fixed = TRUE)
  data.frame(mz = as.numeric(vapply(sp, `[`, character(1), 1)),
             intensity = as.numeric(vapply(sp, `[`, character(1), 2)),
             annot = vapply(sp, `[`, character(1), 3))
})

## ------------------------------------------- 4. full peak parse: data.table::fread
tm("peaks text parse: fread(text=)", {
  data.table::fread(paste(ln[isPeak], collapse = "\n"), sep = "\t",
                    col.names = c("mz", "intensity", "annot"), header = FALSE)
})

## --------------------- 5. per-spectrum grouped parse (what a real reader must do)
tm("grouped parse: readr-less split into per-spectrum peak matrices", {
  sid <- as.integer(sub("^<Spectrum=([0-9]+)>$", "\\1", ln))
  grp <- rep(NA_integer_, length(ln)); grp[!is.na(sid)] <- sid[!is.na(sid)]
  grp <- cumsum(!is.na(grp))[isPeak]
  peaks <- data.table(mz = as.numeric(sub("\t.*$", "", ln[isPeak])))
  out <- split(seq_along(grp), grp)
  length(out)
})

## -------------------------------------------------- 6. JSON parse (whole file)
tm("json: fromJSON(simplifyVector=TRUE)", {
  j <- jsonlite::fromJSON(JSN, simplifyVector = TRUE)
  length(j$spectra)
})
tm("json: fromJSON(simplifyVector=FALSE)", {
  j <- jsonlite::fromJSON(JSN, simplifyVector = FALSE)
  length(j$spectra)
})
tm("json: stream per-spectrum (fromJSON txt= on 1 spectra)", {
  ## proxy for streaming: read whole, then touch arrays
  j <- jsonlite::fromJSON(JSN, simplifyVector = TRUE)
  m <- unlist(j$spectra[[1]]$mzs); sum(m)
})

## ------------------------------- 7. numeric array materialisation cost (R side)
tm("materialise all mzs+intensities as list of matrices", {
  j <- jsonlite::fromJSON(JSN, simplifyVector = FALSE)
  out <- lapply(j$spectra, function(s)
    cbind(mz = unlist(s$mzs), intensity = unlist(s$intensities)))
  length(out)
})

## ----------------------------- 8. real-spec example files: correctness spot read
ex <- list.files("/home/hechth/dev/mzSpecLib/examples", recursive = TRUE,
                 pattern = "mzSpecLib\\.(txt|json)$", full.names = TRUE)
cat("\n--- checked-in example libraries (real files) ---\n")
for (f in ex) {
  t <- system.time({
    if (grepl("\\.txt$", f)) { z <- readLines(f) } else { z <- jsonlite::fromJSON(f) }
  })
  cat(sprintf("%-62s %6.2fs %s\n", basename(f), t[[3]],
              if (grepl("\\.txt$", f)) paste0(length(z), " lines") else paste0(length(z$spectra), " spectra")))
}
