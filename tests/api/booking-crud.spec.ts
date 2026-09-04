import { expect, test } from '@playwright/test';
import { buildBookingPayload, type BookingPayload } from '@data/booking.data';
import {
  AUTH_CREDENTIALS,
  authCookieHeader,
  authenticate,
  createBooking,
  deleteBookingIfExists,
} from './support/booking.api';
import {
  AUTH_TOKEN_CONTRACT,
  BOOKING_CONTRACT,
  CREATED_BOOKING_CONTRACT,
} from './support/contracts';
import { validateSchema } from './support/schema';

/**
 * Smoke-level latency budgets, not a performance test.
 *
 * These catch a gross regression such as an endpoint degrading from milliseconds to seconds. Real
 * latency objectives under concurrency belong to the k6 suite, where percentiles and error rates
 * are measured with load applied.
 */
const SLA_MS = {
  auth: 5_000,
  read: 3_000,
  write: 5_000,
} as const;

test.describe('Booking API lifecycle', () => {
  test('creates, reads, updates and deletes a booking end to end', async ({ request }) => {
    const payload = buildBookingPayload();
    const updatedPayload: BookingPayload = {
      ...payload,
      lastname: `${payload.lastname}-Updated`,
      totalprice: payload.totalprice + 500,
      depositpaid: !payload.depositpaid,
      additionalneeds: 'Airport pickup',
    };

    let token = '';
    let bookingId = 0;
    let alreadyDeleted = false;

    try {
      await test.step('GET /ping confirms the environment is reachable', async () => {
        // Deliberately unmeasured: this call absorbs a cold start so the budgets below are fair.
        const response = await request.get('/ping');
        expect(response.status()).toBe(201);
      });

      await test.step('POST /auth issues a session token', async () => {
        const startedAt = Date.now();
        const response = await request.post('/auth', { data: AUTH_CREDENTIALS });
        const elapsedMs = Date.now() - startedAt;

        expect(response.status()).toBe(200);
        expect(response.headers()['content-type'] ?? '').toContain('application/json');

        const body: unknown = await response.json();
        expect(validateSchema(body, AUTH_TOKEN_CONTRACT), 'auth response contract').toEqual([]);

        // The cast is safe only because the contract was just validated at runtime.
        token = (body as { token: string }).token;
        expect(token.length).toBeGreaterThan(0);
        expect(elapsedMs, `POST /auth exceeded its ${SLA_MS.auth} ms budget`).toBeLessThan(
          SLA_MS.auth,
        );
      });

      await test.step('POST /booking creates the resource and returns its identifier', async () => {
        const startedAt = Date.now();
        const response = await request.post('/booking', { data: payload });
        const elapsedMs = Date.now() - startedAt;

        expect(response.status()).toBe(200);
        expect(response.headers()['content-type'] ?? '').toContain('application/json');

        const body: unknown = await response.json();
        expect(validateSchema(body, CREATED_BOOKING_CONTRACT), 'create response contract').toEqual(
          [],
        );

        const created = body as { bookingid: number; booking: BookingPayload };
        // The API must echo back exactly what was sent, with no silent coercion.
        expect(created.booking).toEqual(payload);

        bookingId = created.bookingid;
        expect(bookingId).toBeGreaterThan(0);
        expect(elapsedMs, `POST /booking exceeded its ${SLA_MS.write} ms budget`).toBeLessThan(
          SLA_MS.write,
        );
      });

      await test.step('GET /booking/{id} returns the persisted record unchanged', async () => {
        const startedAt = Date.now();
        const response = await request.get(`/booking/${bookingId}`);
        const elapsedMs = Date.now() - startedAt;

        expect(response.status()).toBe(200);
        expect(response.headers()['content-type'] ?? '').toContain('application/json');

        const body: unknown = await response.json();
        expect(validateSchema(body, BOOKING_CONTRACT, { strict: true }), 'read contract').toEqual(
          [],
        );
        // Data integrity: what was written is what is read back, field by field.
        expect(body).toEqual(payload);
        expect(elapsedMs, `GET /booking exceeded its ${SLA_MS.read} ms budget`).toBeLessThan(
          SLA_MS.read,
        );
      });

      await test.step('PUT /booking/{id} replaces the record when authenticated', async () => {
        const startedAt = Date.now();
        const response = await request.put(`/booking/${bookingId}`, {
          headers: authCookieHeader(token),
          data: updatedPayload,
        });
        const elapsedMs = Date.now() - startedAt;

        expect(response.status()).toBe(200);
        expect(response.headers()['content-type'] ?? '').toContain('application/json');

        const body: unknown = await response.json();
        expect(validateSchema(body, BOOKING_CONTRACT, { strict: true }), 'update contract').toEqual(
          [],
        );
        expect(body).toEqual(updatedPayload);
        expect(body).not.toEqual(payload);
        expect(elapsedMs, `PUT /booking exceeded its ${SLA_MS.write} ms budget`).toBeLessThan(
          SLA_MS.write,
        );
      });

      await test.step('DELETE /booking/{id} removes the record', async () => {
        const response = await request.delete(`/booking/${bookingId}`, {
          headers: authCookieHeader(token),
        });

        // restful-booker answers 201 on a successful delete, which is part of its published contract.
        expect(response.status()).toBe(201);
        alreadyDeleted = true;
      });

      await test.step('GET /booking/{id} confirms the record is gone', async () => {
        const response = await request.get(`/booking/${bookingId}`);

        expect(response.status()).toBe(404);
        // A deleted resource must not answer with a JSON body that a client could mistake for data.
        expect(response.headers()['content-type'] ?? '').toContain('text/plain');
      });
    } finally {
      // Idempotent teardown: the record is removed even if an assertion above aborted the flow,
      // so a failing run never leaves orphan data behind for the next execution.
      if (bookingId > 0 && token.length > 0 && !alreadyDeleted) {
        await deleteBookingIfExists(request, bookingId, token);
      }
    }
  });

  test('rejects an update that carries no authentication token', async ({ request }) => {
    const payload = buildBookingPayload();
    const token = await authenticate(request);
    const bookingId = await createBooking(request, payload);

    try {
      await test.step('PUT without a token is forbidden', async () => {
        const response = await request.put(`/booking/${bookingId}`, {
          data: { ...payload, firstname: 'Should-Not-Persist' },
        });

        expect(response.status()).toBe(403);
      });

      await test.step('the stored record was not modified', async () => {
        const response = await request.get(`/booking/${bookingId}`);

        expect(response.status()).toBe(200);
        expect(await response.json()).toEqual(payload);
      });
    } finally {
      await deleteBookingIfExists(request, bookingId, token);
    }
  });
});
