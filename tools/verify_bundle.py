"""Check that a downloaded scan bundle (.zip) contains files byte-identical to sample_scan/manifest.json.

Usage: python tools/verify_bundle.py downloaded.zip
"""
import hashlib, json, sys, zipfile, zlib
from pathlib import Path

if len(sys.argv) != 2:
    sys.exit("usage: python tools/verify_bundle.py downloaded.zip")
manifest = json.loads((Path(__file__).resolve().parent.parent / "sample_scan" / "manifest.json").read_text())["files"]
ok = True
try:
    bundle = zipfile.ZipFile(sys.argv[1])
except (OSError, zipfile.BadZipFile) as e:
    sys.exit(f"CORRUPT  cannot open {sys.argv[1]} as a zip file: {e}")
with bundle as z:
    # ignore folders and macOS clutter (__MACOSX/, .DS_Store)
    entries = [n for n in z.namelist() if not n.endswith("/") and "__MACOSX" not in Path(n).parts and Path(n).name != ".DS_Store"]
    names = {}
    for n in entries:
        if Path(n).name in names:
            print(f"DUPLICATE {Path(n).name}: {names[Path(n).name]} and {n}"); ok = False
        names.setdefault(Path(n).name, n)
    for n in sorted(set(names) - set(manifest)):
        print(f"WARNING  extra file {names[n]}")
    for name, meta in manifest.items():
        if name not in names:
            print(f"MISSING  {name}"); ok = False; continue
        try:
            good = hashlib.sha256(z.read(names[name])).hexdigest() == meta["sha256"]
        except (zipfile.BadZipFile, zlib.error, EOFError, NotImplementedError, RuntimeError) as e:   # damaged entry
            print(f"CORRUPT  {name} ({type(e).__name__}: {e})"); ok = False; continue
        print(("OK       " if good else "MISMATCH ") + name); ok &= good
sys.exit(0 if ok else 1)
