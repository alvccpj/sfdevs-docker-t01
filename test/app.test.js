const { test } = require("node:test");
const assert = require("node:assert/strict");
const request = require("supertest");
const { app } = require("../src/app");

test("GET /health responde ok", async () => {
  const res = await request(app).get("/health");
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { status: "ok" });
});

test("GET /agendamentos lista os dados fictícios", async () => {
  const res = await request(app).get("/agendamentos");
  assert.equal(res.status, 200);
  assert.ok(res.body.total > 0);
  assert.equal(res.body.itens.length, res.body.total);
});

test("GET /info informa usuário e uid", async () => {
  const res = await request(app).get("/info");
  assert.equal(res.status, 200);
  assert.equal(typeof res.body.uid, "number");
  assert.ok(res.body.usuario);
});
