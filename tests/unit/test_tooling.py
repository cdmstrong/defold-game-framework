"""Guard dependency reproducibility: stale pins must block a build."""
import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('project', pathlib.Path(__file__).resolve().parents[2]/'scripts/project.py')
project = importlib.util.module_from_spec(spec)
spec.loader.exec_module(project)

class DependencyChecks(unittest.TestCase):
    def test_changed_commit_blocks_build_and_sync_preserves_other_settings(self):
        original_root = project.ROOT
        with tempfile.TemporaryDirectory() as directory:
            try:
                project.ROOT = pathlib.Path(directory)
                p = project.ROOT/'game.project'
                p.write_text('[project]\ntitle = Test\ndependencies#0 = stale.zip\n\n[display]\nwidth = 960\n')
                with self.assertRaises(RuntimeError): project.dependencies()
                project.dependencies(write=True)
                project.dependencies()
                self.assertIn('width = 960',p.read_text())
                self.assertIn('title = Test',p.read_text())
                first=p.read_text()
                project.dependencies(write=True)
                self.assertEqual(first,p.read_text())
            finally: project.ROOT = original_root
