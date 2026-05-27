#!/usr/bin/env bash
#
# setup-project.sh
# ────────────────────────────────────────────────────────────────────────────
# Cria estrutura padrão de projeto em /opt/<nome>/
#
# Estrutura criada:
#   /opt/<nome>/
#   ├── api/
#   ├── worker/
#   ├── webhook/
#   ├── frontend/
#   ├── db/migrations/
#   ├── db/backups/
#   ├── caddy/
#   ├── scripts/
#   ├── docs/
#   ├── secrets/
#   ├── volumes/{postgres,redis,caddy-data,caddy-config}/
#   ├── .claude/skills/<nome>-ops/SKILL.md
#   ├── .gitignore
#   ├── .env.example
#   ├── README.md
#   └── CLAUDE.md (template)
#
# Pré-requisitos:
#   - Bootstrap da VPS já rodado (bootstrap-vps.sh)
#   - Usuário com sudo
#
# Uso:
#   ./setup-project.sh
#
# IDEMPOTENTE: pode rodar 2x sem quebrar.
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# CORES
# ────────────────────────────────────────────────────────────────────────────

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}      $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2; }
log_section() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ────────────────────────────────────────────────────────────────────────────
# CONFIG DO PROJETO
# ────────────────────────────────────────────────────────────────────────────

PROJECT_NAME=""
PROJECT_DIR=""
PROJECT_DESC=""
PROJECT_DOMAIN=""
SHORT_NAME=""

