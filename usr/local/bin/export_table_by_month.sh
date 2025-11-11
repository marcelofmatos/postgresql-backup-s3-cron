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
  echo ""
  echo "Exemplos:"
  echo "  TABLE=impacto_request_log DATE_COLUMN=created_at $(basename "$0")"
  echo "  OUTPUT_DIR=/mnt/backup TABLE=orders DATE_COLUMN=order_date $(basename "$0")"
  exit 0
fi

PGHOST="${PGHOST:-database}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-postgres}"
SCHEMA="${SCHEMA:-public}"
OUTPUT_DIR="${OUTPUT_DIR:-/backup}"
TABLE="${TABLE:-}"
DATE_COLUMN="${DATE_COLUMN:-}"

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

i=0
"${PSQL[@]}" -At -F '|' -c "${months_query}" | while IFS='|' read -r ym start_date next_date; do
  i=$((i+1))
  out_file="${OUTPUT_DIR}/${TABLE}_${ym}.csv"

  echo "[${i}/${months_count}] ${ym}: contando linhas ..."
  count=$("${PSQL[@]}" -tAc "
    SELECT COUNT(*)
    FROM ${SCHEMA}.${TABLE}
    WHERE ${DATE_COLUMN} >= '${start_date}'
      AND NOT (${DATE_COLUMN} >= '${next_date}');
  ")

  echo "[${i}/${months_count}] ${ym}: exportando ${count} linhas para ${out_file} ..."
  "${PSQL[@]}" -c "\\COPY (
    SELECT *
    FROM ${SCHEMA}.${TABLE}
    WHERE ${DATE_COLUMN} >= '${start_date}'
      AND NOT (${DATE_COLUMN} >= '${next_date}')
    ORDER BY ${DATE_COLUMN}
  ) TO '${out_file}' WITH (FORMAT CSV, HEADER, DELIMITER ',', QUOTE '\"', ESCAPE '\"');"

  if [[ ! -s "${out_file}" ]]; then
    echo "Aviso: arquivo ${out_file} está vazio."
  else
    lines=$(($(wc -l "${out_file}" 2>/dev/null | awk '{print $1}') - 1))  # Subtract header line
    if [[ "$lines" != "$count" ]]; then
      echo "Aviso: ${ym}: exportadas ${lines} linhas (+ cabeçalho), esperado ${count}."
    else
      echo "[${i}/${months_count}] ${ym}: concluído (${lines} linhas + cabeçalho)."
    fi
  fi
done

echo "Finalizado. Arquivos gravados em ${OUTPUT_DIR}."
