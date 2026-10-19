#!/bin/sh
# Kubernetes only: it changes the cluster in the middle of the test, which a hurl file cannot do.
# Partner A has no subscription to Payments (see the chapter before). We add one, and take it away. Run by ./demo.sh test,
# or on its own from the repo root:   KUBECONFIG=$(k3d kubeconfig write k8s-demo) sh chapters/07-access-control-change/test.sh
set -u
. "$(dirname "$0")/../lib.sh"
sub=payments-access-partner-a
trap 'kubectl -n demo delete managedsubscription $sub --ignore-not-found > /dev/null 2>&1' EXIT
kubectl -n demo delete managedsubscription $sub --ignore-not-found > /dev/null 2>&1   # a clean start, whatever an earlier run left

A=$(token partner-a)

step "1. Partner A calls Payments. It is not subscribed to it"
hurl_inline "payments: 403" --variable token="$A" <<'HURL'
GET {{base_url}}/payments
Authorization: Bearer {{token}}
HTTP 403
HURL

step "2. Add one subscription for Partner A. Nothing changes at the identity provider, and the token is the same one"
kubectl apply -f - <<'YAML'
apiVersion: hub.traefik.io/v1alpha1
kind: ManagedSubscription
metadata: {name: payments-access-partner-a, namespace: demo}
spec:
  apiPlan: {name: standard}
  apis: [{name: payments}]
  managedApplications: [{name: partner-a}]
  claims: "Contains(`aud`, `payments-api`)"
YAML
hurl_inline "payments: 200, within seconds" --variable token="$A" <<'HURL'
GET {{base_url}}/payments
Authorization: Bearer {{token}}
HTTP 200
[Asserts]
body contains "Hostname: payments-"
HURL
hurl_inline "orders is as it was: 200" --variable token="$A" <<'HURL'
GET {{base_url}}/orders
Authorization: Bearer {{token}}
HTTP 200
HURL

step "3. Delete it. The access goes at once, though the token itself is still valid until it expires"
kubectl -n demo delete managedsubscription $sub > /dev/null
hurl_inline "payments: 403 again" --variable token="$A" <<'HURL'
GET {{base_url}}/payments
Authorization: Bearer {{token}}
HTTP 403
HURL

finish
