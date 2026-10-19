---

# API gateway: authentication

*How do I keep strangers out?*

A middleware in front of a service: `chapters/03-api-gateway/basicauth.yaml` holds the route, the middleware and the users

```
$ curl -i localhost:8080/basic-auth
HTTP/1.1 401 Unauthorized

$ curl -i -u demo:Password123 localhost:8080/basic-auth
HTTP/1.1 200 OK
```

The router matched the path, the middleware checked the login, the service answered

---

## The scenario

__The cast__: a service behind the route `/basic-auth`, and one user, `demo`

__We will__ call it without a login, then with one

__You will see__ a 401 without, and the service's answer with

---

## Basic auth: simple, and where it stops

- the gateway holds the list of users and their password hashes
- anyone with the right password gets in, and every caller looks alike
- fine for a few callers. It does not tell you which client may do what

For many clients, the usual answer is tokens from an identity provider

