---

# Token exchange

A user signs in and gets a token. The token says who they are, and which service it is __for__ (its audience)

If the gateway passes that token straight to every backend:

- the backend gets a token meant for another service
- it carries more than the backend needs: email, roles, everything
- if it leaks, it works everywhere the user can go

__Token exchange__ (RFC 8693): the gateway trades the token at the identity provider for a new one, made for this backend

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

## What changes, and what you configure

```
                token A (the caller's)    token B (the backend's)
aud             gateway                   demo-backend
azp             demo-app                  gateway
sub             the same user             the same user
email, roles    yes                       no
```

```
oAuthTokenExchange:                  # a Traefik Hub middleware (early access)
  url: https://<keycloak>/realms/<realm>/protocol/openid-connect/token
  clientID, clientSecret:            # the gateway's own client
  rfc8693:
    subjectTokenType: urn:ietf:params:oauth:token-type:access_token
    audience: demo-backend           # who the new token is for
```

In Keycloak, the gateway's client has token exchange switched on, and token A has to name the gateway in its audience
