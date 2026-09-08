#!/usr/bin/env python3
"""Deterministic RPC lifecycle failures, without model calls."""
import json
import os
import sys
import time

scenario = sys.argv[1]

def emit(value):
    raw = (json.dumps(value, ensure_ascii=False) + '\n').encode()
    # Split a record to exercise incremental LF framing.
    sys.stdout.buffer.write(raw[:9]); sys.stdout.buffer.flush()
    sys.stdout.buffer.write(raw[9:]); sys.stdout.buffer.flush()

for line in sys.stdin.buffer:
    command = json.loads(line)
    if scenario == 'crash': os._exit(7)
    if scenario == 'timeout': time.sleep(30)
    if scenario == 'overflow':
        sys.stdout.buffer.write(b'x' * 2_100_000); sys.stdout.buffer.flush(); time.sleep(30)
    if scenario == 'tool':
        emit({'type': 'tool_execution_start'}); continue
    response = {'type': 'response', 'id': command['id'], 'command': command['type'], 'success': True}
    if command['type'] == 'new_session':
        response['data'] = {'cancelled': scenario == 'cancelled-reset'}
    if command['type'] == 'get_state':
        response['data'] = {'messageCount': 2 if scenario == 'dirty-reset' else 0, 'pendingMessageCount': 0, 'isStreaming': False}
    if command['type'] == 'prompt':
        emit({'type': 'message_end', 'message': {'role': 'assistant', 'stopReason': 'stop', 'content': [{'type': 'text', 'text': 'Hello\u2028world.'}]}})
        emit({'type': 'agent_end'})
    emit({**response, 'id': 'stale-response'})
    emit(response)
