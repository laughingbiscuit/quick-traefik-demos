# Passthrough

Every request passes through 4 stages: 

`Entrypoint -> Router -> Middleware -> Service`.

Entrypoint - listener bound to a port and a protocol (TCP, UDP, HTTP, HTTP/2, HTTP/3).

Router - matches the request against a rule such as Host() or PathPrefix() and selects what happens next.

Middleware - an ordered chain of optional transformations and policies.

Service - the load-balanced pool of backend instances that receives the request, or an external endpoint.

## Kubernetes Providers

```
# k8s-providers/scenarios/stack/00-traefik-hub.yaml
###
# Step 1 - Entrypoint
###
m4_esyscmd([[[yq 'select(.kind == "HelmRelease") | .spec.values | {"ports": .ports, "gateway": .gateway}' k8s-providers/scenarios/stack/00-traefik-hub.yaml]]])
```

```
# k8s-providers/scenarios/00-passthrough.yaml
m4_include([[[k8s-providers/scenarios/00-passthrough.yaml]]])
```

## File Provider

```
# file-provider/scenarios/traefik-install-conf/00-entrypoints.yaml
m4_include([[[file-provider/scenarios/traefik-install-conf/00-entrypoints.yaml]]])
```

```
# file-provider/scenarios/00-passthrough.yaml
m4_include([[[file-provider/scenarios/00-passthrough.yaml]]])
```

## Result

```
# tests/00-passthrough.hurl
m4_include([[[tests/00-passthrough.hurl]]])
```