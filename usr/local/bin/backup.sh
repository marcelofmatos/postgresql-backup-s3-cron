#!/bin/bash

BACKUP_FILE="/backup/$(date +\%Y-\%m-\%d_\%H-\%M-\%S).sql"
COMPRESSED_FILE="/backup/$(date +\%Y-\%m-\%d_\%H-\%M-\%S).tgz"

S3_DIRECTORY_NAME=${S3_DIRECTORY_NAME:-"default-directory"}

pg_dump -f $BACKUP_FILE
tar -czf $COMPRESSED_FILE -C /backup $(basename $BACKUP_FILE)

aws s3 cp $COMPRESSED_FILE s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$(basename $COMPRESSED_FILE) --region $S3_REGION

rm $BACKUP_FILE $COMPRESSED_FILE
