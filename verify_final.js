const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.setViewportSize({ width: 1280, height: 800 });

  try {
    await page.goto('http://localhost:3000', { waitUntil: 'networkidle' });
    await page.waitForTimeout(3000);
    await page.screenshot({ path: 'final_home.png' });
    console.log('Screenshot saved as final_home.png');
  } catch (e) {
    console.error('Error:', e);
  } finally {
    await browser.close();
  }
})();
