"""Local Socket Mode bridge from an authorized command to a CLI provider session."""

import os
import queue
import signal
import sys
from contextlib import ExitStack
from pathlib import Path

from conversation import State, acknowledge, handle
from providers import processes, require_available
from reactions import react
from routing import command_providers, project_workspaces
from thread_queue import ThreadQueue


def required(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"Set {name} in the environment or .env")
    return value


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if args:
        raise ValueError("Usage: ./run.sh (configure keyword commands in .env)")
    state_dir = Path(os.environ.get("AGENT_SLACK_STATE_DIR", "~/.local/state/agent-slack")).expanduser()
    commands = command_providers()
    for provider_name in dict.fromkeys(commands.values()):
        require_available(provider_name)
    from slack_sdk import WebClient
    from slack_sdk.socket_mode import SocketModeClient
    from slack_sdk.socket_mode.response import SocketModeResponse

    app_token = required("SLACK_APP_TOKEN")
    user_token = required("SLACK_USER_TOKEN")
    user_id = required("SLACK_USER_ID")
    workspace = Path(required("AGENT_SLACK_WORKSPACE")).expanduser().resolve()
    if not workspace.is_dir():
        raise ValueError(f"AGENT_SLACK_WORKSPACE is not a directory: {workspace}")
    projects = project_workspaces()
    if not app_token.startswith("xapp-") or not user_token.startswith("xoxp-"):
        raise ValueError("Use an xapp app token and xoxp authorized-user token")
    user_client = WebClient(token=user_token)
    user_auth = user_client.auth_test()
    if user_auth.get("bot_id") or user_auth.get("user_id") != user_id:
        raise ValueError("SLACK_USER_TOKEN must belong to SLACK_USER_ID as a human user")
    team = user_auth["team_id"]
    events = queue.Queue()

    def process_event(event, parsed):
        if processes.closed:
            react(user_client, event["channel"], event["ts"], "eyes", remove=True)
            return
        state = State(state_dir)
        try:
            client = WebClient(token=user_token)
            handle(event, parsed, team, client, state, workspace, state_dir)
        except Exception:
            if not processes.closed:
                raise
        finally:
            state.db.close()

    workers = ThreadQueue(process_event)
    socket = SocketModeClient(app_token=app_token, web_client=user_client)

    def receive(client, request):
        client.send_socket_mode_response(SocketModeResponse(envelope_id=request.envelope_id))
        if request.type == "events_api" and request.payload.get("team_id") == team:
            events.put(request.payload.get("event", {}))

    socket.socket_mode_request_listeners.append(receive)

    def interrupt(signum, frame):
        raise KeyboardInterrupt

    with ExitStack() as cleanup:
        admission_state = State(state_dir)
        cleanup.callback(admission_state.db.close)
        previous = signal.signal(signal.SIGTERM, interrupt)
        cleanup.callback(signal.signal, signal.SIGTERM, previous)
        cleanup.callback(workers.close)
        cleanup.callback(socket.close)
        cleanup.callback(processes.close)
        socket.connect()
        print(f"Agent Slack listening for {'/'.join(commands)} commands from {user_id}", flush=True)
        while True:
            event = events.get()
            parsed = acknowledge(event, team, user_id, user_client, admission_state, projects, commands)
            if parsed is not None:
                workers.submit(event, parsed)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (ValueError, RuntimeError) as error:
        print(f"Agent Slack: {error}", file=sys.stderr)
        sys.exit(1)
