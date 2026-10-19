# The file provider's route, on the VM: Traefik reads file-provider.yaml and serves it, with no Kubernetes. This test goes to the VM, and
# after `export` it passes there too. On k3d the same route runs through the file provider of the one Traefik (platform/k8s/00-traefik-hub.yaml).
GET {{base_url}}/passthrough?route=file
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo-Route" == "file"
