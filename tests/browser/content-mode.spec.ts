import {test,expect} from './preview-fixture';
import {readFile} from 'node:fs/promises';
import type {Page} from '@playwright/test';

async function openManualStudio(page:Page){
 await page.getByRole('button',{name:'Open content mode',exact:true}).click();
 const studio=page.getByLabel('Content studio',{exact:true});
 // Opening starts the intentional clean automatic tour; Escape must stop it
 // and restore the controls before testing individual director operations.
 await expect(studio).toHaveClass(/is-collapsed/);
 await page.keyboard.press('Escape');
 await expect(studio).toBeVisible();
 await expect(studio.getByRole('status')).toHaveText('Ready to frame a shot');
 await studio.getByLabel('Camera speed',{exact:true}).selectOption('normal');
 return studio;
}
test.use({channel:process.env.HISAAB_BROWSER_CHANNEL});
test.setTimeout(90000);
test('card presets frame source sections, preserve unknowns and replay saved framing',async({page})=>{
 await page.goto('/asset/f822c8e8a8d3fb70e9b4%3A95317?state=9&explore=1');await page.getByRole('heading',{name:'Panchayat HQ',exact:true}).waitFor();const studio=await openManualStudio(page);
 await expect(studio.getByLabel('Card shot presets').locator('div > button')).toHaveCount(9);
 await studio.getByLabel('Wait for imagery',{exact:true}).uncheck();await studio.getByRole('button',{name:'Money close-up',exact:true}).click();await expect(page.locator('.atlas-shell')).toHaveAttribute('data-card-focus','money');await expect(page.locator('.atlas-receipt-money strong')).toHaveText(['—','—','—']);
 await studio.getByRole('button',{name:'Payment detail',exact:true}).click();await expect(studio.getByText(/This record has no individual payment details/)).toBeVisible();
 await studio.getByRole('button',{name:'Source proof',exact:true}).click();await expect(page.locator('.atlas-location-source')).toHaveAttribute('open','');await expect.poll(()=>page.getByLabel('Project receipt',{exact:true}).evaluate(el=>el.scrollTop)).toBeGreaterThan(0);
 await studio.getByRole('button',{name:'Save current camera',exact:true}).click();await studio.getByLabel('Shot 1 movement seconds').fill('.5');await studio.getByLabel('Shot 1 hold seconds').fill('0');await studio.getByRole('button',{name:'Director',exact:true}).click();await studio.getByRole('button',{name:'Reset card framing',exact:true}).click();await expect(page.locator('.atlas-shell')).toHaveAttribute('data-card-focus','overview');
 await studio.getByRole('button',{name:'Shot Builder',exact:true}).click();await studio.getByRole('button',{name:'Preview shot 1',exact:true}).click();await expect(studio.getByRole('status')).toHaveText('Sequence complete',{timeout:15000});await expect(page.locator('.atlas-shell')).toHaveAttribute('data-card-focus','source');
});
test('Director, saved timeline, framing, import safety and keyboard controls work together',async({page})=>{
 const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('/?explore=1');await page.locator('.map-canvas[data-zoom]').waitFor();
 const studio=await openManualStudio(page);
 await expect(studio.getByRole('button',{name:'Gentle push-in',exact:true})).toBeEnabled();
 await studio.getByLabel('Wait for imagery',{exact:true}).uncheck();await studio.getByLabel('Shot duration in seconds').fill('2');
 await studio.getByRole('button',{name:'Gentle push-in',exact:true}).click();await expect(studio.getByRole('status')).toContainText('Gentle push-in');
 await page.waitForTimeout(250);await page.keyboard.press('Space');await expect(studio.getByRole('status')).toContainText('Paused');
 await page.keyboard.press('Space');await expect(studio.getByRole('status')).toContainText('Looping',{timeout:10000});
 await studio.getByRole('button',{name:'Stop camera sequence',exact:true}).click();await expect(studio.getByRole('status')).toHaveText('Ready to frame a shot');
 await studio.getByRole('button',{name:'Save current camera',exact:true}).click();await studio.getByRole('button',{name:'Save current camera',exact:true}).click();await expect(studio.locator('.content-timeline article')).toHaveCount(2);
 await studio.getByLabel('Shot 1 name',{exact:true}).fill('Opening');await studio.getByRole('button',{name:'Move shot 1 down',exact:true}).click();await expect(studio.getByLabel('Shot 2 name',{exact:true})).toHaveValue('Opening');
 const downloadPromise=page.waitForEvent('download');await studio.getByRole('button',{name:'Export',exact:true}).click();const download=await downloadPromise;const project=JSON.parse(await readFile((await download.path())!,'utf8'));expect(project.shots).toHaveLength(2);expect(project.shots[1].name).toBe('Opening');expect(project.shots[0]).not.toHaveProperty('payments');
 await studio.locator('input[type=file]').setInputFiles({name:'bad.json',mimeType:'application/json',buffer:Buffer.from('{"version":999,"shots":[]}')});await expect(studio.getByText('Invalid shot file. Your current timeline was kept.')).toBeVisible();await expect(studio.locator('.content-timeline article')).toHaveCount(2);
 for(let i=1;i<=2;i++){await studio.getByLabel(`Shot ${i} movement seconds`).fill('.5');await studio.getByLabel(`Shot ${i} hold seconds`).fill('0');}
 await studio.getByRole('button',{name:'Play timeline',exact:true}).click();await expect(studio.getByRole('status')).toHaveText('Sequence complete',{timeout:12000});
 await studio.getByLabel('Content framing').selectOption('portrait');await expect.poll(async()=>{const b=await page.locator('.atlas-shell').boundingBox();return b!.width/b!.height;}).toBeCloseTo(9/16,2);
 await studio.getByLabel('Clean frame',{exact:true}).check();await expect(page.getByLabel('Map controls',{exact:true})).toBeHidden();await expect(page.locator('.mapboxgl-ctrl-attrib')).toBeVisible();
 await page.keyboard.press('h');await expect(studio).toBeHidden();await page.keyboard.press('Escape');await expect(studio).toBeVisible();
 await studio.getByRole('button',{name:'Exit content mode',exact:true}).click();await expect(page.locator('.atlas-shell')).toHaveAttribute('data-content','false');
 await openManualStudio(page);await studio.getByRole('button',{name:'Shot Builder',exact:true}).click();await expect(studio.locator('.content-timeline article')).toHaveCount(2);
 expect(errors).toEqual([]);
});

