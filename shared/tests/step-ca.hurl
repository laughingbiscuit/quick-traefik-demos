# The CA is healthy, serves its root, and has an ACME directory
GET https://localhost:9000/health
HTTP 200
[Asserts]
jsonpath "$.status" == "ok"

GET https://localhost:9000/roots.pem
HTTP 200
[Asserts]
body contains "BEGIN CERTIFICATE"

GET https://localhost:9000/acme/acme/directory
HTTP 200
[Asserts]
jsonpath "$.newOrder" exists
