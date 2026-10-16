# Vault is unsealed, PKI has its root CA, ACME is on, and the demo secret is there
GET https://localhost:8200/v1/secret/data/demo
X-Vault-Token: root
HTTP 200
[Asserts]
jsonpath "$.data.data.greeting" == "hello"

GET https://localhost:8200/v1/pki/ca/pem
HTTP 200
[Asserts]
body contains "BEGIN CERTIFICATE"

GET https://localhost:8200/v1/pki/config/acme
X-Vault-Token: root
HTTP 200
[Asserts]
jsonpath "$.data.enabled" == true

GET https://localhost:8200/v1/pki/acme/directory
HTTP 200
[Asserts]
jsonpath "$.newOrder" exists
