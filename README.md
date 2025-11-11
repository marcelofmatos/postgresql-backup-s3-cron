# PostgreSQL Backup to S3 with Cron

🐘 ➡️ 📦 ➡️ ☁️

Sistema automatizado de backup de bancos de dados PostgreSQL com sincronização para Amazon S3 usando Docker e agendamento via cron.

## 📋 Índice

- [Características](#características)
- [Arquitetura](#arquitetura)
- [Requisitos](#requisitos)
- [Instalação](#instalação)
- [Configuração](#configuração)
- [Uso](#uso)
- [Scripts](#scripts)
- [Variáveis de Ambiente](#variáveis-de-ambiente)
- [Volumes](#volumes)
- [Exemplos](#exemplos)
- [Recuperação de Backups](#recuperação-de-backups)
- [CI/CD](#cicd)
- [Troubleshooting](#troubleshooting)
- [Contribuindo](#contribuindo)
- [Licença](#licença)

## ✨ Características

- 🔄 **Backup automatizado** via cron schedule customizável
- 🗜️ **Compressão gzip** dos dumps para economia de espaço
- ☁️ **Sincronização com S3** com storage class Glacier Instant Retrieval
- 🐳 **Containerizado** com Docker para fácil deploy
- 📊 **Logs detalhados** de todas as operações
- 🔒 **Seguro** - remove arquivos locais apenas após upload bem-sucedido
- 🔁 **Retry automático** em caso de falhas
- 📁 **Preserva estrutura** de diretórios no S3
- ⚡ **Leve** - baseado em Alpine Linux
- 🛠️ **Modular** - scripts separados para backup e sincronização

## 🏗️ Arquitetura

O projeto é composto por dois scripts principais:

```
┌─────────────┐
│  backup.sh  │  ← Realiza dumps PostgreSQL
└──────┬──────┘
       │ chamada automática
       ▼
┌─────────────┐
│   sync.sh   │  ← Sincroniza com S3
└─────────────┘
```

### Fluxo de Operação

1. **Cron** dispara o `backup.sh` no horário agendado
2. **backup.sh** conecta ao PostgreSQL e faz dump de todos os databases
3. Dumps são comprimidos com gzip e salvos em `/backup`
4. **sync.sh** é automaticamente chamado ao final
5. Todos os arquivos em `/backup` são enviados para S3
6. Arquivos são removidos localmente apenas após upload bem-sucedido
7. Logs são enviados para stdout/stderr para captura pelo Docker

## 📦 Requisitos

- Docker 20.10+
- Docker Compose 2.0+ (opcional, mas recomendado)
- Acesso a um bucket S3 com credenciais válidas
- Rede com acesso ao servidor PostgreSQL e ao S3

## 🚀 Instalação

### Método 1: Docker Compose (Recomendado)

1. Clone o repositório:
```bash
git clone https://github.com/seu-usuario/postgresql-backup-s3-cron.git
cd postgresql-backup-s3-cron
```

2. Edite o `docker-compose.yml` com suas configurações

3. Inicie o container:
```bash
docker-compose up -d
```

4. Verifique os logs:
```bash
docker-compose logs -f pg-backup-s3
```

### Método 2: Docker Run

```bash
# Build da imagem
docker build -t postgresql-backup-s3-cron .

# Executar container
docker run -d \
  --name pg-backup \
  -e PGHOST=seu-host-postgres \
  -e PGUSER=postgres \
  -e PGPASSWORD=senha-segura \
  -e S3_BUCKET_NAME=seu-bucket \
  -e S3_REGION=sa-east-1 \
  -e AWS_ACCESS_KEY_ID=sua-chave \
  -e AWS_SECRET_ACCESS_KEY=sua-chave-secreta \
  -e CRON_SCHEDULE="0 2 * * *" \
  -v backup-data:/backup \
  postgresql-backup-s3-cron
```

### Método 3: Docker Registry

Se a imagem já está publicada em um registry:

```bash
docker pull seu-registry/postgresql-backup-s3-cron:latest

docker run -d \
  --name pg-backup \
  -e PGHOST=database \
  -e PGUSER=postgres \
  -e PGPASSWORD=senha \
  -e S3_BUCKET_NAME=meu-bucket \
  -e S3_REGION=sa-east-1 \
  -e AWS_ACCESS_KEY_ID=sua-chave \
  -e AWS_SECRET_ACCESS_KEY=sua-chave-secreta \
  seu-registry/postgresql-backup-s3-cron:latest
```

## ⚙️ Configuração

### docker-compose.yml

```yaml
version: '3.8'

services:
  pg-backup-s3:
    image: seu-registry/postgresql-backup-s3-cron:latest
    environment:
      # Conexão PostgreSQL
      PGHOST: "database"
      PGPORT: 5432
      PGUSER: "postgres"
      PGPASSWORD: "senha-segura"
      
      # Configuração S3
      S3_BUCKET_NAME: "meu-bucket-backups"
      S3_REGION: "sa-east-1"
      AWS_ACCESS_KEY_ID: "AKIAIOSFODNN7EXAMPLE"
      AWS_SECRET_ACCESS_KEY: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
      S3_DIRECTORY_NAME: "postgres-backups"
      
      # Agendamento (cron format)
      CRON_SCHEDULE: "0 2 * * *"  # 2h da manhã todo dia
      
    volumes:
      - backup-data:/backup
    deploy:
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3

volumes:
  backup-data:
```

### Variáveis de Ambiente Detalhadas

Veja a seção [Variáveis de Ambiente](#variáveis-de-ambiente) para lista completa.

## 📝 Uso

### Backup Manual

Execute um backup imediatamente:

```bash
# Dentro do container
docker exec pg-backup /usr/local/bin/backup.sh

# Ou acessando o container
docker exec -it pg-backup bash
/usr/local/bin/backup.sh
```

### Sincronização Manual

Sincronize arquivos específicos:

```bash
docker exec pg-backup /usr/local/bin/sync.sh /caminho/personalizado
```

### Verificar Logs

```bash
# Logs em tempo real
docker logs -f pg-backup

# Últimas 100 linhas
docker logs --tail 100 pg-backup

# Logs desde uma data
docker logs --since 2025-11-11T00:00:00 pg-backup
```

### Verificar Cron

```bash
# Ver agendamento do cron
docker exec pg-backup cat /etc/crontabs/root

# Ver últimas execuções
docker exec pg-backup grep CRON /var/log/messages
```

## 🛠️ Scripts

### backup.sh

Script principal que realiza os backups PostgreSQL.

**Localização:** `/usr/local/bin/backup.sh`

**Funcionalidades:**
- Lista todos os databases (exceto templates e postgres)
- Faz dump individual de cada database
- Faz dump das configurações globais (roles, tablespaces)
- Comprime tudo com gzip
- Calcula tempo de execução
- Chama automaticamente o sync.sh

**Uso dentro do container:**
```bash
docker exec pg-backup /usr/local/bin/backup.sh
```

### sync.sh

Script de sincronização com S3.

**Localização:** `/usr/local/bin/sync.sh`

**Funcionalidades:**
- Sincroniza qualquer arquivo em um diretório
- Preserva estrutura de subdiretórios
- Upload com GLACIER_IR storage class
- Remove localmente apenas após sucesso
- Logs detalhados por arquivo
- Relatório final de operações

**Uso dentro do container:**
```bash
docker exec pg-backup /usr/local/bin/sync.sh /backup
```

**Códigos de retorno:**
- `0` - Sucesso total
- `1` - Erro de pré-checagem (AWS CLI, variáveis)
- `2` - Falha parcial (alguns arquivos não foram enviados)

### start-cron.sh

Script de inicialização do container.

**Funcionalidades:**
- Configura o cron com CRON_SCHEDULE
- Configura o comando de backup
- Inicia o crond em foreground

## 🔧 Variáveis de Ambiente

### PostgreSQL (Obrigatórias)

| Variável | Descrição | Padrão | Exemplo |
|----------|-----------|--------|---------|
| `PGHOST` | Host do PostgreSQL | `localhost` | `database` |
| `PGPORT` | Porta do PostgreSQL | `5432` | `5432` |
| `PGUSER` | Usuário do PostgreSQL | `postgres` | `backup_user` |
| `PGPASSWORD` | Senha do PostgreSQL | - | `senha-segura` |

### AWS S3 (Obrigatórias)

| Variável | Descrição | Padrão | Exemplo |
|----------|-----------|--------|---------|
| `S3_BUCKET_NAME` | Nome do bucket S3 | - | `meu-bucket-backups` |
| `S3_REGION` | Região do bucket | `sa-east-1` | `us-east-1` |
| `AWS_ACCESS_KEY_ID` | Chave de acesso AWS | - | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | Chave secreta AWS | - | `wJalr...` |

### Backup (Opcionais)

| Variável | Descrição | Padrão | Exemplo |
|----------|-----------|--------|---------|
| `BACKUP_DIR` | Diretório local de backup | `/backup` | `/var/backups` |
| `S3_DIRECTORY_NAME` | Diretório no bucket S3 | `postgres-backups` | `prod-backups` |
| `S3_PARAMS` | Parâmetros extras AWS CLI | - | `--endpoint-url https://...` |

### Cron (Opcionais)

| Variável | Descrição | Padrão | Exemplo |
|----------|-----------|--------|---------|
| `CRON_SCHEDULE` | Agendamento cron | `0 22 * * *` | `0 2 * * *` (2h da manhã) |
| `CRON_BACKUP_COMMAND` | Comando a executar | `backup.sh ...` | Customizado |

### Exemplos de CRON_SCHEDULE

```bash
# A cada hora
CRON_SCHEDULE="0 * * * *"

# Todo dia às 2h da manhã
CRON_SCHEDULE="0 2 * * *"

# Todo domingo às 3h
CRON_SCHEDULE="0 3 * * 0"

# A cada 6 horas
CRON_SCHEDULE="0 */6 * * *"

# Segunda a sexta às 22h
CRON_SCHEDULE="0 22 * * 1-5"
```

## 💾 Volumes

### backup-data

Volume para armazenamento temporário dos backups antes do upload.

```yaml
volumes:
  - backup-data:/backup
```

**Nota:** Os arquivos são removidos automaticamente após upload bem-sucedido.

### restore-data (Opcional)

Volume para restauração de backups.

```yaml
volumes:
  - restore-data:/docker-entrypoint-initdb.d
```

## 📚 Exemplos

### Exemplo 1: Backup Diário às 2h

```yaml
environment:
  PGHOST: "postgres-db"
  PGUSER: "admin"
  PGPASSWORD: "senha123"
  S3_BUCKET_NAME: "backups-prod"
  S3_REGION: "sa-east-1"
  AWS_ACCESS_KEY_ID: "AKI..."
  AWS_SECRET_ACCESS_KEY: "wJa..."
  CRON_SCHEDULE: "0 2 * * *"
```

### Exemplo 2: Backup a cada 6h

```yaml
environment:
  CRON_SCHEDULE: "0 */6 * * *"
```

### Exemplo 3: Usando MinIO (S3-compatible)

```yaml
environment:
  S3_BUCKET_NAME: "backups"
  S3_REGION: "us-east-1"
  S3_PARAMS: "--endpoint-url https://minio.exemplo.com"
  AWS_ACCESS_KEY_ID: "minioadmin"
  AWS_SECRET_ACCESS_KEY: "minioadmin"
```

### Exemplo 4: Múltiplos Bancos PostgreSQL

Para fazer backup de múltiplos servidores PostgreSQL, crie um container para cada:

```yaml
services:
  backup-db1:
    image: postgresql-backup-s3-cron
    environment:
      PGHOST: "postgres-db1"
      S3_DIRECTORY_NAME: "db1-backups"
      # ...
  
  backup-db2:
    image: postgresql-backup-s3-cron
    environment:
      PGHOST: "postgres-db2"
      S3_DIRECTORY_NAME: "db2-backups"
      # ...
```

## 🔄 Recuperação de Backups

### Listar backups disponíveis

```bash
aws s3 ls s3://meu-bucket/postgres-backups/
```

### Baixar backup específico

```bash
aws s3 cp s3://meu-bucket/postgres-backups/localhost_mydb_2025-11-11_02-00-00.sql.gz .
```

### Restaurar backup

```bash
# Descompactar
gunzip localhost_mydb_2025-11-11_02-00-00.sql.gz

# Restaurar
psql -h localhost -U postgres -d mydb -f localhost_mydb_2025-11-11_02-00-00.sql
```

### Restaurar configurações globais (roles, etc)

```bash
gunzip localhost_globals_2025-11-11_02-00-00.sql.gz
psql -h localhost -U postgres -f localhost_globals_2025-11-11_02-00-00.sql
```

### Script de restauração automática

```bash
#!/bin/bash
BUCKET="meu-bucket"
PREFIX="postgres-backups"
DATABASE="mydb"

# Buscar backup mais recente
LATEST=$(aws s3 ls s3://$BUCKET/$PREFIX/ | grep $DATABASE | sort | tail -1 | awk '{print $4}')

# Baixar e restaurar
aws s3 cp s3://$BUCKET/$PREFIX/$LATEST .
gunzip $LATEST
psql -h localhost -U postgres -d $DATABASE -f ${LATEST%.gz}
```

## 🔨 CI/CD

O projeto inclui configurações para:

### GitHub Actions

Workflows em `.github/workflows/`:
- `docker-image.yml` - Build e push da imagem
- `release-and-build.yml` - Criação de releases
- `docker-set-tag.yml` - Gerenciamento de tags
- `pr-checks.yml` - Validações em PRs
- `pr-labeler.yml` - Auto-label de PRs

### GitLab CI

Pipeline em `.gitlab-ci.yml`:
- Build automático da imagem
- Push para registry
- Deploy automático via webhook

### Versionamento

O projeto usa tags semânticas:
- `1.0.1`, `1.0.2`, `1.0.3`, `1.0.4`
- `main` - branch principal
- `homolog` - branch de homologação

## 🐛 Troubleshooting

### Erro: "AWS CLI não está instalado"

**Causa:** Container não tem AWS CLI instalado

**Solução:** O Dockerfile já inclui AWS CLI. Se o erro persistir, reconstrua a imagem:
```bash
docker-compose build --no-cache
```

### Erro: "Variável S3_BUCKET_NAME não está definida"

**Causa:** Variável de ambiente obrigatória não configurada

**Solução:** Defina no docker-compose.yml ou docker run:
```yaml
environment:
  S3_BUCKET_NAME: "seu-bucket"
```

### Backup não está sendo executado

**Possíveis causas:**
1. Cron não está rodando
2. Variáveis não estão disponíveis no ambiente do cron
3. Permissões incorretas

**Verificações:**
```bash
# Ver se cron está rodando
docker exec pg-backup ps aux | grep crond

# Ver configuração do cron
docker exec pg-backup cat /etc/crontabs/root

# Testar backup manualmente
docker exec pg-backup /usr/local/bin/backup.sh

# Ver logs do container
docker logs pg-backup
```

### Arquivos não são removidos após upload

**Causa:** Falha no upload para S3

**Verificação:**
```bash
# Ver logs detalhados do sync
docker logs pg-backup | grep "\[sync\]"

# Verificar conectividade S3
docker exec pg-backup aws s3 ls s3://seu-bucket/

# Verificar credenciais
docker exec pg-backup aws sts get-caller-identity
```

### Permissão negada no S3

**Causa:** Credenciais AWS sem permissões adequadas

**Solução:** Garanta que a IAM role/user tem as seguintes permissões:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::seu-bucket/*"
    }
  ]
}
```

### Container reiniciando constantemente

**Verificações:**
```bash
# Ver logs de erro
docker logs pg-backup

# Verificar se pode conectar ao PostgreSQL
docker exec pg-backup psql -h $PGHOST -U $PGUSER -c "SELECT 1;"

# Verificar variáveis de ambiente
docker exec pg-backup env | grep -E "(PG|S3|AWS)"
```

## 📖 Documentação Adicional

Para informações detalhadas sobre os scripts, consulte:
- [`usr/local/bin/README.md`](usr/local/bin/README.md) - Documentação completa dos scripts

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor:

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo `LICENSE` para mais detalhes.

## 👥 Autores

- **Marcelo Matos** - *Trabalho inicial*

## 🙏 Agradecimentos

- PostgreSQL community
- AWS CLI team
- Alpine Linux team
- Docker community

## 📞 Suporte

Para suporte, abra uma issue no GitHub ou entre em contato através de:
- Issues: https://github.com/seu-usuario/postgresql-backup-s3-cron/issues
- Email: seu-email@exemplo.com

---

**Feito com ❤️ para a comunidade open source**
