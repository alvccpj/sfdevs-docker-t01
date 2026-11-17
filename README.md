# T01 · Docker avançado — SF Devs

Seminário da disciplina **DevOps Tools** (Ciência da Computação · UNINASSAU · 2026.2).
**Grupo SF Devs:** Álvaro, Vinicius e Arthur.

O que a demonstração prova (resultado mínimo do tema):

1. **Duas builds da mesma aplicação**: `Dockerfile.naive` (ingênua) contra `Dockerfile` (multi-stage otimizada), comparando tamanho, camadas e uso de cache.
2. **Execução como usuário sem privilégios**: a build otimizada roda como `node` (UID 1000), não como `root`, e o sistema de arquivos fica somente leitura.
3. **Um limite configurado**: memória (128 MB), CPU (0,5 núcleo) e PIDs (100) via cgroups, verificados com `docker inspect`, `docker stats` e um OOM Kill de verdade.

A aplicação é uma API Node.js + Express pequena, com **dados fictícios** de agendamentos.

---

## Estrutura

```
.
├── src/
│   ├── app.js            # rotas da API
│   ├── agendamentos.js   # dados fictícios
│   └── server.js         # sobe o servidor e trata SIGTERM
├── test/app.test.js      # testes (rodam dentro do estágio builder)
├── Dockerfile.naive      # BUILD A: imagem completa, root, 1 estágio
├── Dockerfile            # BUILD B: multi-stage, alpine, USER node, HEALTHCHECK
├── .dockerignore
├── docker-compose.yml    # execução da Parte 3 em formato declarativo
└── scripts/demo.sh       # roteiro da demo com pausas para narração
```

### Endpoints

| Rota | O que faz |
|---|---|
| `GET /health` | Health check (`{"status":"ok"}`) |
| `GET /agendamentos` | Lista os agendamentos fictícios |
| `GET /info` | Usuário, UID, versão do Node e **limite de memória lido do cgroup** |
| `GET /escrever` | Tenta escrever em `/etc`, `/app` e `/tmp` e mostra o que foi negado |
| `GET /cpu?segundos=15` | Ocupa 1 núcleo por N segundos (para ver o `--cpus` agir) |
| `GET /stress?mb=400` | Aloca memória aos poucos (10 MB / 300 ms) até o container ser morto pelo OOM Killer |

---

## Pré-requisitos e versões

- Docker Desktop (Windows/macOS) ou Docker Engine (Linux), com **BuildKit** (padrão nas versões atuais)
- `curl`
- Para o script: **bash** (Linux/macOS, ou no Windows o **Git Bash** ou o **WSL**)
- Node.js 22 ou superior **só** se quiser rodar a API fora do Docker

Registrem as versões usadas na apresentação (o professor pede "versões registradas"):

| Item | Comando | Versão usada |
|---|---|---|
| Docker Engine | `docker version --format "{{.Server.Version}}"` | _preencher_ |
| Docker Compose | `docker compose version` | _preencher_ |
| Imagem base A | `node:24` | Node 24 |
| Imagem base B | `node:24-alpine` | Node 24 |
| Sistema operacional | — | _preencher_ |

> O script `scripts/demo.sh` grava as versões e os resultados medidos na pasta `resultados/`.

---

## Rodar a demonstração

### Opção 1: script guiado (recomendado para a apresentação)

```bash
bash scripts/demo.sh
```

O script pausa a cada passo (Enter para seguir), para cada integrante narrar a sua parte.

### Opção 2: comando por comando

Os comandos estão em uma linha só para funcionarem também no PowerShell.
No **PowerShell**, troque `curl` por `curl.exe`.

#### Parte 1 (Álvaro): duas builds da mesma aplicação

```bash
docker build -f Dockerfile.naive -t app:naive .
docker build -t app:optimized .
docker images app
docker image inspect app:naive --format "{{.Size}} bytes | {{len .RootFS.Layers}} camadas"
docker image inspect app:optimized --format "{{.Size}} bytes | {{len .RootFS.Layers}} camadas"
docker history app:optimized
```

**Teste de cache:** altere qualquer linha de `src/agendamentos.js` e rode os dois builds de novo.
- Na **A**, o `COPY . .` vem antes do `npm install`, então qualquer mudança no código reinstala todas as dependências.
- Na **B**, só `package*.json` é copiado antes do `npm ci`, então essa camada aparece como `CACHED` e o rebuild fica bem mais rápido.

#### Parte 2 (Vinicius): usuário sem privilégios

```bash
docker run --rm app:naive id
docker run --rm app:optimized id
docker run --rm app:naive sh -c "touch /etc/invasao && echo ESCREVEU"
docker run --rm app:optimized sh -c "touch /etc/invasao; touch /app/src/app.js"
```

Resultado esperado:
- `app:naive`: `uid=0(root)` e a escrita em `/etc` funciona.
- `app:optimized`: `uid=1000(node)` e `Permission denied` em `/etc` e no próprio código. Os arquivos da aplicação pertencem ao root e o processo só consegue lê-los.

#### Parte 3 (Arthur): limites configurados

