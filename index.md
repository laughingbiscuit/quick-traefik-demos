
# Passthrough

Every request passes through 4 stages: 

`Entrypoint -> Router -> Middleware -> Service`.

Entrypoint - listener bound to a port and a protocol (TCP, UDP, HTTP, HTTP/2, HTTP/3).

Router - matches the request against a rule such as Host() or PathPrefix() and selects what happens next.

Middleware - an ordered chain of optional transformations and policies.

Service - the load-balanced pool of backend instances that receives the request, or an external endpoint.

## Kubernetes Providers

```
# k8s-providers/stack/00-traefik-hub.yaml
###
# Step 1 - Entrypoint
###
ports:
  web:
    port: 8000
    exposedPort: 80
gateway:
  listeners:
    web:
      port: 8000 # must match ports.web.port
      namespacePolicy:
        from: All # let HTTPRoutes in the demo namespace attach

```

```
# k8s-providers/scenarios/00-passthrough.yaml
###
# Step 2 Router 
###

# Version 1 - Kube Ingress with annotations with run-time validation

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  namespace: demo
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.middlewares: demo-add-forwarded-headers@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
    - http:
        paths:
          - path: /passthrough # note - no query param support!
            pathType: Prefix
            backend:
              service:
                name: whoami
                port:
                  number: 80
---

# Version 2 - Traefik Ingress CRD with deploy-time validation

apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: whoami
  namespace: demo
spec:
  entryPoints: [web]
  routes:
    - match: PathPrefix(`/passthrough`) && Query(`route`, `ingressroute`)
      kind: Rule
      middlewares:
        - name: add-forwarded-headers
      services:
        - name: whoami
          port: 80
---

# Version 3 - Gateway API Spec

apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: whoami
  namespace: demo
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
      sectionName: web
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /passthrough
          queryParams:
            - type: Exact
              name: route
              value: "httproute"
      filters:
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: add-forwarded-headers
      backendRefs:
        - name: whoami
          port: 80
---

###
# Step 3 - Middleware
###

apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: add-forwarded-headers
  namespace: demo
spec:
  headers:
    customResponseHeaders:
      X-Demo: "true"
---

###
# Step 4 - Service
###

apiVersion: v1
kind: Service
metadata:
  name: whoami
  namespace: demo
spec:
  selector: { app: whoami }
  ports: [{ port: 80 }]
```

## File Provider

```
# file-provider/traefik-install-conf/00-entrypoints.yaml
entryPoints:
  web:
    address: ":8000"
  traefik:
    address: ":8001"

```

```
# file-provider/scenarios/00-passthrough.yaml
# Passthrough: /passthrough goes through the addForwardedHeaders middleware to whoami.
#   curl -i http://localhost:8000/passthrough
http:
  routers:
    whoami:
      rule: PathPrefix(`/passthrough`)
      entryPoints: [web]
      middlewares: [addForwardedHeaders]
      service: whoami
  middlewares:
    addForwardedHeaders:
      headers: 
        customResponseHeaders:
          X-Demo: "true"
  services:
    whoami:
      loadBalancer:
        servers:
          - url: http://localhost:9000
 
```

## Result

```
# tests/00-passthrough.hurl
GET {{base_url}}/passthrough
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo" contains "true"

GET {{base_url}}/passthrough?route=ingressroute
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo" contains "true"

GET {{base_url}}/passthrough?route=httproute
HTTP 200
[Asserts]
body contains "Hostname:"
header "X-Demo" contains "true"
```