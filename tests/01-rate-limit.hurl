# 2 requests/s with a burst of 4: four pass, the fifth is refused.
# Wait 3s first (on the unlimited base route) so earlier runs have refilled
# the bucket. Hurl repeats a delay on every repeat, so it can't go below.
GET {{base_url}}/
[Options]
delay: 3000
HTTP 200

GET {{base_url}}/rate-limit
[Options]
repeat: 4
HTTP 200

GET {{base_url}}/rate-limit
HTTP 429
