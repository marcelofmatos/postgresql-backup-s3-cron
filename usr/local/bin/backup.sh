#!/bin/bash

PGHOST=${PGHOST:-"localhost"}
PGPORT=${PGPORT:-"5432"}
PGUSER=${PGUSER:-"postgres"}
BACKUP_DIR="/backup"
S3_DIRECTORY_NAME=${S3_DIRECTORY_NAME:-"postgres-backups"}
S3_PARAMS=${S3_PARAMS:-""}
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

mkdir -p "$BACKUP_DIR"

echo "Iniciando backup..."

DATABASES=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -lqt | cut -d'|' -f1 | grep -v template | grep -v postgres | grep -v "prisma_migrate_shadow" | sed '/^$/d' | sed 's/^ *//')

for database in $DATABASES; do
    echo "Backup: $database"
    BACKUP_FILE="$BACKUP_DIR/${PGHOST}_${database}_${TIMESTAMP}.sql.gz"
    
    pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$database" | gzip > "$BACKUP_FILE"
    
    aws s3 cp "$BACKUP_FILE" "s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/" --region "$S3_REGION" --storage-class GLACIER_IR $S3_PARAMS
    
    rm "$BACKUP_FILE"
done

echo "Backup das configurações globais..."
GLOBALS_FILE="$BACKUP_DIR/${PGHOST}_globals_${TIMESTAMP}.sql.gz"
pg_dumpall -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" --globals-only | gzip > "$GLOBALS_FILE"
aws s3 cp "$GLOBALS_FILE" "s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/" --region "$S3_REGION" --storage-class GLACIER_IR $S3_PARAMS
rm "$GLOBALS_FILE"

echo "Backup concluído!"