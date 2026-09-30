"""Writes an object directly, bypassing the actions: tamper.py <key> [file]. Without a file the
object becomes the bytes 'tampered'."""
import os
import sys

import boto3

body = open(sys.argv[2], "rb").read() if len(sys.argv) > 2 else b"tampered"
boto3.client("s3", endpoint_url=os.environ["S3_TEST_ENDPOINT"], region_name="us-east-1",
             aws_access_key_id=os.environ["S3_TEST_KEY_ID"], aws_secret_access_key=os.environ["S3_TEST_SECRET"]
             ).put_object(Bucket="ci-artifacts", Key=sys.argv[1], Body=body)
