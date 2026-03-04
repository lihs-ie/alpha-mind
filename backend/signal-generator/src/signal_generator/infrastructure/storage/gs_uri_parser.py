"""GS URI parser utility."""


def parse_gs_uri(uri: str) -> tuple[str, str]:
    """gs://bucket/path 形式の URI をバケット名とオブジェクトパスに分割する。"""
    if not uri.startswith("gs://"):
        raise ValueError(f"Cloud Storage URI は gs:// で始まる必要がある (got: {uri})")

    without_prefix = uri[len("gs://"):]
    slash_index = without_prefix.find("/")
    if slash_index == -1:
        raise ValueError(f"Cloud Storage URI にオブジェクトパスが含まれていない (got: {uri})")

    bucket_name = without_prefix[:slash_index]
    object_path = without_prefix[slash_index + 1:]
    return bucket_name, object_path
