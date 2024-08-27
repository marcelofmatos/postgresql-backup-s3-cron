#!/bin/bash

# Nome do arquivo de backup
BACKUP_FILE="/backup/$(date +\%Y-\%m-\%d_\%H-\%M-\%S).sql"

# Dump do banco de dados
pg_dump -Fc -f $BACKUP_FILE

# Enviar o backup para o S3
aws s3 cp $BACKUP_FILE s3://$S3_BUCKET_NAME/$(basename $BACKUP_FILE) --region $S3_REGION

# Remover o arquivo de backup local após o upload
rm $BACKUP_FILE
