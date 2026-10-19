---

# The file provider: Traefik without Kubernetes

*What if there is no Kubernetes?*

Traefik reads its configuration from a file. Change the file and Traefik reloads it, with no restart

---

## The scenario

__The cast__

- a Linux VM, with Traefik Hub and the `whoami` service as plain programs: no containers, no Kubernetes
- one file that holds the route

__We will__ call the route on the VM

__You will see__ whoami answer on the VM, through the same four stages as on Kubernetes

---

## The file provider

`chapters/03-file-provider/file-provider.yaml`

```
m4_include([[[chapters/03-file-provider/file-provider.yaml]]])
```

`chapters/03-file-provider/test.hurl` calls it on the VM

---

## Static and dynamic config

Traefik's configuration comes in two kinds

__Static__ - the install. Read at start, a change restarts Traefik

- entrypoints, providers, certificate resolvers, the licence

__Dynamic__ - what you demo. Hot-reloaded, no restart

- routers, middlewares, services, TLS options

`platform/vm/traefik-static.yaml` is the VM's static config:

```
m4_esyscmd([[[yq '.entryPoints' platform/vm/traefik-static.yaml]]])
```
