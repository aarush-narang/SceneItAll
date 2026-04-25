from __future__ import annotations
import mimetypes
from pathlib import Path
import boto3
from ..config import settings


def _client():
    return boto3.client(
        "s3",
        region_name=settings.aws_region,
        aws_access_key_id=settings.aws_access_key_id,
        aws_secret_access_key=settings.aws_secret_access_key,
    )


def _public_url(key: str) -> str:
    return f"https://{settings.s3_bucket}.s3.{settings.aws_region}.amazonaws.com/{key}"


def upload_file(local_path: str | Path, key: str, content_type: str | None = None) -> str:
    local_path = Path(local_path)
    if content_type is None:
        content_type, _ = mimetypes.guess_type(str(local_path))
    extra: dict = {}
    if content_type:
        extra["ContentType"] = content_type

    _client().upload_file(str(local_path), settings.s3_bucket, key, ExtraArgs=extra or None)
    return _public_url(key)


def upload_bytes(data: bytes, key: str, content_type: str = "application/octet-stream") -> str:
    _client().put_object(
        Bucket=settings.s3_bucket,
        Key=key,
        Body=data,
        ContentType=content_type,
    )
    return _public_url(key)


def delete_file(key: str) -> None:
    _client().delete_object(Bucket=settings.s3_bucket, Key=key)
