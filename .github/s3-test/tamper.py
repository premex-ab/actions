"""Overwrites a stored archive so the download action must reject it."""
import os
import sys

import boto3

boto3.client("s3", endpoint_url=os.environ["S3_TEST_ENDPOINT"], region_name="us-east-1",
             aws_access_key_id=os.environ["S3_TEST_KEY_ID"], aws_secret_access_key=os.environ["S3_TEST_SECRET"]
             ).put_object(Bucket="ci-artifacts", Key=sys.argv[1], Body=b"tampered")
