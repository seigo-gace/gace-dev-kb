#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, re, subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

REQUIRED_BUNDLE_FILES=("asset.json","knowledge-units.jsonl","manifest.json")
REQUIRED_UNIT_KEYS=("schema_version","knowledge_id","parent_asset_id","asset_kind","name","summary","verification","provenance","data_class")
ALLOWED_DATA_CLASSES={"canonical","derived"}
ALLOWED_LIFECYCLE={"experimental","verified","active","deprecated","superseded","retired"}

@dataclass(frozen=True)
class KnowledgeRecord:
    type:str; repository:str; commit:str; summary:str; cause:str; fix:str; validation:str; source:str

def git(repo:Path,*args:str)->str:
    r=subprocess.run(["git","-C",str(repo),*args],capture_output=True,text=True,encoding="utf-8",errors="replace")
    if r.returncode: raise RuntimeError(f"git {' '.join(args)} failed ({r.returncode}): {r.stderr.strip()}")
    return r.stdout.strip()

def sha256_file(path:Path)->str:
    d=hashlib.sha256()
    with path.open('rb') as h:
        for c in iter(lambda:h.read(1024*1024),b''): d.update(c)
    return d.hexdigest()

def verify_manifest(bundle:Path,manifest:dict[str,Any])->None:
    if manifest.get('algorithm')!='sha256': raise RuntimeError('BUNDLE_MANIFEST_ALGORITHM_NOT_SHA256')
    files=manifest.get('files')
    if not isinstance(files,list) or not files: raise RuntimeError('BUNDLE_MANIFEST_FILES_MISSING')
    listed=set()
    for item in files:
        if not isinstance(item,dict): raise RuntimeError('BUNDLE_MANIFEST_FILE_ENTRY_INVALID')
        rel=str(item.get('path') or '').replace('\\','/').strip('/')
        if not rel: raise RuntimeError('BUNDLE_MANIFEST_PATH_EMPTY')
        if rel in listed: raise RuntimeError(f'BUNDLE_MANIFEST_DUPLICATE_PATH={rel}')
        listed.add(rel)
        path=(bundle/rel).resolve()
        try: path.relative_to(bundle.resolve())
        except ValueError as e: raise RuntimeError(f'BUNDLE_MANIFEST_PATH_ESCAPE={rel}') from e
        if not path.is_file(): raise RuntimeError(f'BUNDLE_MANIFEST_FILE_MISSING={rel}')
        if item.get('size') is not None and path.stat().st_size!=int(item['size']): raise RuntimeError(f'BUNDLE_MANIFEST_SIZE_MISMATCH={rel}')
        if str(item.get('sha256') or '').lower()!=sha256_file(path): raise RuntimeError(f'BUNDLE_MANIFEST_SHA256_MISMATCH={rel}')
    for rel in REQUIRED_BUNDLE_FILES:
        if rel!='manifest.json' and rel not in listed: raise RuntimeError(f'BUNDLE_REQUIRED_FILE_NOT_MANIFESTED={rel}')

def read_jsonl(path:Path)->list[dict[str,Any]]:
    rows=[]
    for n,line in enumerate(path.read_text(encoding='utf-8').splitlines(),1):
        if not line.strip(): continue
        item=json.loads(line)
        if not isinstance(item,dict): raise RuntimeError(f'KNOWLEDGE_UNIT_NOT_OBJECT line={n}')
        rows.append(item)
    if not rows: raise RuntimeError('KNOWLEDGE_UNITS_EMPTY')
    return rows

