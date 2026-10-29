#!/usr/bin/env python3
"""Pin a real local signing identity; never silently fall back to ad-hoc signing."""
import os
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[2]
saved = root / 'local-build/.signing-identity'
output = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
identities = dict(re.findall(r'\d+\) ([0-9A-F]{40}) "([^"]+)"', output))
requested = os.environ.get('SIGN_IDENTITY')
if not requested and saved.exists():
    requested = saved.read_text().strip()
if requested:
    matches = [key for key, name in identities.items() if requested in (key, name)]
else:
    matches = [key for key, name in identities.items()
               if name.startswith(('Apple Development:', 'Developer ID Application:'))]
if len(matches) != 1:
    raise SystemExit('Set SIGN_IDENTITY to one valid certificate name or SHA-1. '
                     'The saved identity must remain available; ad-hoc fallback is disabled.')
saved.parent.mkdir(parents=True, exist_ok=True)
saved.write_text(matches[0] + '\n')
print(matches[0])
