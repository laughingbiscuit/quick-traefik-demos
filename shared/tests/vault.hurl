# Vault is unsealed and its secrets engine stores and returns a secret
POST http://localhost:8200/v1/secret/data/smoke
X-Vault-Token: Password123
{"data": {"ok": "yes"}}
HTTP 200

GET http://localhost:8200/v1/secret/data/smoke
X-Vault-Token: Password123
HTTP 200
[Asserts]
jsonpath "$.data.data.ok" == "yes"
