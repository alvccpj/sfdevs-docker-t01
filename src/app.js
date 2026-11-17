const express = require("express");
const fs = require("node:fs");
const os = require("node:os");
const { Worker } = require("node:worker_threads");
const { agendamentos } = require("./agendamentos");

const app = express();

// Memória alocada pelo /stress fica aqui para não ser coletada pelo GC.
const reservas = [];

// Lê o limite de memória que o cgroup impôs ao container (v2 e v1).
function limiteMemoriaCgroup() {
  const caminhos = [
    "/sys/fs/cgroup/memory.max", // cgroup v2
    "/sys/fs/cgroup/memory/memory.limit_in_bytes" // cgroup v1
  ];
  for (const caminho of caminhos) {
    try {
      const valor = fs.readFileSync(caminho, "utf8").trim();
      if (valor === "max" || Number(valor) > 2 ** 60) return "sem limite";
      return `${Math.round(Number(valor) / 1024 / 1024)} MiB`;
    } catch {
      // tenta o próximo caminho
    }
  }
  return "indisponível (fora de um container Linux?)";
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.get("/agendamentos", (_req, res) => {
  res.json({ total: agendamentos.length, itens: agendamentos });
});

// Quem está rodando o processo e com quais limites.
app.get("/info", (_req, res) => {
  const usuario = os.userInfo();
  res.json({
    usuario: usuario.username,
    uid: usuario.uid,
    gid: usuario.gid,
    node: process.version,
    hostname: os.hostname(),
    limiteMemoria: limiteMemoriaCgroup(),
    memoriaUsadaMiB: Math.round(process.memoryUsage().rss / 1024 / 1024)
  });
});

// Tenta escrever em locais diferentes para provar as restrições de permissão.
app.get("/escrever", (_req, res) => {
  const alvos = ["/etc/teste-sfdevs.txt", "/app/teste-sfdevs.txt", "/tmp/teste-sfdevs.txt"];
  const resultado = alvos.map((alvo) => {
    try {
      fs.writeFileSync(alvo, `escrito em ${new Date().toISOString()}\n`);
      return { alvo, ok: true };
    } catch (erro) {
      return { alvo, ok: false, erro: erro.code };
    }
  });
  res.json(resultado);
});

// Aloca memória aos poucos (padrão: 10 MB a cada 300 ms) até chegar em ?mb.
// Com --memory=128m o kernel mata o container (OOM Killer) antes de terminar.
app.get("/stress", (req, res) => {
  const alvoMb = Math.min(Number(req.query.mb) || 300, 2048);
  const passoMb = Math.min(Number(req.query.passo) || 10, 100);
  let alocadoMb = 0;

  const timer = setInterval(() => {
    // Buffer.alloc preenche com zeros, então as páginas são realmente usadas (RSS sobe).
    reservas.push(Buffer.alloc(passoMb * 1024 * 1024, 1));
    alocadoMb += passoMb;
    const rss = Math.round(process.memoryUsage().rss / 1024 / 1024);
    console.log(`[stress] alocados ${alocadoMb} MB | RSS do processo: ${rss} MiB`);
    if (alocadoMb >= alvoMb) {
      clearInterval(timer);
      console.log("[stress] alvo atingido sem ser morto — o limite de memória está configurado?");
    }
  }, 300);

  res.status(202).json({ mensagem: `Alocando ${alvoMb} MB em passos de ${passoMb} MB. Acompanhe com: docker logs -f <container>` });
});

// Ocupa 1 núcleo de CPU por ?segundos em uma worker thread.
// Com --cpus=0.5 o docker stats mostra o uso travado perto de 50%.
app.get("/cpu", (req, res) => {
  const segundos = Math.min(Number(req.query.segundos) || 20, 120);
  const worker = new Worker(
    `const fim = Date.now() + ${segundos * 1000}; while (Date.now() < fim) { Math.sqrt(Math.random()); }`,
    { eval: true }
  );
  worker.on("exit", () => console.log(`[cpu] carga de ${segundos}s finalizada`));
  console.log(`[cpu] iniciando carga de ${segundos}s`);
  res.status(202).json({ mensagem: `Carga de CPU por ${segundos}s iniciada. Acompanhe com: docker stats` });
});

module.exports = { app };
