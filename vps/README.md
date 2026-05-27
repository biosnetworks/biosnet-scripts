# Scripts VPS

Scripts pra preparação e gestão de VPS Ubuntu 24.04 LTS.

## Scripts disponíveis

### bootstrap-vps.sh

Bootstrap completo de VPS recém-instalada.

**O que faz:**
- Atualiza o sistema
- Instala ferramentas (ufw, fail2ban, htop, ncdu, tmux, git, vim, curl, jq, rsync)
- Configura firewall UFW (apenas 22, 80, 443)
- Configura fail2ban com proteção SSH
- Habilita atualizações automáticas
- Instala Docker oficial + Compose
- Adiciona usuário ao grupo docker
- Instala Node.js 20 LTS
- Configura Git globalmente
- Gera chave SSH ed25519 (opcional)

**Pré-requisitos:**
- Ubuntu 24.04 LTS limpo
- Usuário NÃO-ROOT com sudo
- Acesso à internet

**Uso:**

```bash
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/bootstrap-vps.sh -o bs.sh
chmod +x bs.sh
./bs.sh
```

Tempo: ~5-10 minutos.

⚠️ Após executar, **saia e entre de novo via SSH** pra o grupo docker valer.

---

### setup-project.sh

Cria estrutura padrão de projeto Docker em /opt/<nome>/.

**O que cria:**
- Diretório /opt/<nome>/ com permissões corretas
- Estrutura: api/, worker/, webhook/, frontend/, db/, caddy/, scripts/, docs/, volumes/
- .gitignore completo
- .env.example template
- README.md
- CLAUDE.md template
- Skill local em .claude/skills/<nome>-ops/
- Git init + primeiro commit

**Pré-requisitos:**
- Bootstrap da VPS já rodado
- Git com user.name e user.email globais configurados

**Uso:**

```bash
./setup-project.sh
```

Tempo: ~30 segundos.

## Roadmap

- ⏳ harden-ssh.sh — desabilita senha SSH, só chave
- ⏳ add-swap.sh — adiciona arquivo de swap
- ⏳ rotate-logs.sh — configura logrotate
