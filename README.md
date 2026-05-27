# Biosnet Scripts

Scripts ops reusáveis pra VPS Ubuntu, Docker e gestão de projetos.

Mantido por [biosnetworks](https://github.com/biosnetworks).

## Estrutura
biosnet-scripts/
├── vps/          # Bootstrap de VPS, setup de projetos
├── docker/       # Gestão de containers e volumes (em breve)
├── postgres/     # Backup, restore, manutenção (em breve)
└── docs/         # Guias de instalação

## Uso rápido

### Bootstrap de VPS Ubuntu 24.04 LTS

Numa VPS recém-instalada, como usuário com sudo:

```bash
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/bootstrap-vps.sh -o bs.sh
chmod +x bs.sh
./bs.sh
```

Em ~5-10 minutos a VPS está pronta com hardening, Docker, Node.js e Git.

### Criar projeto novo em /opt

```bash
curl -fsSL https://raw.githubusercontent.com/biosnetworks/biosnet-scripts/main/vps/setup-project.sh -o sp.sh
chmod +x sp.sh
./sp.sh
```

## Princípios

Todo script segue:

- **Idempotência**: pode rodar 100x, mesmo resultado
- **`set -euo pipefail`** no topo de todo .sh
- **Logging colorido**: [INFO], [OK], [WARN], [ERROR]
- **Confirmação interativa** antes de operações destrutivas
- **Validação de pré-requisitos** no início

## Documentação

- [Instalação Git + GitHub](docs/INSTALL-GIT.md)
- [Instalação Claude Code](docs/INSTALL-CLAUDE-CODE.md)

## Roadmap

### Em produção
- ✅ vps/bootstrap-vps.sh
- ✅ vps/setup-project.sh

### Planejado
- ⏳ docker/cleanup.sh
- ⏳ docker/backup-volumes.sh
- ⏳ postgres/backup-all.sh
- ⏳ postgres/restore.sh

## Licença

MIT — use, modifique, distribua livremente.
