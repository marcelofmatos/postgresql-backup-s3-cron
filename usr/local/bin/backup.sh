#!/bin/bash

PGHOST=${PGHOST:-"localhost"}
PGPORT=${PGPORT:-"5432"}
PGUSER=${PGUSER:-"postgres"}
BACKUP_DIR="/backup"
S3_DIRECTORY_NAME=${S3_DIRECTORY_NAME:-"postgres-backups"}

if [ -z "$S3_BUCKET_NAME" ]; then
    echo "Erro: Variável S3_BUCKET_NAME não está definida"
    exit 1
fi

if [ -z "$S3_REGION" ]; then
    echo "Erro: Variável S3_REGION não está definida"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

echo "Iniciando backup de todos os bancos de dados em $PGHOST:$PGPORT"
echo "Timestamp: $TIMESTAMP"

DATABASES=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -lqt | cut -d\| -f1 | grep -vE '^\s*$|template[0-9]*|postgres\s*

while IFS= read -r database; do
    if [ -n "$database" ]; then
        TOTAL_DBS=$((TOTAL_DBS + 1))
        echo "Fazendo backup do banco: $database"
        
        BACKUP_FILE="$BACKUP_DIR/${PGHOST}_${database}_${TIMESTAMP}.sql.gz"
        
        if pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$database" | gzip > "$BACKUP_FILE"; then
            echo "✓ Backup local criado: $BACKUP_FILE"
            
            S3_PATH="s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$(basename "$BACKUP_FILE")"
            if aws s3 cp "$BACKUP_FILE" "$S3_PATH" --region "$S3_REGION"; then
                echo "✓ Upload para S3 concluído: $S3_PATH"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                
                rm "$BACKUP_FILE"
                echo "✓ Arquivo local removido"
            else
                echo "✗ Erro no upload para S3: $database"
                FAILED_DBS="$FAILED_DBS $database"
            fi
        else
            echo "✗ Erro no backup do banco: $database"
            FAILED_DBS="$FAILED_DBS $database"
        fi
        echo ""
    fi
done <<< "$DATABASES"

echo "Fazendo backup das configurações globais (roles, tablespaces, etc.)"
GLOBALS_FILE="$BACKUP_DIR/${PGHOST}_globals_${TIMESTAMP}.sql.gz"

if pg_dumpall -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" --globals-only | gzip > "$GLOBALS_FILE"; then
    echo "✓ Backup de configurações globais criado: $GLOBALS_FILE"
    
    S3_GLOBALS_PATH="s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$(basename "$GLOBALS_FILE")"
    if aws s3 cp "$GLOBALS_FILE" "$S3_GLOBALS_PATH" --region "$S3_REGION"; then
        echo "✓ Upload de configurações globais para S3 concluído"
        rm "$GLOBALS_FILE"
        echo "✓ Arquivo local de configurações globais removido"
    else
        echo "✗ Erro no upload das configurações globais para S3"
    fi
else
    echo "✗ Erro no backup das configurações globais"
fi

echo ""
echo "========== RESUMO DO BACKUP =========="
echo "Total de bancos processados: $TOTAL_DBS"
echo "Backups bem-sucedidos: $SUCCESS_COUNT"
echo "Backups falharam: $((TOTAL_DBS - SUCCESS_COUNT))"

if [ -n "$FAILED_DBS" ]; then
    echo "Bancos com falha:$FAILED_DBS"
    exit 1
else
    echo "✓ Todos os backups foram concluídos com sucesso!"
    exit 0
fi | awk '{$1=$1};1')

if [ -z "$DATABASES" ]; then
    echo "Nenhum banco de dados encontrado para backup"
    exit 1
fi

echo "Bancos encontrados:"
echo "$DATABASES"
echo ""

TOTAL_DBS=0
SUCCESS_COUNT=0
FAILED_DBS=""

# Faz backup de cada banco individualmente
while IFS= read -r database; do
    if [ -n "$database" ]; then
        TOTAL_DBS=$((TOTAL_DBS + 1))
        echo "Fazendo backup do banco: $database"
        
        BACKUP_FILE="$BACKUP_DIR/${PGHOST}_${database}_${TIMESTAMP}.sql.gz"
        
        # Executa o pg_dump
        if pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$database" | gzip > "$BACKUP_FILE"; then
            echo "✓ Backup local criado: $BACKUP_FILE"
            
            # Upload para S3
            S3_PATH="s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$(basename "$BACKUP_FILE")"
            if aws s3 cp "$BACKUP_FILE" "$S3_PATH" --region "$S3_REGION"; then
                echo "✓ Upload para S3 concluído: $S3_PATH"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                
                # Remove arquivo local após upload bem-sucedido
                rm "$BACKUP_FILE"
                echo "✓ Arquivo local removido"
            else
                echo "✗ Erro no upload para S3: $database"
                FAILED_DBS="$FAILED_DBS $database"
            fi
        else
            echo "✗ Erro no backup do banco: $database"
            FAILED_DBS="$FAILED_DBS $database"
        fi
        echo ""
    fi
done <<< "$DATABASES"

# Backup adicional com pg_dumpall para roles e configurações globais
echo "Fazendo backup das configurações globais (roles, tablespaces, etc.)"
GLOBALS_FILE="$BACKUP_DIR/${PGHOST}_globals_${TIMESTAMP}.sql.gz"

if pg_dumpall -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" --globals-only | gzip > "$GLOBALS_FILE"; then
    echo "✓ Backup de configurações globais criado: $GLOBALS_FILE"
    
    # Upload para S3
    S3_GLOBALS_PATH="s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$(basename "$GLOBALS_FILE")"
    if aws s3 cp "$GLOBALS_FILE" "$S3_GLOBALS_PATH" --region "$S3_REGION"; then
        echo "✓ Upload de configurações globais para S3 concluído"
        rm "$GLOBALS_FILE"
        echo "✓ Arquivo local de configurações globais removido"
    else
        echo "✗ Erro no upload das configurações globais para S3"
    fi
else
    echo "✗ Erro no backup das configurações globais"
fi

echo ""
echo "========== RESUMO DO BACKUP =========="
echo "Total de bancos processados: $TOTAL_DBS"
echo "Backups bem-sucedidos: $SUCCESS_COUNT"
echo "Backups falharam: $((TOTAL_DBS - SUCCESS_COUNT))"

if [ -n "$FAILED_DBS" ]; then
    echo "Bancos com falha:$FAILED_DBS"
    exit 1
else
    echo "✓ Todos os backups foram concluídos com sucesso!"
    exit 0
fi