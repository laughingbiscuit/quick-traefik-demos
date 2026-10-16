#!/bin/sh
set -xe

m4 -P docs/*.md > index.md

#| pandoc -f markdown -s -o index.html