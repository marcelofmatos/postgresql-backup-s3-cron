#!/bin/bash
PGDATABASE=${PGDATABASE:-"postgres"}
PGHOST=${PGHOST:-"localhost"}
BACKUP_FILE="/backup/$(PGHOST)_$(PGDATABASE)_$(date +\%Y-\%m-\%d_\%H-\%M-\%S).sql.gz"

S3_DIRECTORY_NAME=${S3_DIRECTORY_NAME:-"default-directory"}

pg_dump $PGDATABASE | gzip > $BACKUP_FILE

aws s3 cp $BACKUP_FILE s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$(basename $BACKUP_FILE) --region $S3_REGION

rm $BACKUP_FILE
