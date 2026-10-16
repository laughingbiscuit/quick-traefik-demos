#!/bin/sh
# Build the workshop deck into _site/ (what GitHub Pages publishes):
#   docs/deck.md.m4 -> _site/deck.md (m4 pulls in the real config files; also works with `mdp`)
#   _site/deck.md   -> _site/index.html (mdp2html: one self-contained page)
# Needs m4, yq, pandoc and mdp2html (github.com/laughingbiscuit/mdp2html) on the PATH.
set -e
cd "$(dirname "$0")"
mkdir -p _site
m4 -P docs/deck.md.m4 > _site/deck.md
mdp2html _site/deck.md > _site/index.html
