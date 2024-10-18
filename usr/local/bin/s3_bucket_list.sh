#!/bin/bash
EXTRA_PARAMS=$@
aws s3 ls s3://$S3_BUCKET_NAME/$EXTRA_PARAMS