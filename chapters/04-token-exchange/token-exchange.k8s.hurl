# Kubernetes only: the middleware reaches Keycloak at host.k3d.internal and reads its client secret from a Kubernetes Secret.
# The caller signs in at Keycloak. Its token names the gateway as the audience.
POST http://localhost:8180/realms/demo/protocol/openid-connect/token
[Form]
grant_type: password
client_id: demo-app
username: demo
password: Password123
HTTP 200
[Captures]
user_token: jsonpath "$.access_token"
user_sub: jsonpath "$.access_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.sub"

# No token, no entry. A token Keycloak will not exchange gets no entry either.
GET {{base_url}}/token-exchange
HTTP 401

GET {{base_url}}/token-exchange
Authorization: Bearer not-a-token
HTTP 401

# With a token, the backend still gets a request, but not the caller's token: Traefik traded it at Keycloak for one made
# for the backend. whoami echoes the headers it received.
GET {{base_url}}/token-exchange
Authorization: Bearer {{user_token}}
HTTP 200
[Captures]
backend_token: regex "(?i)Authorization: Bearer (\\S+)"
[Asserts]
body contains "Hostname:"
body not contains {{user_token}}
variable "backend_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.aud" == "demo-backend"
variable "backend_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.azp" == "gateway"
variable "backend_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.sub" == {{user_sub}}
