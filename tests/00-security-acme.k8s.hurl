# Kubernetes only: the VM can't own the :80 that step-ca validates on.
# Plain HTTP only redirects: the app is served on :443.
GET {{base_url}}/
Host: api.traefik-hub.test
HTTP 308
[Asserts]
header "Location" == "https://api.traefik-hub.test/"

# Traefik asked step-ca for api.traefik-hub.test (no certificate is pre-issued), so this is its own short-lived certificate.
# Until it arrives sniStrict refuses the handshake, and hurl's retry covers the wait.
GET https://api.traefik-hub.test:{{tls_port}}/
[Options]
resolve: api.traefik-hub.test:{{tls_port}}:127.0.0.1
HTTP 200
[Asserts]
body contains "Hostname:"
certificate "Subject" contains "api.traefik-hub.test"
certificate "Issuer" contains "Demo Intermediate CA"
certificate "Expire-Date" daysAfterNow < 2
