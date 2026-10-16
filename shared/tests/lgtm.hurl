# Grafana is up and the OTLP endpoint accepts data
GET http://localhost:3001/api/health
HTTP 200
[Asserts]
jsonpath "$.database" == "ok"

POST http://localhost:4318/v1/traces
Content-Type: application/json
{"resourceSpans": []}
HTTP 200
