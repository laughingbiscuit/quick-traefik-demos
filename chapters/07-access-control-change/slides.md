---

# Change access, not the identity provider

*What happens when access has to change?*

A decision made in the identity provider travels with the token: it holds until the token expires and a new one is issued

A decision made at the gateway can change at once, and the client keeps the token it has

---

## The scenario

__The cast__

- Partner A, with the token it already has, and the Payments API it may not call
- the gateway's subscriptions: its own record, kept in Git and applied by Flux

__We will__ add one subscription for Partner A: a change to the repo, applied by Flux

__You will see__ Payments answer 200 where it answered 403 a moment ago. The token never changes, and nothing happens at the identity provider

---

## One more subscription

`chapters/07-access-control-change/manifests.yaml`

```
m4_esyscmd([[[yq '{"kind": .kind, "spec": .spec}' chapters/07-access-control-change/manifests.yaml]]])
```

```
Partner A -> Payments      403
(add that subscription to Git: Flux applies it)
Partner A -> Payments      200      same token, same client, seconds later
(take it out: Flux removes it)
Partner A -> Payments      403
```

- nothing restarts
- a token already issued stays valid at the identity provider until it expires, but the gateway stops honouring it at once

`chapters/07-access-control-change/test.hurl` calls Payments with Partner A's token

Need a different, narrower token for the backend? That is token exchange: a separate step, and the identity provider has to support it
