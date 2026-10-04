import hashlib
import hmac
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import devlog_producer as producer


def event():
    return {'schema': producer.SCHEMA, 'event_id': 'event-1', 'occurred_at': '2026-10-01T00:00:00Z',
        'source_surface': 'codex', 'source_instance': 'generic-hmac-sha256:devlog', 'session_id': 'session-1',
        'turn_id': None, 'change_unit_id': None, 'project': {'repository': 'seigo-gace/TGserver', 'stream': 'default'},
        'event_type': 'FAILED', 'severity': 'info', 'summary': 'observable result', 'details': {}, 'evidence': [],
        'privacy': {'redacted': True, 'contains_internal_reasoning': False}}


class ProducerTest(unittest.TestCase):
    def test_immutable_redacted_checkpoint_and_restart(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'outbox.db'
            database = producer.open_outbox(path)
            value = os.urandom(32).hex()
            candidate = {**event(), 'details': {'password': value, 'text': 'Bearer '+value}}
            producer.enqueue(database, candidate)
            payload = database.execute('SELECT payload FROM devlog_outbox').fetchone()[0]
            self.assertNotIn(value, payload)
            with self.assertRaisesRegex(ValueError, 'EVENT_ID_CONFLICT'):
                producer.enqueue(database, {**event(), 'summary': 'altered retry'})
            self.assertEqual(database.execute('SELECT count(*) FROM devlog_outbox').fetchone()[0], 1)
            database.close()
            database = producer.open_outbox(path)
            self.assertEqual(database.execute('SELECT payload FROM devlog_outbox').fetchone()[0], payload)
            self.assertEqual(database.execute('SELECT gateway_accepted FROM devlog_outbox').fetchone()[0], 0)
            database.close()

    def test_gateway_failure_retains_identical_event_and_valid_signature(self):
        key = os.urandom(32).hex()
        requests = []
        mode = [503]
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_POST(self):
                body = self.rfile.read(int(self.headers['content-length']))
                timestamp = self.headers['x-timestamp']
                expected = hmac.new(key.encode(), timestamp.encode()+b'.'+body, hashlib.sha256).hexdigest()
                if self.headers['x-signature'] != 'sha256='+expected:
                    self.send_error(401); return
                requests.append((self.headers['x-event-id'], body))
                self.send_response(mode[0]); self.end_headers()
                self.wfile.write(json.dumps({'ok': True, 'eventId': 'durable-test-id'}).encode())
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                database = producer.open_outbox(Path(tmp)/'outbox.db')
                producer.enqueue(database, event())
                url = f'http://127.0.0.1:{server.server_port}/ingress/devlog'
                with self.assertRaises(Exception): producer.flush(database, url, key)
                self.assertEqual(database.execute('SELECT gateway_accepted FROM devlog_outbox').fetchone()[0], 0)
                database.close()
                database = producer.open_outbox(Path(tmp)/'outbox.db')
                mode[0] = 202
                self.assertEqual(producer.flush(database, url, key), 1)
                self.assertEqual(producer.flush(database, url, key), 0)
                self.assertEqual(requests[0], requests[1])
                self.assertEqual(json.loads(requests[0][1])['occurred_at'], event()['occurred_at'])
                database.close()
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_no_reasoning_or_producer_ingested_time(self):
        with tempfile.TemporaryDirectory() as tmp:
            database = producer.open_outbox(Path(tmp)/'outbox.db')
            for candidate in [{**event(), 'details': {'analysis': 'excluded'}}, {**event(), 'ingested_at': 'spoofed'}]:
                with self.assertRaises(ValueError): producer.enqueue(database, candidate)
            self.assertEqual(database.execute('SELECT count(*) FROM devlog_outbox').fetchone()[0], 0)
            database.close()

if __name__ == '__main__': unittest.main()
