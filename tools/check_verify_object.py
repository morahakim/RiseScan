"""Self-check for your verify_object (backend/app/checksum.py), against the storage of the running compose stack.

    docker compose up -d
    cd backend && uv run python ../tools/check_verify_object.py     

Puts a few small objects in the bucket, calls your function on each, prints one line per case, then deletes them.
Basics only: it does not show that a ~1 GiB object works (see tools/large_object_check.py). Defaults come from
.env.example; override with MINIO_ROOT_USER, MINIO_ROOT_PASSWORD, S3_BUCKET or STORAGE_URL.
"""
import hashlib, os, sys, uuid
from pathlib import Path

import boto3
from botocore.client import Config

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from app.checksum import verify_object  # noqa: E402  (your file)

url = os.environ.get("STORAGE_URL", "http://localhost:9000")
bucket = os.environ.get("S3_BUCKET", "scans")
user, password = os.environ.get("MINIO_ROOT_USER", "minioadmin"), os.environ.get("MINIO_ROOT_PASSWORD", "minioadmin")
path_style = Config(s3={"addressing_style": "path"})
s3 = boto3.client("s3", endpoint_url=url, region_name="ap-south-1", aws_access_key_id=user,
                  aws_secret_access_key=password, config=path_style)
folder = f"self-check-{uuid.uuid4()}/"
body = os.urandom(64 * 1024)
digest = hashlib.sha256(body).hexdigest()
flipped = bytearray(body)
flipped[1000] ^= 1
failures = []


def describe(value):
    if value is None:
        return "None"
    if isinstance(value, str) and value:
        return f"the reason {value!r}"
    return f"{value!r} ({'an empty string' if value == '' else type(value).__name__})"


def case(name, key, sha, size, want_none):
    """Call verify_object once; want_none: the object matches, so it must return exactly None."""
    expected = "None" if want_none else "a non-empty string (the failure reason)"
    try:
        got = verify_object(s3, bucket, key, sha, size)
    except NotImplementedError:
        sys.exit("FAIL  verify_object is not implemented yet (it raises NotImplementedError)")
    except Exception as e:
        problem = f"raised {type(e).__name__}: {e}, expected {expected}"
    else:
        if not (got is None or (isinstance(got, str) and len(got) > 0)):
            problem = f"returned {describe(got)}; only None or a non-empty string are allowed"
        elif (got is None) != want_none:
            problem = f"returned {describe(got)}, expected {expected}"
        else:
            return print(f"ok    {name}: returned {describe(got)}")
    failures.append(name)
    print(f"FAIL  {name}: {problem}")


try:
    s3.put_object(Bucket=bucket, Key=folder + "a", Body=body)
    s3.put_object(Bucket=bucket, Key=folder + "b", Body=bytes(flipped))
except Exception as e:
    sys.exit(f"cannot put test objects into bucket {bucket!r} at {url} ({type(e).__name__}: {e}); "
             "is `docker compose up` running?")
try:
    n = len(body)
    case("object matches", folder + "a", digest, n, True)
    case("digest differs in its last hex character", folder + "a", digest[:-1] + ("0" if digest[-1] != "0" else "1"),
         n, False)
    case("one byte of the object changed", folder + "b", digest, n, False)
    case("declared size one byte larger", folder + "a", digest, n + 1, False)
    case("declared size one byte smaller", folder + "a", digest, n - 1, False)
    try:
        got = verify_object(s3, bucket, folder + "missing", digest, n)
        failures.append("missing object")
        print(f"FAIL  missing object: returned {describe(got)}; it should raise (let the storage error propagate)")
    except NotImplementedError:
        sys.exit("FAIL  verify_object is not implemented yet (it raises NotImplementedError)")
    except Exception as e:
        print(f"ok    missing object: raised {type(e).__name__}")
finally:
    for name in ("a", "b"):
        s3.delete_object(Bucket=bucket, Key=folder + name)

rebuild = ("This checked backend/app/checksum.py on disk. The running server only uses your latest edit after "
           "`docker compose up -d --build`.")
if failures:
    sys.exit(f"Result: {len(failures)} of 6 checks failed\n{rebuild}")
print("Result: all 6 basic checks passed (large objects are not covered here: stream them, about 1 GiB with 512 MiB of RAM;"
      " tools/large_object_check.py tries one)")
print(rebuild)
