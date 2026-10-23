## Generator for the synthetic benchmark corpus used by bench2.R (report §4.7).
##
## Why this file exists: the corpus §4.7 was originally measured on lived in
## /tmp/work/data and is gone, and it was never checked in — so those timings
## were not reproducible. This regenerates a corpus of the same *shape* from a
## fixed seed. Sizes are whatever this script reports; §4.7 quotes the numbers
## produced by this generator, not the lost original.
##
## Usage:  Rscript bench_gen.R [outdir]        # default /tmp/work/data
## Then:   Rscript bench2.R

args <- commandArgs(trailingOnly = TRUE)
outdir <- if (length(args)) args[[1]] else "/tmp/work/data"
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

set.seed(20260929L)                     # fixed: the corpus must be reproducible

## ---- shape ------------------------------------------------------------
n_spec   <- 6000L                       # spectra
n_peak   <- 330497L                     # total peak rows (mean 55.1 / spectrum)
n_cv_hdr <- 8L                          # library-level CV parameter lines
## per spectrum: <Spectrum=>, <Analyte=>, 2 analyte CV, 1 NCBITaxon CV (not
## matched by bench2.R's header regex), <Interpretation=>, 1 interp CV,
## <Peaks=>, 6 spectrum CV  = 12 lines on top of the peak rows.
per_spec <- c(spec = 1L, analyte = 2L, taxon = 1L, interp = 2L, peaks = 1L,
              spec_cv = 6L)

## ---- peak counts: lognormal, then pinned so the total is exactly n_peak ----
pk <- round(rlnorm(n_spec, meanlog = 3.4, sdlog = 0.55))
pk <- pmax(4L, as.integer(pk))
pk[length(pk)] <- as.integer(n_peak - sum(pk[-length(pk)]))
while (pk[length(pk)] < 4L) {            # keep the last spectrum plausible
  j <- which.max(pk); pk[j] <- pk[j] - 1L
  pk[length(pk)] <- pk[length(pk)] + 1L
}
stopifnot(sum(pk) == n_peak)

## annotation and sequence forms copied verbatim from the style used in
## examples/SpectraST/fetal_brain_tiny.mzSpecLib.txt (mzPAF: ion + optional
## neutral loss + delta, and "?" for unannotated peaks)
ann <- c("?", "?", "b3/0.0123", "y7/0.0041", "b5-H2O/-0.0008",
         "IC[Carbamidomethyl]/-0.0008", "IC[Carbamidomethyl]+i/0.0027", "a2/0.0066")
pep <- c("PEPTIDEK", "FAC[Carbamidomethyl]HSASLTVR", "ELVIDNQK", "GDFSETGK",
         "TVPVPIAPLGK", "ISGLYFGAGASVVK", "DAASGLVDLGTR")

txt <- file.path(outdir, "bench.mzSpecLib.txt")
con <- file(txt, "w")
writeLines("<mzSpecLib>", con)
## library header: exactly n_cv_hdr CV parameter lines. Every accession|name pair
## below is copied VERBATIM from a checked-in example library
## (examples/SpectraST/fetal_brain_tiny.mzSpecLib.txt) or from the normative table —
## nothing is invented. Note the grouped `[1]…` provenance lines and the
## CV-term-as-value form, both of which a naive reader gets wrong.
## (An earlier revision of this script wrote `UO:0000266|intensity unit=relative
## intensity`; UO:0000266 is `electronvolt`, so that pairing was invented. Fixed
## 2026-10-22 after checking every term against OLS + the examples.)
writeLines(c(
  "MS:1003186|library format version=1.0",
  "MS:1003190|library version=1",
  "MS:1003187|library identifier=mzspec:bench:synthetic",
  "MS:1003188|library name=bench synthetic library",
  "MS:1003189|library description=synthetic benchmark data, not a real library",
  "MS:1001017|release date=2023-05-04T00:00:00",
  "[1]MS:1003207|library creation software=MS:1001477|SpectraST",
  "[1]MS:1003200|software version=6.0"
), con)

