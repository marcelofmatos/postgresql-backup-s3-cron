FILENAME=$1
aws s3 cp s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$FILENAME /docker-entrypoint-initdb.d/
cd /docker-entrypoint-initdb.d/
rm /docker-entrypoint-initdb.d/$FILENAME
tar xzvf /docker-entrypoint-initdb.d/$FILENAME
chmod +x /docker-entrypoint-initdb.d/*