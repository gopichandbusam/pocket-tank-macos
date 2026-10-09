#!/usr/bin/env python3
"""Compile/test canonical advisor thread against a deterministic model stub."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='pocket-mailbox-') as directory:
 exe=Path(directory)/'mailbox'
 subprocess.run(['cc','-O2','-std=c11','-pthread','-I'+str(root/'common'),'-I'+str(root/'common/llm'),str(Path(__file__).with_suffix('.c')),'-o',str(exe)],check=True)
 for case in ["unread", "removed-inflight", "reindexed-inflight", "removed-completed"]:
  subprocess.run([str(exe), case],check=True)
