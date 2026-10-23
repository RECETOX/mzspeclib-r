#!/usr/bin/env bash
# Is mzSpecLib present in five analysis tools? Full default-branch source trees,
# not code search — re-measured 2026-10-22 because the GitHub code-search API
# rate-limited the *control* queries mid-check on the first pass, which is exactly
# the failure mode that turns a broken query into a confident-looking zero.
#
# Two rules, enforced below:
#   1. every tool is grepped for mzspeclib/mzpaf AND for two terms that must be
#      present in any proteomics tool's own source ("peptide", "mgf"). A zero with
#      dead controls means nothing.
#   2. hits are reported as FILES, and every non-zero hit is printed with context so
#      a substring accident is visible. Two were found and are documented in the
#      report: FlashLFQ matches "mzlib" because it depends on PNNL's *mzLib* (a
#      different library format), and SIRIUS matches it inside base64 in a bundled
#      JS asset. Neither is mzSpecLib.
#
# Usage:  bash tool_tree_grep.sh [workdir]      # default /tmp/toolsrc
# Network: ~200 MB of tarballs from codeload.github.com. Takes a couple of minutes.

set -u
WORK="${1:-/tmp/toolsrc}"
mkdir -p "$WORK"
cd "$WORK" || exit 1

# repo:branch — resolved via the GitHub API on 2026-10-22; note that FlashLFQ lives
# under smith-chem-wisc and spectrum_utils under bittremieuxlab (both moved org).
REPOS=(
  "wilhelm-lab/koina:main"
  "smith-chem-wisc/FlashLFQ:master"
  "Nesvilab/MSBooster:master"
  "sirius-ms/sirius:stable"
  "bittremieuxlab/spectrum_utils:main"
)
TERMS=(mzspeclib mzpaf mzlib)          # 'mzlib' is deliberately included: it is the
                                       # overloaded term, see the two false positives
CONTROLS=(peptide mgf "spectral library")

for entry in "${REPOS[@]}"; do
  repo="${entry%%:*}"; branch="${entry##*:}"
  slug="${repo//\//_}"
  tgz="$WORK/$slug.tgz"
  [ -s "$tgz" ] || curl -sSL -o "$tgz" "https://codeload.github.com/$repo/tar.gz/refs/heads/$branch" || {
    echo "!! $repo download failed"; continue; }
  dir=$(tar tzf "$tgz" 2>/dev/null | head -1 | cut -d/ -f1)
  [ -d "$WORK/$dir" ] || tar xzf "$tgz" -C "$WORK"
  nfiles=$(find "$WORK/$dir" -type f | wc -l)
  printf '\n== %s (%s)  files=%s\n' "$repo" "$branch" "$nfiles"
  for t in "${TERMS[@]}"; do
    hits=$(grep -rIl -i -- "$t" "$WORK/$dir" 2>/dev/null)
    cnt=$(printf '%s' "$hits" | grep -c . || true)
    printf '   %-16s files=%s\n' "$t" "$cnt"
    if [ "$cnt" -gt 0 ]; then
      grep -rIoi -E ".{0,40}${t}.{0,40}" "$WORK/$dir" 2>/dev/null | head -3 | sed 's/^/        /'
    fi
  done
  for c in "${CONTROLS[@]}"; do
    cnt=$(grep -rIl -i -- "$c" "$WORK/$dir" 2>/dev/null | grep -c . || true)
    printf '   CONTROL %-14s files=%s\n' "$c" "$cnt"
  done
done

cat <<'EOF'

Scope of the negatives above: the default-branch working tree of each repository at
the time of the fetch. Not covered: wiki/issue text, vendor documentation sites,
closed-source editions, and any plugin installed separately. A zero here means "no
mzSpecLib or mzPAF code or mention in the source I fetched", never "cannot support it".
EOF
