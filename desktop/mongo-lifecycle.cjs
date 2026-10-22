'use strict';

const { MongoClient } = require('mongodb');

/**
 * mongodb-memory-server-core uses a generic SIGINT process stop for a
 * standalone MongoDB; on Windows that can terminate the process before
 * recently acknowledged writes have reached disk.
 *
 * Flush and request MongoDB's own shutdown command first, then wait for
 * mongod's exit before letting mongodb-memory-server dispose its manager.
 * Never remove the fixed dbPath (user conversations live there).
 */
async function stopMongoSafely(server, options = {}) {
  if (!server) return;
  const timeoutMs = options.timeoutMs ?? 20000;
  const child = server.instanceInfo?.instance?.mongodProcess;
  if (!child) {
    await server.stop({ doCleanup: false });
    return;
  }
  if (child.exitCode !== null || child.signalCode !== null) {
    await server.stop({ doCleanup: false });
    return;
  }

  let exitTimer;
  let onExit;
  const exited = new Promise((resolve, reject) => {
    onExit = () => { clearTimeout(exitTimer); resolve(); };
    child.once('exit', onExit);
    exitTimer = setTimeout(() => {
      child.off('exit', onExit);
      reject(new Error('MongoDB did not exit after its shutdown command.'));
    }, timeoutMs);
  });
  // Do not retain a rejected promise before shutdown command handling.
  exited.catch(() => {});

  const client = new MongoClient(server.getUri('admin'), {
    serverSelectionTimeoutMS: 5000,
    directConnection: true,
  });
  let shutdownRequested = false;
  try {
    await client.connect();
    // A write concern acknowledgement is not equivalent to durable flush.
    // Flush the WiredTiger journal before issuing the server-side shutdown.
    await client.db('admin').command({ fsync: 1 });
    try {
      await client.db('admin').command({ shutdown: 1, force: true, timeoutSecs: 5 });
      shutdownRequested = true;
    } catch (error) {
      // MongoDB intentionally drops the admin connection when shutting down.
      // The process exit, not this network error, determines success.
      const networkClosed =
        error?.name === 'MongoNetworkError' ||
        error?.name === 'MongoServerSelectionError' ||
        /ECONNRESET|connection .* closed|socket.*closed|connection.*ended/i.test(error?.message || '');
      if (!networkClosed) throw error;
      shutdownRequested = true;
    }
    await exited;
  } finally {
    clearTimeout(exitTimer);
    child.off('exit', onExit);
    await client.close().catch(() => {});
  }
  if (!shutdownRequested) {
    throw new Error('MongoDB graceful shutdown was not confirmed; refusing an unsafe cleanup.');
  }
  await server.stop({ doCleanup: false });
}

module.exports = { stopMongoSafely };
