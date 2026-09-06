#!/usr/bin/env python3
"""Send one manual command to an explicitly enabled local Godot review session."""
import argparse
import json
import socket

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('command', nargs='?', default='{"action":"state"}', help='One JSON command')
parser.add_argument('--port', type=int, default=45901)
parser.add_argument('--full', action='store_true')
parser.add_argument('--brief', action='store_true')
args = parser.parse_args()
request = json.loads(args.command)
with socket.create_connection(('127.0.0.1', args.port), timeout=10) as connection:
    connection.sendall((json.dumps(request) + '\n').encode())
    response = b''
    while not response.endswith(b'\n'):
        chunk = connection.recv(65536)
        if not chunk:
            break
        response += chunk
result = json.loads(response)
if not args.full:
    result.pop('players', None)
    result['ledger'] = result.get('ledger', [])[-3:]
if args.brief:
    keep = ['screen', 'season', 'round', 'score', 'phase', 'receiving', 'flight_remaining', 'aim', 'shot', 'block_lane', 'rival_lane', 'rival_shot', 'contacts', 'match_seconds', 'upgrades', 'unlocked', 'fps']
    if result['screen'] == 'upgrade':
        keep.append('offers')
    result = {k: result[k] for k in keep if k in result}
print(json.dumps(result, indent=None if args.brief else 2))
