# websecure answers with the *.test certificate signed by step-ca's CA. Nothing routes there yet, hence the 404.
GET https://whoami.demo.test:{{tls_port}}/
[Options]
resolve: whoami.demo.test:{{tls_port}}:127.0.0.1
HTTP 404
[Asserts]
certificate "Subject" contains "*.test"
certificate "Issuer" contains "Demo Intermediate CA"
