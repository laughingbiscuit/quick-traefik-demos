---

# API access control: who may call what

*Every client has a valid token. How do I let each reach only its own APIs?*

An identity provider issues tokens. Often every client's token is equally broad: the same scope, every API in the audience

- a valid token does not mean the client __should__ reach every API
- doing it in the identity provider means redesigning it, client by client
- doing it in every backend means every backend does it again

Keep the identity provider for sign-in and tokens. Let the gateway decide which API each client may call

---

## The scenario

__The cast__

- three clients: Partner A, Partner B and Internal. All three hold the same broad token from the identity provider
- two APIs, Orders and Payments, behind Traefik

__What should be allowed__

```
                 Orders    Payments
Partner A         yes         no
Partner B         no          yes
Internal          yes         yes
```

__We will__ call each API with each token, then give Partner A access to Payments

__You will see__ the gateway, not the token, decide: 200 or 403

---

## How it works

```
   Client A      Client B      Internal
        \           |           /
         \          |          /
         Identity provider: tokens, all equally broad
                    |
               Traefik Hub
     1. is the token valid?       signature, issuer, expiry
     2. which client is it?       a claim in the token
     3. may it call this API?     a subscription
                    |
            +-------+-------+
        Orders API      Payments API
```

- no token, or a bad one: __401__
- a good token from a client with no subscription to the API: __403__

---

## Where each step lives

```
step                       object                file
1 is the token valid?      APIAuth               chapters/04-api-access-control/api-auth.yaml
2 which client is it?      ManagedApplication    chapters/04-api-access-control/partners.yaml
3 may it call this API?    ManagedSubscription   chapters/04-api-access-control/partners.yaml
```

The identity provider knows none of these objects: they are the gateway's own record

---

## 1. Is the token valid?

`chapters/04-api-access-control/api-auth.yaml`

```
m4_esyscmd([[[yq 'select(.kind == "APIAuth") | .spec.jwt | {"appIdClaim": .appIdClaim, "trustedIssuers": .trustedIssuers}' chapters/04-api-access-control/api-auth.yaml]]])
```

- the signature is checked against the issuer's keys (`jwksUrl`), and the issuer must be the one named
- `appIdClaim` says which claim names the client: here `azp`

---

## 2 and 3. Which client, and what may it call?

`chapters/04-api-access-control/partners.yaml`

```
m4_esyscmd([[[yq 'select((.kind == "ManagedApplication" and .metadata.name == "partner-a") or (.kind == "ManagedSubscription" and .metadata.name == "orders-access")) | {"kind": .kind, "spec": .spec}' chapters/04-api-access-control/partners.yaml | sed 's/^---$//']]])
```

- the application's `appId` is the value of that claim in the token
- the subscription lists who may call which API. It also checks the audience

---

## The result

```
                 Orders    Payments
Partner A         200        403
Partner B         403        200
Internal          200        200
```

All three tokens are equally broad. Partner A is subscribed to Orders only, so Payments is 403

`chapters/04-api-access-control/access-control.k8s.hurl` runs this, and the 401 cases

---

## Change access, not the identity provider

`chapters/04-api-access-control/grant-partner-a-payments.yaml`

```
m4_esyscmd([[[yq '.spec' chapters/04-api-access-control/grant-partner-a-payments.yaml]]])
```

```
Partner A -> Payments      403
(apply that one subscription)
Partner A -> Payments      200      same token, same client, seconds later
(delete it)
Partner A -> Payments      403
```

- nothing changes at the identity provider, and nothing restarts
- a token already issued stays valid there until it expires, but the gateway stops honouring it at once
- the gateway can also hand the backend the client it verified, and overwrite a header the caller made up

Need a different, narrower token for the backend? That is token exchange: a separate step, and the identity provider has to support it
