process.env.NODE_ENV = 'test';
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';
import http from 'node:http';
import {
  resilientTelecomRequest,
  TwilioSmsGateway,
  LiveSmsDispatcher,
} from '../shared/src/services/sms_provider';

describe('RootU Telecom Gateway Resilience & Retry Test Suite', () => {
  let mockServer: http.Server;
  let mockServerPort: number;
  let requestCounter = 0;
  let simulatedScenario = 'normal';

  before(async () => {
    mockServer = http.createServer((req, res) => {
      requestCounter++;

      if (simulatedScenario === 'flaky_500_then_success') {
        if (requestCounter === 1) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Internal Server Error' }));
        } else {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ sid: 'SMtest123', status: 'delivered' }));
        }
        return;
      }

      if (simulatedScenario === 'rate_limit_429_then_success') {
        if (requestCounter === 1) {
          res.writeHead(429, {
            'Content-Type': 'application/json',
            'Retry-After': '1',
          });
          res.end(JSON.stringify({ code: 20429, message: 'Too Many Requests' }));
        } else {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ sid: 'SMtest429', status: 'delivered' }));
        }
        return;
      }

      if (simulatedScenario === 'client_400_bad_request') {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ code: 21211, message: 'Invalid To Phone Number' }));
        return;
      }

      // Default normal 200 response
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ sid: 'SMnormal', status: 'sent' }));
    });

    await new Promise<void>((resolve) => {
      mockServer.listen(0, '127.0.0.1', () => {
        const address = mockServer.address() as any;
        mockServerPort = address.port;
        resolve();
      });
    });
  });

  after(async () => {
    await new Promise<void>((resolve) => mockServer.close(() => resolve()));
  });

  it('RES-01: Automatically retries on HTTP 500 server outage and recovers on attempt 2', async () => {
    requestCounter = 0;
    simulatedScenario = 'flaky_500_then_success';

    const response = await resilientTelecomRequest(
      `http://127.0.0.1:${mockServerPort}/sms`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ to: '+916369524324' }),
        maxRetries: 2,
        initialDelayMs: 50,
      },
      'TestMock'
    );

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.ok, true);
    assert.strictEqual(requestCounter, 2, 'Should have made exactly 2 attempts (1 retry)');
    const body = await response.json();
    assert.strictEqual(body.sid, 'SMtest123');
  });

  it('RES-02: Automatically retries on HTTP 429 rate limit respecting backoff', async () => {
    requestCounter = 0;
    simulatedScenario = 'rate_limit_429_then_success';

    const response = await resilientTelecomRequest(
      `http://127.0.0.1:${mockServerPort}/sms`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ to: '+916369524324' }),
        maxRetries: 2,
        initialDelayMs: 50,
      },
      'TestMock'
    );

    assert.strictEqual(response.status, 200);
    assert.strictEqual(response.ok, true);
    assert.strictEqual(requestCounter, 2, 'Should have retried once after 429');
    const body = await response.json();
    assert.strictEqual(body.sid, 'SMtest429');
  });

  it('RES-03: Does not waste retries on HTTP 400 Bad Request (non-transient client error)', async () => {
    requestCounter = 0;
    simulatedScenario = 'client_400_bad_request';

    const response = await resilientTelecomRequest(
      `http://127.0.0.1:${mockServerPort}/sms`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ to: 'invalid' }),
        maxRetries: 2,
        initialDelayMs: 50,
      },
      'TestMock'
    );

    assert.strictEqual(response.status, 400);
    assert.strictEqual(response.ok, false);
    assert.strictEqual(requestCounter, 1, 'HTTP 400 must return immediately without retrying');
  });

  it('RES-04: Gracefully handles socket timeout within configured timeout bounds', async () => {
    const hangingServer = http.createServer((_req, _res) => {
      // Intentionally do nothing and never reply
    });

    await new Promise<void>((resolve) => hangingServer.listen(0, '127.0.0.1', () => resolve()));
    const hangingPort = (hangingServer.address() as any).port;

    try {
      await assert.rejects(
        async () => {
          await resilientTelecomRequest(
            `http://127.0.0.1:${hangingPort}/timeout`,
            {
              method: 'POST',
              timeoutMs: 150,
              maxRetries: 1,
              initialDelayMs: 20,
            },
            'HangingMock'
          );
        },
        /Timeout/i
      );
    } finally {
      await new Promise<void>((resolve) => hangingServer.close(() => resolve()));
    }
  });

  it('RES-05: TwilioSmsGateway handles unconfigured credentials safely', async () => {
    const gw = new TwilioSmsGateway('', '', '');
    assert.strictEqual(gw.isConfigured(), false);
    const result = await gw.sendOtp('+916369524324', '123456', 'registration');
    assert.strictEqual(result, false);
  });

  it('RES-06: LiveSmsDispatcher records and clears transmission logs cleanly', async () => {
    LiveSmsDispatcher.clearTransmissionLog();
    assert.strictEqual(LiveSmsDispatcher.getTransmissionLog().length, 0);

    const dispatcher = new LiveSmsDispatcher();
    await dispatcher.sendOtp('+919876543210', '987654', 'registration');
    const code = LiveSmsDispatcher.getLatestDispatchedCode('+919876543210');
    assert.strictEqual(code, '987654');
    LiveSmsDispatcher.clearTransmissionLog();
    assert.strictEqual(LiveSmsDispatcher.getLatestDispatchedCode('+919876543210'), undefined);
  });
});
