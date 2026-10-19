# Kubernetes only: the gateway gets Keycloak's keys through host.k3d.internal, and the clients are Kubernetes objects.
# Every client signs in with the OAuth2 client credentials grant. Their tokens are equally broad: the same scope, and
# both APIs in the audience. Only the gateway tells them apart.

POST http://localhost:8180/realms/partners/protocol/openid-connect/token
[BasicAuth]
partner-a: Password123
[Form]
grant_type: client_credentials
HTTP 200
[Captures]
partner_a: jsonpath "$.access_token"
[Asserts]
jsonpath "$.access_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.scope" == "all-services"
jsonpath "$.access_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.aud" count == 2
jsonpath "$.access_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.azp" == "partner-a"

POST http://localhost:8180/realms/partners/protocol/openid-connect/token
[BasicAuth]
partner-b: Password123
[Form]
grant_type: client_credentials
HTTP 200
[Captures]
partner_b: jsonpath "$.access_token"
[Asserts]
jsonpath "$.access_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.scope" == "all-services"
jsonpath "$.access_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.aud" count == 2

POST http://localhost:8180/realms/partners/protocol/openid-connect/token
[BasicAuth]
internal: Password123
[Form]
grant_type: client_credentials
HTTP 200
[Captures]
internal: jsonpath "$.access_token"

# --- Who may call what -------------------------------------------------------------------------------------------

GET {{base_url}}/orders
Authorization: Bearer {{partner_a}}
HTTP 200
[Asserts]
body contains "Hostname: orders-"
# The token reaches the backend as it came: the gateway decided, it did not change the token
body contains {{partner_a}}

GET {{base_url}}/payments
Authorization: Bearer {{partner_a}}
HTTP 403

GET {{base_url}}/orders
Authorization: Bearer {{partner_b}}
HTTP 403

GET {{base_url}}/payments
Authorization: Bearer {{partner_b}}
HTTP 200
[Asserts]
body contains "Hostname: payments-"

GET {{base_url}}/orders
Authorization: Bearer {{internal}}
HTTP 200

GET {{base_url}}/payments
Authorization: Bearer {{internal}}
HTTP 200

# --- Tokens the gateway must refuse ------------------------------------------------------------------------------

# No token
GET {{base_url}}/orders
HTTP 401

# Not a token
GET {{base_url}}/orders
Authorization: Bearer not-a-token
HTTP 401

# A genuine token, signed by Keycloak, but from another realm: not the issuer the gateway trusts
POST http://localhost:8180/realms/master/protocol/openid-connect/token
[Form]
grant_type: password
client_id: admin-cli
username: demo
password: Password123
HTTP 200
[Captures]
other_issuer: jsonpath "$.access_token"

GET {{base_url}}/orders
Authorization: Bearer {{other_issuer}}
HTTP 401

# A valid token for a client the gateway has never been told about: who it is is not enough, it needs a subscription
POST http://localhost:8180/realms/partners/protocol/openid-connect/token
[BasicAuth]
partner-short-lived: Password123
[Form]
grant_type: client_credentials
HTTP 200
[Captures]
short_lived: jsonpath "$.access_token"

GET {{base_url}}/orders
Authorization: Bearer {{short_lived}}
HTTP 403

# The same token once it has expired (its lifetime is 2 seconds)
GET {{base_url}}/orders
Authorization: Bearer {{short_lived}}
[Options]
delay: 4000
HTTP 401

# --- Who is calling, as the backend sees it ---------------------------------------------------------------------

# The gateway tells the backend which client it verified, and overwrites a header the caller made up
GET {{base_url}}/orders
Authorization: Bearer {{partner_a}}
X-Client-Id: internal
HTTP 200
[Asserts]
body contains "X-Client-Id: partner-a"
body not contains "X-Client-Id: internal"
