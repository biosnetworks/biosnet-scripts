# Scripts VPS

Scripts pra preparar e configurar VPS Ubuntu LTS (22.04 e 24.04).

> 📖 **Veja o [README principal](../README.md)** pra contexto geral do repositório e o fluxo completo de 8 etapas.

---

## 📋 Scripts desta pasta

Esta pasta contém **4 scripts** que cobrem todo o ciclo de preparação de VPS:

| Ordem | Script | Roda como | Tempo | O que faz |
|---|---|---|---|---|
| 1 | `prepare-vps.sh` | root | 1 min | Cria usuário operacional não-root |
| 2 | `bootstrap-vps.sh` | usuário | 5-10 min | Instala Docker + Node + Git + hardening |
| 3 | `setup-github.sh` | usuário | 2 min | Configura SSH e conecta com GitHub |
| 4 | `setup-project.sh` | usuário | 30 seg | Cria estrutura de projeto novo em /opt/ |

---

## 🔧 prepare-vps.sh

**Roda como:** `root`  
**Pré-requisito:** VPS recém-instalada com Ubuntu 22.04 ou 24.04, acesso root

### O que faz

1. Valida que está rodando como root
2. Verifica versão do Ubuntu
3. Confirma acesso à internet
4. Atualiza pacotes essenciais (`apt update && upgrade`)
5. Instala ferramentas mínimas: `sudo`, `curl`, `wget`, `vim`, `nano`, `openssh-server`
6. Pergunta nome do usuário operacional (valida formato)
7. Cria o usuário e pede senha
8. Adiciona ao grupo `sudo`
9. Cria `/home/<user>/.ssh/` com permissões corretas
10. Se detectar chave SSH em `/root/.ssh/authorized_keys`, oferece copiar
11. Ajusta `sshd_config` se tiver `AllowUsers` restritivo
12. Mostra próximos passos

### Como usar

```bash
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/prepare-vps.sh -o prep.sh
chmod +x prep.sh
./prep.sh
```

### Após executar

```bash
# Sai como root
exit

# Loga com o novo usuário (em outro terminal, mantém root como backup)
ssh <novo-usuario>@<IP-DA-VPS>

# Testa que sudo funciona
sudo whoami   # deve retornar 'root'
```

---

## 🛠️ bootstrap-vps.sh

**Roda como:** usuário não-root com sudo  
**Pré-requisito:** `prepare-vps.sh` executado (ou usuário não-root com sudo já existe)

### O que faz

#### 1. Validações iniciais
- Verifica que NÃO está rodando como root
- Verifica Ubuntu LTS
- Confirma sudo disponível
- Confirma internet

#### 2. Atualização do sistema
- `apt update && apt upgrade -y`
- Usa `DEBIAN_FRONTEND=noninteractive` pra evitar prompts

#### 3. Ferramentas essenciais
Instala ~20 pacotes que cobrem 95% das necessidades:
- `ufw`, `fail2ban` — segurança
- `unattended-upgrades` — updates automáticos
- `curl`, `wget`, `git`, `vim`, `nano` — básicos
- `htop`, `ncdu`, `jq` — diagnóstico
- `tmux`, `screen` — sessões persistentes
- `net-tools`, `dnsutils` — rede
- `build-essential` — compiladores (npm precisa)
- `zip`, `unzip`, `rsync` — utilitários

#### 4. Firewall UFW
- Reseta regras
- Default: deny incoming, allow outgoing
- Abre apenas: 22/tcp (SSH), 80/tcp (HTTP), 443/tcp (HTTPS)
- Ativa o UFW

#### 5. fail2ban
- Cria `/etc/fail2ban/jail.local` com:
  - `bantime = 1h`
  - `findtime = 10m`
  - `maxretry = 3` para SSH
- Habilita e inicia o serviço
- Faz backup se já existir config

#### 6. Atualizações automáticas
- Configura `/etc/apt/apt.conf.d/20auto-upgrades`
- Habilita `unattended-upgrades`
- Apenas updates de segurança (sem dist-upgrade automático)

