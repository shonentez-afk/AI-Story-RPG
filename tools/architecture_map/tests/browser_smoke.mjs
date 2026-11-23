import { chromium } from 'playwright';
import assert from 'node:assert/strict';
const browser = await chromium.launch({headless: true});
const page = await browser.newPage({viewport:{width:1440,height:900}});
const issues=[];
page.on('pageerror',error=>issues.push(String(error)));
try {
  const response=await page.goto('http://127.0.0.1:8765/docs/architecture-map/index.html',{waitUntil:'networkidle'});
  assert.equal(response?.status(),200);
  await page.getByRole('heading',{name:/RPG API/}).waitFor();
  assert.ok(await page.locator('#nodes .node').count()>=10);
  await page.waitForFunction(() => Boolean(customElements.get('likec4-view')), null, {timeout:30000});
  const nativeView = page.locator('likec4-view');
  await nativeView.waitFor({state:'visible'});
  assert.equal(await nativeView.getAttribute('view-id'),'overview');
  await page.locator('#architectureView').selectOption('runtime');
  assert.equal(await nativeView.getAttribute('view-id'),'runtime');
  await page.locator('#architectureView').selectOption('overview');

  assert.ok(await page.getByRole('link',{name:/Исходник, строка/}).first().getAttribute('href'));
  await page.locator('#code').click();
  await page.getByRole('heading',{name:/Связи кода/}).waitFor({timeout:30000});
  assert.ok((await page.locator('#path').textContent()).includes('GitNexus'));
  assert.ok((await page.locator('#path').textContent()).includes('7395') ||
            (await page.locator('#path').textContent()).includes('узлов'));
  await page.locator('#search').fill('commitChoice');
  await page.waitForTimeout(500);
  const codeNodes=page.locator('#nodes .node');
  assert.ok(await codeNodes.count()>0);
  console.log('CODE_CANVAS_DEBUG', await page.evaluate(() => ({
    mode: document.getElementById('code').className,
    canvasHidden: document.getElementById('canvas').hasAttribute('hidden'),
    canvasDisplay: getComputedStyle(document.getElementById('canvas')).display,
    canvasRect: document.getElementById('canvas').getBoundingClientRect().toJSON(),
    likec4Hidden: document.getElementById('likec4Host').hidden,
    firstNode: document.querySelector('#nodes .node')?.getBoundingClientRect().toJSON()
  })));
  assert.equal(await page.locator('#canvas').evaluate(el=>el.hasAttribute('hidden')),false);
  const firstVisible=page.locator('#nodes .node:not(.hidden)').first();
  await firstVisible.click({timeout:8000});

  await page.getByText('Потенциальное влияние изменений').waitFor();
  await page.locator('#direction').selectOption('incoming');
  await page.locator('#confidence').selectOption('gitnexus');
  await page.locator('#confidence').selectOption('call_candidate');
  await page.locator('#zin').click();
  await page.locator('#fit').click();
  await page.locator('#arch').click();
  assert.equal(await page.locator('#canvas').evaluate(el=>el.hasAttribute('hidden')),true);
  await page.screenshot({path:'/tmp/architecture-map-desktop.png',fullPage:true});
  await page.getByRole('heading',{name:/RPG API/}).waitFor();
  assert.deepEqual(issues,[]);
  console.log('Browser QA PASS: overview, indexed code graph, search, details, impact, filters, navigation, zoom.');
} finally {
  await browser.close();
}
