#!/usr/bin/env bash
# How to run:  bash count_tool_sweep.sh [repo] [pattern]
#              (defaults: /home/hechth/dev/mzSpecLib  MS:1000045)
#
# Five counting tools over the SAME whole-tree target, to show that a "count over
# the repository" is a function of the tool and its file selection, not of the
# repository. Re-measured 2026-10-22 for report section 4.15. Each tool embeds a
# different default file selection:
#
#   grep -rc      reads every regular file, .git included; counts matching LINES
#   ugrep         not installed on this machine — the sweep says so instead of
#                 silently dropping a tool from its own tool list
#   rg            same trap one level further down: on this machine `rg` in an
#                 interactive shell is a Claude Code wrapper function around the
#                 CLI's bundled ripgrep, and `type -P rg` (an executable on PATH,
#                 functions excluded) finds nothing — so there is no ripgrep a
#                 script can run. The sweep probes for an executable, not for the
#                 name, and reports the absence. Where a real ripgrep exists it
#                 skips hidden (.git) and gitignored paths and binary files by
#                 default; --hidden --no-ignore undoes the file selection.
#   python walk   os.walk sees .git too; text is utf-8 decoded with errors="ignore",
#                 so binary hits appear as whatever survives decoding
#   find -exec    same file set as grep -rc, but grep runs per-file via + batches
#
# Two constructs are counted so the .txt/.json twin effect is visible: the bare
# accession (present in both serializations) and the accession|name concatenation
# (present in the text serialization only, because JSON splits the two fields).

set -u
REPO="${1:-/home/hechth/dev/mzSpecLib}"
ACCESSION="${2:-MS:1000045}"
CONCAT="$ACCESSION|collision energy"

count_occurrences () { # stdin -> occurrences
  wc -l | tr -d ' '
}

echo "repo:    $REPO"
echo "pattern: $ACCESSION   (and $CONCAT)"
echo

# 1. grep -rc, summed. Matching lines, not occurrences; every file including .git.
lines=$(grep -rc "$ACCESSION" "$REPO" 2>/dev/null | awk -F: '{s+=$NF} END {print s}')
echo "grep -rc (sum of per-file line counts, .git included):     $lines"

# 2. ugrep — report availability rather than pretending it ran.
if command -v ugrep >/dev/null 2>&1; then
  echo "ugrep: $(ugrep -r -c "$ACCESSION" "$REPO" 2>/dev/null | awk -F: '{s+=$NF} END {print s}')"
else
  echo "ugrep: not installed on this machine (command -v ugrep -> nothing);"
  echo "       a five-tool sweep that silently runs four tools is still four tools"
fi

# 3. ripgrep, default selection vs selection-forced-everything vs -o occurrences.
#    type -P looks for an executable on PATH and ignores functions/aliases, which
#    is the only honest availability test in an interactive shell (see header).
RGP=$(type -P rg)
if [ -n "$RGP" ]; then
  echo "rg -c (default: skips .git, gitignored, binary):           $("$RGP" -c "$ACCESSION" "$REPO" 2>/dev/null | awk -F: '{s+=$2} END {print s}')"
  echo "rg --hidden --no-ignore -c (selection forced wide):        $("$RGP" --hidden --no-ignore -c "$ACCESSION" "$REPO" 2>/dev/null | awk -F: '{s+=$2} END {print s}')"
  echo "rg --hidden --no-ignore -o | wc -l (occurrences):          $("$RGP" --hidden --no-ignore -o "$ACCESSION" "$REPO" 2>/dev/null | count_occurrences)"
else
  echo "rg: no executable named rg on PATH (type -P rg -> empty); the interactive"
  echo "    shell's rg is a Claude Code function wrapper, not a standalone tool"
fi

# 4. python walk, same wide file set as grep -rc, occurrence-counting.
python3 - "$REPO" "$ACCESSION" <<'PY'
import os, sys
root, pat = sys.argv[1], sys.argv[2]
total = 0
for dirpath, dirnames, filenames in os.walk(root):
    for name in filenames:
        try:
            with open(os.path.join(dirpath, name), 'rb') as fh:
                total += fh.read().decode('utf-8', errors='ignore').count(pat)
        except OSError:
            pass
print(f"python os.walk (occurrences, utf-8 errors=ignore):         {total}")
PY

# 5. find -exec grep — grep's own file set driven by find instead.
echo "find -type f -exec grep -o … + (occurrences, .git incl.):  $(find "$REPO" -type f -exec grep -o "$ACCESSION" {} + 2>/dev/null | count_occurrences)"

echo
# The twin effect: which files hold the accession, split by serialization.
echo "per-serialization split of the accession hits (text vs json vs other):"
find "$REPO" -type f \( -name '*.txt' -o -name '*.json' \) -exec grep -o "$ACCESSION" {} + 2>/dev/null |
  cut -d: -f1 | sed 's/.*\.mzSpecLib\.\(txt\|json\)$/mzSpecLib.\1/' | sort | uniq -c
echo "and of the accession|name concatenation (text only — JSON splits the two fields):"
find "$REPO" -type f -exec grep -o "$CONCAT" {} + 2>/dev/null | cut -d: -f1 | wc -l
echo
# A gz-aware sweep would be zgrep over *.gz; this tree contains none — checked:
echo "compressed files in the tree: $(find "$REPO" \( -name '*.gz' -o -name '*.zst' -o -name '*.bz2' \) | wc -l)"
