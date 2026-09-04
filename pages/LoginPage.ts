import type { Locator, Page } from '@playwright/test';

/**
 * Page Object for the SauceDemo login screen.
 *
 * Design rules applied across every page object in this repository:
 *  - It exposes BEHAVIOUR (actions) and STATE (locators), never assertions. Assertions live in the
 *    spec so the test reads as the requirement it verifies.
 *  - Query methods return Locator, not string. A Locator is lazy, so the spec can wrap it in a
 *    web-first assertion that retries. Returning a resolved string would snapshot the DOM at an
 *    arbitrary instant and reintroduce the race conditions auto-waiting exists to remove.
 *  - It never returns another page object. Navigation changes the URL, and the spec decides which
 *    page it wants to talk to next. That keeps the graph of page objects acyclic and readable.
 */
export class LoginPage {
  private static readonly PATH = '/';

  private readonly usernameInput: Locator;
  private readonly passwordInput: Locator;
  private readonly loginButton: Locator;
  private readonly errorMessage: Locator;

  constructor(private readonly page: Page) {
    // testIdAttribute is configured as 'data-test', so getByTestId targets the contract the
    // application itself publishes rather than volatile CSS classes.
    this.usernameInput = page.getByTestId('username');
    this.passwordInput = page.getByTestId('password');
    this.loginButton = page.getByTestId('login-button');
    // Rendered as an <h3>, therefore announced as a heading by assistive technology.
    this.errorMessage = page.getByTestId('error');
  }

  async goto(): Promise<void> {
    await this.page.goto(LoginPage.PATH);
  }

  /** Fills both credentials and submits. No waits: fill() and click() auto-wait for actionability. */
  async login(username: string, password: string): Promise<void> {
    await this.usernameInput.fill(username);
    await this.passwordInput.fill(password);
    await this.loginButton.click();
  }

  /** Submits whatever is currently in the form, used for required-field validation. */
  async submit(): Promise<void> {
    await this.loginButton.click();
  }

  getErrorMessage(): Locator {
    return this.errorMessage;
  }

  getUsernameInput(): Locator {
    return this.usernameInput;
  }

  getPasswordInput(): Locator {
    return this.passwordInput;
  }

  getLoginButton(): Locator {
    return this.loginButton;
  }
}
