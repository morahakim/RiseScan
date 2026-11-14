"""In-memory record of what the server saw for each upload, served read-only by GET /debug/trace (see API.md).

Recording never changes a response. Times are Unix seconds. Part PUTs go straight to storage, so parts show up
only as snapshots of what storage holds, taken whenever the server lists parts (status, re-initiate, start of
complete). A part sent twice appears as the same part_number with a new last_modified.
"""
import copy
import threading
import time

_lock = threading.Lock()
_uploads: dict[str, dict] = {}   # upload_id -> {"upload_id", "scan_id", "kind", ..., "events": [...]}, oldest first


def _now():
    return round(time.time(), 3)


def new_upload(upload_id: str, scan_id: str, kind: str, size_bytes: int, part_size: int, total_parts: int):
    with _lock:
        _uploads[upload_id] = {"upload_id": upload_id, "scan_id": scan_id, "kind": kind, "size_bytes": size_bytes,
                               "part_size": part_size, "total_parts": total_parts, "created_at": _now(), "events": []}


def event(upload_id: str, type_: str, **fields):
    with _lock:
        if upload_id in _uploads:
            _uploads[upload_id]["events"].append({"t": _now(), "type": type_, **fields})


def parts(upload_id: str, source: str, held: list[dict]):
    """Snapshot of the parts storage holds. Stored only when it differs from the previous snapshot."""
    snap = sorted(({k: p[k] for k in ("part_number", "etag", "size", "last_modified")} for p in held),
                  key=lambda p: p["part_number"])
    with _lock:
        u = _uploads.get(upload_id)
        if u is None:
            return
        last = next((e["parts"] for e in reversed(u["events"]) if e["type"] == "parts"), None)
        if snap != last:
            u["events"].append({"t": _now(), "type": "parts", "source": source, "parts": snap})


def dump() -> dict:
    with _lock:
        return {"server_time": _now(), "uploads": copy.deepcopy(list(_uploads.values()))}
