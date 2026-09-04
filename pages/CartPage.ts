import type { Locator, Page } from '@playwright/test';

/**
 * Page Object for the cart.
 *
 * It exists as its own class because /cart.html is a distinct URL with its own controls. Folding
 * its checkout button into InventoryPage or CheckoutPage would make a page object act on a page it
 * does not own, which is the ownership smell that makes POM layers rot.
 */
export class CartPage {
  static readonly PATH = '/cart.html';

  private readonly title: Locator;
  private readonly cartItems: Locator;
  private readonly checkoutButton: Locator;
  private readonly continueShoppingButton: Locator;

  constructor(private readonly page: Page) {
    this.title = page.getByTestId('title');
    this.cartItems = page.getByTestId('inventory-item');
    this.checkoutButton = page.getByTestId('checkout');
    this.continueShoppingButton = page.getByTestId('continue-shopping');
  }

  async checkout(): Promise<void> {
    await this.checkoutButton.click();
  }

  async continueShopping(): Promise<void> {
    await this.continueShoppingButton.click();
  }

  async removeItem(itemName: string): Promise<void> {
    await this.getItemRow(itemName).getByRole('button', { name: 'Remove' }).click();
  }

  getItemRow(itemName: string): Locator {
    return this.cartItems.filter({
      has: this.page.getByRole('link', { name: itemName, exact: true }),
    });
  }

  getTitle(): Locator {
    return this.title;
  }

  getCartItems(): Locator {
    return this.cartItems;
  }

  getCheckoutButton(): Locator {
    return this.checkoutButton;
  }
}
