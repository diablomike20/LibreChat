'use strict';

// Bootstrap is loaded using node --require before LibreChat registers its signal handlers.
// On Windows, child.kill('SIGTERM') cannot be relied upon for graceful shutdown.
// Sending an IPC control message lets LibreChat's existing SIGTERM handler drain work first.
process.on('message', (message) => {
  if (message && message.type === 'librechat-desktop:shutdown') {
    process.emit('SIGTERM');
  }
});
