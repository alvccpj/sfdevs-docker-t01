# T01 · Docker avançado — SF Devs

Seminário de **DevOps Tools** · Ciência da Computação · UNINASSAU · 2026.2

| Integrante | Matrícula | Parte da demo |
|---|---|---|
| Álvaro Jordão | 01748200 | 1. Duas builds da mesma aplicação |
| Vinícius Trigueiro | 01794959 | 2. Execução sem privilégios |
| Arthur Sales | 01593811 | 3. Limites de recursos |

**Objetivo:** comparar duas builds da mesma aplicação, executar como usuário sem privilégios e mostrar um limite configurado. A aplicação é uma API Node.js + Express pequena, com dados fictícios de agendamentos.

---

## Como rodar

**No GitHub Codespaces (recomendado, já tem Docker):**
1. Abra https://codespaces.new/alvccpj/sfdevs-docker-t01
2. No terminal, rode `bash scripts/demo.sh`. O script pausa a cada passo (Enter para seguir) e salva os resultados em `resultados/`.

**Localmente:** Docker Desktop ou Docker Engine + bash (no Windows, use Git Bash ou WSL). Mesmo comando.

## O que a demo mostra

| Parte | Comandos principais | Resultado esperado |
|---|---|---|
| 1. Builds | `docker build -f Dockerfile.naive -t app:naive .` · `docker build -t app:optimized .` · `docker images app` · `docker history app:optimized` | B bem menor; mudar o código não reinstala as dependências na B (`npm ci` → `CACHED`) |
| 2. Usuário | `docker run --rm app:naive id` · `docker run --rm app:optimized id` · `touch /etc/...` · `touch /app/src/app.js` | A: `uid=0(root)` e escreve em `/etc`. B: `uid=1000(node)` e `Permission denied` |
| 3. Limites | `docker run --memory=128m --memory-swap=128m --cpus=0.5 --pids-limit=100 --read-only ...` · `docker inspect` · `docker stats` · `curl /cpu` · `curl /stress?mb=400` | CPU travada em cerca de 50%; o container é morto com `OOMKilled=true`, `ExitCode=137` |

Rotas da API: `/health`, `/agendamentos`, `/info` (usuário, UID e limite de memória do cgroup), `/escrever`, `/cpu?segundos=N`, `/stress?mb=N`.
Alternativa declarativa da Parte 3: `docker compose up -d --build`.

## Build A vs. Build B

| | A · `Dockerfile.naive` | B · `Dockerfile` |
|---|---|---|
| Base | `node:24` (Debian) | `node:24-alpine` |
| Estágios | 1 | 2 (builder → runtime) |
| Dependências | todas, via `npm install` | só produção (`npm ci` + `npm prune --omit=dev`) |
| Ordem das camadas | `COPY . .` antes do install | manifestos primeiro, depois o código |
| Testes | não roda | roda no builder; o build falha se um teste falhar |
| Usuário / código | root, pode alterar tudo | `node`; código com dono root, somente leitura |
| HEALTHCHECK | não | sim |

## Resultados medidos

Ambiente: GitHub Codespaces · Ubuntu 24.04.5 LTS · Docker Engine 29.9.2 · Compose v5.6.1 · Node 24.22.3 · 18/11/2026.

| Métrica | A (naive) | B (optimized) |
|---|---|---|
| Tamanho da imagem | 1577 MB | **237 MB (−85%)** |
| Tamanho de download | 414 MB | **63,2 MB** |
| Camadas | 11 | 8 |
| 1º build | 93 s | **21 s** |
| Usuário | `uid=0(root)` | `uid=1000(node)` |
| CPU com `--cpus=0.5` | — | **50,32%** |
| `/stress` com `--memory=128m` | — | **`OOMKilled=true`, `ExitCode=137`** |

> Com poucas dependências, os dois rebuilds levam cerca de 5 s. A prova do cache é a linha `CACHED` no `npm ci` da B.
> Exit code 137 = 128 + 9: o processo recebeu SIGKILL do OOM Killer do kernel.

## Limitações

- O Alpine usa musl em vez de glibc, e pacotes com binário nativo podem quebrar.
- Rodar sem root não isola o kernel; para isso existem o Docker rootless e o userns-remap.
- Os 128 MB são didáticos. Em produção, meça antes de calibrar os limites.
- A demo roda em ambiente de desenvolvimento (Codespaces ou local), sem produção.

## Referências

- Docker — Multi-stage builds: https://docs.docker.com/build/building/multi-stage/
- Docker — Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Docker — Build best practices: https://docs.docker.com/build/building/best-practices/
- Docker — Resource constraints: https://docs.docker.com/engine/containers/resource_constraints/
- OWASP Docker Security Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html
- CIS Docker Benchmark: https://www.cisecurity.org/benchmark/docker
