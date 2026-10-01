#!/usr/bin/env python3
from __future__ import annotations
import hashlib, importlib.util, json, shutil, subprocess, tempfile, unittest, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MODULE_PATH=ROOT/'scripts'/'import_reusable_asset_bundle.py'
SPEC=importlib.util.spec_from_file_location('import_reusable_asset_bundle',MODULE_PATH)
module=importlib.util.module_from_spec(SPEC); sys.modules[SPEC.name]=module; SPEC.loader.exec_module(module)

def sha(path:Path)->str: return hashlib.sha256(path.read_bytes()).hexdigest()
class T(unittest.TestCase):
    def setUp(self):
        self.tmp=Path(tempfile.mkdtemp()); self.catalog=self.tmp/'catalog'; self.bundle=self.catalog/'kb-export'/'asset-a'; self.out=self.tmp/'out'; self.bundle.mkdir(parents=True)
        subprocess.run(['git','init','-q',str(self.catalog)],check=True); subprocess.run(['git','-C',str(self.catalog),'config','user.email','test@example.com'],check=True); subprocess.run(['git','-C',str(self.catalog),'config','user.name','test'],check=True)
        (self.catalog/'seed.txt').write_text('seed\n'); subprocess.run(['git','-C',str(self.catalog),'add','.'],check=True); subprocess.run(['git','-C',str(self.catalog),'commit','-q','-m','seed'],check=True)
        self.commit=subprocess.check_output(['git','-C',str(self.catalog),'rev-parse','HEAD'],text=True).strip(); self.write_bundle()
    def tearDown(self): shutil.rmtree(self.tmp,ignore_errors=True)
    def unit(self,derived=False):
        return {'schema_version':1,'knowledge_id':'asset-a::logic','parent_asset_id':'asset-a','asset_kind':'logic','name':'Reusable Logic','summary':'Deterministic reusable decision logic','version':'1.0.0','data_class':'derived' if derived else 'canonical','classification':{'languages':['JavaScript'],'runtimes':['Node.js 22+'],'tags':['decision']},'discovery':{'purpose':'Choose a deterministic route','capabilities':['route resolution']},'applicability':{'use_when':['policy is explicit'],'do_not_use_when':['policy is missing']},'contract':{'inputs':['action','policy'],'outputs':['route'],'required_fields':['action','policy'],'side_effects':'none','mutation_authority':False},'constraints':['fail closed'],'composition':{'depends_on':[]},'implementation':{'language':'JavaScript','entrypoint':'source/index.js','symbol':'run'},'cases':[{'case_id':'normal-001','case_type':'normal','scenario':'explicit policy route','input':{'action':'publish'},'expected':{'route':'PUBLISHER'},'result':'PASS'}],'verification':{'status':'verified','verified_at':'2026-10-01T00:00:00Z','normal_test':{'passed':True},'user_test':{'passed':True},'validation_boundary':'fixture only'},'provenance':{'origin':{'repository':'local://fixture','commit':'origin-1'},'catalog':{'repository':'seigo-gace/modular-catalog','commit':self.commit,'asset_id':'asset-a','asset_path':'assets/asset-a'}},'lifecycle':{'status':'active'},'integrity':{'asset_hash':'abc'},'derivation':{'type':'ai-derived','derived_from':['logic.md'],'verified':False} if derived else {'type':'canonical'}}
    def write_bundle(self,units=None):
        (self.bundle/'asset.json').write_text(json.dumps({'schema_version':1,'asset_id':'asset-a','name':'Asset A'}))
        with (self.bundle/'knowledge-units.jsonl').open('w',newline='\n') as h:
            for u in units or [self.unit()]: h.write(json.dumps(u)+'\n')
        files=[]
        for rel in ('asset.json','knowledge-units.jsonl'):
            p=self.bundle/rel; files.append({'path':rel,'size':p.stat().st_size,'sha256':sha(p)})
        (self.bundle/'manifest.json').write_text(json.dumps({'schemaVersion':1,'algorithm':'sha256','files':files}))
    def test_imports(self):
        records,meta,corpus=module.build(self.catalog,'kb-export/asset-a',self.out,1); self.assertEqual(len(records),1); self.assertEqual(records[0].type,'reusable_asset'); self.assertEqual(meta[0]['asset_kind'],'logic'); txt=next(corpus.glob('*.md')).read_text(); self.assertIn('Applicability',txt); self.assertIn('route resolution',txt); self.assertIn('policy is missing',txt); self.assertTrue((self.out/'knowledge-metadata.jsonl').is_file())
    def test_manifest_tamper(self):
        (self.bundle/'asset.json').write_text('{}')
        with self.assertRaisesRegex(RuntimeError,'BUNDLE_MANIFEST_'): module.build(self.catalog,'kb-export/asset-a',self.out,1)
    def test_unverified(self):
        u=self.unit(); u['verification']['status']='experimental'; self.write_bundle([u])
        with self.assertRaisesRegex(RuntimeError,'KNOWLEDGE_UNIT_NOT_VERIFIED'): module.build(self.catalog,'kb-export/asset-a',self.out,1)
    def test_derived_without_source(self):
        u=self.unit(True); u['derivation']['derived_from']=[]; self.write_bundle([u])
        with self.assertRaisesRegex(RuntimeError,'DERIVED_UNIT_SOURCE_MISSING'): module.build(self.catalog,'kb-export/asset-a',self.out,1)
    def test_commit_mismatch(self):
        u=self.unit(); u['provenance']['catalog']['commit']='0'*40; self.write_bundle([u])
        with self.assertRaisesRegex(RuntimeError,'CATALOG_COMMIT_MISMATCH'): module.build(self.catalog,'kb-export/asset-a',self.out,1)
if __name__=='__main__': unittest.main(verbosity=2)
