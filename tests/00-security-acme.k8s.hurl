# Kubernetes only: the VM can't own the :80 that step-ca validates on.
# Traefik asked step-ca for whoami.acme.test (outside the wildcard), so this is its own short-lived certificate.
GET https://whoami.acme.test:{{tls_port}}/
[Options]
resolve: whoami.acme.test:{{tls_port}}:127.0.0.1
HTTP 200
[Asserts]
body contains "Hostname:"
certificate "Subject" contains "whoami.acme.test"
certificate "Issuer" contains "Demo Intermediate CA"
certificate "Expire-Date" daysAfterNow < 2
