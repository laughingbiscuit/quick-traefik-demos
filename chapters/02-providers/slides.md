---

# Providers: one Traefik, many sources

*What if my configuration lives in more than one place?*

Each provider watches its own source of truth and translates it into Traefik's dynamic configuration

Kubernetes Ingress, Kubernetes CRD, Gateway API, Docker, Swarm, Consul, Nomad, ECS, Redis, etcd, file...

They run __at the same time__ in one instance, and every object carries its provider's name, so nothing collides:

`whoami@kubernetes`  `whoami@kubernetescrd`  `whoami@kubernetesgateway`  `whoami@file`

---

## The scenario

__The cast__

- one Traefik, reading four sources at once: an Ingress, an IngressRoute, a Gateway API HTTPRoute and a file
- one service, `whoami`, behind all of them

__We will__ call the same URL four times, choosing the route with `?route=`

__You will see__ four different `X-Demo-Route` headers from one Traefik, and one dashboard listing all four providers

---

## One request, four providers

```
$ curl -si localhost:8080/passthrough
X-Demo-Route: ingress           <- the Ingress in chapters/01-passthrough/manifests.yaml

$ curl -si 'localhost:8080/passthrough?route=ingressroute'
X-Demo-Route: ingressroute      <- the IngressRoute in chapters/01-passthrough/manifests.yaml

$ curl -si 'localhost:8080/passthrough?route=httproute'
X-Demo-Route: httproute         <- the HTTPRoute in chapters/01-passthrough/manifests.yaml

$ curl -si 'localhost:8080/passthrough?route=file'
X-Demo-Route: file              <- platform/k8s/00-traefik-hub.yaml (providers.file)
```

Four providers, one Traefik. The header tells you which route answered

`chapters/02-providers/test.hurl` makes these four calls and checks the dashboard's list of providers

---

## One dashboard

Every route of every provider, in one list, each named `route@provider`

Open `http://localhost:8082/dashboard/`
