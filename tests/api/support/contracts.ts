import type { SchemaSpec } from './schema';

/**
 * The contract the API promises. These constants are the single place to update when the provider
 * publishes a new version, which is what turns a suite of requests into contract testing.
 */
export const AUTH_TOKEN_CONTRACT: SchemaSpec = {
  token: 'string',
};

export const BOOKING_DATES_CONTRACT: SchemaSpec = {
  checkin: 'string',
  checkout: 'string',
};

export const BOOKING_CONTRACT: SchemaSpec = {
  firstname: 'string',
  lastname: 'string',
  totalprice: 'number',
  depositpaid: 'boolean',
  bookingdates: BOOKING_DATES_CONTRACT,
  additionalneeds: 'string',
};

export const CREATED_BOOKING_CONTRACT: SchemaSpec = {
  bookingid: 'number',
  booking: BOOKING_CONTRACT,
};

/** GET /booking returns identifiers only, never the full record. */
export const BOOKING_SUMMARY_CONTRACT: SchemaSpec = {
  bookingid: 'number',
};
