# Base route reaches whoami
GET {{base_url}}/
HTTP 200
[Asserts]
body contains "Hostname:"
