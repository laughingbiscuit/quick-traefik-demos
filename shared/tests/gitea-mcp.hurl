# The MCP server answers an initialize request
POST http://localhost:8081/mcp
Accept: application/json, text/event-stream
{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "1"}}}
HTTP 200
[Asserts]
body contains "Gitea MCP Server"
