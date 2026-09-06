"""Disposable fixed-frame capture setup; output only, no gameplay inputs or tests."""
from pathlib import Path
import shutil
work=Path('/tmp/spikeseason-forward-review')
for kind in ['baseline','candidate']:
 source=work/kind
 target=work/(kind+'-capture')
 shutil.copytree(source,target,ignore=shutil.ignore_patterns('.godot','evidence','build'),dirs_exist_ok=True)
 # Both receive the same shader clock driven at fixed 60Hz by the capture session.
 for p in (target/'shaders').rglob('*.gdshader'):
  s=p.read_text()
  if 'TIME' in s:
   first,rest=s.split('\n',1)
   p.write_text(first+'\nuniform float capture_time=0.;\n'+rest.replace('TIME','capture_time'))
