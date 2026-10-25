import {test as base, expect} from '@playwright/test';

// Existing journeys exercise the map as a returning visitor. The entry notice
// itself is covered separately without this acknowledgement fixture.
export const test = base.extend<{acknowledgedPreview: void}>({
 acknowledgedPreview: [async ({context}, use) => {
  await context.addInitScript(() => {
   try { sessionStorage.setItem('hisaab-public-preview-2026-10-25', 'understood'); } catch {}
  });
  await use();
 }, {auto: true}],
});
export {expect};
