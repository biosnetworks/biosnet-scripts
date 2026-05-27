#!/usr/bin/env bash
#
# bootstrap-vps.sh
# ────────────────────────────────────────────────────────────────────────────
# Bootstrap de VPS Ubuntu 24.04 LTS
#
# Faz o setup completo de uma VPS recém-instalada:
#   - Update do sistema
#   - Ferramentas essenciais (ufw, fail2ban, htop, ncdu, tmux, etc.)
#   - Firewall UFW (apenas 22, 80, 443)
#   - fail2ban com proteção SSH
#   - Atualizações automáticas de segurança
#   - Docker oficial + Compose
#   - Node.js 20 LTS
#   - Configurações de Git globais
#   - Geração de chave SSH (opcional)
#
# Pré-requisitos:
#   - Ubuntu 24.04 LTS limpo
#   - Usuário NÃO-ROOT com sudo
#   - Acesso à internet
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/SEU_USER/scripts/main/bootstrap-vps.sh -o bootstrap.sh
#   chmod +x bootstrap.sh
#   ./bootstrap.sh
#
# OU localmente:
#   ./bootstrap-vps.sh
#
# É IDEMPOTENTE: pode ser rodado várias vezes sem causar problemas.
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# CORES E LOGGING
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
# VALIDAÇÕES INICIAIS
# ────────────────────────────────────────────────────────────────────────────

check_ubuntu_version() {
    if ! [[ -f /etc/os-release ]]; then
        log_error "Não foi possível detectar o SO. Esperado: Ubuntu 24.04."
        exit 1
    fi

    local version
    version=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)
    
    if [[ "$version" != "24.04" ]]; then
        log_warn "Esperado Ubuntu 24.04, detectado: $version"
        read -rp "Continuar mesmo assim? [s/N] " resp
        [[ ! "$resp" =~ ^[sS]$ ]] && exit 1
    else
        log_ok "Ubuntu 24.04 detectado."
    fi
}

check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "NÃO execute este script como root."
        log_error "Use um usuário comum com sudo. Ex: ./bootstrap-vps.sh"
        exit 1
    fi
    log_ok "Executando como usuário '$USER' (não-root)."
}

check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_info "Este script precisa de sudo. Você pode ser solicitado pela senha."
        if ! sudo true; then
            log_error "Falha ao obter sudo."
            exit 1
        fi
    fi
    log_ok "Sudo disponível."
}

check_internet() {
    if ! curl -fsSL --max-time 5 https://1.1.1.1 >/dev/null 2>&1; then
        log_error "Sem internet. Verifique a conexão."
        exit 1
    fi
    log_ok "Internet OK."
}

# ────────────────────────────────────────────────────────────────────────────
# BANNER E CONFIRMAÇÃO
# ────────────────────────────────────────────────────────────────────────────

show_banner() {
    cat <<'EOF'

   ╔══════════════════════════════════════════════════════════╗
   ║                                                          ║
   ║      VPS Bootstrap - Ubuntu 24.04 LTS                    ║
   ║                                                          ║
   ║      Hardening + Docker + Node.js + Git                  ║
   ║                                                          ║
   ╚══════════════════════════════════════════════════════════╝

EOF
}

