"""Slack reaction updates must not interrupt an otherwise successful reply."""

import logging


def react(client, channel, ts, name, *, remove=False):
    try:
        method = client.reactions_remove if remove else client.reactions_add
        method(channel=channel, timestamp=ts, name=name)
    except Exception as error:
        code = (getattr(error, "response", None) or {}).get("error")
        if code != ("no_reaction" if remove else "already_reacted"):
            logging.getLogger(__name__).warning(
                "Could not %s :%s: on %s/%s: %s",
                "remove" if remove else "add", name, channel, ts, code or str(error),
            )