prompt_project_info() {
    log_section "Informações do projeto"

    while [[ -z "$PROJECT_NAME" ]]; do
        read -rp "Nome do projeto (ex: biosnet-mkt): " PROJECT_NAME
        # Valida: minúsculas, números, hífen apenas
        if [[ ! "$PROJECT_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
            log_error "Use apenas letras minúsculas, números e hífen. Começa com letra."
            PROJECT_NAME=""
        fi
    done

    PROJECT_DIR="/opt/$PROJECT_NAME"

    # Sugere short name (ex: biosnet-mkt → mkt)
    SHORT_NAME=$(echo "$PROJECT_NAME" | awk -F'-' '{print $NF}')
    read -rp "Short name pra containers (default: $SHORT_NAME): " input_short
    SHORT_NAME="${input_short:-$SHORT_NAME}"

    read -rp "Descrição curta do projeto: " PROJECT_DESC
    read -rp "Domínio principal (ex: mkt.biosnet.com.br ou enter pra pular): " PROJECT_DOMAIN

    echo ""
    log_info "Resumo:"
    echo "  Nome:        $PROJECT_NAME"
    echo "  Diretório:   $PROJECT_DIR"
    echo "  Short name:  $SHORT_NAME (containers serão $SHORT_NAME-api, $SHORT_NAME-postgres, etc.)"
    echo "  Descrição:   $PROJECT_DESC"
    echo "  Domínio:     ${PROJECT_DOMAIN:-(nenhum)}"
    echo ""

    read -rp "Confirma? [S/n] " resp
    if [[ "$resp" =~ ^[nN]$ ]]; then
        log_info "Cancelado."
        exit 0
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# VALIDAÇÕES
# ────────────────────────────────────────────────────────────────────────────

check_prerequisites() {
    log_section "Validações"

    if [[ $EUID -eq 0 ]]; then
        log_error "Não execute como root."
        exit 1
    fi
    log_ok "Não-root."

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker não instalado. Rode bootstrap-vps.sh primeiro."
        exit 1
    fi
    log_ok "Docker disponível."

    if ! command -v git >/dev/null 2>&1; then
        log_error "Git não instalado."
        exit 1
    fi
    log_ok "Git disponível."

    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")
    if [[ -z "$git_name" || -z "$git_email" ]]; then
        log_error "Git sem user.name ou user.email global. Configure antes."
        echo "  git config --global user.name 'seu-nome'"
        echo "  git config --global user.email 'seu@email.com'"
        exit 1
    fi
    log_ok "Git configurado: $git_name <$git_email>"

    if [[ -d "$PROJECT_DIR" && -n "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]]; then
        log_warn "$PROJECT_DIR já existe e não está vazio."
        read -rp "Continuar mesmo assim (idempotente)? [s/N] " resp
        [[ ! "$resp" =~ ^[sS]$ ]] && exit 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 1 — CRIAÇÃO DE DIRETÓRIOS
# ────────────────────────────────────────────────────────────────────────────

step_create_dirs() {
    log_section "1/5  Criando estrutura de pastas"

    log_info "mkdir $PROJECT_DIR (precisa sudo)..."
    sudo mkdir -p "$PROJECT_DIR"
    sudo chown "$USER:$USER" "$PROJECT_DIR"

    cd "$PROJECT_DIR"

    local dirs=(
        api worker webhook frontend
        ixc-adapter
        db/migrations db/backups
        caddy scripts docs secrets
        ".claude/skills/${PROJECT_NAME}-ops"
        volumes/postgres volumes/redis
        volumes/caddy-data volumes/caddy-config
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done

    log_ok "Estrutura criada em $PROJECT_DIR"
    tree -d -L 2 -I 'volumes' "$PROJECT_DIR" 2>/dev/null || find "$PROJECT_DIR" -maxdepth 2 -type d -not -path '*/volumes*'
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 2 — ARQUIVOS BASE (.gitignore, README, .env.example)
# ────────────────────────────────────────────────────────────────────────────

step_base_files() {
    log_section "2/5  Criando arquivos base"

    cd "$PROJECT_DIR"

    # ── .gitignore ──
    if [[ ! -f .gitignore ]]; then
        cat > .gitignore <<'EOF'
# Secrets
.env
.env.*
!.env.example
secrets/

# Volumes Docker (bind mounts)
volumes/

# Backups locais
db/backups/
*.bak
*.sql.gz

# Logs
*.log
logs/

# Python
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/
venv/
.venv/

# Node
node_modules/
npm-debug.log*
yarn-error.log
.next/
dist/
build/

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Claude Code cache
.claude/cache/

# Docker
*.pid
EOF
        log_ok ".gitignore criado"
    else
        log_warn ".gitignore já existe (preservado)"
    fi

    # ── .env.example ──
    if [[ ! -f .env.example ]]; then
        cat > .env.example <<EOF
# ─── Database ────────────────────────────────────────────
POSTGRES_USER=${SHORT_NAME}
POSTGRES_PASSWORD=changeme
POSTGRES_DB=${PROJECT_NAME//-/_}

# ─── Redis ───────────────────────────────────────────────
REDIS_PASSWORD=changeme

# ─── Application ─────────────────────────────────────────
NODE_ENV=development
API_PORT=8000
LOG_LEVEL=info

# ─── Externals (preencher quando integrar) ───────────────
# META_APP_ID=
# META_APP_SECRET=
# META_PHONE_NUMBER_ID=
# META_WEBHOOK_VERIFY_TOKEN=
# IXC_HOST=
# IXC_TOKEN=
EOF
        log_ok ".env.example criado"
    else
        log_warn ".env.example já existe (preservado)"
    fi

    # ── README.md ──
    if [[ ! -f README.md ]]; then
        cat > README.md <<EOF
# ${PROJECT_NAME}

${PROJECT_DESC}

## Status

🚧 Em desenvolvimento inicial.

## Documentação

### Setup e instalação
- [Instalação do Git + GitHub](docs/INSTALL-GIT.md)
- [Instalação do Claude Code](docs/INSTALL-CLAUDE-CODE.md)

### Arquitetura
- \`CLAUDE.md\` — visão geral, stack, regras de ouro do projeto
- \`.claude/skills/${PROJECT_NAME}-ops/SKILL.md\` — regras de negócio

## Infraestrutura

$([ -n "$PROJECT_DOMAIN" ] && echo "- **Domínio**: ${PROJECT_DOMAIN}")
- **Workdir**: ${PROJECT_DIR}
- **Containers**: \`${SHORT_NAME}-*\` (ex: \`${SHORT_NAME}-api\`, \`${SHORT_NAME}-postgres\`)
- **Rede Docker**: \`${SHORT_NAME}-net\`

## Desenvolvimento

\`\`\`bash
# Sobe stack
docker compose up -d

# Logs
docker compose logs -f

# Para
docker compose down
\`\`\`
EOF
        log_ok "README.md criado"
    else
        log_warn "README.md já existe (preservado)"
    fi

    # ── CLAUDE.md ──
    if [[ ! -f CLAUDE.md ]]; then
        cat > CLAUDE.md <<EOF
# ${PROJECT_NAME} — ${PROJECT_DESC}

## Stack

- Backend: (a decidir)
- Frontend: (a decidir)
- Banco: PostgreSQL 16
- Fila: Redis 7
- Reverse proxy: Caddy 2
- Orquestração: Docker Compose

## Skills do Claude Code

- Skill global da VPS (se houver): \`~/.claude/skills/\`
- Skill deste projeto: \`.claude/skills/${PROJECT_NAME}-ops/\`

## Infra

$([ -n "$PROJECT_DOMAIN" ] && echo "- **Domínio**: ${PROJECT_DOMAIN}")
- **Workdir**: ${PROJECT_DIR}
- **Usuário ops**: $USER (sudo + docker)
- **Container prefix**: ${SHORT_NAME}-
- **Rede Docker**: ${SHORT_NAME}-net

## Estrutura

\`\`\`
${PROJECT_NAME}/
├── api/              # backend HTTP
├── worker/           # consumer de fila
├── webhook/          # endpoints externos
├── frontend/         # dashboard
├── db/migrations/    # SQL numerado: 001_, 002_
├── caddy/            # Caddyfile
├── scripts/          # deploy, backup
└── docs/             # runbooks, ADRs
\`\`\`

## Regras de ouro

1. NUNCA commitar secrets (\`.env\` está no \`.gitignore\`)
2. NUNCA usar \`:latest\` em produção
3. NUNCA expor banco/redis direto na internet
4. SEMPRE \`restart: unless-stopped\` em produção
5. SEMPRE \`healthcheck\` em serviços críticos
6. SEMPRE migrations numeradas em \`db/migrations/\`

## Convenções

- Commits: Conventional Commits (feat:, fix:, chore:, docs:, refactor:)
- Branches: main (prod), dev (staging), feat/<nome>
- SQL: snake_case, FK + índice

## Aprendizados

<!-- Adicione descobertas conforme o projeto evolui -->

- $(date +%Y-%m-%d): Projeto criado via setup-project.sh
EOF
        log_ok "CLAUDE.md criado (template)"
    else
        log_warn "CLAUDE.md já existe (preservado)"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 3 — SKILL DO PROJETO
# ────────────────────────────────────────────────────────────────────────────

step_create_skill() {
    log_section "3/5  Criando skill do projeto"

    local skill_dir="$PROJECT_DIR/.claude/skills/${PROJECT_NAME}-ops"
    local skill_file="$skill_dir/SKILL.md"

    if [[ -f "$skill_file" ]]; then
        log_warn "SKILL.md já existe (preservado)"
        return
    fi

    cat > "$skill_file" <<EOF
---
name: ${PROJECT_NAME}-ops
description: Skill operacional do projeto ${PROJECT_NAME}. Use quando trabalhar com este projeto - regras de negócio, schema do banco específico, integrações de API, lógica do projeto. Não cobre infraestrutura geral - use a skill global da VPS pra isso.
---

# ${PROJECT_NAME} — Regras Operacionais

${PROJECT_DESC}

## Stack

- Backend: (a decidir)
- Banco: PostgreSQL 16
- Fila: Redis 7
- Container prefix: \`${SHORT_NAME}-\`
- Rede Docker: \`${SHORT_NAME}-net\`

## Convenções deste projeto

### Naming
- Containers: \`${SHORT_NAME}-<servico>\` (ex: \`${SHORT_NAME}-api\`, \`${SHORT_NAME}-postgres\`)
- Volumes: bind mounts em \`./volumes/<servico>/\`
- Rede: \`${SHORT_NAME}-net\`

### Código
- Conventional Commits: feat, fix, chore, docs, refactor, test
- Migrations: \`db/migrations/NNN_descricao.sql\` (numeradas)
- SQL: snake_case, FK explícita + índice

### Docker
- Tag específica (NUNCA \`:latest\` em prod)
- \`restart: unless-stopped\`
- \`healthcheck\` em serviços críticos
- Containers de banco/cache em rede interna isolada

## Regras absolutas

(Adicione conforme o projeto evolui)

### Sobre integrações externas
- Toda função que chama API externa: retry com backoff exponencial
- Idempotência via chave única (ex: external_id)

### Sobre banco
- NUNCA DROP/TRUNCATE/DELETE em massa sem dump prévio
- NUNCA aplicar mudança de schema direto — sempre migration numerada
- SEMPRE adicionar índice em FK

### Sobre código
- NUNCA commitar .env, tokens, credenciais
- NUNCA \`git push --force\` em main ou dev
- NUNCA editar arquivos no servidor — sempre via Git pull

## Quando PARAR e perguntar

- Operação destrutiva em massa
- Mudança em integração externa
- Migration em tabela grande
- Adicionar/remover campo em produção

## Aprendizados

<!-- Adicione toda vez que descobrir algo importante -->

(vazio)
EOF

    log_ok "Skill criada: $skill_file"
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 4 — GIT INIT
# ────────────────────────────────────────────────────────────────────────────

step_init_git() {
    log_section "4/5  Inicializando Git"

    cd "$PROJECT_DIR"

    if [[ -d .git ]]; then
        log_warn "Git já inicializado (.git/ existe)"
    else
        git init -q
        git branch -m main 2>/dev/null || true
        log_ok "Git inicializado, branch: main"
    fi

    # Confere se tem commits
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        log_info "Criando primeiro commit..."
        git add .
        git commit -q -m "chore: initial project structure via setup-project.sh"
        log_ok "Primeiro commit criado"
    else
        log_warn "Repo já tem commits (preservado)"
    fi

    git log --oneline | head -5
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 5 — DOCS DE REFERÊNCIA
# ────────────────────────────────────────────────────────────────────────────

step_reference_docs() {
    log_section "5/5  Docs de referência"

    cd "$PROJECT_DIR/docs"

    log_info "Criando placeholders em docs/..."

    [[ ! -f DEPLOY.md ]] && cat > DEPLOY.md <<'EOF'
# Deploy

## Pré-requisitos
- Bootstrap da VPS feito
- GitHub Secrets configurados

## Processo
1. ...
2. ...

(a preencher)
EOF

    [[ ! -f RUNBOOK.md ]] && cat > RUNBOOK.md <<'EOF'
# Runbook Operacional

## Quando algo der errado, primeiro:

```bash
docker compose ps          # quais containers estão rodando
docker compose logs -f     # logs ao vivo
docker stats               # uso de CPU/RAM
df -h                      # espaço em disco
```

## Cenários comuns

### Container não sobe

```bash
docker compose logs <servico>
```

### Banco com problema

(a preencher)

### Reverse proxy não roteia

(a preencher)
EOF

    [[ ! -f ARCHITECTURE.md ]] && cat > ARCHITECTURE.md <<'EOF'
# Arquitetura

## Visão geral

(diagrama + descrição)

## Decisões arquiteturais

(ADR — Architectural Decision Records)

### ADR-001: Docker Compose puro (não Swarm)

Status: aceito  
Data: $(date +%Y-%m-%d)  
Contexto: Projeto único, host único.  
Decisão: Usar Docker Compose, não inicializar Swarm.  
Consequências: Mais simples de operar; se um dia precisar de multi-host, migrar.
EOF

    log_ok "Templates criados em docs/"
}

# ────────────────────────────────────────────────────────────────────────────
# RESUMO
# ────────────────────────────────────────────────────────────────────────────

show_summary() {
    log_section "✓  Projeto $PROJECT_NAME pronto"

    echo "Localização: $PROJECT_DIR"
    echo ""
    echo "Estrutura criada:"
    cd "$PROJECT_DIR"
    ls -la
    echo ""

    log_info "Próximos passos:"
    echo ""
    echo "  1. Acessa o projeto:"
    echo "     cd $PROJECT_DIR"
    echo ""
    echo "  2. Cria repo no GitHub (privado!) e conecta:"
    echo "     git remote add origin git@github.com:USUARIO/${PROJECT_NAME}.git"
    echo "     git push -u origin main"
    echo ""
    echo "  3. Edita o CLAUDE.md com info real do projeto:"
    echo "     nano CLAUDE.md"
    echo ""
    echo "  4. Inicia Claude Code dentro do projeto:"
    echo "     claude"
    echo ""
    echo "  5. Cria o docker-compose.yml e .env (a partir de .env.example):"
    echo "     cp .env.example .env && nano .env"
    echo "     nano docker-compose.yml"
    echo ""
}

# ────────────────────────────────────────────────────────────────────────────
# MAIN
# ────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                          ║${NC}"
    echo -e "${CYAN}║      Setup Project - Novo projeto em /opt/               ║${NC}"
    echo -e "${CYAN}║                                                          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    prompt_project_info
    check_prerequisites

    step_create_dirs
    step_base_files
    step_create_skill
    step_init_git
    step_reference_docs

    show_summary
}

main "$@"
