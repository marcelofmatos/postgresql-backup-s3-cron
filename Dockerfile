FROM postgres:15-alpine

RUN apk add --no-cache bash curl ca-certificates aws-cli py3-pip \
    && rm -rf /var/cache/apk/*

ENV PGHOST=database
ENV PGPORT=5432
ENV PGUSER=postgres
ENV PGPASSWORD=postgres
ENV PGDATABASE=database
ENV S3_BUCKET_NAME=your_s3_bucket_name
ENV S3_REGION=sa-east-1
ENV AWS_ACCESS_KEY_ID=your_access_key_id
ENV AWS_SECRET_ACCESS_KEY=your_secret_access_key
ENV S3_DIRECTORY_NAME=default-directory

RUN mkdir -p /backup

COPY etc /etc
COPY usr /usr
RUN chmod +x /usr/local/bin/*.sh

CMD ["/usr/local/bin/start-cron.sh"]
