# Kubernetes only: the four providers run in one Traefik on k3d, and the dashboard is that Traefik's API.
# One URL, four providers: the same /passthrough, answered by a different provider's route each time.

GET {{base_url}}/passthrough
HTTP 200
[Asserts]
header "X-Demo-Route" == "ingress"

GET {{base_url}}/passthrough?route=ingressroute
HTTP 200
[Asserts]
header "X-Demo-Route" == "ingressroute"

GET {{base_url}}/passthrough?route=httproute
HTTP 200
[Asserts]
header "X-Demo-Route" == "httproute"

# The file provider's route: in the same Traefik, from a file
GET {{base_url}}/passthrough?route=file
HTTP 200
[Asserts]
header "X-Demo-Route" == "file"

# One dashboard: every provider is in this one Traefik
GET http://localhost:8082/api/overview
HTTP 200
[Asserts]
jsonpath "$.providers" includes "KubernetesIngress"
jsonpath "$.providers" includes "KubernetesCRD"
jsonpath "$.providers" includes "KubernetesGateway"
jsonpath "$.providers" includes "File"