```bash
docker run -d --name api-limitada -p 3000:3000 --memory=128m --memory-swap=128m --cpus=0.5 --pids-limit=100 --read-only --tmpfs /tmp:rw,mode=1777 --cap-drop ALL --security-opt no-new-privileges app:optimized

docker inspect api-limitada --format "Memoria={{.HostConfig.Memory}} Swap={{.HostConfig.MemorySwap}} NanoCpus={{.HostConfig.NanoCpus}} PIDs={{.HostConfig.PidsLimit}} ReadOnly={{.HostConfig.ReadonlyRootfs}}"
curl http://localhost:3000/info
curl http://localhost:3000/escrever

curl "http://localhost:3000/cpu?segundos=15"
docker stats api-limitada

curl "http://localhost:3000/stress?mb=400"
docker logs -f api-limitada
docker inspect api-limitada --format "Status={{.State.Status}} OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}"

docker rm -f api-limitada
```

Resultado esperado:

| Verificação | Esperado |
|---|---|
| `docker inspect` (limites) | `Memoria=134217728 Swap=134217728 NanoCpus=500000000 PIDs=100 ReadOnly=true` |
| `/info` | `"usuario":"node","uid":1000,"limiteMemoria":"128 MiB"` |
| `/escrever` | `/etc` e `/app` → `EROFS` (read-only); só `/tmp` aceita escrita |
| `docker stats` durante `/cpu` | CPU travada perto de **50%** (sem limite, seria cerca de 100%) |
| depois do `/stress` | `Status=exited OOMKilled=true ExitCode=137` |

> **Por que `--memory-swap` igual a `--memory`?** Sem isso, o Docker pode deixar o container usar swap além dos 128 MB, e o OOM demora a acontecer (ou não acontece).
> **Exit code 137** = 128 + 9: o processo recebeu `SIGKILL` do OOM Killer do kernel.

#### Alternativa declarativa (Compose)

```bash
docker compose up -d --build
docker inspect api-compose --format "Memoria={{.HostConfig.Memory}} NanoCpus={{.HostConfig.NanoCpus}} PIDs={{.HostConfig.PidsLimit}}"
docker compose down
```

---

## Comparação A vs. B

| | A: `Dockerfile.naive` | B: `Dockerfile` |
|---|---|---|
| Imagem base | `node:24` (Debian completo) | `node:24-alpine` |
| Estágios | 1 | 2 (builder → runtime) |
| Dependências | todas (inclusive dev) | só produção (`npm prune --omit=dev`) |
| Ordem das camadas | `COPY . .` antes do install | manifestos primeiro, depois o código |
| Instalação | `npm install` | `npm ci` (determinística, via lockfile) |
| Testes | não roda | roda no builder; o build falha se um teste falhar |
| Usuário | root (UID 0) | `node` (UID 1000) |
| Dono dos arquivos do app | root, gravável pelo processo | root, **somente leitura** para o processo |
| HEALTHCHECK | não | sim |
| PID 1 | `npm` (repassa sinais mal) | `node` (recebe o SIGTERM do `docker stop`) |

### Resultados medidos (preencher depois de rodar)

| Métrica | A (naive) | B (optimized) |
|---|---|---|
| Tamanho da imagem | | |
| Nº de camadas | | |
| Tempo do 1º build | | |
| Tempo do rebuild após mudar 1 linha | | |
| Usuário (`id`) | | |

---

## Limitações conhecidas

- **Alpine usa musl** em vez de glibc: dependências com binários nativos podem precisar de ajustes.
- Rodar sem root **não isola o kernel**: o container ainda compartilha o kernel do host. Para isolar mais, existem o Docker rootless e o `userns-remap`.
- No **Docker Desktop** (Windows/macOS), os limites valem dentro da VM do Docker. Se a VM tiver pouca memória, ajuste em *Settings → Resources*.
- Limites mal calibrados causam OOM em produção. Os 128 MB daqui são didáticos; em produção, meça antes de definir.
- Demo local, sem nuvem e sem ambiente de produção (o seminário não exige).

## Checklist antes da apresentação

- [ ] Rodar `docker pull node:24 node:24-alpine` antes, para não depender da rede da sala
- [ ] Rodar `bash scripts/demo.sh` uma vez de ponta a ponta e preencher as tabelas acima
- [ ] Copiar os números medidos para os slides de comparação e de interpretação
- [ ] Testar se o link do repositório abre sem login, para o formulário de entrega

## Limpeza

```bash
docker rm -f api-limitada api-compose
docker rmi app:naive app:optimized
docker builder prune -f
```

## Referências

- Docker Docs: Multi-stage builds — https://docs.docker.com/build/building/multi-stage/
- Docker Docs: Dockerfile reference (USER, HEALTHCHECK) — https://docs.docker.com/reference/dockerfile/
- Docker Docs: Building best practices — https://docs.docker.com/build/building/best-practices/
- Docker Docs: Resource constraints — https://docs.docker.com/engine/containers/resource_constraints/
- Docker Docs: `docker run` (`--read-only`, `--cap-drop`, `--security-opt`) — https://docs.docker.com/reference/cli/docker/container/run/
- OWASP Docker Security Cheat Sheet — https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html
- CIS Docker Benchmark — https://www.cisecurity.org/benchmark/docker

---

**Autores:** Álvaro, Vinicius e Arthur (SF Devs) · DevOps Tools · UNINASSAU 2026.2
