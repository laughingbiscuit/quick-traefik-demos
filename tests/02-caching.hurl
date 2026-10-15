# First call is a MISS, the same URL again is a HIT.
# A fresh id per run keeps earlier runs' cache entries out of the way:
# whoami echoes the request line, so capture the id and reuse it.
GET {{base_url}}/cache?run={{newUuid}}
HTTP 200
[Captures]
run: body regex "run=([0-9a-f-]+)"
[Asserts]
header "X-Cache-Status" == "MISS"

GET {{base_url}}/cache?run={{run}}
HTTP 200
[Asserts]
header "X-Cache-Status" == "HIT"
