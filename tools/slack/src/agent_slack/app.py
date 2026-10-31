"""Own configuration, Slack connections, workers, and command processes."""

import os
import queue
import signal
from contextlib import closing
from dataclasses import dataclass, field
from pathlib import Path

from slack_sdk import WebClient
from slack_sdk.socket_mode import SocketModeClient
from slack_sdk.socket_mode.response import SocketModeResponse

from .commands import Command, Executor, load_commands
from .conversation import Conversation, acknowledge
from .process_runner import ProcessRunner
from .reactions import react
from .routing import project_workspaces
from .state import State
from .thread_queue import ThreadQueue


def required(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"Set {name} in the environment or .env")
    return value


@dataclass(frozen=True)
class Config:
    app_token: str = field(repr=False)
    user_token: str = field(repr=False)
    user_id: str
    workspace: Path
    state_dir: Path
    commands: dict[str, Command]
    projects: dict[str, Path]

    @classmethod
    def from_env(cls):
        commands = load_commands()
        app_token, user_token = required("SLACK_APP_TOKEN"), required("SLACK_USER_TOKEN")
        user_id = required("SLACK_USER_ID")
        workspace = Path(required("AGENT_SLACK_WORKSPACE")).expanduser().resolve()
        if not workspace.is_dir():
            raise ValueError(f"AGENT_SLACK_WORKSPACE is not a directory: {workspace}")
        if not app_token.startswith("xapp-") or not user_token.startswith("xoxp-"):
            raise ValueError("Use an xapp app token and xoxp authorized-user token")
        return cls(
            app_token=app_token, user_token=user_token, user_id=user_id, workspace=workspace,
            state_dir=Path(os.environ.get("AGENT_SLACK_STATE_DIR", "~/.local/state/agent-slack")).expanduser(),
            commands=commands, projects=project_workspaces(),
        )


class Application:
    def __init__(self, config: Config):
        self.config = config
        self.events = queue.Queue()

    def receive(self, client, request):
        client.send_socket_mode_response(SocketModeResponse(envelope_id=request.envelope_id))
        if request.type == "events_api" and request.payload.get("team_id") == self.team:
            self.events.put(request.payload.get("event", {}))

    def process_event(self, event, request):
        if self.processes.closed:
            react(self.client, event["channel"], event["ts"], "eyes", remove=True)
            return
        try:
            with closing(State(self.config.state_dir)) as state:
                conversation = Conversation(
                    team=self.team, client=WebClient(token=self.config.user_token), state=state,
                    executor=self.executor, workspace=self.config.workspace,
                )
                conversation.handle(event, request)
        except Exception:
            if not self.processes.closed:
                raise

    def run(self):
        self.client = WebClient(token=self.config.user_token)
        auth = self.client.auth_test()
        if auth.get("bot_id") or auth.get("user_id") != self.config.user_id:
            raise ValueError("SLACK_USER_TOKEN must belong to SLACK_USER_ID as a human user")
        self.team = auth["team_id"]

        def interrupt(signum, frame):
            raise KeyboardInterrupt

        previous = signal.signal(signal.SIGTERM, interrupt)
        try:
            # Stop commands before waiting for workers; each worker owns its database connection.
            with (closing(ThreadQueue(self.process_event)) as self.workers,
                  closing(SocketModeClient(app_token=self.config.app_token, web_client=self.client)) as self.socket,
                  closing(ProcessRunner()) as self.processes,
                  closing(State(self.config.state_dir)) as admission_state):
                self.executor = Executor(self.processes)
                self.socket.socket_mode_request_listeners.append(self.receive)
                self.socket.connect()
                print(f"Agent Slack listening for {'/'.join(self.config.commands)} commands from {self.config.user_id}", flush=True)
                while True:
                    event = self.events.get()
                    request = acknowledge(event, self.team, self.config.user_id, self.client, admission_state,
                                          self.config.projects, self.config.commands)
                    if request is not None:
                        self.workers.submit(event, request)
        finally:
            signal.signal(signal.SIGTERM, previous)
