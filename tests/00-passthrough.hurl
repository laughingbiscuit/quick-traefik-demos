# Ingress
GET {{base_url}}/passthrough
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo-Route" matches /^(ingress|file)$/

# IngressRoute
GET {{base_url}}/passthrough?route=ingressroute
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo-Route" matches /^(ingressroute|file)$/

# HTTPRoute (Gateway API)
GET {{base_url}}/passthrough?route=httproute
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo-Route" matches /^(httproute|file)$/
