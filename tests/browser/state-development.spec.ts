import {test,expect} from '@playwright/test';
test('two-year state evidence stays inside Spending with MFA and distinct amounts',async({page})=>{
 await page.goto('/');
 await page.getByRole('button',{name:'Explore India',exact:true}).click();
 await Promise.all([page.waitForResponse(r=>r.url().includes('/api/v1/evidence-progress')&&r.status()===200),page.getByRole('button',{name:'Evidence progress and data acquisition'}).click()]);
 const section=page.getByRole('region',{name:'Two-year state development collection'});
 await expect(section.getByRole('heading',{name:'State-by-state development collection'})).toBeVisible();
 await expect(section.getByLabel('State',{exact:true}).locator('option')).toHaveCount(28);
 // Server authorization is covered by API tests and a separate live 401 check.
 // Keep this browser interaction deterministic under concurrent WebGL load.
 await page.route('**/api/v1/admin/state-development?**',route=>route.fulfill({status:401,json:{error:'Owner MFA sign-in required to inspect collected state evidence.'}}));
 await section.getByRole('button',{name:'Inspect collected evidence'}).click();
 await expect(section.getByRole('alert')).toContainText('Owner MFA sign-in required');
 // Synthetic browser-only data exercises rendering, never server publication.
 await page.route('**/api/v1/admin/state-development?**',async route=>{
  const p=new URL(route.request().url()).searchParams;
  const budget=p.get('section')==='budget';
  if(p.get('state')==='36'){
   await route.fulfill({json:{state:{code:'36',name:'Telangana'},section:'budget',page:1,pageSize:25,total:1,approved:false,rows:[{id:'synthetic-department',purposeLabel:'Synthetic department allocation',financialYear:'2026-2027',measure:'allocated',estimate:'original',amountRupees:'301.00',components:[{label:'Establishment',amountRupees:'100.00'},{label:'Scheme',amountRupees:'200.00'}],printedArithmeticDifferenceCrore:'0.0000001',source:{url:'https://example.invalid/browser-fixture',locator:'Synthetic test only'}}]}});return;
  }
  await route.fulfill({json:{state:{code:'28',name:'Andhra Pradesh'},section:p.get('section'),page:1,pageSize:25,total:1,approved:false,rows:[budget?{id:'synthetic-budget',purposeLabel:'Synthetic education allocation',financialYear:'2026-2027',measure:'allocated',estimate:'original',amountRupees:'100.10',revenueRupees:'60.00',capitalRupees:'40.10',printedArithmeticDifferenceCrore:'0.00',source:{url:'https://example.invalid/browser-fixture',locator:'Synthetic test only'}}:{id:'synthetic-actual',purposeLabel:'Synthetic expenditure',financialYear:'2025-2026',measure:'reported_spent',amountRupees:'80.00',periodStart:'2025-04-01',periodEnd:'2026-03-31',source:{url:'https://example.invalid/browser-fixture',locator:'Synthetic test only'}}]}});
 });
 await section.getByLabel('Evidence',{exact:true}).selectOption('budget');
 await section.getByRole('button',{name:'Inspect collected evidence'}).click();
 await section.getByText('Synthetic education allocation',{exact:true}).click();
 await expect(section.getByText('₹100.10',{exact:true})).toBeVisible();
 await expect(section.getByText('Components of the total; do not add them again.',{exact:false})).toBeVisible();
 await section.getByLabel('State',{exact:true}).selectOption('36');
 await section.getByRole('button',{name:'Inspect collected evidence'}).click();
 await section.getByText('Synthetic department allocation',{exact:true}).click();
 await expect(section.getByText('₹301.00',{exact:true})).toBeVisible();
 await expect(section.getByText('Establishment: ₹100.00',{exact:false})).toBeVisible();
 await section.getByLabel('State',{exact:true}).selectOption('28');
 await section.getByLabel('Evidence',{exact:true}).selectOption('expenditure');
 await section.getByRole('button',{name:'Inspect collected evidence'}).click();
 await section.getByText('Synthetic expenditure',{exact:true}).click();
 await expect(section.getByText('₹80.00',{exact:true})).toBeVisible();
 await expect(section.getByText('2025-04-01 to 2026-03-31',{exact:false})).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
