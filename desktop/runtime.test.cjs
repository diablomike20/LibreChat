'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { isLoopbackHost, isLocalAppUrl, freePort, waitForHTTP } = require('./runtime.cjs');

test('navigation permits only the local server on the selected port', () => {
  assert.equal(isLoopbackHost('127.0.0.1'), true);
  assert.equal(isLocalAppUrl('http://127.0.0.1:3080/c/new', 3080), true);
  assert.equal(isLocalAppUrl('http://localhost:3080/login', 3080), true);
  assert.equal(isLocalAppUrl('https://localhost:3080/login', 3080), false);
  assert.equal(isLocalAppUrl('http://127.0.0.1:3081', 3080), false);
  assert.equal(isLocalAppUrl('http://localhost.evil.example:3080', 3080), false);
  assert.equal(isLocalAppUrl('javascript:alert(1)', 3080), false);
});

test('freePort allocates an unoccupied local TCP port', async () => {
  const port = await freePort();
  assert.ok(port > 0 && port < 65536);
});

test('waitForHTTP recognizes a running HTTP server', async () => {
  const server = http.createServer((_req, res) => {
    res.statusCode = 200;
    res.end('ok');
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const port = server.address().port;
    assert.equal(await waitForHTTP(`http://127.0.0.1:${port}/`, { timeoutMs: 5000 }), 200);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('waitForHTTP times out on a missing server', async () => {
  const port = await freePort();
  await assert.rejects(
    waitForHTTP(`http://127.0.0.1:${port}/`, { timeoutMs: 280, intervalMs: 30 }),
    /did not become ready/,
  );
});
