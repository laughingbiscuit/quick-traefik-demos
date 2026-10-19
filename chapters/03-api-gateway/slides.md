---

# API gateway: authentication

A middleware in front of a service

```
$ curl -i localhost:8080/basic-auth
HTTP/1.1 401 Unauthorized

$ curl -i -u demo:Password123 localhost:8080/basic-auth
HTTP/1.1 200 OK
```

The router matched the path, the middleware checked the login, the service answered
