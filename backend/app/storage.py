"""S3 access (MinIO in docker compose). Configured from the environment set in docker-compose.yml."""
import os

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError

BUCKET = os.environ.get("S3_BUCKET", "scans")
INTERNAL = os.environ.get("S3_ENDPOINT_URL", "http://localhost:9000")          # how this server reaches storage
PUBLIC = os.environ.get("S3_PUBLIC_ENDPOINT_URL", "http://localhost:9000")     # how the client reaches it (API.md)


def make_client(url):
    return boto3.client("s3", endpoint_url=url, region_name=os.environ.get("AWS_REGION", "ap-south-1"),
                        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}))


# s3: used by the server itself. signer: only signs URLs, so they name a host the client can reach.
s3, signer = make_client(INTERNAL), make_client(PUBLIC)


def error_code(e: ClientError):
    return e.response.get("Error", {}).get("Code")


def object_exists(key: str) -> bool:
    """False only if storage says there is no such object; any other error is raised."""
    try:
        s3.head_object(Bucket=BUCKET, Key=key)
        return True
    except ClientError as e:
        if error_code(e) in ("404", "NoSuchKey", "NotFound"):
            return False
        raise


def list_parts(key: str, s3_upload_id: str) -> list[dict] | None:
    """Parts storage holds for a multipart upload, or None if that upload no longer exists (already assembled)."""
    held = []
    try:
        for page in s3.get_paginator("list_parts").paginate(Bucket=BUCKET, Key=key, UploadId=s3_upload_id):
            held += [{"part_number": p["PartNumber"], "etag": p["ETag"], "size": p["Size"],
                      "last_modified": p["LastModified"].timestamp()} for p in page.get("Parts", [])]
    except ClientError as e:
        if error_code(e) != "NoSuchUpload":
            raise
        return None
    return held


def presign_part(key: str, s3_upload_id: str, part_number: int, expires_in: int = 3600) -> str:
    return signer.generate_presigned_url("upload_part", ExpiresIn=expires_in, Params={
        "Bucket": BUCKET, "Key": key, "UploadId": s3_upload_id, "PartNumber": part_number})


def presign_download(key: str, expires_in: int) -> str:
    return signer.generate_presigned_url("get_object", Params={"Bucket": BUCKET, "Key": key}, ExpiresIn=expires_in)
