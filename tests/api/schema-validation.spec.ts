import { expect, test } from '@playwright/test';
import { buildBookingPayload } from '@data/booking.data';
import { authenticate, createBooking, deleteBookingIfExists } from './support/booking.api';
import {
  BOOKING_CONTRACT,
  BOOKING_SUMMARY_CONTRACT,
  CREATED_BOOKING_CONTRACT,
} from './support/contracts';
import { validateArrayOfObjects, validateSchema } from './support/schema';

const READ_SLA_MS = 3_000;

/**
 * Contract tests.
 *
 * These answer a different question from the CRUD flow. The lifecycle spec asks "can a user
 * complete the journey"; these ask "is the payload still shaped the way every consumer expects".
 * A provider can keep every status code green while renaming a field, and that is precisely the
 * regression this file catches before it reaches a downstream team.
 */
test.describe('Booking API contract', () => {
  test('POST /booking answers with the documented creation envelope', async ({ request }) => {
    const payload = buildBookingPayload();
    const token = await authenticate(request);
    let bookingId = 0;

    try {
      const response = await request.post('/booking', { data: payload });

      expect(response.status()).toBe(200);
      expect(response.headers()['content-type'] ?? '').toContain('application/json');

      const body: unknown = await response.json();

      await test.step('every declared key exists with the declared type', async () => {
        expect(validateSchema(body, CREATED_BOOKING_CONTRACT), 'creation envelope').toEqual([]);
      });

      await test.step('no undeclared key leaked into the envelope', async () => {
        // Strict mode turns an added field into a visible signal instead of a silent change.
        expect(
          validateSchema(body, CREATED_BOOKING_CONTRACT, { strict: true }),
          'creation envelope, strict',
        ).toEqual([]);
      });

      bookingId = (body as { bookingid: number }).bookingid;
    } finally {
      if (bookingId > 0) {
        await deleteBookingIfExists(request, bookingId, token);
      }
    }
  });

  test('GET /booking/{id} answers with the documented booking record', async ({ request }) => {
    const payload = buildBookingPayload();
    const token = await authenticate(request);
    const bookingId = await createBooking(request, payload);

    try {
      const startedAt = Date.now();
      const response = await request.get(`/booking/${bookingId}`);
      const elapsedMs = Date.now() - startedAt;

      await test.step('transport level: status, content type and latency', async () => {
        expect(response.status()).toBe(200);
        expect(response.ok()).toBe(true);
        expect(response.headers()['content-type'] ?? '').toContain('application/json');
        expect(response.headers()['content-type'] ?? '').toContain('charset=utf-8');
        expect(elapsedMs, `read exceeded its ${READ_SLA_MS} ms budget`).toBeLessThan(READ_SLA_MS);
      });

      const body: unknown = await response.json();

      await test.step('structural level: keys, types and nested objects', async () => {
        expect(validateSchema(body, BOOKING_CONTRACT, { strict: true }), 'booking record').toEqual(
          [],
        );
      });

      await test.step('semantic level: values survive the round trip intact', async () => {
        const booking = body as typeof payload;
        expect(booking.firstname).toBe(payload.firstname);
        expect(booking.totalprice).toBe(payload.totalprice);
        expect(booking.depositpaid).toBe(payload.depositpaid);
        expect(booking.bookingdates.checkin).toBe(payload.bookingdates.checkin);
        // A date field typed as string is not enough: the format is part of the contract.
        expect(booking.bookingdates.checkout).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      });
    } finally {
      await deleteBookingIfExists(request, bookingId, token);
    }
  });

  test('GET /booking answers with a collection of identifier summaries', async ({ request }) => {
    const response = await request.get('/booking');

    expect(response.status()).toBe(200);
    expect(response.headers()['content-type'] ?? '').toContain('application/json');

    const body: unknown = await response.json();

    await test.step('the collection is a non-empty array', async () => {
      expect(Array.isArray(body)).toBe(true);
      expect((body as unknown[]).length).toBeGreaterThan(0);
    });

    await test.step('every element exposes only an identifier', async () => {
      // The list endpoint must not leak full records: that is a privacy boundary, not a detail.
      expect(
        validateArrayOfObjects(body, BOOKING_SUMMARY_CONTRACT, { strict: true }),
        'booking summaries',
      ).toEqual([]);
    });
  });

  test('a deleted booking answers 404 with a plain-text body', async ({ request }) => {
    const payload = buildBookingPayload();
    const token = await authenticate(request);
    const bookingId = await createBooking(request, payload);

    // Deleting first makes the negative case deterministic, instead of guessing an unused id.
    await deleteBookingIfExists(request, bookingId, token);

    const response = await request.get(`/booking/${bookingId}`);

    expect(response.status()).toBe(404);
    expect(response.ok()).toBe(false);
    expect(response.headers()['content-type'] ?? '').toContain('text/plain');
    expect(await response.text()).toBe('Not Found');
  });
});