test('guided showcases play map-only sequences and stop cleanly',async({page})=>{
 const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('/?explore=1');await page.locator('.map-canvas[data-zoom]').waitFor();const studio=await openManualStudio(page);
 await studio.getByLabel('Wait for imagery',{exact:true}).uncheck();await studio.getByLabel('Shot duration in seconds').fill('2');await studio.getByRole('button',{name:'Showcase',exact:true}).click();await expect(studio.locator('.content-showcases > button')).toHaveCount(5);
 await studio.getByRole('button',{name:/^Country → scale → receipt/}).click();await expect(studio.getByText('No asset selected: playing the map-only portion. Select a dot to include its receipt.')).toBeVisible();await expect(studio.getByRole('status')).toHaveText('Sequence complete',{timeout:20000});
 await studio.getByRole('button',{name:/^Landscape journey/}).click();await expect(studio.getByRole('status')).toContainText('1/5');await studio.getByRole('button',{name:'Stop camera sequence',exact:true}).click();await expect(studio.getByRole('status')).toHaveText('Ready to frame a shot');expect(errors).toEqual([]);
});

test('saved asset shots restore the source card and receipt reveal remains interruptible',async({page})=>{
 await page.goto('/asset/f822c8e8a8d3fb70e9b4%3A95317?state=9&explore=1');await page.getByRole('heading',{name:'Panchayat HQ',exact:true}).waitFor();
 const studio=await openManualStudio(page);
 await studio.getByLabel('Wait for imagery',{exact:true}).uncheck();await studio.getByLabel('Shot duration in seconds').fill('2');
 await studio.getByRole('button',{name:'Receipt reveal',exact:true}).click();await expect(page.locator('.atlas-shell')).toHaveAttribute('data-content-card','hide');
 await expect(page.locator('.atlas-shell')).toHaveAttribute('data-content-card','show',{timeout:10000});await expect(studio.getByRole('status')).toContainText('Looping');
 await studio.getByRole('button',{name:'Stop camera sequence',exact:true}).click();await expect(studio.getByRole('status')).toHaveText('Ready to frame a shot');
 await studio.getByRole('button',{name:'Save current camera',exact:true}).click();await studio.getByLabel('Shot 1 movement seconds').fill('.5');await studio.getByLabel('Shot 1 hold seconds').fill('0');
 // Restore a saved source selection after navigating away through the real app.
 await studio.getByRole('button',{name:'Hide content controls',exact:true}).click();await page.getByRole('button',{name:'Back from project',exact:true}).click();await page.keyboard.press('Escape');await expect(page.getByLabel('Project receipt',{exact:true})).toBeHidden();
 await studio.getByRole('button',{name:'Preview shot 1',exact:true}).click();await expect(page.getByRole('heading',{name:'Panchayat HQ',exact:true})).toBeVisible();await expect(studio.getByRole('status')).toHaveText('Sequence complete',{timeout:15000});
 await expect(page.getByLabel('Project receipt',{exact:true}).getByText('Funding not linked',{exact:true})).toBeVisible();
});
