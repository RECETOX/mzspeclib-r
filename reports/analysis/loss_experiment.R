.libPaths(c("/tmp/rlib", .libPaths()))
suppressMessages({library(Spectra); library(IRanges)})

## Minimal hand-written reader for the REAL spice.mzSpecLib.txt (small molecule)
## and one proteomics file, to ask: what survives a trip through Spectra?
f <- "/home/hechth/dev/mzSpecLib/examples/spice.mzSpecLib.txt"
ln <- readLines(f)

parseCv <- function(x) {
  m <- regmatches(x, regexec("^([^=]*)=(.*)$", x))[[1]]
  if (length(m) != 3) return(NULL)
  key <- sub("^\\[[0-9]+\\]", "", m[2])
  list(accession = sub("\\|.*$", "", key),
       name = sub("^[^|]*\\|", "", key),
       value = m[3])
}
isSpec <- grepl("^<Spectrum=[0-9]+>$", ln)
specLines <- which(isSpec)
peakStart <- which(ln == "<Peaks>")
## spectrum 1 only
s1 <- (specLines[1] + 1):(if (length(peakStart) > 1) peakStart[2] - 1 else length(ln))
blk <- ln[s1]
meta <- Filter(Negate(is.null), lapply(blk[grepl("=", blk) & !grepl("^<", blk)], parseCv))
metaD <- do.call(rbind, lapply(meta, function(x) data.frame(x, stringsAsFactors = FALSE)))

pk <- ln[(peakStart[1] + 1):length(ln)]
pk <- pk[grepl("^[0-9]", pk)]
pm <- strsplit(pk, "\t", fixed = TRUE)
peaks <- cbind(mz = as.numeric(vapply(pm, `[`, character(1), 1)),
               intensity = as.numeric(vapply(pm, `[`, character(1), 2)))

cat("=== mzSpecLib spectrum 1: ", nrow(metaD), " CV parameters, ", nrow(peaks), " peaks\n", sep = "")
print(metaD[, c("accession", "name", "value")], right = FALSE)

## Now shove it into Spectra the way a pure-backend implementation would.
sd <- DataFrame(
  msLevel = 2L,
  rtime = as.numeric(metaD$value[metaD$name == "retention time"]),
  precursorMz = as.numeric(metaD$value[metaD$name == "experimental precursor monoisotopic m/z"]),
  precursorCharge = as.integer(metaD$value[metaD$name == "charge state"]),
  collisionEnergy = as.numeric(metaD$value[metaD$name == "collision energy"]),
  dataStorage = basename(f), dataOrigin = basename(f),
  mz = NumericList(peaks[, "mz"]), intensity = NumericList(peaks[, "intensity"])
)
sp <- Spectra(sd)
cat("\n=== after Spectra round-trip: spectraVariables available ===\n")
print(spectraVariables(sp))

cat("\n=== what got LOST (present in mzSpecLib, no home in Spectra) ===\n")
lost <- setdiff(metaD$name, c("retention time",
    "experimental precursor monoisotopic m/z", "charge state", "collision energy"))
cat(length(lost), "of", nrow(metaD), "CV parameters dropped/ homeless:\n")
cat(paste0("  - ", lost, "  [", metaD$accession[match(lost, metaD$name)], "]\n", collapse = ""), sep = "")

cat("\n=== does Spectra expose library-level header metadata? ===\n")
cat("'metadata' exported from Spectra namespace:", "metadata" %in% getNamespaceExports("Spectra"), "\n")
cat("'metadata' is a slot on Spectra:", "metadata" %in% slotNames("Spectra"), "\n")
cat("value of that slot for our object: "); print(slot(sp, "metadata"))

cat("\n=== per-peak annotation column support ===\n")
cat("peaksVariables() generic exported by Spectra:",
    "peaksVariables" %in% getNamespaceExports("Spectra"), "\n")
cat("can peaksData return >2 columns here? try:\n")
r <- tryCatch({
  peaksData(sp, columns = c("mz", "intensity"))
}, error = function(e) conditionMessage(e))
print(r)
