"""Run offline Lua 5.1 integration tests (Python + lupa==2.6)."""
from pathlib import Path
import sys
import unittest

root = Path(__file__).resolve().parents[1]
result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.discover(str(root / 'tests')))
sys.exit(0 if result.wasSuccessful() else 1)