#### 7. Docker
- Baixa script oficial: `https://get.docker.com`
- Instala Docker Engine + Compose plugin
- Adiciona usuário atual ao grupo `docker`
- Habilita Docker no boot

#### 8. Node.js 20 LTS
- Adiciona repositório NodeSource
- Instala `nodejs` (inclui npm)
- Confere versões

#### 9. Configuração do Git
- Pergunta `user.name` e `user.email` (interativo)
- Define `init.defaultBranch = main`
- Define `push.default = current`
- Define `pull.rebase = false`
- Define cores e editor padrão

#### 10. Chave SSH (opcional)
- Pergunta se quer gerar `~/.ssh/id_ed25519`
- Sem passphrase (apropriado pra VPS dedicada)
- Mostra a chave pública pra adicionar no GitHub depois

### Como usar

```bash
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/bootstrap-vps.sh -o bs.sh
chmod +x bs.sh
./bs.sh
```

### Após executar

```bash
# Sai e entra de novo (necessário pro grupo docker valer)
exit
ssh <usuario>@<IP-DA-VPS>

# Testa Docker sem sudo
docker run --rm hello-world

# Testa outras ferramentas
node --version
git --version
sudo ufw status
sudo fail2ban-client status sshd
```

---

## 🔗 setup-github.sh

**Roda como:** usuário não-root  
**Pré-requisito:** Git instalado e configurado (vem do `bootstrap-vps.sh`)

### O que faz

1. Valida que NÃO é root
2. Verifica que Git está instalado e configurado
3. Confirma acesso a github.com
4. Detecta se já existe `~/.ssh/id_ed25519`:
   - Se sim, reutiliza
   - Se não, gera nova com `ssh-keygen -t ed25519`
5. Sugere título descritivo (ex: `vps73-20260527`)
6. Mostra a chave pública pra você copiar
7. Aguarda você adicionar no GitHub
8. Adiciona `github.com` aos `known_hosts` automaticamente (sem prompt)
9. Testa autenticação SSH (`ssh -T git@github.com`)
10. Detecta sucesso ("Hi USERNAME!") e mostra próximos passos
11. Em caso de falha, oferece retry

### Como usar

```bash
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/setup-github.sh -o gh.sh
chmod +x gh.sh
./gh.sh
```

### Sucesso esperado

```
Hi seu-username! You've successfully authenticated, but GitHub does not provide shell access.

[OK]      🎉 Autenticação com GitHub funcionou!
[OK]      Usuário GitHub detectado: seu-username
```

### Após executar

Daqui pra frente você pode:

```bash
# Clonar repos privados
git clone git@github.com:seu-user/repo-privado.git

# Conectar projeto local a repo remoto
cd /opt/meu-projeto
git remote add origin git@github.com:seu-user/meu-projeto.git
git push -u origin main
```

---

## 📦 setup-project.sh

**Roda como:** usuário não-root  
**Pré-requisito:** Docker e Git instalados (vêm do `bootstrap-vps.sh`)

### O que faz

#### 1. Coleta informações (interativo)
- Nome do projeto (valida formato: lowercase, hífen, números)
- Short name pra containers (sugere baseado no nome)
- Descrição curta
- Domínio principal (opcional)

#### 2. Cria estrutura em /opt/<nome>/

```
/opt/<nome>/
├── api/
├── worker/
├── webhook/
├── frontend/
├── ixc-adapter/
├── db/
│   ├── migrations/
│   └── backups/
├── caddy/
├── scripts/
├── docs/
├── secrets/
├── .claude/skills/<nome>-ops/
└── volumes/
    ├── postgres/
    ├── redis/
    ├── caddy-data/
    └── caddy-config/
```

#### 3. Cria arquivos base
- `.gitignore` completo (Python, Node, Docker, secrets)
- `.env.example` com variáveis comuns
- `README.md` com info do projeto
- `CLAUDE.md` template (memória institucional pro Claude Code)

