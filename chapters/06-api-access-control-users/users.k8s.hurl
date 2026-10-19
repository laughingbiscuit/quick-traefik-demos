# Kubernetes only: the gateway gets Keycloak's keys through host.k3d.internal, and the application is a Kubernetes object.
# Two people sign in at Keycloak through the same application. Which of them is an admin is only a role in their token.

POST http://localhost:8180/realms/demo/protocol/openid-connect/token
[Form]
grant_type: password
client_id: demo-app
username: demo
password: Password123
HTTP 200
[Captures]
admin_token: jsonpath "$.access_token"
[Asserts]
jsonpath "$.access_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.realm_access.roles" includes "admin"

POST http://localhost:8180/realms/demo/protocol/openid-connect/token
[Form]
grant_type: password
client_id: demo-app
username: guest
password: Password123
HTTP 200
[Captures]
guest_token: jsonpath "$.access_token"
[Asserts]
jsonpath "$.access_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.realm_access" not exists
jsonpath "$.access_token" split "." nth 1 base64UrlSafeDecode charsetDecode "utf-8" jsonpath "$.azp" == "demo-app"

# --- Who may call what -------------------------------------------------------------------------------------------

GET {{base_url}}/catalog
Authorization: Bearer {{admin_token}}
HTTP 200
[Asserts]
body contains "Hostname: catalog-"

GET {{base_url}}/admin
Authorization: Bearer {{admin_token}}
HTTP 200
[Asserts]
body contains "Hostname: admin-"

GET {{base_url}}/catalog
Authorization: Bearer {{guest_token}}
HTTP 200

# Signed in, but not an admin
GET {{base_url}}/admin
Authorization: Bearer {{guest_token}}
HTTP 403

# --- Tokens the gateway must refuse ------------------------------------------------------------------------------

GET {{base_url}}/catalog
HTTP 401

GET {{base_url}}/catalog
Authorization: Bearer not-a-token
HTTP 401

# --- Who is calling, as the backend sees it ---------------------------------------------------------------------

GET {{base_url}}/catalog
Authorization: Bearer {{guest_token}}
X-User: demo
HTTP 200
[Asserts]
body contains "X-User: guest"
body not contains "X-User: demo"
