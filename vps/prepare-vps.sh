#!/usr/bin/env bash
#
# prepare-vps.sh
# ────────────────────────────────────────────────────────────────────────────
# Pré-bootstrap de VPS Ubuntu (qualquer versão LTS recente).
#
# Este script é o "ovo" que precede o "galinha" (bootstrap-vps.sh).
# Roda como ROOT em uma VPS recém-instalada e prepara o terreno:
#
#   1. Atualiza pacotes básicos (sudo, curl, vim, ssh)
#   2. Cria usuário operacional não-root
#   3. Adiciona usuário ao grupo sudo
#   4. Copia chave SSH do root pro novo usuário (se existir)
#   5. Permite SSH desse usuário (sshd config check)
#   6. Mostra instruções claras pro próximo passo
#
# Pré-requisitos:
#   - Ubuntu 22.04 LTS ou 24.04 LTS
#   - Acesso como ROOT (geralmente é só o que tem em VPS nova)
#   - Acesso à internet
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/prepare-vps.sh -o prep.sh
#   chmod +x prep.sh
#   ./prep.sh
#
# DEPOIS:
#   1. Sair como root
#   2. Logar com o usuário novo
#   3. Rodar bootstrap-vps.sh
#
# É IDEMPOTENTE: pode rodar várias vezes sem problemas.
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
# CONFIG (perguntada interativamente)
# ────────────────────────────────────────────────────────────────────────────

NEW_USER=""
SSH_FROM_ROOT="no"
HAS_ROOT_SSH_KEY="no"

# ────────────────────────────────────────────────────────────────────────────
# VALIDAÇÕES INICIAIS
# ────────────────────────────────────────────────────────────────────────────

check_is_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script DEVE ser executado como root."
        log_error "Use: sudo ./prepare-vps.sh   ou   logue como root."
        echo ""
        log_info "Esse é o script de PRÉ-bootstrap (roda como root)."
        log_info "Depois dele, você roda o bootstrap-vps.sh como usuário comum."
        exit 1
    fi
    log_ok "Executando como root."
}

check_ubuntu() {
    if ! [[ -f /etc/os-release ]]; then
        log_error "Não foi possível detectar o SO. Esperado: Ubuntu 22.04 ou 24.04."
        exit 1
    fi

    local distro version
    distro=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    version=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)

    if [[ "$distro" != "ubuntu" ]]; then
        log_warn "Distro detectada: $distro (esperado: ubuntu)"
        read -rp "Continuar mesmo assim? [s/N] " resp
        [[ ! "$resp" =~ ^[sS]$ ]] && exit 1
    fi

    case "$version" in
        22.04|24.04)
            log_ok "Ubuntu $version detectado (LTS suportado)."
            ;;
        *)
            log_warn "Ubuntu $version não está na lista de testados (22.04, 24.04)."
            read -rp "Continuar mesmo assim? [s/N] " resp
            [[ ! "$resp" =~ ^[sS]$ ]] && exit 1
            ;;
    esac
}

check_internet() {
    if ! curl -fsSL --max-time 5 https://1.1.1.1 >/dev/null 2>&1; then
        log_error "Sem internet. Verifique conexão."
        exit 1
    fi
    log_ok "Internet OK."
}

