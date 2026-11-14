"""Server-side check of an assembled upload."""
import hashlib


def verify_object(
    s3,
    bucket: str,
    key: str,
    expected_sha256: str,
    expected_size: int,
) -> str | None:
    """Verify an S3 object using bounded-memory streaming."""

    response = s3.get_object(Bucket=bucket, Key=key)
    body = response["Body"]

    sha256 = hashlib.sha256()
    actual_size = 0

    try:
        for chunk in body.iter_chunks(chunk_size=8 * 1024 * 1024):
            if not chunk:
                continue

            actual_size += len(chunk)
            sha256.update(chunk)
    finally:
        body.close()

    if actual_size != expected_size:
        return "checksum_mismatch"

    if sha256.hexdigest() != expected_sha256.lower():
        return "checksum_mismatch"

    return None
