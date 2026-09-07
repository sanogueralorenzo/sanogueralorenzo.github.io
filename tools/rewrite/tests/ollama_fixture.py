"""A disposable loopback protocol fixture, not a model or an inference claim."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log request text.

    def send(self, data):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        assert self.path == "/api/tags"
        self.send({"models": [{"name": "fixture:local"}, {"name": "remote:cloud"},
                              {"name": "renamed-remote", "remote_host": "https://ollama.com"}]})

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path == "/api/show":
            response = {"details": {"parameter_size": "3B"}, "capabilities": ["completion"]}
            if request["model"] == "renamed-remote":
                response["remote_host"] = "https://ollama.com"
            self.send(response)
        elif self.path == "/api/chat":
            assert request["model"] == "fixture:local"
            assert request["stream"] is False
            assert "tools" not in request
            assert len(request["messages"]) == 2
            system, user = request["messages"]
            assert system["role"] == "system" and user["role"] == "user"
            payload = json.loads(user["content"])
            assert set(payload) == {"source_text", "editing_instruction"}
            assert payload["source_text"] == "She go to the library yesterday."
            self.send({"message": {"role": "assistant", "content": "She went to the library yesterday."}, "done": True})
        else:
            self.send_error(404)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 11435), Handler).serve_forever()
