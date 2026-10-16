GET {{base_url}}/passthrough
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo" contains "true"

GET {{base_url}}/passthrough?route=ingressroute
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo" contains "true"

GET {{base_url}}/passthrough?route=httproute
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo" contains "true"