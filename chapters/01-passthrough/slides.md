---

# Passthrough

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
m4_esyscmd([[[sed 's/^---$//' chapters/01-passthrough/ingressroute.yaml]]])
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

## Static and dynamic config

Traefik's configuration comes in two kinds

__Static__ - the install. Read at start, a change restarts Traefik

- entrypoints, providers, certificate resolvers, the licence

__Dynamic__ - what you demo. Hot-reloaded, no restart

- routers, middlewares, services, TLS options

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
