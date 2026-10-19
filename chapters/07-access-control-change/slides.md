---

# Change access, not the identity provider

*What happens when access has to change?*

A decision made in the identity provider travels with the token: it holds until the token expires and a new one is issued

A decision made at the gateway can change at once, and the client keeps the token it has

---

## The scenario

__The cast__

- Partner A, with the token it already has, and the Payments API it may not call
- the gateway's subscriptions: its own record, outside the identity provider

__We will__ add one subscription for Partner A, then delete it

__You will see__ Payments answer 403, then 200 within seconds, then 403 again. The token never changes, and nothing happens at the identity provider

---

## One more subscription

`chapters/07-access-control-change/test.sh`

```
m4_esyscmd([[[sed -n '/<<.YAML.$/,/^YAML$/{/YAML/!p;}' chapters/07-access-control-change/test.sh]]])
```

```
Partner A -> Payments      403
(apply that subscription)
Partner A -> Payments      200      same token, same client, seconds later
(delete it)
Partner A -> Payments      403
```

- nothing restarts
- a token already issued stays valid at the identity provider until it expires, but the gateway stops honouring it at once

Need a different, narrower token for the backend? That is token exchange: a separate step, and the identity provider has to support it
