---

# Providers: one Traefik, many sources

*What if my configuration lives in more than one place?*

In this lab: one Traefik reads four sources at once, and the same URL is answered from each

Each provider watches its own source of truth and translates it into Traefik's dynamic configuration

Kubernetes Ingress, Kubernetes CRD, Gateway API, Docker, Swarm, Consul, Nomad, ECS, Redis, etcd, file...

They run __at the same time__ in one instance, and every object carries its provider's name, so nothing collides:

`whoami@kubernetes`  `whoami@kubernetescrd`  `whoami@kubernetesgateway`  `whoami@file`

---

## The file provider

The same route, as a file. No Kubernetes needed

`chapters/01-passthrough/vm/passthrough.yaml`

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
X-Demo-Route: ingress           <- chapters/01-passthrough/ingress.yaml

$ curl -si 'localhost:8080/passthrough?route=ingressroute'
X-Demo-Route: ingressroute      <- chapters/01-passthrough/ingressroute.yaml

$ curl -si 'localhost:8080/passthrough?route=httproute'
X-Demo-Route: httproute         <- chapters/01-passthrough/httproute.yaml

$ curl -si 'localhost:8080/passthrough?route=file'
X-Demo-Route: file              <- platform/k8s/00-traefik-hub.yaml (providers.file)
```

Four providers, one Traefik. The header tells you which route answered

---

## One dashboard

Every route of every provider, in one list, each named `route@provider`

Open `http://localhost:8082/dashboard/`
