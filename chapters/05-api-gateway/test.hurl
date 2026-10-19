# Check Happy and Unauthorized Path

GET {{base_url}}/basic-auth
HTTP 401

GET {{base_url}}/basic-auth
[BasicAuth]
demo: Password123
HTTP 200
