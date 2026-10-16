#!/usr/bin/env python3
"""Small offline OpenAI-compatible endpoint used only by the scrimmage."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import time


MODEL = "PlinkAI"
REPLY = "Hello Plinktern! I do love Horse Plinko as much as I do. Let's plink some horses!"


class Handler(BaseHTTPRequestHandler):
    server_version = "PlinkAI/1.0"

    def log_message(self, format_string, *args):
        print(f"{self.client_address[0]} - {format_string % args}")

    def send_json(self, status, value):
        payload = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path in ("/health", "/v1/health"):
            self.send_json(200, {"ok": True, "service": "PlinkAI"})
            return
        if self.path.rstrip("/") == "/v1/models":
            self.send_json(200, {"object": "list", "data": [{"id": MODEL, "object": "model", "created": 1728000000, "owned_by": "ihpl"}]})
            return
        self.send_json(404, {"error": {"message": "route not found"}})

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/chat/completions":
            self.send_json(404, {"error": {"message": "route not found"}})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            request = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self.send_json(400, {"error": {"message": "invalid JSON"}})
            return

        created = int(time.time())
        if request.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            for word in REPLY.split(" "):
                chunk = {"id": "plinkai-local", "object": "chat.completion.chunk", "created": created, "model": MODEL, "choices": [{"index": 0, "delta": {"content": word + " "}, "finish_reason": None}]}
                self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
                self.wfile.flush()
            final_chunk = {"id": "plinkai-local", "object": "chat.completion.chunk", "created": created, "model": MODEL, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}
            self.wfile.write(("data: " + json.dumps(final_chunk) + "\n\n").encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            return

        self.send_json(200, {
            "id": "plinkai-local",
            "object": "chat.completion",
            "created": created,
            "model": MODEL,
            "choices": [{"index": 0, "message": {"role": "assistant", "content": REPLY}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 12, "completion_tokens": 18, "total_tokens": 30},
        })


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 11435), Handler).serve_forever()
