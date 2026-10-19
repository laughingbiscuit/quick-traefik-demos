# Ollama is up. No model is pulled yet: a chapter that needs one pulls it (see the README)
GET http://localhost:11434/api/version
HTTP 200
[Asserts]
jsonpath "$.version" exists
