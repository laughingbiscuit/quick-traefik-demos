# The demo realm is imported, and the demo user can get a token with the admin role
GET http://localhost:8180/realms/demo/.well-known/openid-configuration
HTTP 200
[Asserts]
jsonpath "$.issuer" == "http://localhost:8180/realms/demo"

POST http://localhost:8180/realms/demo/protocol/openid-connect/token
[FormParams]
client_id: traefik
client_secret: traefik-secret
grant_type: password
username: demo
password: Passw0rd!
HTTP 200
[Asserts]
jsonpath "$.access_token" exists
