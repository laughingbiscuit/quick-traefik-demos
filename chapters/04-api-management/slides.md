---

# API management: who may call what

An identity provider issues tokens. Often every client's token is equally broad: the same scope, every API in the audience

- a valid token does not mean the client __should__ reach every API
- doing it in the identity provider means redesigning it, client by client
- doing it in every backend means every backend does it again

Keep the identity provider for sign-in and tokens. Let the gateway decide which API each client may call

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

## What you declare

```
kind: ManagedApplication      # a client the gateway knows
spec: {appId: partner-a}      # the id in the token

kind: ManagedSubscription     # what that client may call
spec:
  apis: [orders]
  managedApplications: [partner-a]
```

```
                 Orders    Payments
Partner A         200        403
Partner B         403        200
Internal          200        200
```

---

## Change access, not the identity provider

```
Partner A -> Payments      403
(one more subscription)
Partner A -> Payments      200      same token, same client, seconds later
(delete it)
Partner A -> Payments      403
```

- nothing changes at the identity provider, and nothing restarts
- a token already issued stays valid there until it expires, but the gateway stops honouring it at once
- the gateway can also hand the backend the client it verified, and overwrite a header the caller made up

Need a different, narrower token for the backend? That is token exchange: a separate step, and the identity provider has to support it
