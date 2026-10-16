# Ollama is up and the model has been pulled
GET http://localhost:11434/api/tags
HTTP 200
[Asserts]
jsonpath "$.models" count >= 1
