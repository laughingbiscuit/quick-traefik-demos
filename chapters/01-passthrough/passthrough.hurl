# The same /passthrough, answered by a different provider each time. On k3d they all run in one Traefik; on the VM
# they arrive with `./demo.sh export`. The X-Demo-Route header names the provider that answered.

# Ingress (the kubernetes provider)
GET {{base_url}}/passthrough
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo-Route" == "ingress"

# IngressRoute (kubernetescrd)
GET {{base_url}}/passthrough?route=ingressroute
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo-Route" == "ingressroute"

# HTTPRoute (kubernetesgateway)
GET {{base_url}}/passthrough?route=httproute
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo-Route" == "httproute"
