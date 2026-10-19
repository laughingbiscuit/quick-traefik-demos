# Kubernetes only: the gateway gets Keycloak's keys through host.k3d.internal, and the subscription is a Kubernetes object.
# Partner A, with the same kind of token as before. The chapter before proves Partner A is denied Payments; here the access has been
# added. ./demo.sh test turns the chapters on one at a time, so each is tested while it is the newest one on.

POST http://localhost:8180/realms/demo/protocol/openid-connect/token
[BasicAuth]
partner-a: Password123
[Form]
grant_type: client_credentials
HTTP 200
[Captures]
partner_a: jsonpath "$.access_token"

# The subscription is applied: Payments now answers Partner A
GET {{base_url}}/payments
Authorization: Bearer {{partner_a}}
HTTP 200
[Asserts]
body contains "Hostname: payments-"

# Nothing else changed
GET {{base_url}}/orders
Authorization: Bearer {{partner_a}}
HTTP 200
