'use strict';

// Exercise the exact MongoDB engine/database-path settings of desktop/main.cjs
// on a real Windows GitHub runner. Run separately from unit tests because the
// MongoDB binary must be downloaded on first launch.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { MongoClient } = require('mongodb');
const { MongoMemoryServer } = require('mongodb-memory-server-core');

test('Windows MongoDB 8.0.20 persists a conversation document across restart', { timeout: 180000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'librechat-desktop-mongo-'));
  const dbPath = path.join(root, 'db');
  const downloadDir = path.join(root, 'binaries');
  fs.mkdirSync(dbPath, { recursive: true });
  fs.mkdirSync(downloadDir, { recursive: true });
  const commonOptions = {
    instance: { ip: '127.0.0.1', dbPath, storageEngine: 'wiredTiger' },
    binary: { version: '8.0.20', downloadDir, checkMD5: true },
  };
  let server;
  let client;
  try {
    server = await MongoMemoryServer.create(commonOptions);
    client = new MongoClient(server.getUri('LibreChat'), { serverSelectionTimeoutMS: 10000 });
    await client.connect();
    await client.db('LibreChat').collection('desktop_smoke').insertOne({
      testId: 'persistent-user-conversation',
      content: 'Adatmegorzes ellenorzese',
    });
    await client.close();
    client = null;
    await server.stop({ doCleanup: false });
    server = null;

    server = await MongoMemoryServer.create(commonOptions);
    client = new MongoClient(server.getUri('LibreChat'), { serverSelectionTimeoutMS: 10000 });
    await client.connect();
    const found = await client.db('LibreChat').collection('desktop_smoke').findOne({
      testId: 'persistent-user-conversation',
    });
    assert.equal(found?.content, 'Adatmegorzes ellenorzese');
  } finally {
    if (client) await client.close();
    if (server) await server.stop({ doCleanup: false });
    fs.rmSync(root, { recursive: true, force: true });
  }
});
