"""A third-party Python client of AI Story RPG. No copied game rules.

Example:
    python3 python_client.py --endpoint http://127.0.0.1:PORT/v1/rpg \
      --token SECRET --op capabilities
Use only a local authenticated host. Private book data never goes to cloud.
"""
from __future__ import annotations

import argparse
import json
from urllib.parse import urlparse
from urllib.request import Request, build_opener, ProxyHandler


PROTOCOL_VERSION = "ai_story_rpg_client_v1"


class RpgClientError(RuntimeError):
    """Opaque error code returned by the authoritative Dart engine."""


class RpgHttpClient:
    def __init__(self, endpoint: str, token: str):
        url = urlparse(endpoint)
        if (
            url.scheme != "http"
            or url.hostname not in {"127.0.0.1", "::1"}
            or url.path != "/v1/rpg"
            or url.username is not None
            or url.password is not None
            or url.query
            or url.fragment
            or len(token) < 32
        ):
            raise ValueError("Only an authenticated loopback RPG host is allowed")
        self.endpoint = endpoint
        self.token = token
        # Force DIRECT loopback traffic. Python's default urlopen honors
        # HTTP_PROXY and may otherwise leak private BookWorld text and token
        # to a machine-wide proxy in enterprise installations.
        self._direct = build_opener(ProxyHandler({}))

    def call(self, op: str, args: dict | None = None) -> dict:
        message = {
            "version": PROTOCOL_VERSION,
            "op": op,
            "args": args if args is not None else {},
        }
        payload = json.dumps(message, ensure_ascii=False).encode("utf-8")
        request = Request(
            self.endpoint,
            data=payload,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "x-rpg-token": self.token,
            },
        )
        with self._direct.open(request, timeout=60) as response:
            result = json.load(response)
        if not isinstance(result, dict) or result.get("version") != PROTOCOL_VERSION:
            raise RpgClientError("incompatible_protocol")
        if result.get("ok") is not True:
            error = result.get("error") or {}
            code = error.get("code", "engine_error") if isinstance(error, dict) else "engine_error"
            raise RpgClientError(code)
        return result["result"]


def main() -> None:
    parser = argparse.ArgumentParser(description="AI Story RPG external Python API client")
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--op", required=True)
    parser.add_argument("--args", default="{}", help="JSON object of operation arguments")
    options = parser.parse_args()
    args = json.loads(options.args)
    if not isinstance(args, dict):
        parser.error("--args must be a JSON object")
    client = RpgHttpClient(options.endpoint, options.token)
    print(json.dumps(client.call(options.op, args), ensure_ascii=False))


if __name__ == "__main__":
    main()
