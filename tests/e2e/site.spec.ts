import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
test.beforeEach(async ({ page }) => {
  // Enforce the deployed CSP on the real production build, not the dev server.
  await page.route('**/*', async (route) => {
    if (route.request().resourceType() !== 'document') return route.continue();
    const response = await route.fetch();
    await route.fulfill({
      response,
      headers: {
        ...response.headers(),
        'Content-Security-Policy':
          "default-src 'self'; script-src 'self' https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
      },
    });
  });
  await page.route(
    'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit',
    (route) =>
      route.fulfill({
        contentType: 'application/javascript',
        body: `let options; window.turnstile = {
      render(element, value) { options = value; setTimeout(() => options.callback('test-token'), 0); return 'test-widget'; },
      reset() { setTimeout(() => options.callback('retry-token'), 50); }
    };`,
      }),
  );
  await page.route('**/api/resume-download', (route) =>
    route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        pdf: Buffer.from('%PDF-1.4\n%%EOF').toString('base64'),
      }),
    }),
  );
});
test('English page and accessible certificate space', async ({
  page,
}, testInfo) => {
  await page.goto('/');
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await expect(
    page.getByRole('heading', { name: 'Infrastructure, built with intent.' }),
  ).toBeVisible();
  await expect(
    page.getByRole('heading', { name: 'Learning with a paper trail.' }),
  ).toBeVisible();
  expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
  await page.screenshot({
    path: `.artifacts/screenshots/${testInfo.project.name}.png`,
    fullPage: true,
  });
});
test('No verifies CAPTCHA without recording recruiter data', async ({
  page,
}) => {
  let calls = 0;
  page.on('request', (request) => {
    if (request.url().includes('/api/')) calls++;
  });
  await page.goto('/');
  await page.getByRole('button', { name: /Download resume/ }).click();
  await page.getByRole('radio', { name: 'No', exact: true }).check();
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: /Continue to download/ }).click();
  await download;
  expect(calls).toBe(1);
});
test('Yes requires a company, waits for success, and preserves the retry key', async ({
  page,
}) => {
  const keys: string[] = [];
  let downloadCount = 0;
  page.on('download', () => downloadCount++);
  await page.route('**/api/recruiter-interest', async (route) => {
    expect(route.request().postDataJSON()).toEqual({
      recruiter: true,
      companyName: 'Example Company',
    });
    keys.push(route.request().headers()['idempotency-key']);
    await route.fulfill({
      status: keys.length === 1 ? 503 : 201,
      contentType: 'application/json',
      body: '{}',
    });
  });
  await page.goto('/');
  await page.getByRole('button', { name: /Download resume/ }).click();
  await page.getByRole('radio', { name: 'Yes', exact: true }).check();
  await page.getByRole('button', { name: /Continue to download/ }).click();
  expect(keys).toHaveLength(0);
  await page.getByLabel('Company name').fill('Example Company');
  expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
  await page.getByRole('button', { name: /Continue to download/ }).click();
  await expect(page.getByRole('status')).toContainText('could not complete');
  expect(downloadCount).toBe(0);
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: /Continue to download/ }).click();
  await download;
  expect(keys).toHaveLength(2);
  expect(keys[0]).toBe(keys[1]);
});
test('Rejected CAPTCHA never downloads', async ({ page }) => {
  let downloads = 0;
  page.on('download', () => downloads++);
  await page.route('**/api/resume-download', (route) =>
    route.fulfill({ status: 403, body: '{}' }),
  );
  await page.goto('/');
  await page.getByRole('button', { name: /Download resume/ }).click();
  await page.getByRole('radio', { name: 'No', exact: true }).check();
  await page.getByRole('button', { name: /Continue to download/ }).click();
  await expect(page.getByRole('status')).toContainText('could not complete');
  expect(downloads).toBe(0);
});
test('Unavailable CAPTCHA keeps download disabled', async ({ page }) => {
  await page.route(
    'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit',
    (route) => route.abort(),
  );
  await page.goto('/');
  await page.getByRole('button', { name: /Download resume/ }).click();
  await expect(page.getByRole('status')).toContainText(
    'Security check unavailable',
  );
  await expect(
    page.getByRole('button', { name: /Continue to download/ }),
  ).toBeDisabled();
});
test('Learning path navigation and three verified credentials', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page.locator('.certificate')).toHaveCount(3);
  await page.getByRole('link', { name: 'Learning path', exact: true }).click();
  await expect(
    page.getByRole('heading', { name: 'Learning path.' }),
  ).toBeVisible();
  expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
});
test('Escape closes the modal and restores focus', async ({ page }) => {
  await page.goto('/');
  const trigger = page.getByRole('button', { name: /Download resume/ });
  await trigger.click();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await expect(trigger).toBeFocused();
});
