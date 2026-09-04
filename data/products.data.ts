/**
 * Catalogue names as rendered by the application.
 *
 * Specs reference products by business name, never by generated selector id, so a change in the
 * DOM id strategy does not ripple into the tests.
 */
export const PRODUCTS = {
  backpack: 'Sauce Labs Backpack',
  bikeLight: 'Sauce Labs Bike Light',
  boltTShirt: 'Sauce Labs Bolt T-Shirt',
  fleeceJacket: 'Sauce Labs Fleece Jacket',
  onesie: 'Sauce Labs Onesie',
  redTShirt: 'Test.allTheThings() T-Shirt (Red)',
} as const;

export type ProductName = (typeof PRODUCTS)[keyof typeof PRODUCTS];

/** The catalogue size is itself a business assertion, so it lives with the data. */
export const CATALOGUE_SIZE = Object.keys(PRODUCTS).length;
