"""Try your verify_object on a very large object (1 GiB) through the running server, under the judged limits.

    docker compose -f docker-compose.yml -f docker-compose.strict.yml up -d --build
    python tools/large_object_check.py

Uploads 1 GiB of zero bytes twice, each under a new scan_id, like a client would (POST /uploads, PUT per part,
then complete with the SHA-256):
  1. bytes as declared: complete must return "verified";
  2. one byte of the last part changed: complete must return "failed".
Standard library only, takes a few minutes. Server: BACKEND_URL (default http://localhost:$BACKEND_PORT or :8000).
The verified object stays in storage (the API has no delete): with boto3 importable
(`cd backend && uv run python ../tools/large_object_check.py`) the script deletes it, otherwise
`docker compose down -v` frees the space.
"""
import hashlib, http.client, json, os, sys, time, urllib.error, urllib.parse, urllib.request, uuid

OBJECT_BYTES = 1 << 30
port = os.environ.get("BACKEND_PORT", "8000")
server = os.environ.get("BACKEND_URL", f"http://localhost:{port}").rstrip("/")

MEMORY_HINT = ("the server process died while it checked the object: most likely killed for running out of memory "
               "(512 MiB under docker-compose.strict.yml). Read the object in chunks and feed each chunk to the hash; "
               "never hold the whole body.")
DISK_HINT = ("no space left on device: the object was written to disk (the writable /tmp is 64 MiB under "
             "docker-compose.strict.yml). Hash the chunks as they arrive instead of saving the object first.")


