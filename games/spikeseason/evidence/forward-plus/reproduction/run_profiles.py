"""Sequential manual performance recording; no inputs, assertions or pass/fail tests."""
from pathlib import Path
import subprocess,time,json,sys
root=Path('/tmp/spikeseason-forward-review')
out=root/'evidence'
for variant in ['baseline','candidate']:
 for venue in [1,6,8]:
  name=f'{variant}-season-{venue}-final-performance'
  inventory=subprocess.check_output(['ps','-axo','pid,state,command'],text=True)
  (out/(name+'-processes.txt')).write_text('\n'.join(x for x in inventory.splitlines() if 'godot' in x.lower() or 'SpikeSeason' in x))
  with (out/(name+'.log')).open('w') as log:
   command=['godot','--path',str(root/variant),'--script',str(root/'profile.gd'),'--','--review-port=45925',f'--review-profile=forward-{variant}',f'--venue={venue}',f'--output={out/name}','--seconds=30']
   p=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT)
   rows=[]
   while p.poll() is None:
    result=subprocess.run(['ps','-o','rss=','-p',str(p.pid)],capture_output=True,text=True)
    if result.stdout.strip(): rows.append({'elapsed_s':round(time.monotonic(),3),'rss_kib':int(result.stdout.strip()),'measuring':'MEASURE pid=' in (out/(name+'.log')).read_text()})
    time.sleep(.5)
  (out/(name+'-rss.json')).write_text(json.dumps({'pid':p.pid,'command':command,'exit_code':p.returncode,'samples':rows},indent=2))
  print(name,'exit',p.returncode,flush=True)
  if p.returncode: print((out/(name+'.log')).read_text(),flush=True);sys.exit(p.returncode)
