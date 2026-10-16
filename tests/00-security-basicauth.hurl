# Check Happy and Unauthorized Path

GET {{base_url}}/basic-auth
HTTP 401

GET {{base_url}}/basic-auth
[BasicAuth]
user: pass
HTTP 200
