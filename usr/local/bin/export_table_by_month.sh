#!/usr/bin/env bash
# export_table_by_month.sh
# Exporta registros de uma tabela em arquivos CSV por mês.
# Variáveis de ambiente:
#   PGHOST (default: database)
#   PGUSER (default: postgres)
#   PGDATABASE (default: postgres)
#   PGPASSWORD (se necessário)
#   OUTPUT_DIR (default: /backup)
#   SCHEMA (default: public)
#   TABLE (obrigatório)
#   DATE_COLUMN (obrigatório)
#   COMPRESSION_TYPE (default: gzip) - Tipo de compactação do CSV
#     Valores: gzip (.csv.gz), bzip2 (.csv.bz2), xz (.csv.xz), plain/none (.csv)

set -Eeuo pipefail
trap 'echo "Erro na linha ${LINENO}. Abortando." >&2' ERR

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Uso: TABLE=<tabela> DATE_COLUMN=<campo_data> $(basename "$0")"
  echo ""
  echo "Variáveis de ambiente OBRIGATÓRIAS:"
  echo "  TABLE        Nome da tabela a exportar"
  echo "  DATE_COLUMN  Nome da coluna de data/timestamp para filtrar por mês"
  echo ""
  echo "Variáveis de ambiente OPCIONAIS:"
  echo "  PGHOST       Host do PostgreSQL (default: database)"
  echo "  PGUSER       Usuário do PostgreSQL (default: postgres)"
  echo "  PGDATABASE   Banco de dados (default: postgres)"
  echo "  PGPASSWORD   Senha (se necessário)"
  echo "  OUTPUT_DIR   Diretório de saída (default: /backup)"
  echo "  SCHEMA       Schema da tabela (default: public)"
  echo "  COMPRESSION_TYPE  Tipo de compactação (default: gzip)"
  echo "                    Valores: gzip, bzip2, xz, plain, none"
  echo ""
  echo "Exemplos:"
  echo "  TABLE=impacto_request_log DATE_COLUMN=created_at $(basename "$0")"
  echo "  OUTPUT_DIR=/mnt/backup TABLE=orders DATE_COLUMN=order_date $(basename "$0")"
  echo "  COMPRESSION_TYPE=xz TABLE=logs DATE_COLUMN=timestamp $(basename "$0")"
  echo "  COMPRESSION_TYPE=plain TABLE=data DATE_COLUMN=date $(basename "$0")"
  exit 0
fi

PGHOST="${PGHOST:-database}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-postgres}"
SCHEMA="${SCHEMA:-public}"
OUTPUT_DIR="${OUTPUT_DIR:-/backup}"
TABLE="${TABLE:-}"
DATE_COLUMN="${DATE_COLUMN:-}"
COMPRESSION_TYPE="${COMPRESSION_TYPE:-gzip}"

if [[ -z "$TABLE" ]]; then
  echo "Erro: Variável TABLE não definida."
  echo "Use: TABLE=nome_tabela DATE_COLUMN=campo_data $(basename "$0")"
  echo "Ou execute: $(basename "$0") --help"
  exit 1
fi

if [[ -z "$DATE_COLUMN" ]]; then
  echo "Erro: Variável DATE_COLUMN não definida."
  echo "Use: TABLE=nome_tabela DATE_COLUMN=campo_data $(basename "$0")"
  echo "Ou execute: $(basename "$0") --help"
  exit 1
fi

command -v psql >/dev/null 2>&1 || { echo "Erro: psql não encontrado no PATH."; exit 1; }

# Funções auxiliares
log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERRO] $*" >&2
}

# Resolver tipo de compactação
resolve_compression() {
  COMPRESSION_TYPE_LC=$(printf %s "${COMPRESSION_TYPE}" | tr '[:upper:]' '[:lower:]')
  case "$COMPRESSION_TYPE_LC" in
    gzip|"")
      COMPRESS_EXT=".csv.gz"
      COMPRESS_CMD=(gzip -c)
      COMPRESS_TOOL="gzip"
      ;;
    bzip2)
      COMPRESS_EXT=".csv.bz2"
      COMPRESS_CMD=(bzip2 -c)
      COMPRESS_TOOL="bzip2"
      ;;
    xz)
      COMPRESS_EXT=".csv.xz"
      COMPRESS_CMD=(xz -c --threads=0)
      COMPRESS_TOOL="xz"
      ;;
    plain|none)
      COMPRESS_EXT=".csv"
      COMPRESS_CMD=()
      COMPRESS_TOOL=""
      ;;
    *)
      log_warn "COMPRESSION_TYPE inválido: '$COMPRESSION_TYPE'. Usando gzip."
      COMPRESS_EXT=".csv.gz"
      COMPRESS_CMD=(gzip -c)
      COMPRESS_TOOL="gzip"
      COMPRESSION_TYPE_LC="gzip"
      ;;
  esac

  if [[ -n "$COMPRESS_TOOL" ]] && ! command -v "$COMPRESS_TOOL" >/dev/null 2>&1; then
    log_error "Ferramenta de compactação '$COMPRESS_TOOL' não encontrada no PATH."
    exit 12
  fi
}

