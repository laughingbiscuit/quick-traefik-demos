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
