"""Acknowledge requests and deliver command answers in Slack threads."""

from pathlib import Path

from commands import Executor
from reactions import react
from routing import Request, command_for
from state import Session, State
from thread_context import prompt_for, thread_messages, timestamp


def acknowledge(event, team, user_id, client, state, projects, commands):
    parsed = command_for(event, user_id, projects, commands)
    if parsed is None:
        return None
    channel, ts = event["channel"], event["ts"]
    if state.seen("posted", team, channel, ts) or state.seen("handled", team, channel, ts):
        return None
    react(client, channel, ts, "eyes")
    if state.seen("handled", team, channel, ts):
        react(client, channel, ts, "eyes", remove=True)
        return None
    return parsed


class Conversation:
    def __init__(self, *, team: str, client, state: State, executor: Executor, workspace: Path):
        self.team = team
        self.client = client
        self.state = state
        self.executor = executor
        self.workspace = workspace

    def handle(self, event, request: Request):
        channel, ts = event["channel"], event["ts"]
        if self.state.seen("posted", self.team, channel, ts) or self.state.seen("handled", self.team, channel, ts):
            return
        try:
            thread_ts = event.get("thread_ts") or ts
            is_reply = thread_ts != ts
            saved = self.state.session(self.team, channel, thread_ts) if is_reply else None
            workspace = request.workspace or (saved.workspace if saved else self.workspace)
            if not workspace.is_dir():
                raise ValueError(f"Agent Slack workspace is not a directory: {workspace}")
            resume = saved if (
                saved and saved.command_key == request.command.key and saved.workspace == workspace
            ) else None
            session_id = resume.session_id if resume else None
            after = resume.context_ts if resume else None
            messages = thread_messages(self.client, event, after) if is_reply else None
            if resume:
                messages = [message for message in messages if not self.state.knows_reply(
                    self.team, channel, message["ts"], resume.command_key, resume.session_id,
                )]
            posted = {message["ts"] for message in messages or ()
                      if self.state.seen("posted", self.team, channel, message["ts"])}
            prompt = prompt_for(event, messages, request.request, posted=posted)
            new_session_id, answer = self.executor.run(request.command, prompt, workspace, session_id)
            session = Session(
                command_key=request.command.key, session_id=new_session_id, workspace=workspace,
                context_ts=max(after, ts, key=timestamp) if after else ts,
            )
            self.state.save_session(self.team, channel, thread_ts, session)
            response = self.client.chat_postMessage(
                channel=channel, thread_ts=thread_ts, markdown_text=answer,
                unfurl_links=False, unfurl_media=False,
            )
            self.state.record_reply(self.team, channel, response["ts"], session.command_key, session.session_id)
            self.state.mark_handled(self.team, channel, ts)
            react(self.client, channel, response["ts"], "robot_face")
            react(self.client, channel, ts, "white_check_mark")
        finally:
            react(self.client, channel, ts, "eyes", remove=True)
