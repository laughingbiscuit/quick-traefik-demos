---

# Token exchange: a token for the backend

*What if the backend should get its own token, not the caller's?*

A user signs in and gets a token. The token says who they are, and which service it is __for__ (its audience)

If the gateway passes that token straight to every backend:

- the backend gets a token meant for another service
- it carries more than the backend needs: email, roles, everything
- if it leaks, it works everywhere the user can go

__Token exchange__ (RFC 8693): the gateway trades the token at the identity provider for a new one, made for this backend

---

## The scenario

__The cast__

- a person, `demo`, who signs in at the identity provider through an application
- Traefik, in front of a backend
- the backend, `whoami`, which shows what it receives

__We will__ call the backend through Traefik with the person's token

__You will see__ the backend receive a different token: made for it, for the same person, with less in it. No token, or one the identity provider refuses, gets a 401

---

## How it works

```
 Client              Traefik              Keycloak            Backend
   |   token A          |                     |                   |
   |   aud: gateway     |                     |                   |
   |------------------->|   trade A for a     |                   |
   |                    |   token for backend |                   |
   |                    |-------------------->|                   |
   |                    |       token B       |                   |
   |                    |<--------------------|                   |
   |                    |   request + token B |                   |
   |                    |---------------------------------------->|
```

- __Traefik__ does the trade, with its own client credentials
- __Keycloak__ decides what goes into token B, or says no: the client gets a 401
- the __backend__ only ever sees token B

---

## What changes between the tokens

```
                token A (the caller's)    token B (the backend's)
aud             gateway                   demo-backend
azp             demo-app                  gateway
sub             the same user             the same user
email, roles    yes                       no
```

`chapters/08-token-exchange/test.hurl` signs in, calls through the gateway and checks exactly this

---

## What you configure

`chapters/08-token-exchange/manifests.yaml`: a Traefik Hub middleware (early access)

```
m4_esyscmd([[[yq 'select(.kind == "Middleware") | .spec.plugin.oAuthTokenExchange' chapters/08-token-exchange/manifests.yaml]]])
```

`shared/keycloak/demo-realm.json`: in Keycloak, the gateway's client has token exchange switched on

```
m4_esyscmd([[[jq -c '.clients[] | select(.clientId == "gateway") | {clientId, attributes}' shared/keycloak/demo-realm.json]]])
```

Token A has to name the gateway in its audience, or Keycloak refuses
