"""Scan upload server: the contract in API.md. State is in memory; file bytes live in S3 (MinIO).

Parts are uploaded by the client straight to storage through presigned URLs; this server plans the parts,
assembles them in `complete` and checks the result with `verify_object` (app/checksum.py).
"""
import logging
import math
import threading
import time
import uuid
from typing import Literal
from uuid import UUID

from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from . import storage, trace
from .checksum import verify_object

PART_SIZE = 5 * 1024 * 1024     # API.md: between 5 MiB (the S3 multipart minimum) and 8 MiB
MAX_PARTS = 10000               # the S3 limit on parts per upload, so size_bytes <= MAX_PARTS * PART_SIZE
DOWNLOAD_EXPIRES = 600          # seconds; API.md: at most 3600

log = logging.getLogger("uvicorn.error")
app = FastAPI(title="Rise Scan Pipeline")
lock = threading.Lock()                         # guards `uploads`, `by_key` and `key_locks`; never held during S3 calls
uploads: dict[str, dict] = {}                   # upload_id -> upload
by_key: dict[tuple[str, str], str] = {}         # (scan_id, kind) -> latest upload_id
key_locks: dict[tuple[str, str], threading.Lock] = {}   # (scan_id, kind) -> serialises POST /uploads for that key


class InitBody(BaseModel):
    scan_id: UUID                               # parsed, so an uppercase and a lowercase UUID name the same scan
    kind: Literal["preview", "original"]
    filename: str = Field(min_length=1)         # informational only: never used
    size_bytes: int = Field(ge=1, le=MAX_PARTS * PART_SIZE, strict=True)   # a JSON integer: not "100", true or 100.0


class PartRef(BaseModel):
    part_number: int = Field(strict=True)
    etag: str


class CompleteBody(BaseModel):
    sha256: str = Field(pattern=r"^[0-9a-fA-F]{64}$")   # hex only: a base64 digest is a 422, never a failed upload
    parts: list[PartRef]


def get(upload_id: str) -> dict:
    """The upload for an id in any usual UUID spelling (iOS `UUID().uuidString` is uppercase), else a 404."""
    try:
        u = uploads.get(str(UUID(upload_id)))
    except ValueError:
        u = None
    if u is None:
        raise HTTPException(404, "unknown upload")
    return u


def numbers_text(nums: list[int]) -> str:
    """[1, 2, 3], or the first 20 and a count: a 10000-part upload must not produce a huge error message."""
    return str(nums) if len(nums) <= 20 else f"{str(nums[:20])[:-1]}, ... ({len(nums)} in all)]"


def parts_list_problem(u: dict, numbers: list[int]) -> str | None:
    """Why the part numbers sent to complete are not exactly 1..total, naming the offending numbers; None if they are."""
    expected, seen, dup = set(range(1, u["total"] + 1)), set(), set()
    for n in numbers:
        (dup if n in seen else seen).add(n)
    problems = [f"{what} {numbers_text(sorted(nums))}" for what, nums in
                (("missing", expected - seen), ("extra", seen - expected), ("duplicated", dup)) if nums]
    if not problems:
        return None
    return f"parts list does not match the {u['total']} part(s) of this upload: " + "; ".join(problems)


def assemble_problem(u: dict, code: str, parts: list) -> str:
    """A readable 400 detail for a parts list storage refused to assemble, naming the part numbers when it can."""
    try:
        held = {p["part_number"]: p for p in storage.list_parts(u["key"], u["s3_id"]) or []}
    except Exception:
        held = {}
    if code == "EntityTooSmall":
        small = [n for n, p in sorted(held.items()) if n < u["total"] and p["size"] < PART_SIZE]
        return ("cannot assemble: a part other than the last is smaller than 5 MiB"
                + (f" (part(s) {numbers_text(small)})" if small else "") + "; resend it in full, then retry complete")
    if code == "InvalidPart":
        wrong = [p.part_number for p in parts
                 if p.part_number not in held or held[p.part_number]["etag"].strip('"') != p.etag.strip('"')]
        return ("cannot assemble: an etag does not match the stored part; resend that part"
                + (f" (part(s) {numbers_text(wrong)})" if wrong else "") + ", then retry complete")
    return f"cannot assemble: {code}"