def validate_unit(unit:dict[str,Any])->None:
    missing=[k for k in REQUIRED_UNIT_KEYS if k not in unit]
    if missing: raise RuntimeError(f"KNOWLEDGE_UNIT_REQUIRED_FIELD_MISSING id={unit.get('knowledge_id')} fields={','.join(missing)}")
    if int(unit['schema_version'])!=1: raise RuntimeError(f"KNOWLEDGE_UNIT_SCHEMA_UNSUPPORTED={unit['schema_version']}")
    for k in ('knowledge_id','parent_asset_id','asset_kind','name','summary'):
        if not str(unit.get(k) or '').strip(): raise RuntimeError(f"KNOWLEDGE_UNIT_FIELD_EMPTY id={unit.get('knowledge_id')} field={k}")
    dc=str(unit['data_class'])
    if dc not in ALLOWED_DATA_CLASSES: raise RuntimeError(f"KNOWLEDGE_UNIT_DATA_CLASS_INVALID id={unit['knowledge_id']} value={dc}")
    verification=unit.get('verification')
    if not isinstance(verification,dict): raise RuntimeError(f"KNOWLEDGE_UNIT_FIELD_NOT_OBJECT id={unit['knowledge_id']} field=verification")
    status=str(verification.get('status') or '')
    if status not in {'verified','active'}: raise RuntimeError(f"KNOWLEDGE_UNIT_NOT_VERIFIED id={unit['knowledge_id']} status={status}")
    provenance=unit.get('provenance')
    if not isinstance(provenance,dict) or not isinstance(provenance.get('catalog'),dict): raise RuntimeError(f"KNOWLEDGE_UNIT_CATALOG_PROVENANCE_MISSING={unit['knowledge_id']}")
    for k in ('repository','commit','asset_id'):
        if not str(provenance['catalog'].get(k) or '').strip(): raise RuntimeError(f"KNOWLEDGE_UNIT_CATALOG_PROVENANCE_FIELD_MISSING id={unit['knowledge_id']} field={k}")
    if dc=='derived':
        derivation=unit.get('derivation')
        if not isinstance(derivation,dict): raise RuntimeError(f"DERIVED_UNIT_DERIVATION_MISSING={unit['knowledge_id']}")
        if not isinstance(derivation.get('derived_from'),list) or not derivation['derived_from']: raise RuntimeError(f"DERIVED_UNIT_SOURCE_MISSING={unit['knowledge_id']}")
    lifecycle=unit.get('lifecycle')
    if lifecycle is not None:
        if not isinstance(lifecycle,dict): raise RuntimeError(f"KNOWLEDGE_UNIT_LIFECYCLE_NOT_OBJECT={unit['knowledge_id']}")
        s=lifecycle.get('status')
        if s is not None and str(s) not in ALLOWED_LIFECYCLE: raise RuntimeError(f"KNOWLEDGE_UNIT_LIFECYCLE_INVALID id={unit['knowledge_id']} value={s}")

def validation_text(unit:dict[str,Any])->str:
    v=unit['verification']; parts=[f"status={v.get('status')}"]
    if v.get('verified_at'): parts.append(f"verifiedAt={v['verified_at']}")
    if v.get('validation_boundary'): parts.append(f"boundary={v['validation_boundary']}")
    for key,label in [('normal_test','normal'),('user_test','user')]:
        sec=v.get(key)
        if isinstance(sec,dict) and 'passed' in sec: parts.append(f"{label}.passed={str(bool(sec['passed'])).lower()}")
    return '; '.join(parts)

def envelope(unit:dict[str,Any],bundle_path:str)->KnowledgeRecord:
    c=unit['provenance']['catalog']; repo=str(c['repository']); commit=str(c['commit'])
    return KnowledgeRecord('reusable_asset',repo,commit,str(unit['summary']),'','',validation_text(unit),f"modulecatalog:{repo}@{commit}#{bundle_path.strip('/')}::{unit['knowledge_id']}")

def section(title:str,value:Any)->str:
    if value in (None,{},[]): return ''
    return f"## {title}\n\n```json\n{json.dumps(value,ensure_ascii=False,indent=2,sort_keys=True)}\n```\n\n"

def render(unit:dict[str,Any],record:KnowledgeRecord)->str:
    ident={k:unit.get(k) for k in ('knowledge_id','parent_asset_id','symbol','name','asset_kind','version','data_class')}
    parts=[f"# {unit['name']}\n\n",f"- Type: `{record.type}`\n- Repository: `{record.repository}`\n- Commit: `{record.commit}`\n- Source: `{record.source}`\n\n",f"## Summary\n\n{unit['summary']}\n\n"]
    for title,key in [('Identity',None),('Classification','classification'),('Discovery','discovery'),('Applicability','applicability'),('Contract','contract'),('Constraints','constraints'),('Composition And Relationships','composition'),('Implementation','implementation'),('Cases','cases'),('Verification','verification'),('Provenance','provenance'),('Lifecycle','lifecycle'),('Integrity','integrity'),('Derivation','derivation')]: parts.append(section(title,ident if key is None else unit.get(key)))
    return ''.join(parts)

