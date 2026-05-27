# Biosnet Scripts

Scripts ops reusáveis pra preparar VPS Ubuntu e gerenciar projetos Docker.

Mantido por [biosnetworks](https://github.com/biosnetworks).

---

## 🚀 Quick start — do zero ao GitHub conectado em ~15 minutos

Numa VPS recém-instalada (só root, Ubuntu 22.04+ cru), execute as etapas em ordem:

```bash
# ETAPA 1 — Como ROOT: prepara o terreno (1 min)
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/prepare-vps.sh -o prep.sh
chmod +x prep.sh && ./prep.sh

# ETAPA 2 — Sai e loga como o usuário novo
exit
ssh <novo-usuario>@<IP-DA-VPS>

# ETAPA 3 — Como USUÁRIO: stack completa (5-10 min)
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/bootstrap-vps.sh -o bs.sh
chmod +x bs.sh && ./bs.sh

# ETAPA 4 — Sai e entra de novo (grupo docker valer)
exit
ssh <novo-usuario>@<IP-DA-VPS>
docker run --rm hello-world   # confirma docker sem sudo

# ETAPA 5 — Conecta GitHub (2 min)
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/setup-github.sh -o gh.sh
chmod +x gh.sh && ./gh.sh

# ETAPA 6 — Instala Claude Code (opcional, 2 min)
sudo npm install -g @anthropic-ai/claude-code
claude   # autentica pelo navegador

# ETAPA 7 — Cria projeto novo (30 seg)
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/setup-project.sh -o sp.sh
chmod +x sp.sh && ./sp.sh

# ETAPA 8 — Conecta projeto com GitHub (manual, 2 min)
cd /opt/<nome-do-projeto>
git remote add origin git@github.com:<seu-user>/<nome-do-projeto>.git
git push -u origin main
```

Resultado: VPS preparada, hardened, com Docker + Node + Git, conectada ao GitHub, com seu primeiro projeto rodando.

---

## 📋 Fluxo visual

```
ETAPA 0  VPS recém-instalada (só root)
    │
    ▼
ETAPA 1  prepare-vps.sh (como root) ............... 1 min
    │   • Atualiza pacotes essenciais
    │   • Cria usuário operacional não-root
    │   • Sudo + SSH key
    │
    ▼
ETAPA 2  Loga como novo usuário (ssh)
    │
    ▼
ETAPA 3  bootstrap-vps.sh (como usuário) .......... 5-10 min
    │   • Hardening (UFW + fail2ban + updates)
    │   • Docker + Compose
    │   • Node.js 20 LTS
    │   • Git configurado globalmente
    │   • Chave SSH ed25519 gerada
    │
    ▼
ETAPA 4  Sai e entra de novo (grupo docker valer)
    │
    ▼
ETAPA 5  setup-github.sh (como usuário) ........... 2 min
    │   • Detecta ou gera SSH key
    │   • Mostra chave pra colar no GitHub
    │   • Testa conexão SSH
    │
    ▼
ETAPA 6  Claude Code (opcional) ................... 2 min
    │   • Instala via npm global
    │   • Autentica pelo navegador
    │
    ▼
ETAPA 7  setup-project.sh (cria projeto) .......... 30 seg
    │   • Estrutura padrão em /opt/<nome>/
    │   • Git init + skill + CLAUDE.md
    │
    ▼
ETAPA 8  Conecta projeto com GitHub ............... 2 min
    │   • Cria repo no GitHub
    │   • git remote add + push
    │
    ▼
VPS PRONTA PRA USO ✓
```

---

## 📁 Estrutura do repositório

```
biosnet-scripts/
├── README.md                  ← este arquivo
├── .gitignore
│
├── vps/                       ← scripts de bootstrap e setup
│   ├── README.md
│   ├── prepare-vps.sh         ← ETAPA 1 (como root)
│   ├── bootstrap-vps.sh       ← ETAPA 3 (como usuário)
│   ├── setup-github.sh        ← ETAPA 5 (como usuário)
│   └── setup-project.sh       ← ETAPA 7 (como usuário)
│
├── docker/                    ← scripts de containers (em breve)
│   └── README.md
│
├── postgres/                  ← scripts de banco (em breve)
│   └── README.md
│
└── docs/                      ← guias de instalação detalhados
    ├── INSTALL-CLAUDE-CODE.md
    └── INSTALL-GIT.md
```

---

## 🎯 Scripts disponíveis

### `vps/prepare-vps.sh`

**Roda como:** `root`  
**Quando usar:** VPS recém-instalada, só com acesso root  
**Tempo:** ~1 minuto

Cria o usuário operacional não-root que você vai usar daqui pra frente.

- Atualiza pacotes essenciais (sudo, curl, vim, ssh)
- Cria usuário não-root (você define o nome)
- Adiciona ao grupo `sudo`
- Copia chave SSH do root (se houver)
- Ajusta `sshd_config` se necessário

### `vps/bootstrap-vps.sh`

**Roda como:** usuário não-root com sudo  
**Quando usar:** depois do `prepare-vps.sh`  
**Tempo:** ~5-10 minutos

Instala e configura toda a stack de infraestrutura.

- Atualiza sistema (`apt upgrade`)
- Ferramentas essenciais (ufw, fail2ban, htop, ncdu, tmux, jq, rsync)
- Firewall UFW (libera apenas 22, 80, 443)
- fail2ban com proteção SSH
- Atualizações automáticas de segurança
- Docker oficial + Docker Compose
- Adiciona usuário ao grupo `docker`
- Node.js 20 LTS
- Git configurado globalmente (interativo)
- Chave SSH ed25519 (opcional)

### `vps/setup-github.sh`

**Roda como:** usuário não-root  
**Quando usar:** depois do `bootstrap-vps.sh`  
**Tempo:** ~2 minutos

Conecta sua VPS ao GitHub via SSH.

- Detecta ou gera chave SSH ed25519
- Mostra a chave pública pra você colar em github.com/settings/keys
- Aguarda você adicionar
- Testa conexão (`ssh -T git@github.com`)
- Mostra próximos passos

### `vps/setup-project.sh`

**Roda como:** usuário não-root  
**Quando usar:** quando quiser criar um projeto novo  
**Tempo:** ~30 segundos

Cria a estrutura padrão de projeto Docker em `/opt/<nome>/`.

- Estrutura de pastas: api/, worker/, webhook/, frontend/, db/migrations/, caddy/, scripts/, docs/, volumes/
- `.gitignore` completo
- `.env.example` template
- `README.md` com info do projeto
- `CLAUDE.md` template (memória institucional pro Claude Code)
- Skill local em `.claude/skills/<nome>-ops/SKILL.md`
- Git init + branch main + primeiro commit
- Docs placeholders (DEPLOY, RUNBOOK, ARCHITECTURE)

---

## 💡 Princípios de design

Todo script nesse repositório segue:

### Idempotência

Pode rodar 100x, mesmo resultado, sem quebrar. O script detecta o que já está feito:

- Docker já instalado? Pula.
- Usuário já existe? Pula criação.
- Já está no grupo sudo? Não duplica.
- Skill já existe? Preserva.

### Validação antes de agir

Cada script verifica pré-requisitos no início:

- **prepare-vps.sh**: precisa ser root, Ubuntu LTS, internet
- **bootstrap-vps.sh**: NÃO pode ser root, precisa sudo, internet
- **setup-github.sh**: precisa Git instalado e configurado
- **setup-project.sh**: precisa Docker e Git instalados

### Logging colorido e estruturado

```
[INFO]    Mensagens informativas
[OK]      Operações bem-sucedidas
[WARN]    Avisos não-críticos
[ERROR]   Erros que param a execução
```

Cabeçalhos de seção facilitam o acompanhamento:

```
════════════════════════════════════════════════════════════════
  3/8  Configurando firewall (UFW)
════════════════════════════════════════════════════════════════
```

### Confirmação antes de operações destrutivas

```bash
read -rp "Vai resetar configuração X. Continuar? [s/N] " resp
```

### Não-destrutivo por padrão

Faz backup com timestamp antes de sobrescrever configs:

```bash
sudo cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak.$(date +%Y%m%d_%H%M%S)
```

### `set -euo pipefail` no topo de todo `.sh`

- `-e`: para na primeira falha
- `-u`: erro se usar variável não definida
- `-o pipefail`: falha de pipe propaga

---

## 🤔 Por que esses scripts funcionam sem Git instalado?

`curl` vem por padrão no Ubuntu, mas Git **não**. Como então o primeiro script chega na VPS?

Resposta: `raw.githubusercontent.com` é um **CDN HTTP simples** que serve arquivos de repos públicos. Não exige Git, não exige autenticação. É a mesma coisa que clicar em "Raw" no GitHub.

Por isso este repositório é **público** — ele é o "ovo" que precede a "galinha" (Git instalado).

Repositórios com código de negócio devem ser **privados**, mas os de bootstrap precisam ser públicos pra funcionar.

---

## 📚 Documentação

- **[Setup completo de VPS](vps/README.md)** — detalhes de cada etapa
- **[Instalação Git + GitHub](docs/INSTALL-GIT.md)** — passo a passo manual (referência)
- **[Instalação Claude Code](docs/INSTALL-CLAUDE-CODE.md)** — IA de pair-programming na VPS

---

## 🗺️ Roadmap

### Em produção ✅

- `vps/prepare-vps.sh` — pré-bootstrap (cria usuário)
- `vps/bootstrap-vps.sh` — stack completa
- `vps/setup-github.sh` — conecta GitHub
- `vps/setup-project.sh` — cria projeto novo

### Planejado ⏳

#### VPS
- `vps/harden-ssh.sh` — desabilita senha SSH (só permite chave)
- `vps/add-swap.sh` — adiciona arquivo de swap em VPS pequenas
- `vps/rotate-logs.sh` — configura logrotate pra logs do Docker
- `vps/change-hostname.sh` — muda hostname de forma idempotente

#### Docker
- `docker/cleanup.sh` — remove containers parados + imagens dangling
- `docker/backup-volumes.sh` — tar.gz de volumes pra `/opt/backups/`
- `docker/healthcheck-all.sh` — verifica saúde de todos os containers
- `docker/prune-safe.sh` — `docker system prune` com confirmação

#### Postgres
- `postgres/backup-all.sh` — `pg_dump` de todos os bancos em containers
- `postgres/restore.sh` — restore interativo a partir de dump
- `postgres/vacuum.sh` — manutenção periódica
- `postgres/check-bloat.sh` — diagnóstico de tabelas inchadas

#### Monitoring
- `monitoring/disk-alert.sh` — alerta de disco >80% via webhook
- `monitoring/container-health.sh` — alerta containers caídos

---

## 🤝 Contribuindo

Esses scripts evoluem com os aprendizados. Pra contribuir:

1. **Fork ou clone**: `git clone git@github.com:biosnetworks/biosnet-scripts.git`
2. **Cria branch**: `git checkout -b feat/novo-script`
3. **Segue os princípios**: idempotência, validações, logging colorido, `set -euo pipefail`
4. **Atualiza o README** da pasta correspondente
5. **Testa idempotência**: roda 2x sem quebrar
6. **Commit com Conventional Commits**:
   - `feat(vps): adiciona harden-ssh.sh`
   - `fix(bootstrap): corrige detecção de SSH key`
   - `docs: atualiza README com novo fluxo`
7. **Push + Pull Request**

---

## 📜 Licença

MIT — use, modifique, distribua livremente.

---

## ❓ FAQ

### Posso usar em VPS de outros provedores?

Sim. Funciona em qualquer Ubuntu LTS 22.04+ de qualquer provedor: Hostinger, Hetzner, DigitalOcean, AWS EC2, Google Cloud, Oracle Cloud, Azure, etc.

### Funciona em ARM (Raspberry Pi, AWS Graviton)?

Os scripts são compatíveis com ARM64 e AMD64. Docker e Node 20 LTS têm builds pra ambos.

### Posso adaptar pra Debian?

A maioria funciona, mas alguns detalhes mudam (nome de pacote, versão do unattended-upgrades). Não foi testado oficialmente em Debian — abra issue se for testar.

### Por que não usar Ansible/Terraform?

Pra projeto solo ou time pequeno, shell scripts no GitHub fazem 80% do que essas ferramentas fazem, com 10% da complexidade. Quando o time crescer ou a infra complexificar, vale migrar pra Ansible. Por enquanto, simplicidade vence.

### Posso rodar tudo de uma vez em um comando?

Tecnicamente sim, mas **não recomendo**:

```bash
# NÃO faz isso na primeira vez:
curl -fsSL .../prepare-vps.sh | bash && exit  # perde a sessão!
```

A separação em etapas é proposital — você precisa fazer **logout/login** entre prepare e bootstrap pra o usuário novo ser usado, e entre bootstrap e setup-github pra grupo docker valer.

### Esqueci a senha do usuário criado, e agora?

Como root (sessão de backup que você não fechou):

```bash
passwd alexandreluna
```

Define nova senha. Anota num gerenciador.

### Posso usar esses scripts em produção real?

Sim, mas com responsabilidade:
- Sempre lê o script antes de rodar (use `less script.sh`)
- Testa em VPS de staging primeiro
- Tem backup antes de mexer em prod
- Revisa o `git log` do repositório pra ver mudanças recentes
  
