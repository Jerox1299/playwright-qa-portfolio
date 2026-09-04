import type { Locator, Page } from '@playwright/test';
import type { CustomerInformation } from '@data/checkout.data';

/**
 * Page Object for the three-step checkout funnel: customer information, order overview and
 * confirmation.
 *
 * The three screens share one class because they form a single business transaction with no
 * meaningful entry point in the middle. Splitting them would produce classes with one method each
 * and force the spec to orchestrate plumbing instead of describing the requirement.
 */
export class CheckoutPage {
  static readonly INFORMATION_PATH = '/checkout-step-one.html';
  static readonly OVERVIEW_PATH = '/checkout-step-two.html';
  static readonly COMPLETE_PATH = '/checkout-complete.html';

  private readonly title: Locator;
  private readonly firstNameInput: Locator;
  private readonly lastNameInput: Locator;
  private readonly postalCodeInput: Locator;
  private readonly continueButton: Locator;
  private readonly cancelButton: Locator;
  private readonly errorMessage: Locator;
  private readonly summaryItems: Locator;
  private readonly subtotalLabel: Locator;
  private readonly taxLabel: Locator;
  private readonly totalLabel: Locator;
  private readonly finishButton: Locator;
  private readonly confirmationHeader: Locator;
  private readonly confirmationText: Locator;
  private readonly backHomeButton: Locator;

  constructor(private readonly page: Page) {
    this.title = page.getByTestId('title');

    // Step one: customer information.
    this.firstNameInput = page.getByTestId('firstName');
    this.lastNameInput = page.getByTestId('lastName');
    this.postalCodeInput = page.getByTestId('postalCode');
    this.continueButton = page.getByTestId('continue');
    this.cancelButton = page.getByTestId('cancel');
    this.errorMessage = page.getByTestId('error');

    // Step two: order overview and totals.
    this.summaryItems = page.getByTestId('inventory-item');
    this.subtotalLabel = page.getByTestId('subtotal-label');
    this.taxLabel = page.getByTestId('tax-label');
    this.totalLabel = page.getByTestId('total-label');
    this.finishButton = page.getByTestId('finish');

    // Step three: confirmation.
    this.confirmationHeader = page.getByTestId('complete-header');
    this.confirmationText = page.getByTestId('complete-text');
    this.backHomeButton = page.getByTestId('back-to-products');
  }

  /** Fills the customer form without submitting, so a spec can assert field-level validation. */
  async fillCustomerInformation(customer: CustomerInformation): Promise<void> {
    await this.firstNameInput.fill(customer.firstName);
    await this.lastNameInput.fill(customer.lastName);
    await this.postalCodeInput.fill(customer.postalCode);
  }

  async continueToOverview(): Promise<void> {
    await this.continueButton.click();
  }

  async cancel(): Promise<void> {
    await this.cancelButton.click();
  }

  async finishOrder(): Promise<void> {
    await this.finishButton.click();
  }

  async backToProducts(): Promise<void> {
    await this.backHomeButton.click();
  }

  getTitle(): Locator {
    return this.title;
  }

  getErrorMessage(): Locator {
    return this.errorMessage;
  }

  getSummaryItems(): Locator {
    return this.summaryItems;
  }

  getSummaryItemRow(itemName: string): Locator {
    return this.summaryItems.filter({
      has: this.page.getByRole('link', { name: itemName, exact: true }),
    });
  }

  getSubtotalLabel(): Locator {
    return this.subtotalLabel;
  }

  getTaxLabel(): Locator {
    return this.taxLabel;
  }

  getTotalLabel(): Locator {
    return this.totalLabel;
  }

  getConfirmationHeader(): Locator {
    return this.confirmationHeader;
  }

  getConfirmationText(): Locator {
    return this.confirmationText;
  }

  getFinishButton(): Locator {
    return this.finishButton;
  }
}
