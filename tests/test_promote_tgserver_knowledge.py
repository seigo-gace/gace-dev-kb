import copy
from dataclasses import asdict
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
from promote_tgserver_knowledge import promote
from render_knowledge_corpus import write_corpus
from gace_knowledge_adapter import write_jsonl

class AdmissionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name)/'repo'
        self.repo.mkdir()
        self.git('init')
        self.git('config','user.email','test@example.invalid')
        self.git('config','user.name','test fixture')
        self.git('remote','add','origin','https://github.com/fixture/project.git')
        (self.repo/'test.py').write_text('assert True\n')
        self.git('add','test.py'); self.git('commit','-m','test: evidence fixture')
        self.sha = self.git('rev-parse','HEAD').strip()
        self.event = {'schema':'gace.development.event.v1','event_id':'candidate-1','event_type':'KNOWLEDGE_CANDIDATE',
            'source_surface':'codex','source_instance':'generic-hmac-sha256:devlog','session_id':'session-1',
            'turn_id':None,'change_unit_id':None,'summary':'explicit reusable candidate',
            'project':{'repository':'fixture/project','stream':'default'},'occurred_at':'2026-10-01T00:00:00Z',
            'ingested_at':'2026-10-05T00:00:00Z','privacy':{'redacted':True,'contains_internal_reasoning':False},
            'details':{'knowledge':{'type':'fix','commit':self.sha,'summary':'reuse candidate','cause':'observed cause',
                'fix':'explicit fix','validation':'verified test execution','reuse_scope':'second project'}},
            'evidence':[{'kind':'git','ref':f'git:fixture/project@{self.sha}','state':'OBSERVED'},
                {'kind':'test','ref':f'git:fixture/project@{self.sha}:test.py','state':'OBSERVED'}]}
        self.hit = {'message':json.dumps(self.event),'telegram_message_ids':[42],
            'event_timestamp':self.event['occurred_at'],'ingested_at':self.event['ingested_at']}
        self.ci = {'head_sha':self.sha,'head_repository':{'full_name':'fixture/project'},'status':'completed','conclusion':'success','html_url':'https://github.com/fixture/project/actions/runs/1'}
    def tearDown(self): self.temp.cleanup()
    def git(self,*args):
        return subprocess.run(['git','-C',str(self.repo),*args],capture_output=True,text=True,check=True).stdout
    def test_admission_reuses_existing_record_renderer_with_provenance(self):
        record = promote(self.hit,self.repo,self.ci)
        self.assertEqual(record.repository,'fixture/project')
        self.assertIn('tgserver:candidate-1',record.source)
        self.assertIn(self.sha,record.source)
        output = Path(self.temp.name)/'records.jsonl'
        write_jsonl([record],output)
        corpus = Path(self.temp.name)/'corpus'
        self.assertEqual(write_corpus([asdict(record)],corpus),1)
        content = next(corpus.glob('*.md')).read_text()
        self.assertIn('observed cause',content)
        self.assertIn('second project',content)
    def test_rejects_raw_logs_missing_correlation_ci_or_committed_test(self):
        variants = []
        for key,value in [('event_type','FAILED'),('details',{}),('privacy',{'redacted':False,'contains_internal_reasoning':False})]:
            event=copy.deepcopy(self.event); event[key]=value
            variants.append({**self.hit,'message':json.dumps(event)})
        variants.append({**self.hit,'telegram_message_ids':[]})
        event=copy.deepcopy(self.event); event['evidence'][1]['ref']=f'git:fixture/project@{self.sha}:missing.py'
        variants.append({**self.hit,'message':json.dumps(event)})
        for hit in variants:
            with self.assertRaises(Exception): promote(hit,self.repo,self.ci)
        for ci in [{**self.ci,'conclusion':'failure'},{**self.ci,'head_sha':'0'*40},{**self.ci,'head_repository':{'full_name':'other/repo'}}]:
            with self.assertRaises(ValueError): promote(self.hit,self.repo,ci)
    def test_secret_bearing_candidate_never_becomes_knowledge(self):
        event=copy.deepcopy(self.event); event['details']['password']='synthetic-private-value'
        with self.assertRaisesRegex(ValueError,'PRIVACY_GATE_FAILED'):
            promote({**self.hit,'message':json.dumps(event)},self.repo,self.ci)

if __name__=='__main__': unittest.main()
