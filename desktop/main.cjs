'use strict';

/**
 * LibreChat Desktop proof of concept — a local Electron shell.
 * It never starts Docker and never exposes the API or database on a LAN interface.
 * MongoDB data survives restart; this is NOT an in-memory/ephemeral database.
 */
const { app, BrowserWindow, dialog, shell, session } = require('electron');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { MongoMemoryServer } = require('mongodb-memory-server-core');
const { freePort, isLocalAppUrl, waitForHTTP, requestBackendStop } = require('./runtime.cjs');

const repoDir = path.resolve(__dirname, '..');
const localRoot = process.env.LOCALAPPDATA
  ? path.join(process.env.LOCALAPPDATA, 'LibreChatDesktop')
  : path.join(app.getPath('home'), 'LibreChatDesktop');
const userData = path.join(localRoot, 'data');
const logsDir = path.join(userData, 'logs');
const dbDir = path.join(userData, 'mongodb');
const mongoBinaryDir = path.join(userData, 'mongodb-binaries');
const secretsDir = path.join(userData, 'secrets');
const nodeExe = path.join(localRoot, 'runtime', 'node', process.platform === 'win32' ? 'node.exe' : 'bin/node');

let window = null;
let mongo = null;
let backend = null;
let isQuitting = false;
let backendLog = null;
let desktopUrl = '';
let startupAborted = false;
let startupTask = null;

for (const dir of [userData, logsDir, dbDir, mongoBinaryDir, secretsDir]) {
  fs.mkdirSync(dir, { recursive: true });
}
app.setName('LibreChat Desktop');
app.setPath('userData', userData);
if (process.platform === 'win32') app.setAppUserModelId('org.librechat.desktop.local');
// The single-instance lock must be scoped to the configured application data
// location, not Electron's default shared development userData directory.
const hasSingleInstanceLock = app.requestSingleInstanceLock();

function log(message) {
  const stamp = new Date().toISOString();
  fs.appendFileSync(path.join(logsDir, 'desktop.log'), `[${stamp}] ${String(message)}\n`);
}

function reportStatus(message) {
  log(message);
  if (window && !window.isDestroyed()) window.setTitle(`LibreChat Desktop — ${message}`);
}

function showError(error) {
  const message = error instanceof Error ? error.message : String(error);
  log(`START ERROR: ${message}\n${error && error.stack ? error.stack : ''}`);
  if (window && !window.isDestroyed()) window.setTitle('LibreChat Desktop — hiba');
  dialog.showMessageBox(window || undefined, {
    type: 'error',
    title: 'LibreChat Desktop nem indult el',
    message: message,
    detail: `Naplók:\n${logsDir}\n\nA telepítéshez internet, illetve a Node.js és MongoDB binárisok letöltése szükséges.`,
    buttons: ['Rendben'],
  }).catch(() => {});
}

function isAllowedExternal(url) {
  try {
    const target = new URL(url);
    return target.protocol === 'https:' || target.protocol === 'mailto:';
  } catch {
    return false;
  }
}

function makeWindow() {
  window = new BrowserWindow({
    width: 1330,
    height: 850,
    minWidth: 760,
    minHeight: 540,
    title: 'LibreChat Desktop',
    show: false,
    backgroundColor: '#18181b',
    autoHideMenuBar: true,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
      devTools: true,
    },
  });
  window.webContents.setWindowOpenHandler(({ url }) => {
    if (isAllowedExternal(url)) shell.openExternal(url).catch((err) => log(`External link failed: ${err}`));
    return { action: 'deny' };
  });
  window.webContents.on('will-navigate', (event, target) => {
    if (!desktopUrl) {
      event.preventDefault();
      return;
    }
    const port = Number(new URL(desktopUrl).port);
    if (!isLocalAppUrl(target, port)) {
      event.preventDefault();
      if (isAllowedExternal(target)) shell.openExternal(target).catch((err) => log(`External navigation failed: ${err}`));
    }
  });
  window.loadFile(path.join(__dirname, 'status.html'));
  window.once('ready-to-show', () => window && window.show());
  window.on('closed', () => { window = null; });
  return window;
}

function setupPermissions() {
  session.defaultSession.setPermissionRequestHandler((webContents, permission, callback, details) => {
    const origin = details.requestingUrl || webContents.getURL();
    const port = desktopUrl ? Number(new URL(desktopUrl).port) : 0;
    const trusted = port && isLocalAppUrl(origin, port);
    callback(Boolean(trusted && (permission === 'media' || permission === 'notifications')));
  });
}

