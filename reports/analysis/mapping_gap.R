## How much of real mzSpecLib metadata survives a mapping onto Spectra's
## spectraVariables?  Uses the real checked-in example libraries, all spectra.
.libPaths(c("/tmp/rlib", .libPaths()))

files <- list.files("/home/hechth/dev/mzSpecLib/examples", recursive = TRUE,
                    pattern = "mzSpecLib\\.txt$", full.names = TRUE)

## names that map onto a core/standard Spectra spectraVariable (verified list of
## 19 core variables from coreSpectraVariables() / .SPECTRA_DATA_COLUMNS)
MAPPED <- c(
  "retention time", "normalized retention time",
  "experimental precursor monoisotopic m/z", "selected ion m/z",
  "charge state", "collision energy", "ms level", "scan polarity",
  "precursor intensities", "isolation window target m/z",
  "isolation window lower offset", "isolation window upper offset",
  "spectrum index", "acquisition num", "data processing action"
)

nm <- c()
for (f in files) {
  ln <- readLines(f)
  cv <- ln[grepl("^(\\[[0-9]+\\])?(MS|UO|NCBITaxon):[0-9]+\\|[^=]+=", ln)]
  ## drop library-header-only terms by keeping only lines after the first <Spectrum=
  firstSpec <- min(which(grepl("^<Spectrum=[0-9]+>", ln)))
  cv <- cv[min(which(cv == cv[1])) > 0]                # placeholder
  cv <- ln[(firstSpec + 1):length(ln)]
  cv <- cv[grepl("^(\\[[0-9]+\\])?(MS|UO|NCBITaxon):[0-9]+\\|", cv)]
  n <- sub("^\\[[0-9]+\\]", "", cv)
  n <- sub("^[^|]*\\|", "", n); n <- sub("=.*$", "", n)
  nm <- c(nm, n)
}

tot <- length(nm)
tab <- sort(table(nm), decreasing = TRUE)
mapped <- names(tab) %in% MAPPED
nMapped <- sum(tab[mapped]); nUn <- sum(tab[!mapped])

cat(sprintf("real example .txt libraries: %d files, %d spectrum-level CV parameter occurrences\n", length(files), tot))
cat(sprintf("  mappable to a Spectra spectraVariable : %4d (%.1f%%)\n", nMapped, 100 * nMapped / tot))
cat(sprintf("  NO home in Spectra's model            : %4d (%.1f%%)\n", nUn, 100 * nUn / tot))
cat(sprintf("distinct terms: %d (mapped %d / unmapped %d)\n\n", length(tab), sum(mapped), sum(!mapped)))

cat("TOP unmapped terms (count):\n")
un <- tab[!mapped]
for (i in seq_len(min(22, length(un)))) cat(sprintf("  %6d  %s\n", un[i], names(un)[i]))
cat("\nAll mapped terms:\n")
for (i in seq_along(tab[mapped])) cat(sprintf("  %6d  %s\n", tab[mapped][i], names(tab[mapped])[i]))
