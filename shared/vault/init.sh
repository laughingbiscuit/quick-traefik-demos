#!/bin/sh
# Configures Vault headlessly (dev mode keeps nothing, so this runs on every start):
# a root CA, an ACME directory that issues from it, a wildcard role for the gateways, and a demo secret.
set -e

vault secrets list | grep -q '^pki/' || {
  # The headers are the ones ACME clients need Vault to pass through.
  vault secrets enable -max-lease-ttl=87600h \
    -passthrough-request-headers=If-Modified-Since \
    -allowed-response-headers=Last-Modified -allowed-response-headers=Location \
    -allowed-response-headers=Replay-Nonce -allowed-response-headers=Link pki
  vault write pki/root/generate/internal common_name="Demo Root CA" ttl=87600h
  vault write pki/config/cluster path=https://localhost:8200/v1/pki aia_path=https://localhost:8200/v1/pki
  vault write pki/roles/demo allow_any_name=true key_type=any max_ttl=72h
  # The gateways' own certificate: signed from a CSR, with the names taken from the request, not the CSR
  vault write pki/roles/wildcard allow_any_name=true key_type=any use_csr_sans=false max_ttl=720h
  vault write pki/config/acme enabled=true default_directory_policy=role:demo
}

vault kv put -mount=secret demo greeting=hello
