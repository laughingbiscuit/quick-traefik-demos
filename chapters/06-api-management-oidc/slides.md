---

# OpenID Connect: signing people in

OAuth2 gives a client a token. __OpenID Connect__ adds the part for people: a login flow, and a token that says who signed in

The gateway can run that flow, so the applications behind it don't have to

---

## What happens

```
 Browser                Traefik               Keycloak
    |  GET /portal         |                      |
    |--------------------->|                      |
    |  no session: go sign in                     |
    |<---------------------|                      |
    |  sign in -------------------------------->  |
    |  back to /callback with a code              |
    |--------------------->|  trade the code      |
    |                      |--------------------->|
    |                      |  tokens              |
    |                      |<---------------------|
    |  session cookie, the page                   |
    |<---------------------|                      |
```

- the page is told who signed in, and gets the access token as a bearer token

---

## Then call an API

The app uses that token against an API the gateway protects: the token is checked, the person's role decides

```
admin signs in  ->  /profile with the token   200
guest signs in  ->  /profile with the token   403
```

The login and the API checks are two routes: on one route the API check runs first, before there is a login to wait for
