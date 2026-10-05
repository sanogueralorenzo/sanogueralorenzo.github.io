#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Steam interface binding adapted from DroidDeck/Bannerlator's
# bannerlator-steam-games, Droid-Deck/DroidDeck commit
# 255c64551ec7d5a810da622d918eb88ffdccb231. See THIRD_PARTY.md.
"""Query the existing local Steam client; never start or authenticate one."""
import ctypes as C
import json
import sys
import time


def method(obj, slot, result, *args):
    if not obj:
        raise RuntimeError("Steam's local interface is unavailable. Update the app or reopen Steam.")
    table = C.cast(obj, C.POINTER(C.POINTER(C.c_void_p))).contents
    return C.CFUNCTYPE(result, C.c_void_p, *args)(table[slot])


ids = json.loads(sys.stdin.read(131072))
if not isinstance(ids, list) or len(ids) > 10000 or any(type(i) is not int or not 0 < i < 0x80000000 for i in ids):
    raise RuntimeError("Invalid game metadata request.")
library = C.CDLL("/root/.local/share/Steam/steamrtarm64/steamclient.so")
library.CreateInterface.argtypes = [C.c_char_p, C.c_void_p]
library.CreateInterface.restype = C.c_void_p
client = library.CreateInterface(b"SteamClient020", None)
pipe = method(client, 0, C.c_int)(client)
if not pipe:
    raise RuntimeError("Open Steam and sign in before refreshing the library.")
user = 0
try:
    user = method(client, 2, C.c_int, C.c_int)(client, pipe)
    if not user:
        raise RuntimeError("Open Steam and sign in before refreshing the library.")
    get = lambda slot, version: method(client, slot, C.c_void_p, C.c_int, C.c_int, C.c_char_p)(client, user, pipe, version)
    account = get(5, b"SteamUser021")
    if not method(account, 1, C.c_bool)(account):
        raise RuntimeError("Steam is offline. Reconnect in Steam, then refresh the library.")
    steamid = method(account, 2, C.c_uint64)(account)
    apps = get(15, b"STEAMAPPS_INTERFACE_VERSION008")
    subscribed = method(apps, 6, C.c_bool, C.c_uint32)
    snapshot = {"account": str(steamid & 0xffffffff), "checked": int(time.time()),
                "available": [appid for appid in ids if subscribed(apps, appid)]}
    print("ANDROIDSTEAM_LIBRARY=" + json.dumps(snapshot), flush=True)
finally:
    if user:
        method(client, 4, None, C.c_int, C.c_int)(client, pipe, user)
    method(client, 1, C.c_bool, C.c_int)(client, pipe)
