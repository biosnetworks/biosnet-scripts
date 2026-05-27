#!/usr/bin/env bash
#
# bootstrap-vps.sh
# ────────────────────────────────────────────────────────────────────────────
# Bootstrap de VPS Ubuntu LTS (22.04 ou 24.04)
#
# v3 - Correção do bug de leitura de stdin (lia "lixo" e abortava sem motivo).
#      Agora lê DIRETO de /dev/tty e sanitiza inputs.
#
# Pré-requisitos:
#   - Ubuntu 22.04 ou 24.04 LTS
#   - Usuário NÃO-ROOT com sudo (use prepare-vps.sh antes se não tiver)
#   - Acesso à internet
#
# Uso CORRETO:
#   curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/bootstrap-vps.sh -o bs.sh
#   chmod +x bs.sh
#   ./bs.sh
#
# É IDEMPOTENTE: pode ser rodado várias vezes sem causar problemas.
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

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
# HELPER: ask_yes_no - lê resposta s/n direto de /dev/tty
# ────────────────────────────────────────────────────────────────────────────

ask_yes_no() {
    local prompt="$1"
    local default="${2:-N}"
    local resp=""

    if [[ -r /dev/tty ]]; then
        read -rp "$prompt" resp < /dev/tty
    else
        read -rp "$prompt" resp
    fi

    resp="${resp//$'\r'/}"
    resp="${resp//$'\n'/}"
    resp="${resp// /}"
    resp="${resp:0:1}"

    [[ -z "$resp" ]] && resp="$default"

    if [[ "$resp" =~ ^[sSyY]$ ]]; then
        return 0
    else
        return 1
    fi
}

read_input() {
    local prompt="$1"
    local var_name="$2"
    local input=""

    if [[ -r /dev/tty ]]; then
        read -rp "$prompt" input < /dev/tty
    else
        read -rp "$prompt" input
    fi

    input="${input//$'\r'/}"
    input="${input//$'\n'/}"

    printf -v "$var_name" '%s' "$input"
}

# ────────────────────────────────────────────────────────────────────────────
# VALIDAÇÕES INICIAIS
# ────────────────────────────────────────────────────────────────────────────

check_ubuntu_version() {
    if ! [[ -f /etc/os-release ]]; then
        log_error "Não foi possível detectar o SO. Esperado: Ubuntu 22.04 ou 24.04."
        exit 1
    fi

    local version distro
    version=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)
    distro=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')

    if [[ "$distro" != "ubuntu" ]]; then
        log_warn "Distro detectada: $distro (esperado: ubuntu)"
        if ! ask_yes_no "Continuar mesmo assim? [s/N] "; then
            log_info "Cancelado pelo usuário."
            exit 0
        fi
        return 0
    fi

    case "$version" in
        22.04)
            log_ok "Ubuntu $version LTS detectado (suportado)."
            ;;
        24.04)
            log_ok "Ubuntu $version LTS detectado (suportado, recomendado)."
            ;;
        *)
            log_warn "Ubuntu $version não é LTS testada (suportadas: 22.04, 24.04)."
            if ! ask_yes_no "Continuar mesmo assim? [s/N] "; then
                log_info "Cancelado pelo usuário."
                exit 0
            fi
            ;;
    esac
}

check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "NÃO execute como root."
        log_error "Use um usuário comum com sudo. Se a VPS só tem root,"
        log_error "rode primeiro o prepare-vps.sh."
        exit 1
    fi
    log_ok "Executando como usuário '$USER' (não-root)."
}

check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_info "Este script precisa de sudo. Pode ser solicitado pela senha."
        if ! sudo true; then
            log_error "Falha ao obter sudo."
            exit 1
        fi
    fi
    log_ok "Sudo disponível."
}

check_internet() {
    if ! curl -fsSL --max-time 5 https://1.1.1.1 >/dev/null 2>&1; then
        log_error "Sem internet."
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
   ║      VPS Bootstrap - Ubuntu LTS (22.04 / 24.04)          ║
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
    if ! ask_yes_no "Continuar? [s/N] "; then
        log_info "Cancelado pelo usuário."
        exit 0
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPAS DE INSTALAÇÃO
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

step_install_tools() {
    log_section "2/8  Instalando ferramentas essenciais"
    local packages=(
        ufw fail2ban
        unattended-upgrades apt-listchanges
        ca-certificates curl wget
        git vim nano tmux screen
        htop ncdu jq
        net-tools dnsutils
        build-essential software-properties-common
        gnupg lsb-release
        zip unzip rsync
    )
    log_info "Instalando ${#packages[@]} pacotes..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"
    log_ok "Ferramentas instaladas."
}

step_configure_ufw() {
    log_section "3/8  Configurando firewall (UFW)"
    sudo ufw --force reset >/dev/null 2>&1
    sudo ufw default deny incoming >/dev/null
    sudo ufw default allow outgoing >/dev/null
    sudo ufw allow 22/tcp comment 'SSH' >/dev/null
    sudo ufw allow 80/tcp comment 'HTTP' >/dev/null
    sudo ufw allow 443/tcp comment 'HTTPS' >/dev/null
    sudo ufw --force enable >/dev/null
    log_ok "Firewall ativo."
    sudo ufw status verbose
}

step_configure_fail2ban() {
    log_section "4/8  Configurando fail2ban"
    if [[ -f /etc/fail2ban/jail.local ]]; then
        sudo cp /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    local backend="systemd"
    local ubuntu_version
    ubuntu_version=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)
    [[ "$ubuntu_version" == "22.04" ]] && backend="auto"

    sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = $backend

[sshd]
enabled  = true
port     = 22
filter   = sshd
maxretry = 3
EOF

    sudo systemctl enable fail2ban >/dev/null 2>&1
    sudo systemctl restart fail2ban
    sleep 2
    log_ok "fail2ban configurado (backend: $backend)."
}

