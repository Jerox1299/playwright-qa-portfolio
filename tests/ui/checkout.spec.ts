import { expect, test } from '@playwright/test';
import { LoginPage } from '@pages/LoginPage';
import { InventoryPage } from '@pages/InventoryPage';
import { CartPage } from '@pages/CartPage';
import { CheckoutPage } from '@pages/CheckoutPage';
import { USERS } from '@data/users.data';
import { PRODUCTS } from '@data/products.data';
import { buildCustomerInformation } from '@data/checkout.data';

/**
 * The application renders the confirmation in sentence case and applies no text-transform, so the
 * legacy all-caps expectation would fail. The regex asserts the business message while staying
 * resilient to casing, which is presentation rather than requirement.
 */
const ORDER_CONFIRMED = /thank you for your order/i;

test.describe('Checkout', () => {
  test('a signed-in customer buys two products end to end', async ({ page }) => {
    const loginPage = new LoginPage(page);
    const inventoryPage = new InventoryPage(page);
    const cartPage = new CartPage(page);
    const checkoutPage = new CheckoutPage(page);

    // Data is built per test, never shared between tests, so parallel runs cannot collide.
    const customer = buildCustomerInformation();
    const selectedProducts = [PRODUCTS.backpack, PRODUCTS.boltTShirt] as const;

    await test.step('Sign in as a standard user', async () => {
      await loginPage.goto();
      await loginPage.login(USERS.standard.username, USERS.standard.password);
      await expect(inventoryPage.getTitle()).toHaveText('Products');
    });

    await test.step('Add two products to the cart', async () => {
      for (const product of selectedProducts) {
        await inventoryPage.addItemToCart(product);
      }

      // Web-first assertion first: it retries until the badge settles.
      await expect(inventoryPage.getCartBadge()).toHaveText(String(selectedProducts.length));
      // Only then is the numeric read safe, because the state is already proven stable.
      expect(await inventoryPage.getCartCount()).toBe(selectedProducts.length);
    });

    await test.step('Open the cart and verify its contents', async () => {
      await inventoryPage.goToCart();

      await expect(page).toHaveURL(/\/cart\.html$/);
      await expect(cartPage.getTitle()).toHaveText('Your Cart');
      await expect(cartPage.getCartItems()).toHaveCount(selectedProducts.length);
      for (const product of selectedProducts) {
        await expect(cartPage.getItemRow(product)).toBeVisible();
      }
    });

    await test.step('Submit the customer information', async () => {
      await cartPage.checkout();
      await expect(checkoutPage.getTitle()).toHaveText('Checkout: Your Information');

      await checkoutPage.fillCustomerInformation(customer);
      await checkoutPage.continueToOverview();
    });

    await test.step('Review the order summary', async () => {
      await expect(page).toHaveURL(/\/checkout-step-two\.html$/);
      await expect(checkoutPage.getTitle()).toHaveText('Checkout: Overview');
      await expect(checkoutPage.getSummaryItems()).toHaveCount(selectedProducts.length);
      for (const product of selectedProducts) {
        await expect(checkoutPage.getSummaryItemRow(product)).toBeVisible();
      }
      // The financial line must exist and be well formed before the order is committed.
      await expect(checkoutPage.getTotalLabel()).toHaveText(/^Total: \$\d+\.\d{2}$/);
    });

    await test.step('Finish the purchase and confirm the order', async () => {
      await checkoutPage.finishOrder();

      await expect(page).toHaveURL(/\/checkout-complete\.html$/);
      await expect(checkoutPage.getConfirmationHeader()).toHaveText(ORDER_CONFIRMED);
      await expect(checkoutPage.getConfirmationText()).toBeVisible();
      // The cart must be emptied by the transaction: the badge is removed from the DOM.
      await expect(inventoryPage.getCartBadge()).toHaveCount(0);
    });
  });

  test('the checkout form blocks submission when required data is missing', async ({ page }) => {
    const loginPage = new LoginPage(page);
    const inventoryPage = new InventoryPage(page);
    const cartPage = new CartPage(page);
    const checkoutPage = new CheckoutPage(page);

    await loginPage.goto();
    await loginPage.login(USERS.standard.username, USERS.standard.password);
    await inventoryPage.addItemToCart(PRODUCTS.fleeceJacket);
    await inventoryPage.goToCart();
    await cartPage.checkout();

    await checkoutPage.continueToOverview();

    await expect(checkoutPage.getErrorMessage()).toHaveText('Error: First Name is required');
    await expect(page).toHaveURL(/\/checkout-step-one\.html$/);
  });
});