async function startMongo() {
  reportStatus('Helyi MongoDB indítása');
  // mongodb-memory-server-core fetches a verified MongoDB binary on first run;
  // WiredTiger + fixed dbPath are crucial for persistent user conversations.
  mongo = await MongoMemoryServer.create({
    instance: { ip: '127.0.0.1', dbPath: dbDir, storageEngine: 'wiredTiger' },
    binary: { version: '8.0.20', downloadDir: mongoBinaryDir, checkMD5: true },
  });
  return mongo.getUri('LibreChat');
}

async function startLibreChat(mongoUri) {
  if (!fs.existsSync(nodeExe)) {
    throw new Error(`Nem található a hordozható Node.js: ${nodeExe}. Futtasd újra a Desktop telepítőt.`);
  }
  const entrypoint = path.join(repoDir, 'api', 'server', 'index.js');
  const builtFrontend = path.join(repoDir, 'client', 'dist', 'index.html');
  if (!fs.existsSync(entrypoint) || !fs.existsSync(builtFrontend)) {
    throw new Error('A LibreChat forrás vagy a lefordított UI hiányzik. Futtasd újra a Desktop telepítőt.');
  }
  const port = await freePort();
  desktopUrl = `http://127.0.0.1:${port}/`;
  reportStatus('LibreChat szerver indítása');
  backendLog = fs.createWriteStream(path.join(logsDir, 'backend.log'), { flags: 'a' });
  const env = {
    ...process.env,
    NODE_ENV: 'production',
    HOST: '127.0.0.1',
    PORT: String(port),
    DOMAIN_CLIENT: desktopUrl.slice(0, -1),
    DOMAIN_SERVER: desktopUrl.slice(0, -1),
    MONGO_URI: mongoUri,
    SEARCH: 'false',
    LIBRECHAT_TEMP_CREDENTIALS_PATH: path.join(secretsDir, '.env.temp'),
    NO_PROXY: '127.0.0.1,localhost',
  };
  backend = spawn(nodeExe, ['--require', path.join(__dirname, 'backend-control.cjs'), entrypoint], {
    cwd: repoDir,
    env,
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
  });
  backend.stdout.pipe(backendLog, { end: false });
  backend.stderr.pipe(backendLog, { end: false });
  backend.on('error', (error) => log(`Backend spawn error: ${error.message}`));
  backend.on('exit', (code, signal) => {
    log(`Backend exited code=${code}, signal=${signal}`);
    if (!isQuitting && window && !window.isDestroyed()) {
      showError(new Error('A LibreChat háttérfolyamata váratlanul leállt. Nézd meg a backend.log fájlt.'));
    }
  });
  // LibreChat serves /health before post-listen initialization completes.
  // /readyz returns 200 only when the application is fully initialized.
  await waitForHTTP(`${desktopUrl}readyz`, { child: backend, timeoutMs: 180000 });
  return desktopUrl;
}

async function start() {
  makeWindow();
  setupPermissions();
  try {
    const uri = await startMongo();
    if (startupAborted) return;
    const url = await startLibreChat(uri);
    if (startupAborted) return;
    reportStatus('Kész');
    if (window && !window.isDestroyed()) {
      await window.loadURL(url);
      window.setTitle('LibreChat Desktop');
    }
  } catch (error) {
    if (!startupAborted) showError(error);
  }
}

async function stop() {
  startupAborted = true;
  // On a slow first run MongoDB may still be downloading when the user closes
  // the splash screen. Wait for startup to settle before inspecting children,
  // otherwise stop() can miss a newly created mongod process entirely.
  if (startupTask) {
    try { await startupTask; } catch (error) { log(`Startup settling during shutdown: ${error.message}`); }
  }
  if (backend) {
    try { await requestBackendStop(backend, 25000); } catch (e) { log(`Backend shutdown failed: ${e.message}`); }
    backend = null;
  }
  if (mongo) {
    // Explicitly keep the dbPath: never drop user conversations on shutdown.
    try { await mongo.stop({ doCleanup: false }); } catch (e) { log(`Mongo stop failed: ${e.message}`); }
    mongo = null;
  }
  if (backendLog) {
    backendLog.end();
    backendLog = null;
  }
}

app.on('before-quit', (event) => {
  if (isQuitting) return;
  event.preventDefault();
  isQuitting = true;
  stop().finally(() => app.exit(0));
});
app.on('window-all-closed', () => app.quit());
if (hasSingleInstanceLock) {
  app.on('second-instance', () => {
    if (window && !window.isDestroyed()) {
      if (window.isMinimized()) window.restore();
      window.focus();
    }
  });
  app.whenReady().then(() => {
    startupTask = start();
    return startupTask;
  }).catch(showError);
} else {
  app.quit();
}
