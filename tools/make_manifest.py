"""Write sample_scan/manifest.json (SHA-256 + size of every file, OBJ vertex/face record counts)."""
import hashlib, json, sys
from pathlib import Path

scan = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "sample_scan")
files = sorted(p for p in scan.iterdir() if p.is_file() and p.name != "manifest.json" and not p.name.startswith("."))   # skips .gitkeep, .DS_Store
manifest = {"files": {p.name: {"sha256": hashlib.sha256(p.read_bytes()).hexdigest(), "bytes": p.stat().st_size} for p in files}}
for p in files:
    if p.suffix.lower() == ".obj":
        v = f = 0
        with p.open("rb") as fh:
            for line in fh:
                if line.startswith(b"v "): v += 1
                elif line.startswith(b"f "): f += 1
        manifest["obj_vertex_records"], manifest["obj_face_records"] = v, f
(scan / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
