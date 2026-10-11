import type { NextConfig } from 'next';
import {existsSync} from 'node:fs';
if(existsSync('.env.mapbox.local'))process.loadEnvFile('.env.mapbox.local');
const mapToken=process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN??'';
if(mapToken&&!mapToken.startsWith('pk.'))throw new Error('Mapbox browser configuration requires a public map token.');
const config: NextConfig = {
  poweredByHeader: false,
  // Private acquisition originals and the local 330 MB geography fallback never ship.
  // Hosted geography is read from its checksummed, immutable storage manifest.
  outputFileTracingExcludes: {'/*':['./data/acquisition/**/*','./data/originals/**/*','./.hisaab/**/*','./tmp/**/*','./.env*']},
  env:{NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN:mapToken},
  async rewrites(){return [{source:'/state/:code',destination:'/'},{source:'/asset/:id',destination:'/'}];},
  async headers() { return [{ source: '/:path*', headers: [
    {key:'X-Content-Type-Options',value:'nosniff'},
    {key:'Referrer-Policy',value:'no-referrer'},
    {key:'Permissions-Policy',value:'camera=(self), microphone=(), geolocation=(self)'},
    {key:'X-Frame-Options',value:'DENY'},
  ]}]; },
};
export default config;
