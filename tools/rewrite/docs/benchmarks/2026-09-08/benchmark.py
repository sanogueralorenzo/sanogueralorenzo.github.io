"""Opt-in real provider benchmark. Uses synthetic source and temporary credentials."""
import argparse, json, os, pathlib, re, subprocess, tempfile, time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=pathlib.Path, default=HERE / 'source.txt')
parser.add_argument('--output', type=pathlib.Path, default=HERE)
options = parser.parse_args()
source = options.source.read_text().rstrip('\n')
HERE = options.output.resolve()
HERE.mkdir(parents=True, exist_ok=True)
swift = (ROOT / 'Sources/Editing.swift').read_text()
rules = '\n'.join(line[4:] for line in re.search(r'static let rules = """\n(.*?)\n    """', swift, re.S).group(1).splitlines())
payload = json.dumps({'editing_instruction': 'Improve readability and phrasing.', 'source_text': source}, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
isolation = ['--offline', '--no-session', '--no-tools', '--no-extensions', '--no-skills', '--no-prompt-templates', '--no-context-files', '--no-themes', '--no-approve']
env = {k: v for k, v in os.environ.items() if k in ['HOME', 'PATH', 'USER', 'TMPDIR', 'LANG', 'SSL_CERT_FILE', 'SSL_CERT_DIR']}
env.update(PI_OFFLINE='1', PI_TELEMETRY='0', NO_COLOR='1', TERM='dumb')
results = []
for index, harness in enumerate(['pi', 'codex', 'codex', 'pi', 'pi', 'codex']):
    with tempfile.TemporaryDirectory(prefix='rewrite-benchmark-') as tmp:
        work = pathlib.Path(tmp)
        started = time.perf_counter()
        child_env = dict(env)
        auth_seconds = 0
        if harness == 'pi':
            auth_env = dict(env)
            if os.environ.get('PI_CODING_AGENT_DIR'): auth_env['PI_CODING_AGENT_DIR'] = os.environ['PI_CODING_AGENT_DIR']
            auth = subprocess.run(['pi', 'auth', 'check', '--provider', 'openai-codex', '--json', '--credentials'], env=auth_env, cwd=tmp, capture_output=True, timeout=30)
            obj = json.loads(auth.stdout)
            if auth.returncode or obj.get('status') != 'ready': raise RuntimeError('Pi sign-in unavailable')
            credential = {'type':'oauth', 'access':obj['credentials'], 'refresh':'', 'expires': (time.time()+600)*1000}
            path = work / 'auth.json'
            path.write_text(json.dumps({'openai-codex':credential})); path.chmod(0o600)
            del obj, credential, auth
            (work / 'settings.json').write_text('{"compaction":{"enabled":false},"retry":{"enabled":false}}')
            extension = work / 'fast.ts'
            extension.write_text('export default function(pi) { pi.on("before_provider_request", event => { const payload = {...event.payload, service_tier: "priority"}; console.error("REWRITE_AUDIT " + JSON.stringify({tier: payload.service_tier, tools: (payload.tools || []).length, instructions_chars: (payload.instructions || "").length})); return payload; }); }')
            child_env['PI_CODING_AGENT_DIR'] = tmp
            args = ['pi'] + isolation + ['-e', str(extension), '--print', '--mode', 'json', '--provider', 'openai-codex', '--model', 'gpt-5.6-luna', '--thinking', 'low', '--system-prompt', rules]
            auth_seconds = time.perf_counter()-started
        else:
            rules_path = work / 'instructions.txt'; rules_path.write_text(rules)
            child_env['RUST_LOG'] = 'off'
            child_env['CODEX_HOME'] = os.environ.get('CODEX_HOME', str(pathlib.Path.home()/'.codex'))
            args = ['codex','exec','--ephemeral','--ignore-user-config','--ignore-rules','--skip-git-repo-check','--sandbox','read-only','--json','--color','never','--model','gpt-5.6-luna']
            settings = {'model_reasoning_effort':'low','service_tier':'fast','approval_policy':'never','project_doc_max_bytes':0,'web_search':'disabled','history.persistence':'none','analytics.enabled':False,'feedback.enabled':False,'model_instructions_file':str(rules_path),'sqlite_home':tmp,'log_dir':tmp}
            for key,value in settings.items(): args += ['-c',key+'='+json.dumps(value)]
            for feature in ['shell_tool','unified_exec','shell_snapshot','apps','plugins','hooks','memories','multi_agent','multi_agent_v2','browser_use','computer_use','image_generation','view_image','code_mode','code_mode_host','skill_search','workspace_dependencies','tool_suggest']:
                args += ['--disable',feature]
            args += ['--enable','skip_host_skill_discovery','--enable','fast_mode','-']
        process_start = time.perf_counter()
        output = subprocess.run(args,input=payload.encode(),env=child_env,cwd=tmp,capture_output=True,timeout=150)
        seconds = time.perf_counter()-process_start
        events = []
        for line in output.stdout.decode().split('\n'):
            if line.strip():
                try: events.append(json.loads(line))
                except ValueError: pass
        result = {'run':index+1,'harness':harness,'seconds':round(seconds,3),'total_seconds':round(time.perf_counter()-started,3),'auth_setup_seconds':round(auth_seconds,3),'exit_status':output.returncode,'requested_tier':'priority' if harness=='pi' else 'fast'}
        text = None
        if harness == 'pi':
            for event in events:
                if event.get('type')=='message_end' and event.get('message',{}).get('role')=='assistant':
                    msg = event['message']; result['usage']=msg.get('usage'); result['stop_reason']=msg.get('stopReason')
                    text=''.join(c.get('text','') for c in msg['content'] if c['type']=='text')
            result['request_audit']=[json.loads(line[len('REWRITE_AUDIT '):]) for line in output.stderr.decode().splitlines() if line.startswith('REWRITE_AUDIT ')]
            result['completed']=any(e.get('type')=='agent_end' for e in events) and result.get('stop_reason')=='stop'
        else:
            for event in events:
                if event.get('type')=='item.completed' and event.get('item',{}).get('type')=='agent_message':text=event['item']['text']
                if event.get('type')=='turn.completed': result['usage']=event.get('usage')
            result['completed']=any(e.get('type')=='turn.completed' for e in events)
            result['tool_actions']=[e['item']['type'] for e in events if e.get('type')=='item.completed' and e.get('item',{}).get('type') not in ['agent_message','error']]
            result['notices']=[e['item'].get('message','').replace(str(pathlib.Path.home()), '~') for e in events if e.get('type')=='item.completed' and e.get('item',{}).get('type')=='error']
        if text: (HERE / f'{index+1}-{harness}.txt').write_text(text)
        if not result['completed'] or output.returncode:
            result['error_events']=[e for e in events if e.get('type') in ['error','turn.failed']]
            print(json.dumps(result),flush=True)
            raise RuntimeError('Benchmark failed; no timing comparison produced')
        results.append(result)
        (HERE/'results.json').write_text(json.dumps({'source_words':len(source.split()),'source_characters':len(source),'model':'gpt-5.6-luna','reasoning':'low','results':results},indent=2)+'\n')
        print(json.dumps(result),flush=True)
