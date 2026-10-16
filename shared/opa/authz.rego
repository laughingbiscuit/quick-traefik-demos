# Shared authorization policy. Nothing runs it centrally: every gateway evaluates this file itself
# (Traefik's OPA middleware takes a path or the content), and `./demo.sh test` checks it with `opa test`.
# Allows a request whose bearer token carries the "admin" realm role (see keycloak/demo-realm.json).
# The token's signature is the JWT middleware's job, not this policy's.
package demo.authz

import rego.v1

default allow := false

allow if "admin" in claims.realm_access.roles

claims := payload if {
	[_, payload, _] := io.jwt.decode(bearer)
}

bearer := token if {
	startswith(input.headers.Authorization, "Bearer ")
	token := substring(input.headers.Authorization, count("Bearer "), -1)
}
