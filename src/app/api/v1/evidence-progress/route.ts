import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {delhiCoverage} from '@/lib/delhi-coverage';
export async function GET(){try{const data=JSON.parse(await readFile(path.join(process.cwd(),'data/evidence-progress.json'),'utf8'));if(data.delhiCoverage)data.delhiCoverage=delhiCoverage(data.delhiCoverage);return Response.json(data,{headers:{'Cache-Control':'no-store'}});}catch{return Response.json({error:'Evidence progress unavailable'},{status:503,headers:{'Cache-Control':'no-store'}});}}
