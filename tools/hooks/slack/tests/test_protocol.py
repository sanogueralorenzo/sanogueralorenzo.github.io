import contextlib, hashlib, json, os, sys, tempfile, time, unittest
from pathlib import Path
from support import Backend, configuration, event, ROOT, ORIGIN, Client

REPO = ROOT.parents[1]


def wait_until(predicate, seconds=4):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError("Condition did not become true")


def dead(pid):
    import subprocess

    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True
    )
    return not result.stdout.strip() or result.stdout.strip().startswith("Z")


class NativeProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="browser-hooks-parity-")
        self.home = Path(self.temp.name)
        self.backends = []
        self.sockets = []

    def tearDown(self):
        for c in self.sockets:
            with contextlib.suppress(OSError):
                c.close()
        for b in self.backends:
            b.stop()
        self.temp.cleanup()

    def start(self, **kw):
        config = kw.pop("config", configuration(self.home))
        b = Backend(self.home, config, **kw)
        self.backends.append(b)
        return b

    def ws(self, b):
        c = b.socket()
        self.sockets.append(c)
        return c

    def test_pairing_authentication_permissions_and_replay(self):
        b = self.start(auto_pair=False)
        code = b.bootstrap()["code"]
        self.assertGreater(b.bootstrap()["expiresAt"], time.time() * 1000)
        self.assertEqual(
            (self.home / "extension/bridge-pairing.json").stat().st_mode & 0o777, 0o600
        )
        self.assertEqual(b.call("GET", "/config")[0], 403)
        self.assertFalse(b.call("GET", "/health")[1]["paired"])
        self.assertEqual(
            b.call("GET", "/health", headers={"Host": "evil.example"})[0], 403
        )
        self.assertEqual(
            b.call(
                "POST",
                "/pair",
                {"code": code},
                headers={"Origin": "https://app.slack.com"},
            )[0],
            403,
        )
        status, paired, headers = b.call("POST", "/pair", {"code": code})
        self.assertEqual(status, 200)
        b.token = paired["token"]
        self.assertEqual(b.call("POST", "/run", event())[0], 404)
        self.assertEqual(b.call("POST", "/github/run", event())[0], 404)
        self.assertNotIn("Access-Control-Allow-Origin", headers)
        self.assertFalse((self.home / "extension/bridge-pairing.json").exists())
        self.assertEqual(
            (self.home / "pairing.json").stat().st_mode & 0o777, 0o600
        )
        self.assertEqual(
            (self.home / "hooks/slack/sessions.sqlite3").stat().st_mode & 0o777, 0o600
        )
        self.assertEqual(b.call("POST", "/pair", {"code": code})[0], 403)
        self.assertEqual(
            b.call("GET", "/config", headers={"Authorization": "Bearer wrong"})[0], 403
        )
        self.assertEqual(
            b.call(
                "GET",
                "/config",
                headers={"X-Browser-Hooks-Origin": "chrome-extension://" + "b" * 32},
            )[0],
            403,
        )
        self.assertEqual(b.call("GET", "/config")[1], {"hooks": {"slack": {"keywords": ["hook"]}}})

    def test_websocket_origin_authentication_keepalive_and_completion(self):
        b = self.start()
        for kwargs, status in [
            ({"origin": "https://app.slack.com"}, 403),
            ({"origin": "chrome-extension://" + "b" * 32}, 403),
            ({"host": "evil.example"}, 403),
            ({"key": "invalid"}, 400),
        ]:
            c = Client(b.server, **kwargs)
            self.sockets.append(c)
            self.assertIn(" " + str(status) + " ", c.response)
        for token in ("wrong", "non-ascii-\u2603"):
            c = Client(b.server)
            self.sockets.append(c)
            c.send({"type": "authenticate", "token": token})
            self.assertIsNone(c.receive())
        c = self.ws(b)
        c.send({"type": "ping"})
        self.assertEqual(c.receive(), {"type": "pong"})
        c.send(b"heartbeat", opcode=9)
        self.assertEqual(c.receive(), (10, b"heartbeat"))
        accepted = b.request("POST", "/slack/run", event())
        expected = hashlib.sha256(
            json.dumps(["ETEST", "UTEST", "CTEST", "2000000001.000001"]).encode()
        ).hexdigest()
        self.assertEqual(accepted["job"], expected)
        self.assertEqual(c.receive(), {"type": "job", "hook": "slack", "job": expected})
        self.assertEqual(
            b.request("GET", "/slack/jobs/" + expected)["answer"], "synthetic answer"
        )

    def test_pair_rotation_disconnects_old_stream(self):
        folder = self.home / "hooks/slack"
        folder.mkdir(parents=True)
        saved = {"origin": ORIGIN, "token": "synthetic-saved-token"}
        (self.home / "pairing.json").write_text(json.dumps(saved))
        b = self.start(auto_pair=False)
        c = self.ws(b)
        code = b.bootstrap()["code"]
        old = b.token
        status, value, _ = b.call("POST", "/pair", {"code": code})
        self.assertEqual(status, 200)
        self.assertNotEqual(value["token"], old)
        self.assertIsNone(c.receive())
        self.assertEqual(b.call("GET", "/config")[0], 403)
        b.token = value["token"]
        self.assertEqual(b.call("GET", "/config")[0], 200)

    def test_graceful_shutdown_removes_bootstrap_and_closes_stream(self):
        folder = self.home / "hooks/slack"
        folder.mkdir(parents=True)
        (self.home / "pairing.json").write_text(
            json.dumps({"origin": ORIGIN, "token": "synthetic-saved-token"})
        )
        b = self.start(auto_pair=False)
        c = self.ws(b)
        b.stop()
        self.assertFalse((self.home / "extension/bridge-pairing.json").exists())
        self.assertIsNone(c.receive())

    def test_input_validation_and_http_limits(self):
        b = self.start()
        invalid = [
            {"token": "forbidden"},
            {"command": ["sh"]},
            {"channel": "https://example.com"},
            {"text": " hook test"},
            {"text": "unknown test"},
            {"text": "hook "},
            {"user": "U"},
            {"ts": "bad"},
            {"messages": [{"ts": "bad", "user": "UTEST", "text": "x"}]},
            {
                "messages": [
                    {"ts": "1.000001", "user": "UTEST", "text": "x", "extra": True}
                ]
            },
            {"messages": [{"ts": "1.000001", "user": "UTEST", "text": "x" * 12001}]},
            {"messages": [{"ts": "1.000001", "user": "UTEST", "text": "x"}] * 1001},
        ]
        for extra in invalid:
            self.assertEqual(
                b.call("POST", "/slack/run", event(**extra))[0], 400, extra.keys()
            )
        self.assertEqual(b.call("POST", "/slack/run", raw="[]")[0], 400)
        self.assertEqual(b.call("POST", "/slack/run", raw="{broken")[0], 400)
        self.assertEqual(
            b.call("POST", "/slack/run", event(), headers={"Content-Type": "text/plain"})[0],
            415,
        )
        self.assertEqual(
            b.call(
                "POST",
                "/slack/run",
                raw="x",
                headers={"Content-Length": str(2 * 1024 * 1024 + 1)},
            )[0],
            413,
        )
        for name in ("claim", "delivered", "cancel"):
            self.assertEqual(b.call("POST", "/slack/" + name, {"job": "../config"})[0], 400)
        self.assertEqual(
            b.call("POST", "/slack/delivered", {"job": "a" * 64, "ts": "bad"})[0], 400
        )

    def test_cancellation_and_shutdown_kill_descendant_processes(self):
        pids = self.home / "pids.json"
        script = (
            'import json,os,subprocess,sys,time;sys.stdin.read();p=subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"]);open('
            + repr(str(pids))
            + ',"w").write(json.dumps([os.getpid(),p.pid]));time.sleep(30)'
        )
        b = self.start(config=configuration(self.home, script))
        job = b.request("POST", "/slack/run", event())["job"]
        wait_until(pids.exists)
        parent, child = json.loads(pids.read_text())
        b.request("POST", "/slack/cancel", {"job": job})
        b.wait(job, "cancelled")
        wait_until(lambda: dead(parent) and dead(child))
        pids.unlink()
        b.request("POST", "/slack/run", event(ts="2000000002.000001"))
        wait_until(pids.exists)
        parent, child = json.loads(pids.read_text())
        b.stop()
        wait_until(lambda: dead(parent) and dead(child))

    def test_successful_parent_exit_also_cleans_up_descendants(self):
        pid_file = self.home / "child.pid"
        script = (
            'import json,subprocess,sys;child=subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"]);open('
            + repr(str(pid_file))
            + ',"w").write(str(child.pid));print(json.dumps({"session_id":"s","answer":"answer"}))'
        )
        b = self.start(config=configuration(self.home, script))
        job = b.request("POST", "/slack/run", event())["job"]
        self.assertEqual(b.wait(job)["answer"], "answer")
        wait_until(lambda: dead(int(pid_file.read_text())))

    def test_timeout_output_limits_and_response_validation(self):
        scripts = [
            ("import time;time.sleep(30)", "timeout", 1),
            (
                'import sys,time;sys.stdin.read();sys.stdout.write("x"*2097152);sys.stdout.flush();time.sleep(.2)',
                "output_limit",
                2,
            ),
            (
                'import sys,time;sys.stdin.read();sys.stderr.write("x"*2097152);sys.stderr.flush();time.sleep(.2)',
                "output_limit",
                2,
            ),
            ('print("invalid")', "invalid_response", 2),
            (
                'import json;print(json.dumps({"session_id":"x","answer":"x"*12001}))',
                "invalid_response",
                2,
            ),
        ]
        for index, (script, code, limit) in enumerate(scripts):
            # Each subcase uses a separate private home and service.
            sub = self.home / str(index)
            sub.mkdir()
            b = Backend(sub, configuration(sub, script, limit))
            self.backends.append(b)
            job = b.request("POST", "/slack/run", event())["job"]
            self.assertEqual(b.wait(job, "failed")["error"]["code"], code)
            b.stop()

    def test_child_environment_excludes_bridge_and_slack_credentials(self):
        script = 'import json,os,sys;sys.stdin.read();print(json.dumps({"session_id":"s","answer":json.dumps({k:v for k,v in os.environ.items() if k.endswith("_PARITY")})}))'
        env = {
            **os.environ,
            "SLACK_PARITY": "fixture-secret",
            "AGENT_SLACK_PARITY": "fixture-secret",
            "BROWSER_HOOKS_PARITY": "fixture-secret",
            "KEEP_PARITY": "kept",
        }
        b = self.start(config=configuration(self.home, script), env=env)
        job = b.request("POST", "/slack/run", event())["job"]
        self.assertEqual(json.loads(b.wait(job)["answer"]), {"KEEP_PARITY": "kept"})

    def test_context_limit_and_session_mismatch(self):
        b = self.start()
        context = [
            {"ts": "2000000000.000001", "user": "UTEST", "text": "x" * 12000}
            for _ in range(23)
        ]
        job = b.request("POST", "/slack/run", event(messages=context))["job"]
        self.assertEqual(b.wait(job, "failed")["error"]["code"], "context_limit")
        # Change session on resume; the bridge must reject it.
        b.stop()
        cfg = configuration(
            self.home,
            'import json,sys;sys.stdin.read();print(json.dumps({"session_id":"first" if len(sys.argv)==1 else "changed","answer":"answer"}))',
        )
        b = Backend(self.home, cfg)
        self.backends.append(b)
        job = b.request("POST", "/slack/run", event(ts="2000000002.000001"))["job"]
        b.wait(job)
        job = b.request("POST", "/slack/run", event(ts="2000000003.000001"))["job"]
        self.assertEqual(b.wait(job, "failed")["error"]["code"], "session_invalid")

    def test_queue_admission_is_bounded(self):
        b = self.start(
            config=configuration(self.home, "import time;time.sleep(30)", 600)
        )
        for n in range(100):
            self.assertEqual(
                b.call("POST", "/slack/run", event(ts=f"2000000001.{n:06}"))[0], 200
            )
        self.assertEqual(b.call("POST", "/slack/run", event(ts="2000000002.000001"))[0], 400)
        b.stop()

    def test_large_prompt_preserves_structured_errors_when_cli_ignores_stdin(self):
        script = 'import json;print(json.dumps({"error":{"code":"auth_required","provider":"Claude","message":"fixture-private-secret"}}));raise SystemExit(1)'
        b = self.start(config=configuration(self.home, script))
        context = [
            {"ts": "2000000000.000001", "user": "UTEST", "text": "x" * 12000}
            for _ in range(8)
        ]
        job = b.request("POST", "/slack/run", event(messages=context))["job"]
        value = b.wait(job, "failed")
        self.assertEqual(value["error"]["code"], "auth_required")
        self.assertNotIn(
            "fixture-private-secret",
            json.dumps(value) + json.dumps(b.call("GET", "/health")[1]),
        )

    def test_existing_codex_and_claude_adapters_report_safe_login_failures(self):
        for name in ("codex", "claude"):
            home = self.home / name
            home.mkdir()
            bin_dir = home / "bin"
            bin_dir.mkdir()
            executable = bin_dir / name
            executable.write_text(
                chr(10).join(
                    [
                        "#!" + sys.executable,
                        "import json",
                        'print(json.dumps({"is_error":True,"result":"OAuth token has expired fixture-private-secret"}))',
                        "raise SystemExit(1)",
                        "",
                    ]
                )
            )
            executable.chmod(0o700)
            wrapper = REPO / "tools/hooks/slack/agents" / (name + ".py")
            cfg = configuration(home)
            cfg["commands"]["hook"] = {
                "start": [sys.executable, str(wrapper)],
                "resume": [sys.executable, str(wrapper), "{session_id}"],
            }
            env = {
                **os.environ,
                "PATH": str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
            }
            b = Backend(home, cfg, env=env)
            self.backends.append(b)
            job = b.request("POST", "/slack/run", event())["job"]
            value = b.wait(job, "failed")
            self.assertEqual(value["error"]["code"], "auth_required")
            self.assertEqual(value["error"]["provider"].lower(), name)
            self.assertNotIn("fixture-private-secret", json.dumps(value))
            b.stop()
            self.assertNotIn(
                "fixture-private-secret", (home / "stderr.log").read_text()
            )

    def test_invalid_configuration_fails_before_listening(self):
        good = configuration(self.home)
        bad = [
            {},
            dict(good, workspace="/path-that-does-not-exist"),
            dict(good, timeout_seconds=0),
            dict(good, timeout_seconds=601),
            dict(good, projects={"Invalid Alias": str(self.home)}),
            dict(
                good,
                commands={"hook": {"start": ["/bin/echo"], "resume": ["/bin/echo"]}},
            ),
            dict(
                good,
                commands={
                    "hook": good["commands"]["hook"],
                    "HOOK": good["commands"]["hook"],
                },
            ),
            dict(good, commands={"hook word": good["commands"]["hook"]}),
            dict(good, commands={"hook": dict(good["commands"]["hook"], extra=True)}),
        ]
        for n, cfg in enumerate(bad):
            home = self.home / str(n)
            home.mkdir()
            with self.assertRaises(RuntimeError):
                Backend(home, cfg)

    def test_malformed_websocket_frames_never_produce_application_data(self):
        b = self.start()
        for raw in [
            bytes.fromhex("81027b7d"),
            bytes.fromhex("828061616161"),
            bytes.fromhex("81feffff61616161"),
        ]:
            c = self.ws(b)
            try:
                c.socket.sendall(raw)
                try:
                    value = c.receive()
                except (ConnectionResetError, BrokenPipeError):
                    value = None
                self.assertTrue(
                    value is None or isinstance(value, tuple) and value[0] == 8, value
                )
            finally:
                c.close()

    def test_concurrency_is_bounded_at_eight(self):
        log = self.home / "concurrency.jsonl"
        script = (
            "import json,os,sys,time;sys.stdin.read();f=open("
            + repr(str(log))
            + ',"a");f.write(json.dumps(["start",os.getpid()])+"\\n");f.flush();time.sleep(.2);f.write(json.dumps(["end",os.getpid()])+"\\n");f.flush();print(json.dumps({"session_id":"s","answer":"answer"}))'
        )
        b = self.start(config=configuration(self.home, script, 4))
        jobs = [
            b.request("POST", "/slack/run", event(channel=f"C{n}", ts=f"2000000001.{n:06}"))[
                "job"
            ]
            for n in range(12)
        ]
        for job in jobs:
            b.wait(job)
        active = peak = 0
        for line in log.read_text().splitlines():
            kind, _ = json.loads(line)
            active += 1 if kind == "start" else -1
            peak = max(peak, active)
        self.assertEqual(active, 0)
        self.assertLessEqual(peak, 8)
        self.assertGreaterEqual(peak, 2)


if __name__ == "__main__":
    unittest.main()
