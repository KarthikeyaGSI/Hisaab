import {readFile} from 'node:fs/promises';
import path from 'node:path';

const headers={'Cache-Control':'public, max-age=300, s-maxage=300, stale-while-revalidate=3600'};

export async function GET(request:Request){
 const name=new URL(request.url).searchParams.get('name')?.trim();
 if(!name||name.length>100)return Response.json({error:'A state or territory name is required.'},{status:400,headers});
 try{
  const inventory=JSON.parse(await readFile(path.join(process.cwd(),'data/public-jurisdiction-source-coverage.json'),'utf8'));
  const jurisdiction=inventory.jurisdictions.find((row:{name:string})=>row.name.toLocaleLowerCase('en-IN')===name.toLocaleLowerCase('en-IN'));
  if(!jurisdiction)return Response.json({error:'No saved source inventory for this jurisdiction.'},{status:404,headers});
  return Response.json({auditedAt:inventory.auditedAt,scope:inventory.scope,jurisdiction,odishaAdditionalCollections:jurisdiction.name==='Odisha'?inventory.odishaAdditionalCollections:null},{headers});
 }catch{return Response.json({error:'Jurisdiction source inventory unavailable.'},{status:503,headers});}
}
