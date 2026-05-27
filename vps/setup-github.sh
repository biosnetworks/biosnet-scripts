#!/usr/bin/env bash
#
# setup-github.sh
# ────────────────────────────────────────────────────────────────────────────
# Configura conexão com GitHub via SSH em VPS Ubuntu.
#
# Faz a ponte entre o "VPS preparada" (Git instalado e configurado) e o
# "código sincronizado com GitHub" (push/pull funcionando via SSH).
#
# O que faz:
#   1. Valida que Git está instalado e configurado
#   2. Detecta ou gera chave SSH ed25519
#   3. Mostra a chave pública pra você copiar e adicionar no GitHub
#   4. Aguarda você confirmar que adicionou
#   5. Testa a conexão SSH com GitHub
#   6. Mostra próximos passos
#
# Pré-requisitos:
#   - Git instalado (vem do bootstrap-vps.sh)
#   - Git com user.name e user.email globais (vem do bootstrap-vps.sh)
#   - Conta no GitHub
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/setup-github.sh -o gh.sh
#   chmod +x gh.sh
#   ./gh.sh
#
# É IDEMPOTENTE: pode rodar várias vezes sem quebrar.
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
readonly BOLD='\033[1m'
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
# CONFIG
# ────────────────────────────────────────────────────────────────────────────

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_PUB="$SSH_KEY.pub"
GIT_EMAIL=""
KEY_TITLE=""

# ────────────────────────────────────────────────────────────────────────────
# BANNER
# ────────────────────────────────────────────────────────────────────────────

show_banner() {
    cat <<'EOF'

   ╔══════════════════════════════════════════════════════════╗
   ║                                                          ║
   ║      Setup GitHub                                        ║
   ║                                                          ║
   ║      Configura SSH + testa conexão com GitHub            ║
   ║                                                          ║
   ╚══════════════════════════════════════════════════════════╝

EOF
}

# ────────────────────────────────────────────────────────────────────────────
# VALIDAÇÕES
# ────────────────────────────────────────────────────────────────────────────

check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Não execute como root."
        log_error "Use o usuário operacional (com sudo). Ex: ./setup-github.sh"
        exit 1
    fi
    log_ok "Executando como '$USER' (não-root)."
}

check_git() {
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git não instalado. Rode bootstrap-vps.sh primeiro."
        exit 1
    fi
    log_ok "Git instalado: $(git --version)"

    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -z "$git_name" ]] || [[ -z "$git_email" ]]; then
        log_error "Git sem user.name ou user.email globais."
        log_error "Configure antes:"
        echo "  git config --global user.name 'seu-nome'"
        echo "  git config --global user.email 'seu@email.com'"
        exit 1
    fi

    GIT_EMAIL="$git_email"
    log_ok "Git configurado: $git_name <$git_email>"
}

