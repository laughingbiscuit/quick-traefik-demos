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

# Chapter 1 - Passthrough

Every request passes through 4 stages:

`Entrypoint -> Router -> Middleware -> Service`

---

__Entrypoint__

- listener bound to a port and a protocol (TCP, UDP, HTTP, HTTP/2, HTTP/3)
- configured on installation

__Router__

- matches the request against a rule such as Host() or PathPrefix() and selects what happens next

__Middleware__

- an ordered chain of transformations and policies to protect and manage your APIs, Models and MCP tools

__Service__

- the load-balanced pool of backend instances that receives the request
- supports external endpoints

---

## A router, a middleware and a service

```
m4_esyscmd([[[sed 's/^---$//' chapters/01-passthrough/k8s/ingressroute.yaml]]])
```

---

## Three ways to write a route on Kubernetes

- __Ingress__ - the Kubernetes standard. Traefik settings go in annotations, checked only at runtime
- __IngressRoute__ - Traefik's own object. Every Traefik feature, validated when you deploy
- __HTTPRoute__ - the Gateway API, the standard's successor to Ingress

Same job, three ways of writing it

---

## One Traefik, many providers

Each provider watches its own source of truth and translates it into Traefik's dynamic configuration

Kubernetes Ingress, Kubernetes CRD, Gateway API, Docker, Swarm, Consul, Nomad, ECS, Redis, etcd, file...

They run __at the same time__ in one instance, and every object carries its provider's name, so nothing collides:

`whoami@kubernetes`  `whoami@kubernetescrd`  `whoami@kubernetesgateway`  `whoami@file`

---

## The file provider

The same route, as a file. No Kubernetes needed

```
m4_include([[[chapters/01-passthrough/vm/passthrough.yaml]]])
```

---

## One request, four providers

```
$ curl -si localhost:8080/passthrough
X-Demo-Route: ingress

$ curl -si 'localhost:8080/passthrough?route=ingressroute'
X-Demo-Route: ingressroute

$ curl -si 'localhost:8080/passthrough?route=httproute'
X-Demo-Route: httproute

$ curl -si 'localhost:8080/passthrough?route=file'
X-Demo-Route: file
```

Four providers, one Traefik. The header tells you which route answered

---

## One dashboard

Every route of every provider, in one list, each named `route@provider`

Open `http://localhost:8082/dashboard/`

---

# Chapter 2 - Proxy: TLS from ACME

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

---

## ACME - what you configure

```
certificatesResolvers:            # static: the install
  step:
    acme:
      email: demo@example.com
      caServer: https://<your CA>/acme/directory
      storage: /data/acme.json
      httpChallenge:
        entryPoint: web

tls:                              # dynamic: on the route
  certResolver: step
```

One line on the route is the trigger. No Certificate object, no Secret, no cert-manager

---

## ACME - restarts, renewal and the first request

- `storage` holds the account and the certificates. On a persistent volume, a restart reuses them. Lose it and Traefik registers and orders again
- Traefik renews before expiry by itself (here: 24h certificates, renewed in the last 6h)
- The challenge token is served only while the challenge is pending, but `:80` must be reachable at every renewal
- Until the CA has issued the certificate, `sniStrict: true` refuses the handshake instead of serving Traefik's self-signed one

---

# Chapter 3 - API gateway: authentication

A middleware in front of the same service

```
$ curl -i localhost:8080/basic-auth
HTTP/1.1 401 Unauthorized

$ curl -i -u demo:Password123 localhost:8080/basic-auth
HTTP/1.1 200 OK
```

The router matched the path, the middleware checked the login, the service answered

---

# Static and dynamic config

Traefik merges every provider into one configuration, and keeps two kinds apart

__Static__ - the install. Read at start, a change restarts Traefik

- entrypoints, providers, certificate resolvers, the licence

__Dynamic__ - what you demo. Hot-reloaded, no restart

- routers, middlewares, services, TLS options