confirm_execution() {
    log_warn "Este script vai modificar configurações do sistema:"
    echo "  • Atualizar todos os pacotes"
    echo "  • Instalar UFW, fail2ban, Docker, Node.js, ferramentas"
    echo "  • Ativar firewall (apenas 22, 80, 443)"
    echo "  • Configurar fail2ban contra brute-force SSH"
    echo "  • Ativar atualizações automáticas de segurança"
    echo ""
    read -rp "Continuar? [s/N] " resp
    if [[ ! "$resp" =~ ^[sS]$ ]]; then
        log_info "Cancelado pelo usuário."
        exit 0
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 1 — ATUALIZAÇÃO DO SISTEMA
# ────────────────────────────────────────────────────────────────────────────

step_update_system() {
    log_section "1/8  Atualizando o sistema"

    log_info "apt update..."
    sudo apt-get update -qq

    log_info "apt upgrade (pode demorar)..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"

    log_ok "Sistema atualizado."
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 2 — FERRAMENTAS ESSENCIAIS
# ────────────────────────────────────────────────────────────────────────────

step_install_tools() {
    log_section "2/8  Instalando ferramentas essenciais"

    local packages=(
        ufw                       # firewall
        fail2ban                  # proteção brute-force
        unattended-upgrades       # updates automáticos
        apt-listchanges           # changelog dos updates
        ca-certificates           # certs HTTPS
        curl wget                 # downloads
        git                       # versionamento
        vim nano                  # editores
        tmux screen               # sessões persistentes
        htop ncdu                 # monitoramento
        jq                        # parsing JSON
        net-tools dnsutils        # rede (netstat, dig)
        build-essential           # compiladores (npm precisa)
        software-properties-common
        gnupg                     # chaves GPG
        lsb-release               # detectar distro
        zip unzip                 # compactação
        rsync                     # backup
    )

    log_info "Instalando ${#packages[@]} pacotes..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"

    log_ok "Ferramentas instaladas."
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 3 — FIREWALL UFW
# ────────────────────────────────────────────────────────────────────────────

step_configure_ufw() {
    log_section "3/8  Configurando firewall (UFW)"

    log_info "Resetando regras..."
    sudo ufw --force reset >/dev/null 2>&1

    log_info "Aplicando defaults: deny in, allow out..."
    sudo ufw default deny incoming >/dev/null
    sudo ufw default allow outgoing >/dev/null

    log_info "Abrindo portas: 22 (SSH), 80 (HTTP), 443 (HTTPS)..."
    sudo ufw allow 22/tcp comment 'SSH' >/dev/null
    sudo ufw allow 80/tcp comment 'HTTP' >/dev/null
    sudo ufw allow 443/tcp comment 'HTTPS' >/dev/null

    log_info "Ativando UFW..."
    sudo ufw --force enable >/dev/null

    log_ok "Firewall ativo."
    sudo ufw status verbose
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 4 — FAIL2BAN
# ────────────────────────────────────────────────────────────────────────────

step_configure_fail2ban() {
    log_section "4/8  Configurando fail2ban"

    if [[ -f /etc/fail2ban/jail.local ]]; then
        log_warn "jail.local já existe. Fazendo backup..."
        sudo cp /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[DEFAULT]
# Ban por 1 hora
bantime  = 1h
# Janela de observação: 10 minutos
findtime = 10m
# Máximo de tentativas antes do ban
maxretry = 5
# Backend recomendado pra Ubuntu 24
backend  = systemd

[sshd]
enabled  = true
port     = 22
filter   = sshd
maxretry = 3
EOF

    sudo systemctl enable fail2ban >/dev/null 2>&1
    sudo systemctl restart fail2ban

    sleep 2
    log_ok "fail2ban configurado."
    sudo fail2ban-client status 2>/dev/null || true
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 5 — ATUALIZAÇÕES AUTOMÁTICAS
# ────────────────────────────────────────────────────────────────────────────

step_unattended_upgrades() {
    log_section "5/8  Habilitando atualizações automáticas de segurança"

    sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    sudo systemctl enable unattended-upgrades >/dev/null 2>&1
    sudo systemctl restart unattended-upgrades

    log_ok "Atualizações automáticas configuradas (apenas security)."
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 6 — DOCKER
# ────────────────────────────────────────────────────────────────────────────

step_install_docker() {
    log_section "6/8  Instalando Docker"

    if command -v docker >/dev/null 2>&1; then
        log_ok "Docker já instalado: $(docker --version)"
    else
        log_info "Baixando script oficial do Docker..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh

        log_info "Executando instalação..."
        sudo sh /tmp/get-docker.sh >/dev/null 2>&1
        rm /tmp/get-docker.sh

        log_ok "Docker instalado: $(docker --version)"
    fi

    # Adiciona usuário ao grupo docker (idempotente)
    if ! groups "$USER" | grep -q docker; then
        log_info "Adicionando $USER ao grupo 'docker'..."
        sudo usermod -aG docker "$USER"
        log_warn "Você precisará SAIR E LOGAR DE NOVO para o grupo 'docker' valer."
    else
        log_ok "$USER já está no grupo 'docker'."
    fi

    # Habilita Docker no boot
    sudo systemctl enable docker >/dev/null 2>&1

    # Confere Compose
    if docker compose version >/dev/null 2>&1; then
        log_ok "Docker Compose: $(docker compose version | head -1)"
    else
        log_error "Docker Compose plugin não encontrado."
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 7 — NODE.JS
# ────────────────────────────────────────────────────────────────────────────

step_install_nodejs() {
    log_section "7/8  Instalando Node.js 20 LTS"

    if command -v node >/dev/null 2>&1; then
        local current_version
        current_version=$(node --version)
        if [[ "$current_version" == v20.* ]]; then
            log_ok "Node.js 20 já instalado: $current_version"
            return
        else
            log_warn "Outra versão do Node detectada: $current_version (será substituída)"
        fi
    fi

    log_info "Adicionando repositório NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null 2>&1

    log_info "Instalando nodejs..."
    sudo apt-get install -y -qq nodejs

    log_ok "Node.js: $(node --version)"
    log_ok "npm:     $(npm --version)"
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 8 — CONFIGURAÇÕES GIT
# ────────────────────────────────────────────────────────────────────────────

step_configure_git() {
    log_section "8/8  Configurando Git (global)"

    # Pega configs atuais (se existem)
    local current_name current_email
    current_name=$(git config --global user.name 2>/dev/null || echo "")
    current_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -n "$current_name" && -n "$current_email" ]]; then
        log_ok "Git já configurado:"
        echo "       user.name:  $current_name"
        echo "       user.email: $current_email"
        read -rp "Deseja reconfigurar? [s/N] " resp
        [[ ! "$resp" =~ ^[sS]$ ]] && { configure_git_defaults; return; }
    fi

    read -rp "Git user.name (ex: 'seuusuario'): " git_name
    read -rp "Git user.email (use o do GitHub): " git_email

    git config --global user.name "$git_name"
    git config --global user.email "$git_email"

    configure_git_defaults

    log_ok "Git configurado:"
    git config --global --list | grep -E '^(user|init|push|pull|color|core)' | sed 's/^/       /'
}

configure_git_defaults() {
    git config --global init.defaultBranch main
    git config --global push.default current
    git config --global pull.rebase false
    git config --global color.ui auto
    git config --global core.editor nano
    git config --global credential.helper "cache --timeout=3600"
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA OPCIONAL — CHAVE SSH PARA GITHUB
# ────────────────────────────────────────────────────────────────────────────

step_ssh_key() {
    log_section "OPCIONAL  Gerar chave SSH para GitHub"

    local ssh_key="$HOME/.ssh/id_ed25519"

    if [[ -f "$ssh_key" ]]; then
        log_ok "Chave SSH já existe: $ssh_key"
        echo ""
        log_info "Chave PÚBLICA (cole no GitHub em https://github.com/settings/keys):"
        echo ""
        cat "$ssh_key.pub"
        echo ""
        return
    fi

    read -rp "Gerar chave SSH ed25519 para GitHub agora? [S/n] " resp
    if [[ "$resp" =~ ^[nN]$ ]]; then
        log_info "Pulado. Para gerar depois:"
        echo "   ssh-keygen -t ed25519 -C 'seu@email.com'"
        return
    fi

    local git_email
    git_email=$(git config --global user.email 2>/dev/null || echo "")
    if [[ -z "$git_email" ]]; then
        read -rp "Email para a chave SSH: " git_email
    fi

    log_info "Gerando chave (sem passphrase pra automação)..."
    ssh-keygen -t ed25519 -C "$git_email" -f "$ssh_key" -N "" >/dev/null

    chmod 700 "$HOME/.ssh"
    chmod 600 "$ssh_key"
    chmod 644 "$ssh_key.pub"

    log_ok "Chave SSH gerada."
    echo ""
    log_info "═══ COPIE A CHAVE PÚBLICA ABAIXO ═══"
    echo ""
    cat "$ssh_key.pub"
    echo ""
    log_info "═══ FIM DA CHAVE ═══"
    echo ""
    echo "Próximos passos:"
    echo "  1. Acesse: https://github.com/settings/keys"
    echo "  2. New SSH key → cola o conteúdo acima"
    echo "  3. Teste com: ssh -T git@github.com"
    echo ""
}

# ────────────────────────────────────────────────────────────────────────────
# RESUMO FINAL
# ────────────────────────────────────────────────────────────────────────────

show_summary() {
    log_section "✓  Bootstrap concluído!"

    echo "Estado da VPS:"
    echo ""

    printf "  %-25s %s\n" "Usuário:"      "$USER"
    printf "  %-25s %s\n" "Hostname:"     "$(hostname)"
    printf "  %-25s %s\n" "IP público:"   "$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || echo 'N/A')"
    printf "  %-25s %s\n" "OS:"           "$(lsb_release -ds 2>/dev/null || echo 'N/A')"
    printf "  %-25s %s\n" "Kernel:"       "$(uname -r)"

    echo ""
    echo "Software instalado:"
    echo ""

    printf "  %-25s %s\n" "Docker:"         "$(docker --version 2>/dev/null || echo 'N/A')"
    printf "  %-25s %s\n" "Docker Compose:" "$(docker compose version 2>/dev/null | head -1 || echo 'N/A')"
    printf "  %-25s %s\n" "Node.js:"        "$(node --version 2>/dev/null || echo 'N/A')"
    printf "  %-25s %s\n" "npm:"            "$(npm --version 2>/dev/null || echo 'N/A')"
    printf "  %-25s %s\n" "Git:"            "$(git --version 2>/dev/null || echo 'N/A')"

    echo ""
    echo "Segurança:"
    echo ""

    printf "  %-25s %s\n" "UFW:"        "$(sudo ufw status | head -1)"
    printf "  %-25s %s\n" "fail2ban:"   "$(sudo systemctl is-active fail2ban)"
    printf "  %-25s %s\n" "auto-updates:" "$(sudo systemctl is-active unattended-upgrades)"

    echo ""
    log_warn "PRÓXIMOS PASSOS MANUAIS:"
    echo ""
    echo "  1. SAIA E ENTRE DE NOVO via SSH (pra grupo 'docker' valer)"
    echo "     exit"
    echo "     ssh $USER@$(hostname -I | awk '{print $1}')"
    echo ""
    echo "  2. Testa Docker sem sudo:"
    echo "     docker run --rm hello-world"
    echo ""
    echo "  3. Adiciona chave SSH no GitHub (se gerou acima)"
    echo ""
    echo "  4. Instala Claude Code (precisa autenticação interativa):"
    echo "     sudo npm install -g @anthropic-ai/claude-code"
    echo "     claude"
    echo ""
    echo "  5. Cria estrutura do projeto:"
    echo "     curl -fsSL <url-do-setup-project.sh> -o setup.sh"
    echo "     chmod +x setup.sh"
    echo "     ./setup.sh"
    echo ""
}

# ────────────────────────────────────────────────────────────────────────────
# MAIN
# ────────────────────────────────────────────────────────────────────────────

main() {
    show_banner

    log_section "Validações iniciais"
    check_ubuntu_version
    check_not_root
    check_sudo
    check_internet

    confirm_execution

    step_update_system
    step_install_tools
    step_configure_ufw
    step_configure_fail2ban
    step_unattended_upgrades
    step_install_docker
    step_install_nodejs
    step_configure_git
    step_ssh_key

    show_summary
}

main "$@"
