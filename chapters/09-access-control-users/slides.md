---

# API access control for people

*What changes when the caller is a person?*

Machines are not the only callers. People sign in at the identity provider and call APIs with the token they get

- the application is the same for everyone who uses it
- what a person may call depends on __who they are__: the claims in their token, like a role

The gateway reads those claims. The identity provider does not need to know which API is which

---

## The scenario

__The cast__

- two people: `demo`, who has the admin role, and `guest`, who has no role
- one application, which they both sign in through
- two APIs, Catalog and Admin

__We will__ sign in as each person and call both APIs

__You will see__ both reach Catalog. Only `demo` reaches Admin: `guest` gets a 403

---

## One application, different people

`chapters/09-access-control-users/manifests.yaml`

```
m4_esyscmd([[[yq 'select((.kind == "ManagedApplication") or (.kind == "ManagedSubscription" and .metadata.name == "admin-for-admins")) | {"kind": .kind, "spec": .spec}' chapters/09-access-control-users/manifests.yaml | sed 's/^---$//']]])
```

- one application, `demo-app`: every person comes through it
- the subscription checks the person's role, a claim in their token

---

## The result

```
                  Catalog     Admin
demo (admin)        200        200
guest               200        403
no token            401        401
```

- a valid token from someone without the role: __403__
- the gateway passes the person on as a header, and overwrites one the caller made up

`chapters/09-access-control-users/test.hurl` signs both people in and checks this
