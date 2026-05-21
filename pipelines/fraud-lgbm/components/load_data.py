from kfp import dsl
from kfp.dsl import Output, Dataset


@dsl.component(base_image="k3d-registry.localhost:5000/fraud-component:v1")
def load_data(
    s3_endpoint: str,
    s3_bucket: str,
    s3_key: str,
    data_out: Output[Dataset],
):
    import boto3
    from botocore.client import Config

    s3 = boto3.client(
        "s3",
        endpoint_url=s3_endpoint,
        aws_access_key_id="minio",
        aws_secret_access_key="minio123",
        config=Config(signature_version="s3v4"),
        region_name="us-east-1",
    )
    s3.download_file(s3_bucket, s3_key, data_out.path)
    print(f"Downloaded s3://{s3_bucket}/{s3_key} → {data_out.path}")
