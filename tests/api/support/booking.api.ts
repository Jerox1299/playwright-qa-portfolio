import type { APIRequestContext } from '@playwright/test';
import type { BookingPayload } from '@data/booking.data';

/**
 * Thin plumbing for setup and teardown.
 *
 * These helpers deliberately contain NO assertions. Assertions describe the requirement under
 * test and belong in the spec. A helper that fails throws instead, so a broken precondition is
 * reported as an infrastructure error rather than masquerading as a product defect.
 */

/** Public sandbox credentials published by restful-booker. No secret is stored in this repository. */
export const AUTH_CREDENTIALS = {
  username: 'admin',
  password: 'password123',
} as const;

/** restful-booker authenticates writes with a cookie rather than a bearer header. */
export function authCookieHeader(token: string): Record<string, string> {
  return { Cookie: `token=${token}` };
}

export async function authenticate(request: APIRequestContext): Promise<string> {
  const response = await request.post('/auth', { data: AUTH_CREDENTIALS });

  if (!response.ok()) {
    throw new Error(`Authentication failed with status ${response.status()}`);
  }

  const body = (await response.json()) as { token?: unknown };

  if (typeof body.token !== 'string' || body.token.length === 0) {
    throw new Error('Authentication succeeded but no token was returned');
  }

  return body.token;
}

export async function createBooking(
  request: APIRequestContext,
  payload: BookingPayload,
): Promise<number> {
  const response = await request.post('/booking', { data: payload });

  if (!response.ok()) {
    throw new Error(`Booking creation failed with status ${response.status()}`);
  }

  const body = (await response.json()) as { bookingid?: unknown };

  if (typeof body.bookingid !== 'number') {
    throw new Error('Booking creation returned no numeric bookingid');
  }

  return body.bookingid;
}

/**
 * Idempotent teardown: deleting an already deleted booking must not fail the run.
 * restful-booker answers 405 when the record is gone, so both outcomes are accepted.
 */
export async function deleteBookingIfExists(
  request: APIRequestContext,
  bookingId: number,
  token: string,
): Promise<void> {
  const response = await request.delete(`/booking/${bookingId}`, {
    headers: authCookieHeader(token),
  });

  const acceptedStatuses = [201, 404, 405];

  if (!acceptedStatuses.includes(response.status())) {
    throw new Error(`Cleanup of booking ${bookingId} failed with status ${response.status()}`);
  }
}
