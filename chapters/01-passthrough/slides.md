---

# Passthrough: a request through Traefik

*How does a request get from the outside to my service?*

In this lab: a service on Kubernetes and on a VM. We send it a request and follow it through four stages

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

`chapters/01-passthrough/manifests.yaml`

```
m4_esyscmd([[[yq 'select(.kind == "IngressRoute" or (.kind == "Middleware" and .metadata.name == "add-headers-ingressroute"))' chapters/01-passthrough/manifests.yaml | sed 's/^---$//']]])
```

---

## Three ways to write a route on Kubernetes

- __Ingress__ - the Kubernetes standard. Traefik settings go in annotations, checked only at runtime
- __IngressRoute__ - Traefik's own object. Every Traefik feature, validated when you deploy
- __HTTPRoute__ - the Gateway API, the standard's successor to Ingress

Same job, three ways of writing it: all three are in `chapters/01-passthrough/manifests.yaml`, and `chapters/01-passthrough/test.hurl` calls each
