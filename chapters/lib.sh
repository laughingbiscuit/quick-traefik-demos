# Helpers for a chapter's test.sh. Source it:   . "$(dirname "$0")/../lib.sh"
# The k3d demo on localhost: the gateway on :8080. Needs hurl.
BASE=${BASE:-http://localhost:8080}
fails=0

step() { printf '\n%s\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fails=$((fails+1)); }
finish() { echo; if [ $fails -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi; }

# hurl_inline <label> [hurl options]: a hurl file on stdin, run against the k3d demo ({{base_url}}). A request that fails is
# retried for up to 20s, because the gateway takes a moment to pick up what was just applied. Each call has its own cookies
hurl_inline() {
  label=$1; shift
  f=$(mktemp "$PWD/.hurl-inline.XXXXXX")   # in the working directory: in CI hurl runs in a container that mounts it
  cat > "$f"
  if hurl --test --retry 20 --retry-interval 1000 --variable base_url="$BASE" "$@" "$f" > "$f.out" 2>&1; then ok "$label"
  else bad "$label"; sed 's/^/        /' "$f.out"; fi
  rm -f "$f" "$f.out"
}
