#!/bin/sh
# Build the workshop deck into _site/ (what GitHub Pages publishes):
#   docs/deck.md.m4 -> _site/deck.md (m4 pulls in the real config files; also works with `mdp`)
#   _site/deck.md   -> _site/index.html (mdp2html: one self-contained page)
# Needs m4, yq, pandoc and mdp2html (github.com/laughingbiscuit/mdp2html) on the PATH.
#
#   ./docs.sh                           the full deck: every chapter's slides.md, in order
#   ./docs.sh api-gateway passthrough   a deck for one customer: only these chapters, in this order
# A chapter is named by its directory (03-api-gateway) or without the number (api-gateway).
set -e
cd "$(dirname "$0")"

chapter() {   # <name>: the directory of the chapter with slides called that
  for d in chapters/*/; do
    n=${d#chapters/}; n=${n%/}
    if [ -f "$d/slides.md" ]; then case $n in "$1"|[0-9][0-9]-"$1") echo "$n"; return ;; esac; fi
  done
  echo "docs.sh: no chapter with slides called '$1'. Chapters:$(for d in chapters/*/slides.md; do d=${d#chapters/}; printf ' %s' "${d%/slides.md}"; done)" >&2
  exit 1
}

if [ $# -gt 0 ]; then
  SLIDES=$(for c in "$@"; do chapter "$c"; done)
else
  SLIDES=$(for d in chapters/[0-9][0-9]-*/; do if [ -f "$d/slides.md" ]; then n=${d#chapters/}; echo "${n%/}"; fi; done)
fi
export SLIDES

mkdir -p _site
m4 -P docs/deck.md.m4 > _site/deck.md

# mdp2html reads a --- straight after a line of text as a heading underline, not a slide break: the slides on either
# side would merge. Every --- needs a blank line before it (code blocks are left alone).
bad=$(awk '/^[ \t]*```/ { fence = !fence } !fence && $0 == "---" && prev != "" { printf " %d", NR } { prev = $0 }' _site/deck.md)
[ -z "$bad" ] || { echo "docs.sh: no blank line before --- on line(s)$bad of _site/deck.md: it would not split the slides" >&2; exit 1; }
mdp2html _site/deck.md > _site/index.html
