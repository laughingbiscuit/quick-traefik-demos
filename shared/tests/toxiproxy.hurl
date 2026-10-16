# Toxiproxy is up with the proxies from toxiproxy.json
GET http://localhost:8474/proxies
HTTP 200
[Asserts]
jsonpath "$.redis.enabled" == true
jsonpath "$['api-v1'].enabled" == true
jsonpath "$['api-v2'].enabled" == true
