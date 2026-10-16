#!/bin/sh
# Push the working tree as it is right now (committed or not, new files included)
# to Gitea's main. Your branch and index are untouched: this builds a throwaway commit.
set -e
cd "$(dirname "$0")"
idx=$(mktemp -u)
export GIT_INDEX_FILE=$idx
git add -A
tree=$(git write-tree)
rm -f "$idx"
unset GIT_INDEX_FILE
commit=$(git -c user.name=demo -c user.email=demo@example.com commit-tree "$tree" -p HEAD -m "Working tree snapshot")
git push --force -q gitea "$commit:refs/heads/main"
