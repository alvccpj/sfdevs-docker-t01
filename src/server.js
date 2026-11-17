const { app } = require("./app");

const PORT = Number(process.env.PORT) || 3000;

const server = app.listen(PORT, () => {
  console.log(`API SF Devs ouvindo na porta ${PORT} (NODE_ENV=${process.env.NODE_ENV || "development"})`);
});

// Encerramento limpo quando o Docker envia SIGTERM (docker stop).
for (const sinal of ["SIGTERM", "SIGINT"]) {
  process.on(sinal, () => {
    console.log(`${sinal} recebido, encerrando...`);
    server.close(() => process.exit(0));
  });
}
