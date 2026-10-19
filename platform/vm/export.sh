#!/bin/sh
# The k3d Traefik's dynamic config as file-provider YAML for the VM, on stdout. The sanity check behind
# `./demo.sh export`: everything k3d serves, run on a VM too.
#
#   export.sh URL CONTEXT BACKEND      export.sh http://localhost:8082 k3d-k8s-demo http://localhost:9500
#
# crd2file does the work (https://github.com/laughingbiscuit/crd2file): it reads URL/api/rawdata, points every
# service still on a pod IP at BACKEND (the whoami the VM runs), and drops the dashboard router, since the VM
# has no dashboard. A pinned release is downloaded once and checked against its SHA-256. To use your own copy,
# for example while changing crd2file:   CRD2FILE=~/src/crd2file/crd2file.sh ./demo.sh export
#
# Only dynamic config comes out. Static config (entrypoints, certificate resolvers, providers) does not:
# a route that needs the websecure entrypoint or the "step" resolver loads on the VM but can't work there.
set -eu

CRD2FILE_VERSION=v0.1
CRD2FILE_SHA256=98476be59518421d3b26a2d25593b2ad485c793098de80c809661c0f794b014a   # of the release's crd2file.sh

here=$(cd "$(dirname "$0")" && pwd)
url=${1:?usage: export.sh URL CONTEXT BACKEND} ctx=${2:?usage: export.sh URL CONTEXT BACKEND} backend=${3:?usage: export.sh URL CONTEXT BACKEND}

sha256() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

if [ -z "${CRD2FILE:-}" ]; then
  CRD2FILE=$here/generated/crd2file-$CRD2FILE_VERSION.sh   # `./demo.sh clean` removes it
  if [ ! -x "$CRD2FILE" ] || [ "$(sha256 "$CRD2FILE")" != "$CRD2FILE_SHA256" ]; then
    mkdir -p "$here/generated"
    curl -fsSL -o "$CRD2FILE" "https://github.com/laughingbiscuit/crd2file/releases/download/$CRD2FILE_VERSION/crd2file.sh"
    if [ "$(sha256 "$CRD2FILE")" != "$CRD2FILE_SHA256" ]; then
      rm -f "$CRD2FILE"
      echo "export.sh: crd2file $CRD2FILE_VERSION does not match the SHA-256 pinned in this script" >&2
      exit 1
    fi
    chmod +x "$CRD2FILE"
  fi
fi

exec sh "$CRD2FILE" -c "$ctx" -b "$backend" --drop-internal-routes "$url"