def write_jsonl(path:Path,rows:list[dict[str,Any]])->None:
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('w',encoding='utf-8',newline='\n') as h:
        for row in rows: h.write(json.dumps(row,ensure_ascii=False,separators=(',',':'))+'\n')

def build(catalog_root:Path,bundle_path:str,output_root:Path,expected_record_count:int|None):
    catalog_root=catalog_root.resolve(); bundle=(catalog_root/bundle_path).resolve()
    try: bundle.relative_to(catalog_root)
    except ValueError as e: raise RuntimeError('BUNDLE_PATH_ESCAPES_CATALOG') from e
    for rel in REQUIRED_BUNDLE_FILES:
        if not (bundle/rel).is_file(): raise RuntimeError(f'BUNDLE_REQUIRED_FILE_MISSING={rel}')
    verify_manifest(bundle,json.loads((bundle/'manifest.json').read_text(encoding='utf-8')))
    asset=json.loads((bundle/'asset.json').read_text(encoding='utf-8'))
    if int(asset.get('schema_version',0))!=1: raise RuntimeError(f"ASSET_SCHEMA_UNSUPPORTED={asset.get('schema_version')}")
    asset_id=str(asset.get('asset_id') or '')
    if not asset_id: raise RuntimeError('ASSET_ID_MISSING')
    units=read_jsonl(bundle/'knowledge-units.jsonl'); seen=set(); head=git(catalog_root,'rev-parse','HEAD')
    for unit in units:
        validate_unit(unit); kid=str(unit['knowledge_id'])
        if kid in seen: raise RuntimeError(f'KNOWLEDGE_UNIT_ID_DUPLICATE={kid}')
        seen.add(kid)
        if str(unit['parent_asset_id'])!=asset_id: raise RuntimeError(f'KNOWLEDGE_UNIT_PARENT_MISMATCH id={kid}')
        c=unit['provenance']['catalog']
        if str(c['asset_id'])!=asset_id: raise RuntimeError(f'KNOWLEDGE_UNIT_CATALOG_ASSET_MISMATCH id={kid}')
        if str(c['commit'])!=head: raise RuntimeError(f'KNOWLEDGE_UNIT_CATALOG_COMMIT_MISMATCH id={kid} expected={head} actual={c["commit"]}')
    if expected_record_count is not None and len(units)!=expected_record_count: raise RuntimeError(f'KNOWLEDGE_UNIT_COUNT_MISMATCH expected={expected_record_count} actual={len(units)}')
    output_root=output_root.resolve(); corpus=output_root/'records'; corpus.mkdir(parents=True,exist_ok=True)
    for p in corpus.glob('*.md'): p.unlink()
    records=[]; metadata=[]
    for i,unit in enumerate(units,1):
        rec=envelope(unit,bundle_path); records.append(rec); meta=dict(unit); meta['_gace']={'type':rec.type,'repository':rec.repository,'commit':rec.commit,'source':rec.source}; metadata.append(meta)
        ident=re.sub(r'[^0-9A-Za-z._-]+','-',str(unit['knowledge_id'])).strip('-') or 'knowledge'
        (corpus/f'{i:04d}-{ident[:120]}.md').write_text(render(unit,rec),encoding='utf-8',newline='\n')
    write_jsonl(output_root/'knowledge-records.jsonl',[asdict(x) for x in records]); write_jsonl(output_root/'knowledge-metadata.jsonl',metadata)
    return records,metadata,corpus

def main()->int:
    p=argparse.ArgumentParser(); p.add_argument('--catalog-root',type=Path,required=True); p.add_argument('--bundle-path',required=True); p.add_argument('--output-root',type=Path,required=True); p.add_argument('--expected-record-count',type=int); a=p.parse_args()
    records,metadata,corpus=build(a.catalog_root,a.bundle_path,a.output_root,a.expected_record_count)
    print(f"GACE_REUSABLE_ASSET_IMPORT=PASS RECORDS={len(records)} KINDS={','.join(sorted({str(x['asset_kind']) for x in metadata}))} CORPUS={corpus}")
    return 0
if __name__=='__main__': raise SystemExit(main())
