import {afterEach, describe, expect, it, vi} from 'vitest';
import {NextRequest} from 'next/server';
import {proxy} from '../src/proxy';
import {GET as health} from '../src/app/api/v1/health/route';

function request(path:string, method='GET') {
 return new NextRequest(`https://hisaab-01.netlify.app${path}`, {method});
}

afterEach(()=>vi.unstubAllEnvs());

describe('hosted preview access',()=>{
 it('serves public browsing without a login challenge when no mode is configured',async()=>{
  vi.stubEnv('HISAAB_PUBLIC_PREVIEW',undefined);
  vi.stubEnv('HISAAB_PUBLIC_RELEASE',undefined);
  for(const path of ['/','/spending','/state/21','/asset/example','/api/v1/map/assets','/api/v1/health']){
   const response=proxy(request(path));
   expect(response.status).toBe(200);
   expect(response.headers.get('x-middleware-next')).toBe('1');
   expect(response.headers.has('www-authenticate')).toBe(false);
  }
  expect((await (await health()).json()).status).toBe('public_read_only_preview');
 });

 it('keeps private routes protected and unauthenticated writes closed',()=>{
  vi.stubEnv('HISAAB_PUBLIC_PREVIEW',undefined);
  vi.stubEnv('HISAAB_PUBLIC_RELEASE',undefined);
  vi.stubEnv('HISAAB_ADMIN_TOKEN',undefined);
  for(const path of ['/admin','/api/v1/admin/review'])expect(proxy(request(path)).status).toBe(401);
  expect(proxy(request('/api/v1/reports','POST')).status).toBe(503);
  expect(proxy(request('/api/v1/map/assets','POST')).status).toBe(503);
  expect(proxy(request('/studio')).status).toBe(503);
 });

 it('honors explicitly private installations',async()=>{
  vi.stubEnv('HISAAB_PUBLIC_PREVIEW','false');
  vi.stubEnv('HISAAB_PUBLIC_RELEASE',undefined);
  vi.stubEnv('HISAAB_ADMIN_TOKEN',undefined);
  expect(proxy(request('/')).status).toBe(401);
  expect((await (await health()).json()).status).toBe('private_build');
 });

 it('preserves the public release audit gate',()=>{
  vi.stubEnv('HISAAB_PUBLIC_RELEASE','true');
  expect(proxy(request('/')).status).toBe(503);
 });
});
