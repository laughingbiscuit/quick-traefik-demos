---

# OpenID Connect: who signed in

*The login is an OAuth2 flow. So what does OpenID Connect add?*

The login flow is __OAuth2's authorization code grant__: the browser goes to the identity provider, the person signs in, and the application trades a code for an access token

An access token says what its holder may do. It does not have to say who they are

__OpenID Connect__ adds the identity layer on top:

- an __ID token__: who signed in
- a __discovery document__: a client finds every endpoint from the issuer's URL
- standard scopes and claims: `openid`, `profile`, `email`

---

## The scenario

__The cast__

- a browser, and a portal page behind Traefik
- the identity provider, which signs people in
- a Profile API, which only admins may call

__We will__ open the portal, sign in as `demo` or `guest`, then have the page call the API

__You will see__ the browser sent to sign in, then the page knowing who you are, then the API answer 200 for `demo` and 403 for `guest`

---

## What happens

```
 Browser                Traefik               Keycloak
    |                      |  discovery: the issuer URL tells it where everything is
    |                      |--------------------->|
    |  GET /portal         |                      |
    |--------------------->|                      |
    |  no session: sign in (authorization code flow)
    |<---------------------|                      |
    |  sign in ---------------------------------> |
    |  back to /callback with a code              |
    |--------------------->|  trade the code      |
    |                      |--------------------->|
    |                      |  access token + ID token
    |                      |<---------------------|
    |  session cookie, the page                   |
    |<---------------------|                      |
```

- the gateway runs the flow and keeps the session: the application behind it does not have to
- the page is told who signed in, and gets the access token as a bearer token

---

## What you configure

`chapters/07-api-access-control-oidc/portal.yaml`

```
m4_esyscmd([[[yq 'select(.kind == "Middleware") | .spec.plugin.oidc' chapters/07-api-access-control-oidc/portal.yaml]]])
```

- `issuer` is where discovery happens. `trustedIssuer` is what the tokens say, and where the browser goes
- the person's claims reach the page as headers (`forwardHeaders`)

---

## Then call an API

`chapters/07-api-access-control-oidc/profile-api.yaml`

```
m4_esyscmd([[[yq 'select(.kind == "ManagedSubscription") | .spec' chapters/07-api-access-control-oidc/profile-api.yaml]]])
```

```
admin signs in  ->  /profile with the token   200
guest signs in  ->  /profile with the token   403
```

The page uses the token the gateway forwarded: the token is checked, the person's role decides

The login and the API checks are two routes: on one route the API check runs first, before there is a login to wait for

`chapters/07-api-access-control-oidc/oidc-admin.k8s.hurl` walks the whole login and checks this