# Compactar arquivo CSV
compress_csv() {
  local in="$1"
  local out="$2"

  if [[ -z "$in" ]] || [[ -z "$out" ]]; then
    log_error "compress_csv: parâmetros inválidos"
    return 2
  fi

  if [[ ${#COMPRESS_CMD[@]} -eq 0 ]]; then
    log_info "Sem compactação (plain/none): movendo $(basename "$in") -> $(basename "$out")"
    mv -f "$in" "$out"
  else
    log_info "Compactando ($COMPRESSION_TYPE_LC): $(basename "$in") -> $(basename "$out")"
    "${COMPRESS_CMD[@]}" "$in" > "$out"
    local rc=$?
    if [[ $rc -ne 0 ]] || [[ ! -s "$out" ]]; then
      log_error "Falha na compactação ($COMPRESSION_TYPE_LC). rc=$rc"
      return 3
    fi
    rm -f "$in"
  fi
}

mkdir -p "$OUTPUT_DIR"
if [[ ! -w "$OUTPUT_DIR" ]]; then
  echo "Erro: diretório de saída '$OUTPUT_DIR' não é gravável."
  exit 1
fi

PSQL=(psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -P pager=off)

echo "Testando conexão com postgresql://${PGUSER}@${PGHOST}/${PGDATABASE} ..."
if ! "${PSQL[@]}" -tAc "SELECT 1;"; then
  echo "Erro: não foi possível conectar ao Postgres. Verifique PGHOST, PGUSER, PGDATABASE e PGPASSWORD."
  exit 1
fi

echo "Validando tabela ${SCHEMA}.${TABLE} ..."
table_exists=$("${PSQL[@]}" -tAc "
SELECT 1
FROM information_schema.tables
WHERE table_schema = '${SCHEMA}'
  AND table_name = '${TABLE}';
")
if [[ "$table_exists" != "1" ]]; then
  echo "Erro: tabela ${SCHEMA}.${TABLE} não encontrada."
  exit 1
fi

echo "Validando coluna ${DATE_COLUMN} ..."
has_col=$("${PSQL[@]}" -tAc "
SELECT 1
FROM information_schema.columns
WHERE table_schema = '${SCHEMA}'
  AND table_name = '${TABLE}'
  AND column_name = '${DATE_COLUMN}';
")
if [[ "$has_col" != "1" ]]; then
  echo "Erro: coluna ${DATE_COLUMN} não encontrada em ${SCHEMA}.${TABLE}."
  exit 1
fi

echo "Descobrindo meses distintos ..."
months_query="
WITH months AS (
  SELECT date_trunc('month', ${DATE_COLUMN})::date AS month_start
  FROM ${SCHEMA}.${TABLE}
  WHERE ${DATE_COLUMN} IS NOT NULL
  GROUP BY 1
)
SELECT to_char(month_start, 'YYYY-MM') AS ym,
       month_start::text AS start_date,
       (month_start + INTERVAL '1 month')::date::text AS next_date
FROM months
ORDER BY month_start
"

months_count=$("${PSQL[@]}" -tAc "SELECT COUNT(*) FROM (${months_query}) s")
if [[ -z "$months_count" || "$months_count" == "0" ]]; then
  echo "Nenhum mês encontrado."
  exit 0
fi

# Resolver tipo de compactação
resolve_compression
log_info "Tipo de compactação: $COMPRESSION_TYPE_LC (extensão: $COMPRESS_EXT)"

i=0
"${PSQL[@]}" -At -F '|' -c "${months_query}" | while IFS='|' read -r ym start_date next_date; do
  i=$((i+1))
  tmp_csv="${OUTPUT_DIR}/${TABLE}_${ym}.csv.tmp"
  base_out_file="${OUTPUT_DIR}/${TABLE}_${ym}"
  out_file="${base_out_file}${COMPRESS_EXT}"

  echo "[${i}/${months_count}] ${ym}: contando linhas ..."
  count=$("${PSQL[@]}" -tAc "
    SELECT COUNT(*)
    FROM ${SCHEMA}.${TABLE}
    WHERE ${DATE_COLUMN} >= '${start_date}'
      AND NOT (${DATE_COLUMN} >= '${next_date}');
  ")

  echo "[${i}/${months_count}] ${ym}: exportando ${count} linhas para CSV temporário ..."
  "${PSQL[@]}" -c "\\COPY (
    SELECT *
    FROM ${SCHEMA}.${TABLE}
    WHERE ${DATE_COLUMN} >= '${start_date}'
      AND NOT (${DATE_COLUMN} >= '${next_date}')
    ORDER BY ${DATE_COLUMN}
  ) TO '${tmp_csv}' WITH (FORMAT CSV, HEADER, DELIMITER ',', QUOTE '\"', ESCAPE '\"');"

  if [[ ! -s "${tmp_csv}" ]]; then
    echo "Aviso: arquivo temporário ${tmp_csv} está vazio."
    rm -f "${tmp_csv}"
  else
    lines=$(($(wc -l "${tmp_csv}" 2>/dev/null | awk '{print $1}') - 1))  # Subtract header line
    if [[ "$lines" != "$count" ]]; then
      echo "Aviso: ${ym}: exportadas ${lines} linhas (+ cabeçalho), esperado ${count}."
    fi
    
    # Compactar arquivo
    compress_csv "${tmp_csv}" "${out_file}" || {
      echo "Erro: falha ao compactar ${tmp_csv}"
      rm -f "${tmp_csv}"
      continue
    }
    
    # Exibir informações do arquivo final
    file_size=$(du -h "${out_file}" 2>/dev/null | cut -f1)
    echo "[${i}/${months_count}] ${ym}: concluído - ${lines} linhas, arquivo: $(basename "${out_file}") (${file_size})"
  fi
done

echo "Finalizado. Arquivos gravados em ${OUTPUT_DIR}."
