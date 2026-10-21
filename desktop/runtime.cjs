'use strict';

/** Dependency-free helpers, kept outside Electron so they can be tested with Node. */
const http = require('node:http');
const net = require('node:net');
const { setTimeout: delay } = require('node:timers/promises');

function isLoopbackHost(host) {
  return host === '127.0.0.1' || host === 'localhost' || host === '[::1]' || host === '::1';
}

function isLocalAppUrl(value, expectedPort) {
  try {
    const target = new URL(value);
    return (
      target.protocol === 'http:' &&
      isLoopbackHost(target.hostname) &&
      target.port === String(expectedPort) &&
      target.username === '' &&
      target.password === ''
    );
  } catch {
    return false;
  }
}

async function freePort(host = '127.0.0.1') {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, host, () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        server.close();
        return reject(new Error('Could not allocate a TCP port.'));
      }
      server.close((error) => (error ? reject(error) : resolve(address.port)));
    });
  });
}

function httpStatus(url, timeoutMs = 1200) {
  return new Promise((resolve) => {
    let resolved = false;
    const finish = (status) => {
      if (resolved) return;
      resolved = true;
      resolve(status);
    };
    const req = http.get(url, { timeout: timeoutMs }, (res) => {
      res.resume();
      finish(res.statusCode || 0);
    });
    req.on('timeout', () => req.destroy());
    req.on('error', () => finish(0));
  });
}

async function waitForHTTP(url, options = {}) {
  const {
    timeoutMs = 120000,
    intervalMs = 400,
    signal,
    child,
  } = options;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (signal?.aborted) throw new Error('Startup cancelled.');
    if (child && (child.exitCode !== null || child.signalCode !== null)) {
      throw new Error(`LibreChat backend exited before it became ready (exit ${child.exitCode ?? child.signalCode}).`);
    }
    const status = await httpStatus(url);
    if (status >= 200 && status < 400) return status;
    await delay(intervalMs, undefined, { signal });
  }
  throw new Error('LibreChat did not become ready. Check desktop logs for details.');
}

module.exports = { isLoopbackHost, isLocalAppUrl, freePort, httpStatus, waitForHTTP };
