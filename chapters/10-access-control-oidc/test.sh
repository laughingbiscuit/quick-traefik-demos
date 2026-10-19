#!/bin/sh
# Kubernetes only: the gateway reaches Keycloak through host.k3d.internal, and the login is a Kubernetes middleware.
# Two people sign in through a browser login. Each has their own hurl run, so each has their own cookies, as two browsers
# would. Run by ./demo.sh test, or on its own from the repo root:
#   KUBECONFIG=$(k3d kubeconfig write k8s-demo) sh chapters/10-access-control-oidc/test.sh
set -u
. "$(dirname "$0")/../lib.sh"

step "1. The admin signs in, and the page calls the API with the token the gateway forwarded"
hurl_inline "admin: login, portal, API 200" <<'HURL'

# No session: the gateway sends the browser to Keycloak, with a PKCE challenge.
GET {{base_url}}/portal
HTTP 302
[Captures]
login_url: header "Location"
[Asserts]
header "Location" startsWith "http://localhost:8180/realms/demo/protocol/openid-connect/auth"
header "Location" contains "code_challenge="

# Keycloak shows its login form.
GET {{login_url}}
HTTP 200
[Captures]
form_action: regex "action=\"([^\"]+)\"" replace "&amp;" "&"

# The person signs in. Keycloak sends the browser back to the gateway's callback.
POST {{form_action}}
[Form]
username: demo
password: Password123
credentialId:
HTTP 302
[Captures]
callback: header "Location"
[Asserts]
header "Location" startsWith "http://localhost:8080/oidc/callback"

# The gateway finishes the login, starts a session and sends the browser to the page.
GET {{callback}}
HTTP 302
[Asserts]
header "Location" endsWith "/portal"

# With a session the page answers. It is told who signed in, and gets their access token as a bearer token.
GET {{base_url}}/portal
HTTP 200
[Captures]
access_token: regex "(?i)Authorization: Bearer (\\S+)"
[Asserts]
body contains "Hostname: portal-"
body contains "X-User: demo"

# The app calls the API with that token. The token is valid either way: the role decides.
GET {{base_url}}/profile
Authorization: Bearer {{access_token}}
HTTP 200
[Asserts]
body contains "Hostname: portal-"

# Without a token the API is not reachable at all.
GET {{base_url}}/profile
HTTP 401
HURL

step "2. A user without the admin role signs in: the same login, a different answer from the API"
hurl_inline "guest: login, portal, API 403" <<'HURL'

# No session: the gateway sends the browser to Keycloak, with a PKCE challenge.
GET {{base_url}}/portal
HTTP 302
[Captures]
login_url: header "Location"
[Asserts]
header "Location" startsWith "http://localhost:8180/realms/demo/protocol/openid-connect/auth"
header "Location" contains "code_challenge="

# Keycloak shows its login form.
GET {{login_url}}
HTTP 200
[Captures]
form_action: regex "action=\"([^\"]+)\"" replace "&amp;" "&"

# The person signs in. Keycloak sends the browser back to the gateway's callback.
POST {{form_action}}
[Form]
username: guest
password: Password123
credentialId:
HTTP 302
[Captures]
callback: header "Location"
[Asserts]
header "Location" startsWith "http://localhost:8080/oidc/callback"

# The gateway finishes the login, starts a session and sends the browser to the page.
GET {{callback}}
HTTP 302
[Asserts]
header "Location" endsWith "/portal"

# With a session the page answers. It is told who signed in, and gets their access token as a bearer token.
GET {{base_url}}/portal
HTTP 200
[Captures]
access_token: regex "(?i)Authorization: Bearer (\\S+)"
[Asserts]
body contains "Hostname: portal-"
body contains "X-User: guest"

# The app calls the API with that token. The token is valid either way: the role decides.
GET {{base_url}}/profile
Authorization: Bearer {{access_token}}
HTTP 403
HURL

finish
