"""Public diagnostic messages. Never forward raw subprocess or network output."""
import json


class HookError(RuntimeError):
    def __init__(self, code='command_failed', provider='Command'):
        self.code = code if isinstance(code, str) and code in MESSAGES else 'command_failed'
        self.provider = provider if provider in ('Codex', 'Claude', 'Command') else 'Command'
        super().__init__(self.public()['message'])

    def public(self):
        login = {'Claude': 'claude auth login', 'Codex': 'codex login', 'Command': 'your CLI login command'}[self.provider]
        return {'code': self.code, 'provider': self.provider,
                'message': MESSAGES[self.code].format(provider=self.provider, login=login)}


MESSAGES = {
    'auth_required': '{provider} login expired or is missing. Run `{login}` on your computer, then send a new request.',
    'usage_limit': '{provider} reached a usage or rate limit. Check your CLI account and retry later.',
    'permission_required': '{provider} needs approval. Open the CLI on your computer to approve the operation, then send a new request.',
    'missing_cli': '{provider} CLI was not found. Install it and rerun the Slack browser installer.',
    'timeout': '{provider} exceeded the command time limit. Try a smaller request or adjust timeout_seconds.',
    'cancelled': 'The request was cancelled. Send a new request when the bridge is running.',
    'invalid_response': '{provider} returned an invalid response. The adapter must return session_id and answer as JSON.',
    'session_invalid': '{provider} could not resume this session. Start a new Slack thread.',
    'output_limit': '{provider} produced too much output. Try a smaller request.',
    'context_limit': 'This thread is too large to send to the agent. Start a new Slack thread.',
    'workspace_missing': 'The configured project directory no longer exists. Update workspace/projects and rerun the installer.',
    'command_failed': '{provider} failed. Run the CLI directly on your computer, then send a new request.',
}


def classify(output, provider):
    text = output.lower()
    for code, markers in [
        ('auth_required', ('token has expired', 'token expired', 'oauth token', 'authentication_error', 'invalid api key', 'not logged in', 'please run /login', 'unauthorized', '401')),
        ('usage_limit', ('rate_limit', 'rate limit', 'usage limit', 'credit balance', 'quota exceeded', '429')),
        ('permission_required', ('permission denied', 'requires approval', 'approval required', 'not trusted')),
        ('session_invalid', ('session not found', 'no conversation found', 'invalid session', 'thread not found')),
    ]:
        if any(marker in text for marker in markers):
            return HookError(code, provider)
    return HookError('command_failed', provider)


def from_response(value):
    error = value.get('error') if isinstance(value, dict) else None
    if isinstance(error, dict):
        return HookError(error.get('code'), error.get('provider'))
    return None


def report(error):
    safe = error if isinstance(error, HookError) else HookError('invalid_response')
    print(json.dumps({'error': safe.public()}))
    return 1
