import {test, expect} from '@playwright/test';

test('first visit explains evidence limits before entering and remembers this session', async ({page}) => {
 await page.goto('/');
 const notice = page.getByRole('dialog', {name: 'A clearer picture, built one record at a time.'});
 await expect(notice).toBeVisible();
 await expect(notice).toContainText('Coverage is incomplete');
 await expect(notice).toContainText('does not establish payment or completion');
 const enter = notice.getByRole('button', {name: 'I understand — explore Hisaab'});
 await expect(enter).toBeFocused();
 expect(await page.locator('.atlas-shell').evaluate(element => !!element.closest('[inert]'))).toBe(true);
 await notice.getByText('How the evidence process works', {exact: true}).click();
 await expect(notice).toContainText('Publish reviewed evidence with sources, retain gaps');
 await enter.click();
 await expect(notice).toHaveCount(0);
 expect(await page.locator('.atlas-shell').evaluate(element => !!element.closest('[inert]'))).toBe(false);
 await page.reload();
 await expect(notice).toHaveCount(0);
 await expect(page.getByRole('button', {name: 'Explore India', exact: true})).toBeVisible();
});
