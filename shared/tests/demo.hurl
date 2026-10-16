# Both versions of the demo API answer, each as itself
GET http://localhost:9101/
HTTP 200
[Asserts]
body contains "Name: api-v1"

GET http://localhost:9102/
HTTP 200
[Asserts]
body contains "Name: api-v2"
