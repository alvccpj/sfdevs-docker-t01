# ------------------------------------------------------------------
# BUILD B — otimizada (multi-stage + usuário sem privilégios)
# ------------------------------------------------------------------
ARG NODE_VERSION=24

# ---------- Estágio 1: builder ----------
# Instala TUDO (inclusive devDependencies), roda os testes e depois
# remove o que não é de produção. Nada deste estágio vai para a imagem
# final, exceto o que for copiado explicitamente com COPY --from.
FROM node:${NODE_VERSION}-alpine AS builder

WORKDIR /app

# Só os manifestos primeiro: enquanto package*.json não mudar,
# a camada do npm ci vem do cache, mesmo que o código mude.
COPY package.json package-lock.json ./
RUN npm ci

COPY src ./src
COPY test ./test

# Build falha se os testes falharem. Depois, poda as devDependencies e
# tira a permissão de escrita de grupo/outros (o checkout pode vir com 666,
# e o COPY preserva as permissões).
RUN npm test && npm prune --omit=dev && rm -rf test && chmod -R go-w /app

# ---------- Estágio 2: runtime ----------
FROM node:${NODE_VERSION}-alpine AS runtime

ENV NODE_ENV=production \
    PORT=3000

WORKDIR /app

# Os arquivos ficam com dono root (padrão do COPY) e o processo roda
# como "node": a aplicação consegue LER o próprio código, mas não
# consegue ALTERÁ-LO se for comprometida.
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
COPY --from=builder /app/src ./src

# Usuário sem privilégios que já existe na imagem oficial (UID 1000).
USER node

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Chama o node direto (sem npm): ele vira o PID 1 e recebe o SIGTERM do docker stop.
CMD ["node", "src/server.js"]