step_unattended_upgrades() {
    log_section "5/8  Atualizações automáticas de segurança"
    sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    sudo systemctl enable unattended-upgrades >/dev/null 2>&1
    sudo systemctl restart unattended-upgrades
    log_ok "Atualizações automáticas ativadas."
}

step_install_docker() {
    log_section "6/8  Instalando Docker"
    if command -v docker >/dev/null 2>&1; then
        log_ok "Docker já instalado: $(docker --version)"
    else
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sudo sh /tmp/get-docker.sh >/dev/null 2>&1
        rm /tmp/get-docker.sh
        log_ok "Docker instalado: $(docker --version)"
    fi

    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        log_warn "SAIA E LOGUE DE NOVO para o grupo 'docker' valer."
    else
        log_ok "$USER já está no grupo 'docker'."
    fi

    sudo systemctl enable docker >/dev/null 2>&1

    if docker compose version >/dev/null 2>&1; then
        log_ok "Docker Compose: $(docker compose version | head -1)"
    fi
}

step_install_nodejs() {
    log_section "7/8  Instalando Node.js 20 LTS"
    if command -v node >/dev/null 2>&1; then
        local current_version
        current_version=$(node --version)
        if [[ "$current_version" == v20.* ]]; then
            log_ok "Node.js 20 já instalado: $current_version"
            return
        fi
    fi
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null 2>&1
    sudo apt-get install -y -qq nodejs
    log_ok "Node.js: $(node --version)"
    log_ok "npm:     $(npm --version)"
}

step_configure_git() {
    log_section "8/8  Configurando Git (global)"

    local current_name current_email
    current_name=$(git config --global user.name 2>/dev/null || echo "")
    current_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -n "$current_name" && -n "$current_email" ]]; then
        log_ok "Git já configurado:"
        echo "       user.name:  $current_name"
        echo "       user.email: $current_email"
        if ! ask_yes_no "Deseja reconfigurar? [s/N] "; then
            configure_git_defaults
            return
        fi
    fi

    local git_name git_email
    read_input "Git user.name (ex: 'seuusuario'): " git_name
    read_input "Git user.email (use o do GitHub): " git_email

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

step_ssh_key() {
    log_section "OPCIONAL  Gerar chave SSH para GitHub"

    local ssh_key="$HOME/.ssh/id_ed25519"

    if [[ -f "$ssh_key" ]]; then
        log_ok "Chave SSH já existe: $ssh_key"
        echo ""
        log_info "Chave PÚBLICA (cole no GitHub):"
        cat "$ssh_key.pub"
        echo ""
        return
    fi

    if ! ask_yes_no "Gerar chave SSH ed25519 agora? [S/n] " "S"; then
        log_info "Pulado. Use o setup-github.sh depois."
        return
    fi

    local git_email
    git_email=$(git config --global user.email 2>/dev/null || echo "")

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$git_email" -f "$ssh_key" -N "" >/dev/null

    chmod 600 "$ssh_key"
    chmod 644 "$ssh_key.pub"

    log_ok "Chave gerada."
    echo ""
    log_info "═══ COPIE A CHAVE PÚBLICA ═══"
    cat "$ssh_key.pub"
    log_info "═══ FIM DA CHAVE ═══"
    echo ""
}

show_summary() {
    log_section "✓  Bootstrap concluído!"

    echo "Estado da VPS:"
    echo ""
    printf "  %-25s %s\n" "Usuário:"      "$USER"
    printf "  %-25s %s\n" "Hostname:"     "$(hostname)"
    printf "  %-25s %s\n" "IP público:"   "$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || echo 'N/A')"
    printf "  %-25s %s\n" "OS:"           "$(lsb_release -ds 2>/dev/null || echo 'N/A')"
    echo ""
    echo "Software instalado:"
    echo ""
    printf "  %-25s %s\n" "Docker:"         "$(docker --version 2>/dev/null || echo 'N/A')"
    printf "  %-25s %s\n" "Docker Compose:" "$(docker compose version 2>/dev/null | head -1 || echo 'N/A')"
    printf "  %-25s %s\n" "Node.js:"        "$(node --version 2>/dev/null || echo 'N/A')"
    printf "  %-25s %s\n" "Git:"            "$(git --version 2>/dev/null || echo 'N/A')"
    echo ""
    echo "Segurança:"
    echo ""
    printf "  %-25s %s\n" "UFW:"        "$(sudo ufw status | head -1)"
    printf "  %-25s %s\n" "fail2ban:"   "$(sudo systemctl is-active fail2ban)"

    echo ""
    log_warn "PRÓXIMOS PASSOS:"
    echo ""
    echo "  1. SAIA E ENTRE DE NOVO via SSH (grupo docker):"
    echo "     exit && ssh $USER@$(hostname -I | awk '{print $1}')"
    echo ""
    echo "  2. Teste Docker sem sudo:"
    echo "     docker run --rm hello-world"
    echo ""
    echo "  3. Conecte ao GitHub:"
    echo "     curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/setup-github.sh -o gh.sh"
    echo "     chmod +x gh.sh && ./gh.sh"
    echo ""
}

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