def snapshot_parts(u: dict, source: str) -> bool:
    """Record what storage holds for the trace. False only if the S3 upload no longer exists; never raises."""
    try:
        held = storage.list_parts(u["key"], u["s3_id"])
    except Exception:
        log.warning("trace: could not list parts of %s", u["id"], exc_info=True)
        return True
    if held is None:
        return False
    trace.parts(u["id"], source, held)
    return True


def expire_if_gone(u: dict) -> bool:
    """After NoSuchUpload: if complete never started and no object exists, S3 expired the upload.
    Mark it failed so the next POST /uploads starts a new one."""
    if u["phase"]:   # complete removes the S3 upload itself when it assembles
        return False
    try:
        if storage.object_exists(u["key"]):
            return False
    except Exception:
        log.warning("could not check whether %s was assembled", u["id"], exc_info=True)
        return False
    with lock:
        if u["status"] == "in_progress" and not u["phase"]:
            u["reason"], u["status"] = "upload_expired", "failed"
    return u["status"] == "failed"


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/uploads")
def initiate(b: InitBody):
    scan_id = str(b.scan_id)
    k = (scan_id, b.kind)
    with lock:
        key_lock = key_locks.setdefault(k, threading.Lock())
    with key_lock:   # one initiate per key at a time, so concurrent calls agree; other keys are not held up by S3
        with lock:
            u = uploads.get(by_key.get(k, ""))
        if u and u["status"] == "in_progress" and not u["phase"]:
            # client restarting: record what it already sent; also checks the S3 upload still exists
            if not snapshot_parts(u, "initiate"):
                expire_if_gone(u)
        if u and u["status"] != "failed":
            created = False
            if u["size"] != b.size_bytes:
                trace.event(u["id"], "initiate", size_bytes=b.size_bytes, http_status=409, new_upload=False)
                raise HTTPException(409, f"size_bytes differs from the {u['status']} upload")
        else:
            key = f"{scan_id}/{b.kind}/{uuid.uuid4()}"
            mp = storage.s3.create_multipart_upload(Bucket=storage.BUCKET, Key=key)
            # phase: None -> "assembling" (complete is assembling) -> "assembled" (S3 upload id gone)
            u, created = {"id": str(uuid.uuid4()), "scan_id": scan_id, "kind": b.kind, "key": key,
                          "s3_id": mp["UploadId"], "total": math.ceil(b.size_bytes / PART_SIZE), "size": b.size_bytes,
                          "status": "in_progress", "phase": None, "parts": [], "lock": threading.Lock()}, True
            trace.new_upload(u["id"], scan_id, b.kind, b.size_bytes, PART_SIZE, u["total"])
            with lock:
                uploads[u["id"]] = u
                by_key[k] = u["id"]
    trace.event(u["id"], "initiate", size_bytes=b.size_bytes, http_status=200, new_upload=created, status=u["status"])
    parts = []
    if u["status"] == "in_progress" and not u["phase"]:   # once complete has the parts, there is nothing left to send
        parts = [{"part_number": n, "url": storage.presign_part(u["key"], u["s3_id"], n)}
                 for n in range(1, u["total"] + 1)]
    return {"upload_id": u["id"], "part_size": PART_SIZE, "parts": parts}


@app.get("/uploads/{upload_id}")
def status(upload_id: str):
    u = get(upload_id)
    done = []
    if u["status"] == "in_progress" and not u["phase"]:
        held = storage.list_parts(u["key"], u["s3_id"])
        if held is not None:
            trace.parts(u["id"], "status", held)
            done = [{"part_number": p["part_number"], "etag": p["etag"], "size": p["size"]} for p in held]
        else:   # a concurrent complete just assembled it (handled below), or S3 expired the upload
            expire_if_gone(u)
    # complete stores the parts before setting the phase, so once the phase is set the list is complete
    if u["status"] == "in_progress" and u["phase"]:
        done = u["parts"]
    trace.event(u["id"], "status", status=u["status"], parts_held=len(done))
    body = {"scan_id": u["scan_id"], "kind": u["kind"], "status": u["status"], "total_parts": u["total"], "parts": done}
    if u["status"] == "failed":
        body["reason"] = u.get("reason")
    return body


