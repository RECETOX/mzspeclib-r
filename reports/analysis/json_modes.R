## jsonlite JSON-read modes on the REAL checked-in mzSpecLib JSON examples, and
## on the synthetic bench corpus. Written because report §4.7 previously claimed
## "simplifyVector = TRUE is an order of magnitude slower than FALSE" — that was
## measured on an ad-hoc corpus whose JSON nested objects per peak, and it does
## not reproduce on the real serialisation (parallel mzs/intensities/
## peak_annotations arrays). Run: Rscript json_modes.R
tm1 <- function(expr) { t <- system.time(j <<- force(expr)); t[["elapsed"]] }
real <- c(
  "/home/hechth/dev/mzSpecLib/examples/SpectraST/fetal_brain_tiny.mzSpecLib.json",
  "/home/hechth/dev/mzSpecLib/examples/NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.json",
  "/tmp/work/data/bench.mzSpecLib.json")
reps <- 5L
for (x in real) {
  if (!file.exists(x)) { cat("missing:", x, "\n"); next }
  cat(sprintf("\n%s  (%.0f KB)\n", basename(x), file.info(x)$size / 1000))
  res <- list()
  for (s in c(TRUE, FALSE)) {
    t <- replicate(reps, tm1(jsonlite::fromJSON(x, simplifyVector = s)))
    res[[as.character(s)]] <- median(t)
    ## length() is what a naive reader trusts; nrow() only exists in the data.frame
    cat(sprintf("  simplifyVector=%-5s median=%6.3f s  range=[%.3f-%.3f]  length(spectra)=%3d  nrow=%s\n",
                s, median(t), min(t), max(t), length(j$spectra),
                if (is.data.frame(j$spectra)) nrow(j$spectra) else "-"))
  }
  cat(sprintf("  TRUE/FALSE ratio     %.2f\n", res[["TRUE"]] / res[["FALSE"]]))
}

## ---- the trap this script actually found -------------------------------
## With simplifyVector = TRUE, `spectra` is a data.frame, so length() reports the
## number of *columns*, not the number of spectra — silently wrong, no error.
x <- "/home/hechth/dev/mzSpecLib/examples/SpectraST/fetal_brain_tiny.mzSpecLib.json"
a <- jsonlite::fromJSON(x, simplifyVector = TRUE)
b <- jsonlite::fromJSON(x, simplifyVector = FALSE)
ln <- readLines(sub("[.]json$", ".txt", x))
cat(sprintf("\nlength(fromJSON(TRUE)$spectra)  = %d   <-- number of COLUMNS\n", length(a$spectra)))
cat(sprintf("length(fromJSON(FALSE)$spectra) = %d   <-- number of SPECTRA\n", length(b$spectra)))
cat(sprintf("<Spectrum=N> sections in the .txt twin = %d  (so FALSE is the one that is right)\n",
            sum(grepl("^<Spectrum=[0-9]+>$", ln))))
cat(sprintf("dim(fromJSON(TRUE)$spectra)       = %s   mzs is a list-column of %s vectors\n",
            paste(dim(a$spectra), collapse = " x "), class(a$spectra$mzs)[1]))
