#!/bin/bash

BACKUP_FILE="/backup/$(date +\%Y-\%m-\%d_\%H-\%M-\%S).sql.gz"

S3_DIRECTORY_NAME=${S3_DIRECTORY_NAME:-"default-directory"}

pg_dumpall | gzip > $BACKUP_FILE

aws s3 cp $BACKUP_FILE s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$BACKUP_FILE --region $S3_REGION

rm $BACKUP_FILE
