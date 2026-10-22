'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { EventEmitter } = require('node:events');
const { isLoopbackHost, isLocalAppUrl, freePort, waitForHTTP, requestBackendStop } = require('./runtime.cjs');

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

test('waitForHTTP cancels promptly when startup is aborted', async () => {
  const port = await freePort();
  const controller = new AbortController();
  const pending = waitForHTTP(`http://127.0.0.1:${port}/`, {
    timeoutMs: 30000,
    intervalMs: 30,
    signal: controller.signal,
  });
  const abortTimer = setTimeout(() => controller.abort(), 80);
  try {
    await assert.rejects(pending, { name: 'AbortError' });
  } finally {
    clearTimeout(abortTimer);
  }
});

test('waitForHTTP does not accept a 503 readiness response', async () => {
  let ready = false;
  const server = http.createServer((_req, res) => {
    res.statusCode = ready ? 200 : 503;
    res.end(ready ? 'OK' : 'NOT_READY');
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const port = server.address().port;
    setTimeout(() => { ready = true; }, 120);
    assert.equal(
      await waitForHTTP(`http://127.0.0.1:${port}/readyz`, { timeoutMs: 3000, intervalMs: 30 }),
      200,
    );
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('requestBackendStop waits for the backend IPC acknowledgement and exit', async () => {
  class FakeChild extends EventEmitter {
    exitCode = null;
    signalCode = null;
    connected = true;
    killed = false;
    send(message, cb) {
      assert.deepEqual(message, { type: 'librechat-desktop:shutdown' });
      cb(null);
      setTimeout(() => {
        this.exitCode = 0;
        this.emit('exit', 0, null);
      }, 40);
    }
    kill() { this.killed = true; }
  }
  const child = new FakeChild();
  await requestBackendStop(child, 300);
  assert.equal(child.killed, false);
});

test('requestBackendStop forces a hung backend only after timeout', async () => {
  class HungChild extends EventEmitter {
    exitCode = null;
    signalCode = null;
    connected = true;
    killed = false;
    send(_message, cb) { cb(null); }
    kill() {
      this.killed = true;
      this.exitCode = 1;
      this.emit('exit', 1, null);
    }
  }
  const child = new HungChild();
  await requestBackendStop(child, 35);
  assert.equal(child.killed, true);
});
