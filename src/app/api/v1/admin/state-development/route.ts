import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {requireAdmin} from '@/lib/admin';

export async function GET(request:Request){
 const headers={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'};
 try{await requireAdmin();}catch{return Response.json({error:'Owner MFA sign-in required to inspect collected state evidence.'},{status:401,headers});}
 const params=new URL(request.url).searchParams;
 const code=params.get('state')??'',section=params.get('section')??'sources',page=Number(params.get('page')??'1');
 if([...params.keys()].some(k=>!['state','section','page'].includes(k)||params.getAll(k).length!==1)||!/^\d{1,2}$/.test(code)||!['sources','budget','expenditure','projects','reconciliation'].includes(section)||!Number.isSafeInteger(page)||page<1||page>10000)return Response.json({error:'Invalid state evidence filters'},{status:400,headers});
 try{
  const summary=JSON.parse(await readFile(path.join(process.cwd(),'data/state-development-acquisition.json'),'utf8'));
  const state=summary.states.find((s:{code:string})=>s.code===code);
  if(!state)return Response.json({error:'State outside the current 28-state collection scope'},{status:400,headers});
  const base=path.join(process.cwd(),'data/acquisition/state-development',code);
  let rows:unknown[]=[];
  if(section==='sources'){
   const checkpoint=JSON.parse(await readFile(path.join(base,'checkpoint.json'),'utf8'));
   const versions=[...checkpoint.documents.map((d:Record<string,unknown>)=>({...d,editionStatus:'current collected edition'})),...(checkpoint.previousEditions??[]).map((d:Record<string,unknown>)=>({...d,editionStatus:'earlier preserved edition; reconciliation required'}))];
   rows=versions.map((d:Record<string,unknown>)=>({id:`${d.sourceId}:${d.sha256}:${d.url}`,label:d.label,kind:d.sourceKind,url:d.url,hash:d.sha256,retrievedAt:d.retrievedAt,bytes:d.bytes,extractedPages:d.extractedPages,completeExtraction:d.completeExtraction,permissionStatus:d.permissionStatus,editionStatus:d.editionStatus}));
  }else if(section==='reconciliation'){
   const report=JSON.parse(await readFile(path.join(base,'reconciliation.json'),'utf8'));
   rows=[{id:`reconciliation:${code}:${report.checkedAt}`,label:'Extraction and reconciliation checks',checkedAt:report.checkedAt,identityCheck:report.identityCheck,tableControls:report.tableControls,scopeWarnings:report.scopeWarnings,remaining:report.remaining,completeCoverage:false,publicationApproved:false}];
  }else{
   try{const candidates=JSON.parse(await readFile(path.join(base,'candidates.json'),'utf8'));rows=(section==='budget'?candidates.budgetCandidates:section==='expenditure'?candidates.expenditureCandidates:candidates.projectCandidates)??[];}
   catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}
  }
  return Response.json({state,section,page,pageSize:25,total:rows.length,rows:rows.slice((page-1)*25,page*25),approved:false,scope:'Private source candidates. Budgets, project costs, contracts and payments remain distinct.'},{headers});
 }catch{return Response.json({error:'State evidence unavailable; collection is checkpointed and no missing value is treated as zero.'},{status:503,headers});}
}
