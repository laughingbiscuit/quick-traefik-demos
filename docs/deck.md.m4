m4_changequote([[[,]]])m4_dnl
<!--
title: Traefik Hub Workshop
author: laughingbiscuit
date: m4_esyscmd([[[date +%d/%m/%y]]])
-->

# Traefik Hub Workshop

---

# Introduction

Traefik provides a self-configuring layer to route, secure and observe 
  traffic across VMs, K8s, APIs, MCP and LLMs in a single binary

---

# Lab Environment

TL;DR:

- Kubernetes with k3d
- VM with Lima
- GitOps with Gitea + Flux
- Testing with curl, hurl and hey
- Redis, Keycloak, OPA and Toxiproxy also available 

You can verify the test results and try yourself with this [repo](https://github.com/laughingbiscuit/quick-traefik-demos)

---

# Installing Traefik 

One binary that runs on:

- Kubernetes via Helm
- Docker / Docker Compose
- Hashicorp Nomad 
- Linux under systemd (connected or fully air-gapped)
- Cloud marketplaces
- Also available as a FIPS 140-3 Hardened Image

This demo uses Flux/Helm for Kubernetes and the binary in systemd on VM

---

# Hands on - Passthrough

Every request passes through 4 stages: 

`Entrypoint -> Router -> Middleware -> Service`

---

__Entrypoint__ 

- listener bound to a port and a protocol (TCP, UDP, HTTP, HTTP/2, HTTP/3)
- configured on installation

__Router__ 

- matches the request against a rule such as Host() or PathPrefix() and selects what happens next
- supports vanilla Kubernetes Ingress, Traefik IngressRoute, Gateway API HTTPRoute and file-based configuration

__Middleware__ 

- an ordered chain of transformations and policies to protect and manage your APIs, Models and MCP tools 

__Service__ 

- the load-balanced pool of backend instances that receives the request 
- supports external endpoints

---

## Kubernetes Entrypoint

```
# k8s-providers/stack/00-traefik-hub.yaml

m4_esyscmd([[[yq 'select(.kind == "HelmRelease") | .spec.values | {"ports": .ports, "gateway": .gateway}' k8s-providers/stack/00-traefik-hub.yaml]]])
```

---

## Kubernetes Route Options - Ingress

```
# k8s-providers/scenarios/00-passthrough-ingress.yaml

m4_esyscmd([[[sed '/^---$/,$d' k8s-providers/scenarios/00-passthrough-ingress.yaml]]])
```

Annotations are validated at runtime :-(

---

## Kubernetes Route Options - IngressRoute

```
# k8s-providers/scenarios/00-passthrough-ingressroute.yaml

m4_esyscmd([[[sed '/^---$/,$d' k8s-providers/scenarios/00-passthrough-ingressroute.yaml]]])
```

---

## Kubernetes Route Options - HTTPRoute

```
# k8s-providers/scenarios/00-passthrough-httproute.yaml

m4_esyscmd([[[sed '/^---$/,$d' k8s-providers/scenarios/00-passthrough-httproute.yaml]]])
```

Annotations are validated at deploy time :-)

---

## Middleware and Service

Here is an example of a simple middleware:

```
# k8s-providers/scenarios/00-passthrough-ingress.yaml

m4_esyscmd([[[sed '1,/^---$/d' k8s-providers/scenarios/00-passthrough-ingress.yaml]]])
```

and the corresponding Service:

```
# k8s-providers/stack/01-whoami.yaml

m4_esyscmd([[[sed '1,/^---$/d' k8s-providers/stack/01-whoami.yaml]]])
```

---

## File Provider Entrypoint, Route, Middleware, Service

```
# file-provider/traefik-static.yaml

m4_esyscmd([[[yq '.entryPoints' file-provider/traefik-static.yaml]]])
```

```
# file-provider/scenarios/00-passthrough.yaml

m4_include([[[file-provider/scenarios/00-passthrough.yaml]]])
```

---

## Result

We have successfully proxied a request through our Traefik Hub!

```
$ curl -I traefik.test:8080/passthrough
HTTP/1.1 200 OK
Content-Length: 396
Content-Type: text/plain; charset=utf-8
Date: Fri, 16 Oct 2026 13:46:34 GMT
X-Route: ingress
```

---

# Hands on - Security: ACME

ACME (RFC 8555) lets software get a certificate from a CA with no human in the loop

Three parties:

- __Traefik__ is the ACME client: it does the work
- __CA__ (e.g. DigiCert, Let's Encrypt, or whatever the customer uses today; in this demo step-ca): it decides what to trust
  Any CA that speaks ACME works the same way. You change `caServer`, add `caCertificates` for a private CA, and add `eab` if the CA needs external account binding (DigiCert does)
- __You__ are the operator: you say which CA, which names and which challenge

---

## ACME - who owns which step

1. __Register__ - *Traefik* makes an account key pair and registers it with the *CA*
2. __Order__ - *Traefik* asks for a certificate for the `Host()` names on a router that has `tls.certResolver`
3. __Authorize__ - the *CA* sets a challenge, *Traefik* answers it on `:80`, the *CA* checks the answer
4. __Issue__ - *Traefik* sends a CSR, the *CA* signs it
5. __Install__ - *Traefik* loads the certificate and serves it by SNI, with no restart
6. __Renew__ - *Traefik* repeats 2-5 before expiry. The account from step 1 is reused, not re-registered. Revocation is not automated: *you* do it with the CA's tools

*You* own the setup: email, CA address, challenge type, and a `:80` that the CA can reach

---

## ACME - what you configure (install)

```
# k8s-providers/stack/00-traefik-hub.yaml

m4_esyscmd([[[yq 'select(.kind == "HelmRelease") | .spec.values | {"certificatesResolvers": .certificatesResolvers}' k8s-providers/stack/00-traefik-hub.yaml]]])
```

The resolver is a named recipe. Point `caServer` at another CA to change it

`storage` holds the account key and certificates. Keep it on a persistent volume: after a restart Traefik reuses the account and certificates. Lose it and Traefik registers and orders again (here, a new pod does)

---

## ACME - what you configure (route)

```
# k8s-providers/scenarios/00-security-acme.yaml

m4_esyscmd([[[yq 'select(.metadata.name == "whoami-acme") | .spec' k8s-providers/scenarios/00-security-acme.yaml]]])
```

One line, `certResolver: step`, is the trigger. No Certificate object, no Secret, no cert-manager

---

## ACME - the HTTP-01 challenge

```
 Traefik                                 CA
    |  1. new account, new order          |
    |------------------------------------>|
    |  2. challenge: serve token on :80   |
    |<------------------------------------|
    |  (Traefik answers on /.well-known/  |
    |   acme-challenge/ by itself)        |
    |  3. GET Host: api.traefik-hub.test  |
    |<------------------------------------|
    |  4. token + account key thumbprint  |
    |------------------------------------>|
    |  5. CSR                             |
    |------------------------------------>|
    |  6. signed certificate              |
    |<------------------------------------|
```

Proof of control = being the one who answers on port 80 for that name

The token is served only while the challenge is pending, then dropped. But `:80` must be reachable at every renewal

---

## ACME - renewal and the HTTP redirect

```
# k8s-providers/scenarios/00-security-acme.yaml

m4_esyscmd([[[yq 'select(.metadata.name == "whoami-acme-http" or .kind == "Middleware") | .spec' k8s-providers/scenarios/00-security-acme.yaml]]])
```

- `:80` redirects to HTTPS, as on a real site. Traefik still answers the challenge first
- Until the CA has issued the certificate, `sniStrict: true` refuses the handshake instead of serving Traefik's self-signed one
- Certificates last 24h here, so Traefik renews in the last 6h, checking every 10 minutes
- Try it: `curl --cacert certs/ca.pem https://api.traefik-hub.test/`
