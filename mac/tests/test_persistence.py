#!/usr/bin/env python3
"""Real save-port regression tests; only disposable generated fixture files."""
import os
import errno
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PORT_SOURCE = Path(os.environ.get("PERSIST_PORT_SOURCE", ROOT / "sim/persist_port_sim.c"))
FIXTURES = Path(__file__).resolve().parent / "fixtures"
PAYLOAD = bytes((i * 37 + 11) % 256 for i in range(1688))


class PersistenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="pocket-tank-persist-build-")
        build = Path(cls.build.name)
        flags = ["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT / "common")]
        subprocess.run(flags + ["-include", str(FIXTURES / "persist_fault.h"), "-c",
                               str(PORT_SOURCE), "-o", str(build / "port.o")], check=True)
        cls.runner = build / "persist-fixture"
        subprocess.run(flags + [str(FIXTURES / "persist_fixture.c"), str(build / "port.o"),
                               "-o", str(cls.runner)], check=True)
        cls.progression_runner = build / "progression-fixture"
        subprocess.run(flags + [str(FIXTURES / "progression_fixture.c"),
                               str(PORT_SOURCE),
                               str(ROOT / "common/progression.c"), str(ROOT / "common/tank.c"),
                               "-lm", "-o", str(cls.progression_runner)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix="pocket-tank-persist-save-")
        self.addCleanup(self.fixture.cleanup)
        self.save = Path(self.fixture.name) / "nested/tank.sav"
        self.save.parent.mkdir()
        self.previous = bytes((i * 13 + 7) % 256 for i in range(1688))
        self.save.write_bytes(self.previous)

    def run_port(self, operation, fault=None):
        env = dict(os.environ, POCKET_TANK_SAVE=str(self.save))
        env.pop("AUDIT_WRITE_FAULT", None)
        if fault:
            env["AUDIT_WRITE_FAULT"] = fault
        return subprocess.run([str(self.runner), operation], env=env, text=True, capture_output=True)

    def test_failed_writes_preserve_previous_snapshot_and_remove_temporary_files(self):
        for fault in ("short", "flush", "sync", "close", "replace"):
            with self.subTest(fault=fault):
                self.save.write_bytes(self.previous)
                result = self.run_port("save", fault)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertEqual(self.save.read_bytes(), self.previous)
                self.assertEqual(list(self.save.parent.iterdir()), [self.save])
                expected = {"short": errno.ENOSPC, "flush": errno.ENOSPC, "sync": errno.EIO,
                            "close": errno.EIO, "replace": errno.EACCES}[fault]
                self.assertIn(f"errno={expected}", result.stdout)

    def test_interrupted_process_keeps_previous_snapshot(self):
        result = self.run_port("save", "interrupt")
        self.assertEqual(result.returncode, 77)
        self.assertEqual(self.save.read_bytes(), self.previous)
        # Abrupt process death can leave its private temp file; it must never replace the save.

    def test_successful_atomic_replacement_and_roundtrip(self):
        self.assertEqual(self.run_port("save").returncode, 0)
        self.assertEqual(self.save.read_bytes(), PAYLOAD)
        self.assertEqual(list(self.save.parent.iterdir()), [self.save])
        result = self.run_port("load")
        self.assertEqual(result.returncode, 0)
        self.assertIn("bytes=1688 equal=1", result.stdout)

    def test_real_replacement_failure_preserves_directory_and_cleans_temp(self):
        self.save.unlink()
        self.save.mkdir()
        result = self.run_port("save")
        self.assertEqual(result.returncode, 1)
        self.assertTrue(self.save.is_dir())
        self.assertEqual(list(self.save.parent.iterdir()), [self.save])

    def test_save_destination_symlink_does_not_overwrite_its_target(self):
        target = Path(self.fixture.name) / "unrelated.txt"
        target.write_bytes(b"unrelated fixture")
        self.save.unlink()
        self.save.symlink_to(target)
        self.assertEqual(self.run_port("save").returncode, 0)
        self.assertFalse(self.save.is_symlink())
        self.assertEqual(self.save.read_bytes(), PAYLOAD)
        self.assertEqual(target.read_bytes(), b"unrelated fixture")

    def test_missing_and_empty_load(self):
        self.save.unlink()
        self.assertEqual(self.run_port("load").returncode, 1)
        self.save.touch()
        self.assertEqual(self.run_port("load").returncode, 1)

    def test_load_is_bounded_and_does_not_rewrite_corrupt_bytes(self):
        corrupt = b"not a progression save" * 200
        self.save.write_bytes(corrupt)
        result = self.run_port("load")
        self.assertIn("bytes=1688 equal=0", result.stdout)
        self.assertEqual(self.save.read_bytes(), corrupt)

    def run_progression(self, operation):
        return subprocess.run([str(self.progression_runner), operation],
                              env=dict(os.environ, POCKET_TANK_SAVE=str(self.save)),
                              text=True, capture_output=True)

    def test_real_progression_format_roundtrip_and_corrupt_fallback(self):
        self.assertEqual(self.run_progression("save").returncode, 0)
        valid = self.save.read_bytes()
        self.assertEqual(len(valid), 1688)
        restored = self.run_progression("load")
        self.assertEqual(restored.returncode, 0)
        self.assertIn("name=ruby", restored.stdout)
        for corrupt in (b"", valid[:100], b"BAD!" + valid[4:], valid[:23] + b"\xff" + valid[24:]):
            with self.subTest(length=len(corrupt)):
                self.save.write_bytes(corrupt)
                result = self.run_progression("load")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("name=ruby", result.stdout)
        self.save.unlink()
        self.assertEqual(self.run_progression("load").returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
