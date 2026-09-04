import { randomUUID } from 'node:crypto';

/**
 * Booking payloads for the restful-booker API.
 *
 * Every payload is generated per test with a unique identity. Two tests running in parallel can
 * therefore never assert against each other's record, and a failed run leaves no fixture that a
 * later run would silently depend on.
 */
export interface BookingDates {
  readonly checkin: string;
  readonly checkout: string;
}

export interface BookingPayload {
  readonly firstname: string;
  readonly lastname: string;
  readonly totalprice: number;
  readonly depositpaid: boolean;
  readonly bookingdates: BookingDates;
  readonly additionalneeds: string;
}

/** Response shape returned by POST /booking. */
export interface CreatedBooking {
  readonly bookingid: number;
  readonly booking: BookingPayload;
}

/**
 * Builds a unique booking.
 *
 * The price is derived from the same identifier rather than from a random number generator, so a
 * failing run can be reproduced exactly from the name recorded in the report.
 */
export function buildBookingPayload(overrides: Partial<BookingPayload> = {}): BookingPayload {
  const uniqueId = randomUUID().slice(0, 8);
  const derivedPrice = 100 + (Number.parseInt(uniqueId, 16) % 900);

  return {
    firstname: `QA-${uniqueId}`,
    lastname: `Portfolio-${uniqueId}`,
    totalprice: derivedPrice,
    depositpaid: true,
    bookingdates: {
      checkin: '2026-11-01',
      checkout: '2026-11-08',
    },
    additionalneeds: 'Late checkout',
    ...overrides,
  };
}
