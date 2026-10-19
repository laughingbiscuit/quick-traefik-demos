# Kubernetes only: HTTPS needs the websecure entrypoint and the step resolver, which are static config the VM lacks, and a :80 for step-ca to validate on.
# Plain HTTP only redirects: the app is served on :443.
GET {{base_url}}/
Host: api.traefik-hub.test
HTTP 301
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
