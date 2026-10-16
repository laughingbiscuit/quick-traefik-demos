# Shared by both demos. On Kubernetes each URL is answered by a different route
# type, named in X-Route; on the VM one file router answers all three ("file").

# Ingress
GET {{base_url}}/passthrough
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Route" matches /^(ingress|file)$/

# IngressRoute
GET {{base_url}}/passthrough?route=ingressroute
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Route" matches /^(ingressroute|file)$/

# HTTPRoute (Gateway API)
GET {{base_url}}/passthrough?route=httproute
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Route" matches /^(httproute|file)$/
