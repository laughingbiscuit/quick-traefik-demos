---

# API management for people

Machines are not the only callers. People sign in at the identity provider and call APIs with the token they get

- the application is the same for everyone who uses it
- what a person may call depends on __who they are__: the claims in their token, like a role

The gateway reads those claims. The identity provider does not need to know which API is which

---

## One application, different people

```
kind: ManagedSubscription
spec:
  apis: [admin]
  managedApplications: [demo-app]
  claims: "Contains(`realm_access.roles`, `admin`)"
```

```
                  Catalog     Admin
demo (admin)        200        200
guest               200        403
no token            401        401
```

- a valid token from someone without the role: __403__
- the gateway passes the person on as a header, and overwrites one the caller made up
