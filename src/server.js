const app = require('./app');
const logger = require('./logger');

const port = Number(process.env.PORT || 8080);

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('PORT must be a valid port number.');
}

const server = app.listen(port, '0.0.0.0', () => {
  logger.info(
    {
      port,
      environment: process.env.NODE_ENV || 'development',
    },
    'Application started'
  );
});

let shuttingDown = false;

function shutdown(signal) {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;

  logger.info({ signal }, 'Shutdown signal received');

  const forceExitTimer = setTimeout(() => {
    logger.error('Graceful shutdown timed out');

    server.closeAllConnections();
    process.exit(1);
  }, 10000);

  forceExitTimer.unref();

  server.close((error) => {
    clearTimeout(forceExitTimer);

    if (error) {
      logger.error({ err: error }, 'Error during server shutdown');
      process.exitCode = 1;
      return;
    }

    logger.info('HTTP server closed successfully');
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));