import { defineConfig, devices } from '@playwright/test';
export default defineConfig({
  testDir: './tests/e2e',
  use: { baseURL: 'http://127.0.0.1:4323', trace: 'retain-on-failure' },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['Pixel 7'] } },
  ],
  webServer: {
    command: 'npm run build && npm run preview -- --ignore-lock --port 4323',
    url: 'http://127.0.0.1:4323',
    reuseExistingServer: false,
    env: { PUBLIC_RESUME_VERSION: 'test-v1' },
  },
});
