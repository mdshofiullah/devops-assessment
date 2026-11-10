const express = require('express');
const pinoHttp = require('pino-http');

const logger = require('./logger');
const { register, metricsMiddleware } = require('./metrics');
const packageInfo = require('../package.json');

const app = express();

app.disable('x-powered-by');

app.use(pinoHttp({ logger }));
app.use(metricsMiddleware);

app.get('/', (req, res) => {
  res.status(200).json({
    message: 'Hello from DevOps Task!',
    status: 'running',
    version: process.env.APP_VERSION || packageInfo.version,
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
  });
});

app.get('/metrics', async (req, res, next) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (error) {
    next(error);
  }
});

// Handle unknown routes.
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
  });
});

// Handle application errors.
app.use((err, req, res, next) => {
  logger.error(
    {
      err,
      method: req.method,
      path: req.path,
    },
    'Request failed'
  );

  if (res.headersSent) {
    return next(err);
  }

  res.status(500).json({
    error: 'Internal Server Error',
  });
});

module.exports = app;