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
          "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
      },
    });
  });
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
test('No downloads without an API call', async ({ page }) => {
  let calls = 0;
  page.on('request', (request) => {
    if (request.url().includes('/api/')) calls++;
  });
  await page.route('**/resume/test-v1/resume.pdf', (route) =>
    route.fulfill({ contentType: 'application/pdf', body: '%PDF-1.4\n%%EOF' }),
  );
  await page.goto('/');
  await page.getByRole('button', { name: /Download resume/ }).click();
  await page.getByRole('radio', { name: 'No', exact: true }).check();
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: /Continue to download/ }).click();
  await download;
  expect(calls).toBe(0);
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
  await page.route('**/resume/test-v1/resume.pdf', (route) =>
    route.fulfill({ contentType: 'application/pdf', body: '%PDF-1.4\n%%EOF' }),
  );
  await page.goto('/');
  await page.getByRole('button', { name: /Download resume/ }).click();
  await page.getByRole('radio', { name: 'Yes', exact: true }).check();
  await page.getByRole('button', { name: /Continue to download/ }).click();
  expect(keys).toHaveLength(0);
  await page.getByLabel('Company name').fill('Example Company');
  expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
  await page.getByRole('button', { name: /Continue to download/ }).click();
  await expect(page.getByRole('status')).toContainText('could not save');
  expect(downloadCount).toBe(0);
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: /Continue to download/ }).click();
  await download;
  expect(keys).toHaveLength(2);
  expect(keys[0]).toBe(keys[1]);
});
test('Escape closes the modal and restores focus', async ({ page }) => {
  await page.goto('/');
  const trigger = page.getByRole('button', { name: /Download resume/ });
  await trigger.click();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await expect(trigger).toBeFocused();
});
