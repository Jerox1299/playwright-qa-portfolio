import type { Locator, Page } from '@playwright/test';

/** Page Object for the product catalogue shown after a successful login. */
export class InventoryPage {
  static readonly PATH = '/inventory.html';

  private readonly title: Locator;
  private readonly inventoryList: Locator;
  private readonly inventoryItems: Locator;
  private readonly cartLink: Locator;
  private readonly cartBadge: Locator;
  private readonly sortDropdown: Locator;

  constructor(private readonly page: Page) {
    this.title = page.getByTestId('title');
    this.inventoryList = page.getByTestId('inventory-list');
    this.inventoryItems = page.getByTestId('inventory-item');
    this.cartLink = page.getByTestId('shopping-cart-link');
    this.cartBadge = page.getByTestId('shopping-cart-badge');
    this.sortDropdown = page.getByTestId('product-sort-container');
  }

  async goto(): Promise<void> {
    await this.page.goto(InventoryPage.PATH);
  }

  /**
   * Adds a product by its business name.
   *
   * The card is resolved by its accessible link name and the button by its ARIA role, so the test
   * survives any change to the generated data-test id, which SauceDemo derives from the product
   * name and would otherwise force string munging inside the test layer.
   */
  async addItemToCart(itemName: string): Promise<void> {
    await this.getItemCard(itemName).getByRole('button', { name: 'Add to cart' }).click();
  }

  async removeItemFromCart(itemName: string): Promise<void> {
    await this.getItemCard(itemName).getByRole('button', { name: 'Remove' }).click();
  }

  async goToCart(): Promise<void> {
    await this.cartLink.click();
  }

  /**
   * Numeric snapshot of the cart badge, returning 0 when the badge is absent.
   *
   * This is a query for arithmetic, not a synchronisation point. Assert cart state with
   * expect(getCartBadge()).toHaveText(...) first, which retries; use this only once the state is
   * already settled.
   */
  async getCartCount(): Promise<number> {
    if ((await this.cartBadge.count()) === 0) {
      return 0;
    }
    const raw = (await this.cartBadge.textContent()) ?? '0';
    const parsed = Number.parseInt(raw.trim(), 10);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  getItemCard(itemName: string): Locator {
    return this.inventoryItems.filter({
      has: this.page.getByRole('link', { name: itemName, exact: true }),
    });
  }

  getTitle(): Locator {
    return this.title;
  }

  getInventoryList(): Locator {
    return this.inventoryList;
  }

  getInventoryItems(): Locator {
    return this.inventoryItems;
  }

  getCartBadge(): Locator {
    return this.cartBadge;
  }

  getCartLink(): Locator {
    return this.cartLink;
  }

  getSortDropdown(): Locator {
    return this.sortDropdown;
  }
}
