FILENAME=$1
aws s3 cp s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$FILENAME /docker-entrypoint-initdb.d/
chmod +x /docker-entrypoint-initdb.d/*