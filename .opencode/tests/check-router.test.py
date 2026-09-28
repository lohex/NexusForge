import importlib.util
import io
import unittest
from pathlib import Path
from unittest.mock import patch
import urllib.error

module_path = Path(__file__).resolve().parents[2] / 'serving/check_router.py'
spec = importlib.util.spec_from_file_location('check_router', module_path)
router = importlib.util.module_from_spec(spec)
spec.loader.exec_module(router)

class Response:
    def __init__(self, value): self.value = value
    def __enter__(self): return io.BytesIO(self.value.encode())
    def __exit__(self, *args): return False

class RouterCheckTest(unittest.TestCase):
    def test_bonsai_preset_contains_all_seven_models(self):
        binary, ids = router.expected('bonsai')
        self.assertEqual(len(ids), 7)
        self.assertIn('bonsai-2-27b-ternary', ids)
        self.assertEqual(binary.name, 'llama-server')

    def test_standard_preset_has_six_models(self):
        _, ids = router.expected('standard')
        self.assertEqual(len(ids), 6)
        self.assertNotIn('bonsai-2-27b-ternary', ids)

    def test_matching_runtime_accepted(self):
        binary, ids = router.expected('bonsai')
        import json
        data = {'data': [{'id': name, 'status': {'args': [str(binary)]}} for name in ids]}
        with patch.object(router.urllib.request, 'urlopen', return_value=Response(json.dumps(data))):
            self.assertEqual(router.check('bonsai'), 0)

    def test_other_runtime_rejected(self):
        binary, ids = router.expected('bonsai')
        import json
        data = {'data': [{'id': name, 'status': {'args': [str(binary)]}} for name in ids]}
        data['data'][0]['status']['args'][0] = '/tmp/other/llama-server'
        with patch.object(router.urllib.request, 'urlopen', return_value=Response(json.dumps(data))):
            self.assertEqual(router.check('bonsai'), 11)

    def test_missing_model_rejected(self):
        with patch.object(router.urllib.request, 'urlopen', return_value=Response('{"data": []}')):
            self.assertEqual(router.check('bonsai'), 11)

    def test_connection_refused_requests_start(self):
        error = urllib.error.URLError(ConnectionRefusedError(111, 'refused'))
        with patch.object(router.urllib.request, 'urlopen', side_effect=error):
            self.assertEqual(router.check('bonsai'), 10)

if __name__ == '__main__': unittest.main()
