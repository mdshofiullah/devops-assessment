const request = require('supertest');

const app = require('../src/app');
const { register } = require('../src/metrics');
const packageInfo = require('../package.json');

describe('DevOps Task API', () => {
  beforeEach(() => {
    register.resetMetrics();
  });

  test('GET / returns application information', async () => {
    const response = await request(app).get('/');

    expect(response.status).toBe(200);

    expect(response.body).toEqual({
      message: 'Hello from DevOps Task!',
      status: 'running',
      version: process.env.APP_VERSION || packageInfo.version,
    });
  });

  test('GET /health returns healthy status', async () => {
    const response = await request(app).get('/health');

    expect(response.status).toBe(200);
    expect(response.body).toEqual({
      status: 'ok',
    });
  });

  test('GET /metrics returns Prometheus metrics', async () => {
    await request(app).get('/health');

    const response = await request(app).get('/metrics');

    expect(response.status).toBe(200);
    expect(response.text).toContain('http_requests_total');
    expect(response.text).toContain('http_errors_total');
    expect(response.text).toContain('http_request_duration_seconds_bucket');
  });

  test('Unknown routes return 404', async () => {
    const response = await request(app).get('/unknown');

    expect(response.status).toBe(404);
    expect(response.body.error).toBe('Not Found');
  });
});