@app.post("/uploads/{upload_id}/complete")
def complete(upload_id: str, b: CompleteBody):
    u = get(upload_id)
    started, http_status, result = time.monotonic(), 500, {}
    try:
        result = _complete(u, b)
        http_status = 200
        return result
    except HTTPException as e:
        http_status, result = e.status_code, {"detail": e.detail}
        raise
    finally:
        trace.event(u["id"], "complete", http_status=http_status,
                    duration_s=round(time.monotonic() - started, 3), **result)


def _complete(u: dict, b: CompleteBody) -> dict:
    with u["lock"]:   # a concurrent retry waits here, then returns the stored result
        if u["status"] == "verified":
            return {"status": "verified"}
        if u["status"] == "failed":
            return {"status": "failed", "reason": u.get("reason")}
        problem = parts_list_problem(u, [p.part_number for p in b.parts])
        if problem:
            raise HTTPException(400, problem)
        parts = sorted(b.parts, key=lambda p: p.part_number)
        if u["phase"] != "assembled":   # skipped on a retry after assembly: the S3 upload id no longer exists
            snapshot_parts(u, "complete")
            # parts before phase: status reads the phase first
            u["parts"] = [{"part_number": p.part_number, "etag": p.etag,
                           "size": min(PART_SIZE, u["size"] - (p.part_number - 1) * PART_SIZE)} for p in parts]
            u["phase"] = "assembling"
            try:
                storage.s3.complete_multipart_upload(Bucket=storage.BUCKET, Key=u["key"], UploadId=u["s3_id"],
                                                     MultipartUpload={"Parts": [
                                                         {"PartNumber": p.part_number, "ETag": p.etag} for p in parts]})
            except ClientError as e:
                code = storage.error_code(e)
                # NoSuchUpload with the object present means assembled earlier (response lost): carry on
                if code == "NoSuchUpload" and not storage.object_exists(u["key"]):
                    u["phase"] = None   # S3 expired (or aborted) the multipart upload: start over
                    u["reason"], u["status"] = "upload_expired", "failed"
                    return {"status": "failed", "reason": "upload_expired"}
                if code != "NoSuchUpload":
                    u["phase"] = None   # parts list doesn't match storage: status asks S3 again
                    raise HTTPException(400, assemble_problem(u, code, parts))
            u["phase"] = "assembled"

        # if this raises, the upload stays in_progress + assembled, so a retry verifies again
        try:
            reason = verify_object(storage.s3, storage.BUCKET, u["key"], b.sha256.lower(), u["size"])
        except NotImplementedError:
            raise HTTPException(501, "checksum verification is not implemented yet: "
                                     "implement verify_object in backend/app/checksum.py")
        except Exception as e:
            log.exception("verify_object failed for upload %s", u["id"])   # traceback: docker compose logs backend
            error = f"{type(e).__name__}: {e}" if str(e) else type(e).__name__
            raise HTTPException(500, f"checksum verification did not finish ({error[:200]}); retry complete")

        if reason is not None:   # anything but None is a failure
            if not (isinstance(reason, str) and reason):
                log.warning("verify_object returned %s %.100r for upload %s; it must return None or a non-empty str",
                            type(reason).__name__, reason, u["id"])
                reason = "verify_object_bad_return"
            u["status"], u["reason"] = "failed", reason
            try:
                storage.s3.delete_object(Bucket=storage.BUCKET, Key=u["key"])
            except Exception:
                pass   # never downloadable anyway: status is failed
            return {"status": "failed", "reason": reason}
        u["status"] = "verified"
        return {"status": "verified"}


@app.get("/uploads/{upload_id}/download")
def download(upload_id: str):
    u = get(upload_id)
    if u["status"] != "verified":
        trace.event(u["id"], "download", http_status=409)
        raise HTTPException(409, "not verified")
    trace.event(u["id"], "download", http_status=200)
    return {"url": storage.presign_download(u["key"], DOWNLOAD_EXPIRES), "expires_in": DOWNLOAD_EXPIRES}


@app.get("/scans/{scan_id}")
def scan(scan_id: UUID):   # parsed like POST /uploads: case-insensitive, 422 if not a UUID
    scan_id = str(scan_id)
    st = lambda kind: uploads[by_key[(scan_id, kind)]]["status"] if (scan_id, kind) in by_key else None
    return {"preview": st("preview"), "original": st("original")}


@app.get("/debug/trace")
def debug_trace():
    """Read-only record of the calls seen per upload, oldest upload first (API.md, Debug)."""
    return trace.dump()
