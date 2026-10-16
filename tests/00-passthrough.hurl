GET {{base_url}}/passthrough
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo" contains "true"

GET {{base_url}}/passthrough?route=ingress-route
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo" contains "true"

GET {{base_url}}/passthrough?route=http-route
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo" contains "true"