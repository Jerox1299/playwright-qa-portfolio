/**
 * Checkout customer data plus a small factory.
 *
 * The factory keeps every test independent: a spec asks for a customer and may override only the
 * field under test, instead of mutating a shared object that other parallel tests also read.
 */
export interface CustomerInformation {
  readonly firstName: string;
  readonly lastName: string;
  readonly postalCode: string;
}

const DEFAULT_CUSTOMER: CustomerInformation = {
  firstName: 'Ada',
  lastName: 'Lovelace',
  postalCode: '28001',
};

export function buildCustomerInformation(
  overrides: Partial<CustomerInformation> = {},
): CustomerInformation {
  return { ...DEFAULT_CUSTOMER, ...overrides };
}
