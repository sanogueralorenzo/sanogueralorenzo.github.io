import UnityPy,json,pathlib,sys,collections
root=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
rows=[]; failures=[]
for f in root.iterdir():
 if not (f.suffix=='.assets' or f.name.startswith('level') and f.suffix==''):continue
 try:
  env=UnityPy.load(str(f))
  for o in env.objects:
   if o.type.name not in ['Mesh','Texture2D','Material','AnimationClip','AnimatorController','MonoBehaviour','MonoScript','AudioClip','TerrainData','GameObject']:continue
   try:
    d=o.read();name=getattr(d,'m_Name','');row={'file':f.name,'id':o.path_id,'type':o.type.name,'name':name}
    if o.type.name=='MonoBehaviour':
     try:
      tree=o.read_typetree();row['data']=tree
     except Exception as e:row['tree_error']=str(e)[:100]
    rows.append(row)
   except Exception as e:failures.append([f.name,o.path_id,str(e)[:120]])
 except Exception as e:failures.append([f.name,str(e)])
(out/'inventory.json').write_text(json.dumps(rows,default=str));(out/'failures.json').write_text(json.dumps(failures));print(collections.Counter(r['type'] for r in rows), 'failures',len(failures))
(out/'names.txt').write_text('\n'.join(f"{r['type']} | {r['file']} | {r['id']} | {r['name']}" for r in rows))