check_internet() {
    if ! curl -fsSL --max-time 5 https://api.github.com >/dev/null 2>&1; then
        log_error "Sem acesso a github.com. Verifique a internet."
        exit 1
    fi
    log_ok "GitHub acessível."
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 1 — CHAVE SSH
# ────────────────────────────────────────────────────────────────────────────

step_ssh_key() {
    log_section "1/4  Chave SSH"

    if [[ -f "$SSH_KEY" ]] && [[ -f "$SSH_PUB" ]]; then
        log_ok "Chave SSH já existe: $SSH_KEY"
        return 0
    fi

    log_info "Chave SSH não encontrada. Gerando ed25519..."

    # Garante que o diretório existe com permissões corretas
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Gera sem passphrase (em VPS dedicada é OK)
    log_info "Gerando chave sem passphrase (apropriado pra VPS dedicada)..."
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N "" >/dev/null

    chmod 600 "$SSH_KEY"
    chmod 644 "$SSH_PUB"

    log_ok "Chave SSH gerada."
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 2 — MOSTRA A CHAVE E AGUARDA
# ────────────────────────────────────────────────────────────────────────────

step_display_key() {
    log_section "2/4  Adicionar chave pública no GitHub"

    # Sugere um título descritivo
    local hostname
    hostname=$(hostname)
    KEY_TITLE="$hostname-$(date +%Y%m%d)"

    cat <<EOF
${BOLD}═══════════ ABAIXO ESTÁ A SUA CHAVE PÚBLICA ═══════════${NC}

EOF
    cat "$SSH_PUB"
    cat <<EOF

${BOLD}═════════════════ FIM DA CHAVE ═══════════════════════${NC}

${BOLD}AGORA NO SEU NAVEGADOR:${NC}

  1. Abra: ${CYAN}https://github.com/settings/keys${NC}

  2. Clique em ${BOLD}"New SSH key"${NC} (botão verde no canto superior direito)

  3. Preencha:
     ${BOLD}Title:${NC}     ${KEY_TITLE}
     ${BOLD}Key type:${NC}  Authentication Key
     ${BOLD}Key:${NC}       cola TODA a linha acima (começa com 'ssh-ed25519')

  4. Clique em ${BOLD}"Add SSH key"${NC} (vai pedir sua senha do GitHub)

EOF

    read -rp "$(echo -e ${BOLD}Pressione ENTER quando tiver adicionado a chave no GitHub...${NC})"
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 3 — TESTA CONEXÃO
# ────────────────────────────────────────────────────────────────────────────

step_test_connection() {
    log_section "3/4  Testando conexão com GitHub"

    log_info "Adicionando github.com aos known_hosts (primeira vez)..."

    # Adiciona github.com aos known_hosts sem prompt interativo
    ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    sort -u "$HOME/.ssh/known_hosts" -o "$HOME/.ssh/known_hosts" 2>/dev/null || true

    log_info "Tentando autenticar como SSH em github.com..."
    echo ""

    # Tenta conectar — o GitHub responde com "Hi USERNAME!" e fecha
    local output
    if output=$(ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1); then
        # Sucesso é incomum aqui (GitHub responde mas fecha com exit code 1)
        echo "$output"
        log_ok "Conexão OK."
    else
        # Verifica se o erro é "successfully authenticated"
        if echo "$output" | grep -q "successfully authenticated"; then
            echo "$output"
            echo ""
            log_ok "🎉 Autenticação com GitHub funcionou!"

            # Extrai o username do output
            local gh_user
            gh_user=$(echo "$output" | grep -oP 'Hi \K[^!]+' || echo "")
            if [[ -n "$gh_user" ]]; then
                log_ok "Usuário GitHub detectado: $gh_user"
            fi
        else
            echo "$output"
            echo ""
            log_error "Falha na autenticação."
            log_error "Possíveis causas:"
            echo "  • Chave não foi adicionada no GitHub (https://github.com/settings/keys)"
            echo "  • Chave foi adicionada errada (faltou alguma parte ao copiar)"
            echo "  • Aguardar uns segundos e tentar de novo"
            echo ""
            read -rp "Tentar de novo? [S/n] " resp
            if [[ ! "$resp" =~ ^[nN]$ ]]; then
                step_test_connection
            else
                exit 1
            fi
        fi
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 4 — INSTRUÇÕES FINAIS
# ────────────────────────────────────────────────────────────────────────────

show_summary() {
    log_section "✓  GitHub conectado!"

    cat <<EOF
${BOLD}A partir de agora você pode:${NC}

  ${BOLD}Clonar repos privados:${NC}
    git clone git@github.com:seu-user/repo-privado.git

  ${BOLD}Conectar projeto existente:${NC}
    cd /opt/meu-projeto
    git remote add origin git@github.com:seu-user/meu-projeto.git
    git push -u origin main

  ${BOLD}Verificar quem está autenticado:${NC}
    ssh -T git@github.com

${BOLD}${YELLOW}═══════════════ PRÓXIMOS PASSOS ═══════════════${NC}

${BOLD}1.${NC} Criar um novo projeto (cria estrutura em /opt/):
   ${CYAN}curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/setup-project.sh -o sp.sh${NC}
   ${CYAN}chmod +x sp.sh${NC}
   ${CYAN}./sp.sh${NC}

${BOLD}2.${NC} OU clonar um projeto que já existe no GitHub:
   ${CYAN}sudo mkdir -p /opt/meu-projeto${NC}
   ${CYAN}sudo chown \$USER:\$USER /opt/meu-projeto${NC}
   ${CYAN}cd /opt${NC}
   ${CYAN}git clone git@github.com:seu-user/meu-projeto.git${NC}

${BOLD}3.${NC} Instalar Claude Code (se quiser usar IA dentro do projeto):
   ${CYAN}sudo npm install -g @anthropic-ai/claude-code${NC}
   ${CYAN}cd /opt/meu-projeto && claude${NC}

${BOLD}${YELLOW}═════════════════════════════════════════════════${NC}

EOF
}

# ────────────────────────────────────────────────────────────────────────────
# MAIN
# ────────────────────────────────────────────────────────────────────────────

main() {
    show_banner

    log_section "Validações iniciais"
    check_not_root
    check_git
    check_internet

    step_ssh_key
    step_display_key
    step_test_connection

    show_summary
}

main "$@"
