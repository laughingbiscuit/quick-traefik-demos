m4_changequote([[[,]]])m4_dnl
<!--
title: Traefik Hub Workshop
author: laughingbiscuit
date: m4_esyscmd([[[date +%d/%m/%y]]])
-->

# Traefik Hub Workshop

---

# Introduction

TODO

---

# Lab Environment

TODO

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
# file-provider/traefik.yaml

m4_esyscmd([[[yq '.entryPoints' file-provider/traefik.yaml]]])
```

```
# file-provider/scenarios/00-passthrough.yaml

m4_include([[[file-provider/scenarios/00-passthrough.yaml]]])
```

---

## Result

```
# tests/00-passthrough.hurl

m4_include([[[tests/00-passthrough.hurl]]])
```

You can verify the test results and try yourself with this [repo](https://github.com/laughingbiscuit/quick-traefik-demos)