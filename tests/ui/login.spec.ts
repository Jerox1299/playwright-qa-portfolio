import { expect, test } from '@playwright/test';
import { LoginPage } from '@pages/LoginPage';
import { InventoryPage } from '@pages/InventoryPage';
import { EMPTY_CREDENTIALS, USERS } from '@data/users.data';
import { CATALOGUE_SIZE } from '@data/products.data';

/**
 * Expected copy is asserted verbatim because the message is the requirement: a user must be told
 * why authentication failed. Values were captured from the live application, not assumed.
 */
const ERROR_LOCKED_OUT = 'Epic sadface: Sorry, this user has been locked out.';
const ERROR_USERNAME_REQUIRED = 'Epic sadface: Username is required';

test.describe('Authentication', () => {
  // Navigation only. No shared state is built here, so every test starts from an identical,
  // isolated browser context and the file is safe to run fully in parallel.
  test.beforeEach(async ({ page }) => {
    await new LoginPage(page).goto();
  });

  test('a standard user signs in and lands on the product catalogue', async ({ page }) => {
    const loginPage = new LoginPage(page);
    const inventoryPage = new InventoryPage(page);

    await loginPage.login(USERS.standard.username, USERS.standard.password);

    // Web-first assertions: each one polls until it passes or the expect timeout elapses.
    await expect(page).toHaveURL(/\/inventory\.html$/);
    await expect(inventoryPage.getTitle()).toHaveText('Products');
    await expect(inventoryPage.getInventoryList()).toBeVisible();
    await expect(inventoryPage.getInventoryItems()).toHaveCount(CATALOGUE_SIZE);
  });

  test('a locked out user is rejected with an accessible error', async ({ page }) => {
    const loginPage = new LoginPage(page);

    await loginPage.login(USERS.lockedOut.username, USERS.lockedOut.password);

    const error = loginPage.getErrorMessage();
    await expect(error).toBeVisible();
    await expect(error).toHaveText(ERROR_LOCKED_OUT);
    // The failure must reach assistive technology, not just sighted users.
    await expect(error).toHaveRole('heading');
    // And the rejection must be real: no navigation into the authenticated area.
    await expect(page).not.toHaveURL(/\/inventory\.html$/);
  });

  test('submitting empty credentials surfaces the required-field validation', async ({ page }) => {
    const loginPage = new LoginPage(page);

    await loginPage.login(EMPTY_CREDENTIALS.username, EMPTY_CREDENTIALS.password);

    await expect(loginPage.getErrorMessage()).toHaveText(ERROR_USERNAME_REQUIRED);
    await expect(loginPage.getUsernameInput()).toBeEmpty();
    await expect(page).not.toHaveURL(/\/inventory\.html$/);
  });
});