detect_root_ssh_key() {
    if [[ -f /root/.ssh/authorized_keys ]] && [[ -s /root/.ssh/authorized_keys ]]; then
        HAS_ROOT_SSH_KEY="yes"
        log_ok "Chave SSH detectada em /root/.ssh/authorized_keys"
    else
        log_info "Sem chave SSH no /root (login deve ser por senha)."
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# BANNER E APRESENTAÇÃO
# ────────────────────────────────────────────────────────────────────────────

show_banner() {
    cat <<'EOF'

   ╔══════════════════════════════════════════════════════════╗
   ║                                                          ║
   ║      VPS Prepare (Pré-Bootstrap)                         ║
   ║                                                          ║
   ║      Cria usuário operacional + sudo + SSH key           ║
   ║                                                          ║
   ║      Roda COMO ROOT em VPS recém-instalada               ║
   ║                                                          ║
   ╚══════════════════════════════════════════════════════════╝

EOF
}

show_intro() {
    cat <<EOF
${BOLD}O que este script faz:${NC}

  1. Atualiza pacotes do sistema
  2. Instala ferramentas básicas (sudo, curl, vim, openssh-server)
  3. Cria um usuário operacional novo (você define o nome)
  4. Adiciona o usuário ao grupo 'sudo' (permite usar sudo)
  5. Copia sua chave SSH do root pro novo usuário (se houver)
  6. Mostra próximos passos

${BOLD}Por que isso é necessário?${NC}

  Em VPS recém-instaladas (Hostinger, Locaweb, Hostgator, etc.) você
  só tem acesso root. Mas o script bootstrap-vps.sh PRECISA rodar com
  usuário não-root (segurança). Este script faz a ponte.

${BOLD}O que acontece DEPOIS:${NC}

  1. Você sai do terminal root
  2. Loga via SSH com o usuário novo
  3. Roda o bootstrap-vps.sh (instala Docker, Node, etc.)
  4. VPS pronta pra produção

EOF
}

confirm_execution() {
    read -rp "Continuar? [S/n] " resp
    if [[ "$resp" =~ ^[nN]$ ]]; then
        log_info "Cancelado pelo usuário."
        exit 0
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 1 — DADOS DO USUÁRIO
# ────────────────────────────────────────────────────────────────────────────

prompt_user_info() {
    log_section "1/5  Dados do novo usuário"

    while [[ -z "$NEW_USER" ]]; do
        read -rp "Nome do usuário operacional (ex: alexandreluna, deploy, ops): " NEW_USER

        # Validações de nome de usuário Linux
        if [[ ! "$NEW_USER" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
            log_error "Nome inválido. Use só letras minúsculas, números, hífen e underline."
            log_error "Deve começar com letra. Máximo 32 caracteres."
            NEW_USER=""
            continue
        fi

        # Reservados
        if [[ "$NEW_USER" == "root" ]] || [[ "$NEW_USER" == "admin" ]]; then
            log_error "Não use '$NEW_USER' (nome reservado/perigoso)."
            NEW_USER=""
            continue
        fi

        # Confirmação
        echo ""
        log_info "Usuário a criar: $NEW_USER"
        log_info "Home será: /home/$NEW_USER"
        read -rp "Confirma? [S/n] " resp
        if [[ "$resp" =~ ^[nN]$ ]]; then
            NEW_USER=""
        fi
    done

    # Pergunta sobre SSH key
    if [[ "$HAS_ROOT_SSH_KEY" == "yes" ]]; then
        echo ""
        log_info "Detectei chave SSH em /root/.ssh/authorized_keys"
        read -rp "Copiar essa chave pro novo usuário também? [S/n] " resp
        if [[ ! "$resp" =~ ^[nN]$ ]]; then
            SSH_FROM_ROOT="yes"
        fi
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 2 — ATUALIZAÇÃO DE PACOTES BÁSICOS
# ────────────────────────────────────────────────────────────────────────────

step_update_packages() {
    log_section "2/5  Atualizando pacotes básicos"

    log_info "apt update..."
    apt-get update -qq

    log_info "Instalando pacotes essenciais (sudo, curl, vim, ssh)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        sudo \
        curl \
        wget \
        vim \
        nano \
        openssh-server \
        ca-certificates \
        gnupg

    # Garante SSH ligado (algumas VPS minimalistas não vêm com ele ativo)
    systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true
    systemctl start ssh >/dev/null 2>&1 || systemctl start sshd >/dev/null 2>&1 || true

    log_ok "Pacotes básicos OK."
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 3 — CRIAÇÃO DO USUÁRIO
# ────────────────────────────────────────────────────────────────────────────

step_create_user() {
    log_section "3/5  Criando usuário '$NEW_USER'"

    if id "$NEW_USER" >/dev/null 2>&1; then
        log_warn "Usuário '$NEW_USER' já existe. Pulando criação."
    else
        log_info "Criando usuário (você vai definir senha)..."
        # adduser interativo — pede senha e info básica
        adduser --gecos "" "$NEW_USER"
        log_ok "Usuário '$NEW_USER' criado."
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 4 — SUDO
# ────────────────────────────────────────────────────────────────────────────

step_add_sudo() {
    log_section "4/5  Adicionando '$NEW_USER' ao grupo sudo"

    if groups "$NEW_USER" | grep -q '\bsudo\b'; then
        log_warn "Já está no grupo sudo."
    else
        usermod -aG sudo "$NEW_USER"
        log_ok "Adicionado ao grupo sudo."
    fi

    log_info "Grupos de '$NEW_USER':"
    groups "$NEW_USER" | sed 's/^/        /'
}

# ────────────────────────────────────────────────────────────────────────────
# ETAPA 5 — CHAVE SSH
# ────────────────────────────────────────────────────────────────────────────

step_copy_ssh_key() {
    log_section "5/5  Configurando SSH"

    local user_ssh="/home/$NEW_USER/.ssh"

    # Cria diretório .ssh com permissões corretas (sempre, mesmo sem chave)
    if [[ ! -d "$user_ssh" ]]; then
        mkdir -p "$user_ssh"
        log_info "Criado $user_ssh"
    fi

    if [[ "$SSH_FROM_ROOT" == "yes" ]]; then
        log_info "Copiando authorized_keys do root..."
        cp /root/.ssh/authorized_keys "$user_ssh/authorized_keys"
        log_ok "Chave SSH copiada."
    else
        log_info "Pulando cópia de chave SSH (login será por senha)."
        # Cria authorized_keys vazio pra o diretório fazer sentido
        touch "$user_ssh/authorized_keys"
    fi

    # Permissões críticas
    chown -R "$NEW_USER:$NEW_USER" "$user_ssh"
    chmod 700 "$user_ssh"
    chmod 600 "$user_ssh/authorized_keys"

    log_ok "Permissões corretas em $user_ssh"

    # Garante que SSH permite o usuário
    check_sshd_config
}

check_sshd_config() {
    local sshd_config="/etc/ssh/sshd_config"

    # Se tiver AllowUsers configurado, adiciona o novo usuário
    if grep -qE '^AllowUsers' "$sshd_config" 2>/dev/null; then
        if ! grep -qE "^AllowUsers.*\b$NEW_USER\b" "$sshd_config"; then
            log_warn "AllowUsers existe mas não inclui $NEW_USER. Adicionando..."
            sed -i "s/^AllowUsers/AllowUsers $NEW_USER/" "$sshd_config"
            systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
            log_ok "AllowUsers atualizado, SSH reiniciado."
        fi
    fi

    # Verifica se PasswordAuthentication está habilitado (se for sem SSH key)
    if [[ "$SSH_FROM_ROOT" == "no" ]]; then
        if grep -qE '^PasswordAuthentication\s+no' "$sshd_config"; then
            log_warn "PasswordAuthentication está 'no' no sshd_config."
            log_warn "Como você não copiou chave SSH, o login com senha PRECISA estar habilitado."
            read -rp "Habilitar PasswordAuthentication? [S/n] " resp
            if [[ ! "$resp" =~ ^[nN]$ ]]; then
                sed -i 's/^PasswordAuthentication\s\+no/PasswordAuthentication yes/' "$sshd_config"
                systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
                log_ok "PasswordAuthentication habilitado, SSH reiniciado."
            fi
        fi
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# RESUMO E PRÓXIMOS PASSOS
# ────────────────────────────────────────────────────────────────────────────

show_summary() {
    local public_ip
    public_ip=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || echo "N/A")

    log_section "✓  Pré-bootstrap concluído!"

    echo "Estado atual:"
    echo ""
    printf "  %-22s %s\n" "Hostname:"      "$(hostname)"
    printf "  %-22s %s\n" "IP público:"    "$public_ip"
    printf "  %-22s %s\n" "OS:"            "$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    printf "  %-22s %s\n" "Usuário criado:" "$NEW_USER"
    printf "  %-22s %s\n" "Grupos:"         "$(groups "$NEW_USER" | cut -d: -f2)"

    if [[ "$SSH_FROM_ROOT" == "yes" ]]; then
        printf "  %-22s %s\n" "SSH key:"    "Copiada do root ✓"
    else
        printf "  %-22s %s\n" "SSH key:"    "Não copiada (login por senha)"
    fi

    echo ""
    echo -e "${BOLD}${YELLOW}═══════════════ PRÓXIMOS PASSOS ═══════════════${NC}"
    echo ""
    echo -e "${BOLD}1.${NC} Em OUTRO terminal do seu PC, teste o login do novo usuário:"
    echo ""
    echo -e "   ${CYAN}ssh $NEW_USER@$public_ip${NC}"
    echo ""
    echo "   (vai pedir a senha que você acabou de definir)"
    echo ""
    echo -e "${BOLD}2.${NC} Quando logar como $NEW_USER, teste o sudo:"
    echo ""
    echo -e "   ${CYAN}sudo whoami${NC}"
    echo ""
    echo "   (vai pedir senha de novo, deve retornar 'root')"
    echo ""
    echo -e "${BOLD}3.${NC} SE TUDO FUNCIONOU, rode o bootstrap-vps.sh:"
    echo ""
    echo -e "   ${CYAN}curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/bootstrap-vps.sh -o bs.sh${NC}"
    echo -e "   ${CYAN}chmod +x bs.sh${NC}"
    echo -e "   ${CYAN}./bs.sh${NC}"
    echo ""
    echo -e "${BOLD}${RED}IMPORTANTE:${NC}"
    echo "   • NÃO feche esta sessão root ainda"
    echo "   • Mantenha aberta como BACKUP até confirmar que o novo usuário loga"
    echo "   • Se o login do novo usuário falhar, volta aqui e me chama"
    echo ""
    echo -e "${BOLD}${YELLOW}═════════════════════════════════════════════════${NC}"
    echo ""
}

# ────────────────────────────────────────────────────────────────────────────
# MAIN
# ────────────────────────────────────────────────────────────────────────────

main() {
    show_banner

    log_section "Validações iniciais"
    check_is_root
    check_ubuntu
    check_internet
    detect_root_ssh_key

    show_intro
    confirm_execution

    prompt_user_info
    step_update_packages
    step_create_user
    step_add_sudo
    step_copy_ssh_key

    show_summary
}

main "$@"
