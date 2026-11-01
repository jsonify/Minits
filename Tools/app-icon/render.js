// Renders Tools/app-icon/build/*.svg (from make_icon.py) to the PNGs in Minits/Assets.xcassets/AppIcon.appiconset.
// Needs Node and Playwright with Chromium (npm i -D playwright && npx playwright install chromium).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const build = path.join(__dirname, 'build');
const out = path.join(__dirname, '..', '..', 'Minits', 'Assets.xcassets', 'AppIcon.appiconset');
const jobs = [['ios-light', 'AppIcon-iOS.png', 1024], ['ios-dark', 'AppIcon-iOS-Dark.png', 1024]];
for (const pt of [16, 32, 128, 256, 512]) {
  jobs.push(['mac', `AppIcon-mac-${pt}.png`, pt], ['mac', `AppIcon-mac-${pt}@2x.png`, pt * 2]);
}

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const [svg, file, px] of jobs) {
    const src = fs.readFileSync(path.join(build, `${svg}.svg`), 'utf8').replace('width="1024" height="1024"', `width="${px}" height="${px}"`);
    await page.setViewportSize({ width: px, height: px });
    await page.setContent(`<html><body style="margin:0;background:transparent">${src}</body></html>`);
    // iOS icons must be opaque; macOS ones keep their transparent margin.
    await page.locator('svg').screenshot({ path: path.join(out, file), omitBackground: svg === 'mac' });
  }
  await browser.close();
  console.log('wrote', out);
})();
