"""Creates a signing-enforced test user and bucket on a local moto server (INITIAL_NO_AUTH_ACTION_COUNT=3)."""
import json
import os

import boto3

endpoint = os.environ["S3_TEST_ENDPOINT"]
anonymous = dict(endpoint_url=endpoint, region_name="us-east-1", aws_access_key_id="setup", aws_secret_access_key="setup")
iam = boto3.client("iam", **anonymous)
iam.create_user(UserName="ci")
iam.put_user_policy(UserName="ci", PolicyName="s3", PolicyDocument=json.dumps(
    {"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": "s3:*", "Resource": "*"}]}))
key = iam.create_access_key(UserName="ci")["AccessKey"]
boto3.client("s3", endpoint_url=endpoint, region_name="us-east-1", aws_access_key_id=key["AccessKeyId"],
             aws_secret_access_key=key["SecretAccessKey"]).create_bucket(Bucket="ci-artifacts")
with open(os.environ["GITHUB_OUTPUT"], "a") as out:
    out.write(f"access-key-id={key['AccessKeyId']}\nsecret-access-key={key['SecretAccessKey']}\n")
