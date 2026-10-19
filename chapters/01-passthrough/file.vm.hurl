# The file provider's route. A *.vm.hurl test passes on the hand-written VM config (vm/passthrough.yaml), and on k3d, where the
# same route runs through the file provider of the one Traefik (it is in platform/k8s/00-traefik-hub.yaml).
GET {{base_url}}/passthrough?route=file
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo-Route" == "file"
