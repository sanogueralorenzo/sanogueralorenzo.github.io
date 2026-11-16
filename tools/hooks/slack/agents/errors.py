"""Return fixed error codes; the Rust bridge owns public diagnostic messages."""

import json


class HookError(RuntimeError):
    def __init__(self, code, provider="Command"):
        self.code = code
        self.provider = provider
        super().__init__(code)


def classify(output, provider):
    text = output.lower()
    for code, markers in [
        (
            "auth_required",
            (
                "token has expired",
                "token expired",
                "oauth token",
                "authentication_error",
                "invalid api key",
                "not logged in",
                "please run /login",
                "unauthorized",
                "401",
            ),
        ),
        (
            "usage_limit",
            (
                "rate_limit",
                "rate limit",
                "usage limit",
                "credit balance",
                "quota exceeded",
                "429",
            ),
        ),
        (
            "permission_required",
            (
                "permission denied",
                "requires approval",
                "approval required",
                "not trusted",
            ),
        ),
        (
            "session_invalid",
            (
                "session not found",
                "no conversation found",
                "invalid session",
                "thread not found",
            ),
        ),
    ]:
        if any(marker in text for marker in markers):
            return HookError(code, provider)
    return HookError("command_failed", provider)


def report(error):
    safe = error if isinstance(error, HookError) else HookError("invalid_response")
    print(json.dumps({"error": {"code": safe.code, "provider": safe.provider}}))
    return 1