def call(method, path, body=None, timeout=60):
    """(HTTP status, parsed JSON or text) for one request to the server."""
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(server + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"} if data else {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status, raw = resp.status, resp.read()
    except urllib.error.HTTPError as e:
        status, raw = e.code, e.read()
    try:
        return status, json.loads(raw)
    except ValueError:
        return status, raw.decode(errors="replace")


class Storage:
    """One kept-alive connection to the storage host the part URLs point at."""
    def __init__(self):
        self.conn, self.netloc = None, None

    def put(self, url, payload):
        u = urllib.parse.urlsplit(url)
        if self.conn is None or self.netloc != u.netloc:
            cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
            self.conn, self.netloc = cls(u.netloc, timeout=300), u.netloc
        try:
            self.conn.request("PUT", f"{u.path}?{u.query}", body=payload)
            resp = self.conn.getresponse()
            text = resp.read()
        except (OSError, http.client.HTTPException):
            self.conn = None
            raise
        if resp.status != 200:
            raise RuntimeError(f"storage refused a part: HTTP {resp.status} {text[:200]!r}")
        return resp.getheader("ETag")


def server_restarted(upload_id):
    """After a dropped connection: wait for the server, then see whether it still knows the upload."""
    for _ in range(90):
        try:
            if call("GET", "/health", timeout=5)[0] == 200:
                return call("GET", f"/uploads/{upload_id}")[0] == 404
        except OSError:
            pass
        time.sleep(1)
    return True


def run(title, change_a_byte, want):
    print(f"\n{title}")
    scan_id = str(uuid.uuid4())
    status, init = call("POST", "/uploads", {"scan_id": scan_id, "kind": "original",
                                             "filename": "large-object-check.bin", "size_bytes": OBJECT_BYTES})
    if status != 200:
        return False, f"POST /uploads returned {status}: {str(init)[:300]}", None
    upload_id, part_size, plan = init["upload_id"], init["part_size"], init["parts"]
    zeros, digest, etags, storage, started = bytes(part_size), hashlib.sha256(), [], Storage(), time.monotonic()
    for entry in plan:
        number = entry["part_number"]
        length = min(part_size, OBJECT_BYTES - (number - 1) * part_size)
        payload = zeros[:length]
        digest.update(payload)   # what the client declares: the SHA-256 of the zero bytes
        if change_a_byte and number == len(plan):
            changed = bytearray(payload)
            changed[length // 2] = 0x2A
            payload = bytes(changed)
        etags.append({"part_number": number, "etag": storage.put(entry["url"], payload)})
        if number % 50 == 0 or number == len(plan):
            print(f"  sent part {number} of {len(plan)} ({time.monotonic() - started:.0f} s)", flush=True)
    print("  complete (the server now reads the whole object) ...", flush=True)
    started = time.monotonic()
    try:
        status, result = call("POST", f"/uploads/{upload_id}/complete",
                              {"sha256": digest.hexdigest(), "parts": etags}, timeout=900)
    except (OSError, http.client.HTTPException) as e:
        took = time.monotonic() - started
        if server_restarted(upload_id):
            return False, f"no reply after {took:.0f} s ({type(e).__name__}) and the server restarted: {MEMORY_HINT}", None
        return False, f"no reply after {took:.0f} s ({type(e).__name__}: {e})", None
    took = time.monotonic() - started
    detail = result.get("detail", result) if isinstance(result, dict) else result
    if status == 501:
        return False, ("complete returned 501: the running server still has the unimplemented stub. Rebuild after "
                       "editing: docker compose -f docker-compose.yml -f docker-compose.strict.yml up -d --build"), None
    if status == 500:
        text = str(detail)
        hint = (DISK_HINT if "No space left" in text or "Errno 28" in text else
                MEMORY_HINT if "MemoryError" in text else
                "verify_object raised an error; docker compose logs backend shows the traceback.")
        return False, f"complete returned 500 after {took:.0f} s: {text[:300]}\n  hint: {hint}", None
    if status in (502, 503, 504) or (status == 404 and server_restarted(upload_id)):
        return False, f"complete returned {status} after {took:.0f} s: {MEMORY_HINT}", None
    if status != 200 or not isinstance(result, dict):
        return False, f"complete returned {status} after {took:.0f} s: {str(detail)[:300]}", None
    got = result.get("status")
    kept = upload_id if got == "verified" else None   # a verified object stays in storage
    if got != want:
        extra = f" (reason {result.get('reason')!r})" if result.get("reason") else ""
        return False, f"complete returned {got!r}{extra} after {took:.0f} s; expected {want!r}", kept
    return True, f"complete returned {got!r} after {took:.0f} s, as expected", kept


def remove(upload_id):
    """Delete the verified object this script made, if boto3 is available; else say how to free the space."""
    status, link = call("GET", f"/uploads/{upload_id}/download")
    if status != 200:
        return
    try:
        import boto3
        from botocore.client import Config
    except ImportError:
        print("  (the verified 1 GiB object stays in storage; `docker compose down -v` frees it)")
        return
    u = urllib.parse.urlsplit(link["url"])
    bucket, key = urllib.parse.unquote(u.path).lstrip("/").split("/", 1)
    login = {"aws_access_key_id": os.environ.get("MINIO_ROOT_USER") or "minioadmin",   # .env.example defaults
             "aws_secret_access_key": os.environ.get("MINIO_ROOT_PASSWORD") or "minioadmin"}
    client = boto3.client("s3", endpoint_url=f"{u.scheme}://{u.netloc}", region_name="ap-south-1",
                          config=Config(s3={"addressing_style": "path"}), **login)
    try:
        client.delete_object(Bucket=bucket, Key=key)
        print(f"  deleted the verified test object {key}")
    except Exception as e:
        print(f"  could not delete the test object {key} ({type(e).__name__}); `docker compose down -v` frees it")


def main():
    try:
        call("GET", "/health", timeout=5)
    except OSError as e:
        sys.exit(f"cannot reach the server at {server} ({e}); start the stack first (see README.md, Helpers)")
    print(f"Server {server}: 1 GiB checks (these only mean something under docker-compose.strict.yml)")
    outcomes = []
    for title, change, want in (("1/2 a 1 GiB object as declared", False, "verified"),
                                ("2/2 a 1 GiB object with one byte of its last part changed", True, "failed")):
        try:
            ok, message, upload_id = run(title, change, want)
        except (OSError, RuntimeError, http.client.HTTPException) as e:
            ok, message, upload_id = False, f"could not send the object: {type(e).__name__}: {e}", None
        print(f"  {'ok  ' if ok else 'FAIL'} {message}")
        outcomes.append(ok)
        if upload_id:
            remove(upload_id)
    if all(outcomes):
        print("\nResult: both 1 GiB checks passed")
    else:
        print("(an object whose check did not finish stays in storage; `docker compose down -v` frees the space)")
        sys.exit(f"\nResult: {outcomes.count(False)} of 2 checks failed")


if __name__ == "__main__":
    main()
