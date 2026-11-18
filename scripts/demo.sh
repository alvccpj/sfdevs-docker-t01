#!/usr/bin/env bash
# ------------------------------------------------------------------
# Roteiro da demonstração — T01 · Docker avançado — SF Devs
# Uso (na raiz do projeto):  bash scripts/demo.sh
# No Windows: rode no Git Bash ou no WSL, com o Docker Desktop aberto.
# Cada passo pausa até você apertar Enter, para dar tempo de narrar.
# ------------------------------------------------------------------
set -u
# Git Bash (Windows) não deve converter caminhos como /tmp e /etc
export MSYS_NO_PATHCONV=1

APP_PORT=3000
NAIVE_PORT=3001
LIMITADA=api-limitada
mkdir -p resultados

pausa() { echo; read -r -p "⏎  Enter para continuar..." _; echo; }
titulo() { echo; echo "=================================================================="; echo "  $1"; echo "=================================================================="; }
rodar() { echo "\$ $*"; "$@"; }

limpar() {
  docker rm -f "$LIMITADA" api-naive >/dev/null 2>&1 || true
}
trap limpar EXIT
limpar

# ------------------------------------------------------------------
titulo "0. Ambiente (versões registradas)"
rodar docker version --format 'Docker Client {{.Client.Version}} | Engine {{.Server.Version}} | {{.Server.Os}}/{{.Server.Arch}}'
docker version --format 'Docker Client {{.Client.Version}} | Engine {{.Server.Version}} | {{.Server.Os}}/{{.Server.Arch}}' > resultados/versoes.txt
pausa

# ------------------------------------------------------------------
titulo "PARTE 1 (Álvaro) — Duas builds da mesma aplicação"
echo "Build A: ingênua (Dockerfile.naive)"
inicio=$(date +%s); rodar docker build -f Dockerfile.naive -t app:naive . ; fim=$(date +%s)
echo "tempo build A (frio): $((fim - inicio))s" | tee resultados/tempos.txt
pausa

echo "Build B: otimizada (Dockerfile multi-stage)"
inicio=$(date +%s); rodar docker build -t app:optimized . ; fim=$(date +%s)
echo "tempo build B (frio): $((fim - inicio))s" | tee -a resultados/tempos.txt
pausa

echo "Comparando tamanho:"
rodar docker images app
for tag in naive optimized; do
  tam=$(docker image inspect "app:$tag" --format '{{.Size}}')
  camadas=$(docker image inspect "app:$tag" --format '{{len .RootFS.Layers}}')
  echo "app:$tag -> $((tam / 1024 / 1024)) MB | $camadas camadas" | tee -a resultados/imagens.txt
done
pausa

echo "Camadas da imagem otimizada (repare que nada do builder aparece):"
rodar docker history app:optimized
pausa

echo "Teste de cache: simulando uma mudança no código..."
echo "// alteração de demonstração $(date +%s)" >> src/agendamentos.js
inicio=$(date +%s); docker build --progress=plain -f Dockerfile.naive -t app:naive . 2>&1 | grep -E "RUN npm install|CACHED"; fim=$(date +%s)
echo "rebuild A após mudar 1 linha: $((fim - inicio))s (npm install roda de novo)" | tee -a resultados/tempos.txt
inicio=$(date +%s); docker build --progress=plain -t app:optimized . 2>&1 | grep -E "RUN npm ci|CACHED"; fim=$(date +%s)
echo "rebuild B após mudar 1 linha: $((fim - inicio))s (npm ci vem do cache)" | tee -a resultados/tempos.txt
# desfaz a alteração de demonstração
sed -i.bak '$d' src/agendamentos.js && rm -f src/agendamentos.js.bak
pausa

# ------------------------------------------------------------------
titulo "PARTE 2 (Vinicius) — Executar como usuário sem privilégios"
echo "Build A: quem está rodando?"
rodar docker run --rm app:naive id
echo
echo "Build B: quem está rodando?"
rodar docker run --rm app:optimized id
pausa

echo "Build A: consigo escrever em /etc?"
rodar docker run --rm app:naive sh -c 'touch /etc/invasao && echo "ESCREVEU em /etc (root!)"'
echo
echo "Build B: consigo escrever em /etc? E no código da aplicação?"
rodar docker run --rm app:optimized sh -c 'touch /etc/invasao 2>&1; touch /app/src/app.js 2>&1; ls -l /app/src'
echo "(arquivos com dono root e sem escrita para outros: o usuário node só consegue ler)"
pausa

echo "Build B + reforços: --read-only, --cap-drop ALL, no-new-privileges"
rodar docker run -d --name "$LIMITADA" -p "$APP_PORT:3000" \
  --read-only --tmpfs /tmp:rw,mode=1777 --cap-drop ALL --security-opt no-new-privileges \
  --memory=128m --memory-swap=128m --cpus=0.5 --pids-limit=100 \
  app:optimized
sleep 3
rodar curl -s "http://localhost:$APP_PORT/info"; echo
rodar curl -s "http://localhost:$APP_PORT/escrever"; echo
echo "(só /tmp aceita escrita; /etc e /app dão EROFS = read-only file system)"
pausa

# ------------------------------------------------------------------
titulo "PARTE 3 (Arthur) — Limites de recursos configurados"
echo "O que o Docker registrou para este container:"
rodar docker inspect "$LIMITADA" --format 'Memoria={{.HostConfig.Memory}} Swap={{.HostConfig.MemorySwap}} NanoCpus={{.HostConfig.NanoCpus}} PIDs={{.HostConfig.PidsLimit}} ReadOnly={{.HostConfig.ReadonlyRootfs}}' | tee resultados/limites.txt
rodar docker stats "$LIMITADA" --no-stream
pausa

echo "Limite de CPU: carga de 15s em 1 núcleo (sem limite seria ~100%)"
rodar curl -s "http://localhost:$APP_PORT/cpu?segundos=15"; echo
sleep 5
rodar docker stats "$LIMITADA" --no-stream --format 'CPU={{.CPUPerc}}  MEM={{.MemUsage}}' | tee -a resultados/limites.txt
pausa

echo "Limite de memória: pedindo 400 MB num container de 128 MB"
rodar curl -s "http://localhost:$APP_PORT/stress?mb=400"; echo
sleep 8
rodar docker logs --tail 5 "$LIMITADA"
echo
rodar docker inspect "$LIMITADA" --format 'Status={{.State.Status}} OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}' | tee -a resultados/limites.txt
echo "(ExitCode 137 = 128 + 9 → processo morto com SIGKILL pelo OOM Killer)"
pausa

titulo "Fim — resultados salvos em ./resultados"
cat resultados/*.txt
