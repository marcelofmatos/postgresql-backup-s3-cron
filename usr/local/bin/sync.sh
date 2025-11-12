#!/bin/bash

# Script de sincronização de backups com S3
# Sincroniza arquivos do diretório de backup com S3 e remove localmente após sucesso

# Variáveis externas usadas neste script:
# - BACKUP_DIR: Diretório de backup padrão (usado como fallback para SYNC_DIR se não fornecido como argumento).
# - S3_BUCKET_NAME: Nome do bucket S3 de destino (obrigatório).
# - S3_DIRECTORY_NAME: Nome do diretório dentro do bucket S3 (padrão: postgres-backups).
# - S3_PARAMS: Parâmetros adicionais para o comando AWS CLI (padrão: vazio).
# - S3_REGION: Região do S3 (opcional, adicionada ao comando se definida).

set -e

# Configurações
SYNC_DIR="${1:-${BACKUP_DIR:-/backup}}"
S3_DIRECTORY_NAME="${S3_DIRECTORY_NAME:-postgres-backups}"
S3_PARAMS="${S3_PARAMS:-}"

# Validações
if ! command -v aws &> /dev/null; then
    echo "[sync] ERRO: AWS CLI não está instalado ou não está no PATH"
    exit 1
fi

if [ -z "$S3_BUCKET_NAME" ]; then
    echo "[sync] ERRO: Variável S3_BUCKET_NAME não está definida"
    exit 1
fi

if [ ! -d "$SYNC_DIR" ]; then
    echo "[sync] ERRO: Diretório $SYNC_DIR não existe"
    exit 1
fi

# Informações iniciais
echo "[sync] Iniciando sincronização..."
echo "[sync] Diretório de sincronização: $SYNC_DIR"
echo "[sync] Bucket de destino: s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME"
if [ -n "$S3_REGION" ]; then
    echo "[sync] Região: $S3_REGION"
fi

# Contadores
TOTAL=0
SUCCESS=0
FAILS=0

# Processar todos os arquivos
while IFS= read -r -d '' file; do
    TOTAL=$((TOTAL + 1))
    
    # Calcular caminho relativo
    rel="${file#$SYNC_DIR/}"
    
    # Se o arquivo está diretamente em SYNC_DIR (sem barra no caminho relativo após remoção)
    if [ "$rel" = "$file" ]; then
        rel="$(basename "$file")"
    fi
    
    # Destino no S3
    dest="s3://$S3_BUCKET_NAME/$S3_DIRECTORY_NAME/$rel"
    
    echo "[sync] Enviando: $rel"
    
    # Construir comando AWS
    aws_cmd="aws s3 cp \"$file\" \"$dest\" --storage-class GLACIER_IR"
    
    if [ -n "$S3_REGION" ]; then
        aws_cmd="$aws_cmd --region \"$S3_REGION\""
    fi
    
    if [ -n "$S3_PARAMS" ]; then
        aws_cmd="$aws_cmd $S3_PARAMS"
    fi
    
    # Executar upload
    if eval $aws_cmd; then
        echo "[sync] ✓ Sucesso: $rel enviado, removendo local"
        rm -f "$file"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "[sync] ✗ FALHA: $rel não enviado, mantendo local"
        FAILS=$((FAILS + 1))
    fi
done < <(find "$SYNC_DIR" -type f -print0)

# Relatório final
echo ""
echo "[sync] =========================================="
echo "[sync] Sincronização concluída"
echo "[sync] Total de arquivos: $TOTAL"
echo "[sync] Enviados com sucesso: $SUCCESS"
echo "[sync] Falhas: $FAILS"
echo "[sync] =========================================="

if [ "$FAILS" -gt 0 ]; then
    echo "[sync] ATENÇÃO: $FAILS arquivo(s) não foram enviados e permanecem localmente"
    exit 2
fi

if [ "$TOTAL" -eq 0 ]; then
    echo "[sync] Nenhum arquivo encontrado para sincronizar"
    exit 0
fi

echo "[sync] Todos os arquivos foram sincronizados com sucesso!"
exit 0