#### 4. Cria skill local
- `.claude/skills/<nome>-ops/SKILL.md`
- Pré-preenchida com convenções do projeto

#### 5. Inicializa Git
- `git init`
- `git branch -m main`
- Primeiro commit automático

#### 6. Cria docs placeholders
- `docs/DEPLOY.md`
- `docs/RUNBOOK.md`
- `docs/ARCHITECTURE.md`

### Como usar

```bash
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/setup-project.sh -o sp.sh
chmod +x sp.sh
./sp.sh
```

### Após executar

```bash
cd /opt/<nome-do-projeto>

# Conecta com GitHub
git remote add origin git@github.com:seu-user/<nome>.git
git push -u origin main

# Edita o CLAUDE.md com info real
nano CLAUDE.md

# Cria .env a partir do template
cp .env.example .env
nano .env

# Quando estiver pronto, sobe a stack
docker compose up -d
```

---

## 🐛 Troubleshooting

### prepare-vps.sh

**"Este script DEVE ser executado como root."**
- Confirma que está logado como root: `whoami`
- Se está como outro usuário, sai e loga como root, ou usa `sudo`

**Travou em `adduser`**
- Provavelmente sistema pediu input que não foi respondido
- Mata o processo (Ctrl+C) e roda de novo (é idempotente)

### bootstrap-vps.sh

**"NÃO execute este script como root"**
- Você ainda está como root. Roda o `prepare-vps.sh` primeiro pra criar usuário não-root.

**"Sudo disponível" pede senha repetidamente**
- Roda `sudo -v` antes de executar o script — vai pedir senha 1x e cachear

**Travou no `apt upgrade`**
- Algum prompt interativo de configuração apareceu (raro com `DEBIAN_FRONTEND=noninteractive`)
- Mata o script e roda manualmente: `sudo apt upgrade` e responde os prompts
- Depois roda o bootstrap de novo (idempotente)

**Docker instalou mas `docker ps` pede sudo**
- Você não saiu e entrou de novo na sessão SSH
- Faz: `exit` e `ssh usuario@ip` novamente
- Ou força com: `newgrp docker`

### setup-github.sh

**"Permission denied (publickey)" no teste**
- Chave foi adicionada incorretamente no GitHub (faltou copiar alguma parte)
- Confere em `github.com/settings/keys` que a chave está lá
- Roda o script de novo, ele oferece retry

**Travou em "Pressione ENTER..."**
- Você ainda não terminou de adicionar a chave no GitHub
- Termina o processo no navegador e aperta Enter

### setup-project.sh

**"Docker não instalado"**
- Roda `bootstrap-vps.sh` primeiro
- Confere com `docker --version`

**"Git sem user.name ou user.email globais"**
- O `bootstrap-vps.sh` configura isso, mas se pulou:
  ```bash
  git config --global user.name "Seu Nome"
  git config --global user.email "seu@email.com"
  ```

**"/opt/<projeto>/ já existe e não está vazio"**
- Você já tentou criar esse projeto antes
- Aceita continuar (é idempotente) ou escolhe outro nome

---

## 🗺️ Roadmap desta pasta

- ✅ `prepare-vps.sh` — pré-bootstrap
- ✅ `bootstrap-vps.sh` — stack completa
- ✅ `setup-github.sh` — conecta GitHub
- ✅ `setup-project.sh` — cria projeto novo
- ⏳ `harden-ssh.sh` — desabilita senha SSH (só permite chave) após confirmação
- ⏳ `add-swap.sh` — adiciona arquivo de swap em VPS pequenas (< 4GB RAM)
- ⏳ `rotate-logs.sh` — configura logrotate pra logs do Docker
- ⏳ `change-hostname.sh` — muda hostname de forma idempotente
- ⏳ `migrate-vps.sh` — migra `/opt/` de uma VPS pra outra via rsync

---

## 📚 Veja também

- [README principal do repo](../README.md)
- [Guia de instalação do Git](../docs/INSTALL-GIT.md)
- [Guia de instalação do Claude Code](../docs/INSTALL-CLAUDE-CODE.md)
