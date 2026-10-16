package demo.authz_test

import rego.v1

import data.demo.authz

token(claims) := io.jwt.encode_sign({"alg": "HS256"}, claims, {"kty": "oct", "k": "c2VjcmV0"})

request(claims) := {"headers": {"Authorization": concat(" ", ["Bearer", token(claims)])}}

test_admin_allowed if authz.allow with input as request({"realm_access": {"roles": ["admin"]}})

test_other_role_denied if not authz.allow with input as request({"realm_access": {"roles": ["viewer"]}})

test_no_roles_denied if not authz.allow with input as request({"sub": "guest"})

test_no_token_denied if not authz.allow with input as {"headers": {}}

test_not_a_bearer_token_denied if not authz.allow with input as {"headers": {"Authorization": "Basic abc"}}