## one <Analyte> + one <Interpretation> per spectrum, 16 structural/CV lines per
## spectrum on top of the peak rows (15 of them matched by bench2.R's header
## regex; the NCBITaxon line is not, which is realistic and worth keeping)
for (i in seq_len(n_spec)) {
  np <- pk[[i]]
  writeLines(sprintf("<Spectrum=%d>", i), con)
  writeLines(c(
    sprintf("MS:1003063|universal spectrum identifier=mzspec:bench:SPEC%d", i),
    sprintf("[0]MS:1003237|library spectrum key=%d", i),
    sprintf("[0]MS:1003062|library spectrum index=%d", i),
    sprintf("MS:1000511|ms level=%d", if (i %% 3L == 0L) 1L else 2L),
    sprintf("MS:1003208|experimental precursor monoisotopic m/z=%.4f",
            runif(1, 300, 1500)),
    sprintf("MS:1000041|charge state=%d", sample(1:4, 1)),
    sprintf("MS:1000894|retention time=%.4f min", runif(1, 0, 240))
  ), con)
  writeLines(c("<Analyte=1>",
               sprintf("MS:1003270|proforma peptidoform ion notation=%s/%d",
                       sample(pep, 1), sample(1:4, 1)),
               sprintf("MS:1003043|number of residues=%d", sample(7:25, 1))), con)
  writeLines("NCBITaxon:9606|taxonomy: scientific name=Homo sapiens", con)
  writeLines(c("<Interpretation=1>",
               sprintf("MS:1003288|number of unassigned peaks=%d", sample(0:200, 1)),
               sprintf("MS:1003079|total unassigned intensity fraction=%.2f",
                       runif(1, 0, 1))), con)
  writeLines("<Peaks>", con)
  mz  <- sort(runif(np, 100, 1800))
  int <- round(rexp(np, 1 / 2e5), 3)
  an  <- sample(ann, np, replace = TRUE)
  writeLines(sprintf("%.6f\t%.3f\t%s", mz, int, an), con)   # 3 columns, as upstream
}
close(con)

## ---- a JSON corpus of the same size and nesting ------------------------
## NOTE: this is a *timing corpus*, not a valid mzSpecLib JSON document — the
## keys and nesting imitate the real serialization closely enough to measure
## jsonlite::fromJSON, but it is not schema-valid and must not be fed to the
## python reference implementation. Content is re-drawn, so it is not the same
## library as the .txt above.
## Built as text on purpose: jsonlite::toJSON on the nested list would measure
## the encoder, not the reader, and is slow enough to dominate this script.
## Shape imitated from examples/SpectraST/fetal_brain_tiny.mzSpecLib.json:
## top-level keys and per-spectrum keys are ALPHABETICAL, and peaks are three
## parallel arrays (mzs / intensities / peak_annotations), not an array of objects.
jsn <- file.path(outdir, "bench.mzSpecLib.json")
jc <- file(jsn, "w")
writeLines('{', jc)
writeLines('  "analyte_attribute_sets": { "all": [] },', jc)
hdrTerms <- c("MS:1003186|library format version|\"1.0\"",
              "MS:1003188|library name|\"bench synthetic library\"",
              "MS:1003187|library identifier|\"mzspec:bench:synthetic\"",
              "MS:1003190|library version|\"1\"",
              "MS:1003189|library description|\"synthetic benchmark data\"",
              "MS:1001017|release date|\"2023-05-04T00:00:00\"",
              "MS:1003200|software version|\"6.0\"",
              "MS:1003207|library creation software|\"SpectraST\"")
writeLines(paste0('  "attributes": [', paste(vapply(hdrTerms, function(s) {
  p <- strsplit(s, "|", fixed = TRUE)[[1]]
  sprintf('{"accession":"%s","name":"%s","value":%s}', p[1], p[2], p[3])
}, character(1)), collapse = ","), '],'), jc)
writeLines('  "clusters": {},', jc)
writeLines('  "format_version": "1.0",', jc)
writeLines('  "interpretation_attribute_sets": { "all": [] },', jc)
writeLines('  "spectra": [', jc)
for (i in seq_len(n_spec)) {
  np <- pk[[i]]
  mz  <- sort(runif(np, 100, 1800))
  int <- round(rexp(np, 1 / 2e5), 3)
  an  <- sample(ann, np, replace = TRUE)
  writeLines(sprintf(paste0(
    '    {"analytes":{"1":{"attributes":[]}},"attributes":[',
    '{"accession":"MS:1000041","name":"charge state","value":2}],',
    '"intensities":[%s],"interpretations":{"1":{"attributes":[]}},',
    '"mzs":[%s],"peak_annotations":[%s]}%s'),
    paste(sprintf("%.3f", int), collapse = ","),
    paste(sprintf("%.6f", mz), collapse = ","),
    paste(sprintf('"%s"', an), collapse = ","),
    if (i < n_spec) "," else ""), jc)
}
writeLines('  ],', jc)
writeLines('  "spectrum_attribute_sets": { "all": [] }', jc)
writeLines('}', jc)
close(jc)

## ---- report the shape that bench2.R's numbers refer to ------------------
ln <- readLines(txt)
cat(sprintf("wrote %s  (%.3f MB, %d lines)\n", txt, file.info(txt)$size / 1e6, length(ln)))
cat(sprintf("wrote %s (%.3f MB)\n", jsn, file.info(jsn)$size / 1e6))
cat(sprintf("spectra=%d  peak rows=%d  non-peak lines/spec=%d  header-matching lines=%d  ncv=%d  total lines=%d\n",
            n_spec, sum(pk), 16L,
            sum(grepl("^MS:|^\\[[0-9]+\\]MS:|^UO:|^<", ln)),
            sum(grepl("^MS:|^\\[[0-9]+\\]MS:|^UO:", ln)), length(ln)))
