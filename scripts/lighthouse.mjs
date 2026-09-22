import lighthouse from 'lighthouse';
import { chromium } from '@playwright/test';
import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';

const server = spawn(
  process.execPath,
  [
    'node_modules/astro/bin/astro.mjs',
    'preview',
    '--host',
    '127.0.0.1',
    '--port',
    '4322',
    '--ignore-lock',
  ],
  { stdio: 'ignore' },
);
let chrome;
try {
  for (let attempt = 0; attempt < 50; attempt++) {
    try {
      if ((await fetch('http://127.0.0.1:4322')).ok) break;
    } catch {
      /* Wait for the local server. */
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  chrome = spawn(
    chromium.executablePath(),
    [
      '--headless',
      '--no-sandbox',
      '--remote-debugging-port=9222',
      '--user-data-dir=/tmp/resume-lighthouse-profile',
    ],
    { stdio: 'ignore' },
  );
  for (let attempt = 0; attempt < 50; attempt++) {
    try {
      if ((await fetch('http://127.0.0.1:9222/json/version')).ok) break;
    } catch {
      /* Wait for Chromium. */
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  const result = await lighthouse('http://127.0.0.1:4322', {
    port: 9222,
    output: 'html',
    onlyCategories: ['performance', 'accessibility', 'best-practices'],
    logLevel: 'error',
  });
  await mkdir('.artifacts/lighthouse', { recursive: true });
  await writeFile('.artifacts/lighthouse/report.html', result.report);
  for (const [name, minimum] of Object.entries({
    performance: 0.9,
    accessibility: 0.95,
    'best-practices': 0.9,
  })) {
    const score = result.lhr.categories[name].score;
    console.log(`${name}: ${score}`);
    if (score < minimum) process.exitCode = 1;
  }
} finally {
  chrome?.kill();
  server.kill();
}
