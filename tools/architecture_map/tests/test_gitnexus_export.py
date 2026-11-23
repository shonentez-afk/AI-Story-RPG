import importlib.util
import pathlib
import unittest

SPEC=importlib.util.spec_from_file_location("export",pathlib.Path(__file__).resolve().parents[1]/"gitnexus_export.py")
m=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)

class GitNexusExportTests(unittest.TestCase):
    def test_only_ast_rows_with_grounded_lines(self):
        raw=' GitNexus Cypher\\n{"markdown":"| caller | caller_file | caller_line | callee | callee_file | callee_line | confidence |\\n| --- | --- | --- | --- | --- | --- | --- |\\n| run | packages/core/lib/core.dart | 10 | choose | packages/core/lib/core.dart | 20 | 0.85 |\\n| other | packages/core/lib/core.dart | 30 | rejected | packages/core/lib/core.dart | 40 | 0.3 |","row_count":2}'
        rows,count=m.parse_cli(raw)
        result=m.normalize(rows,count)
        self.assertEqual(result["statistics"]["edges"],1)
        self.assertTrue(result["edges"][0]["evidenceKind"]=="caller_definition")
        self.assertFalse(result["statistics"]["mayBeTruncated"])
    def test_refuse_bogus_results(self):
        with self.assertRaises(ValueError):
            m.parse_cli("not GitNexus")
if __name__=="__main__":
    unittest.main()
