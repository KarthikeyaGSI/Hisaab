import {requireAdmin} from '@/lib/admin';
import {requireOrigin} from '@/lib/security';
import {boundedBody} from '@/lib/request-body';
import {z} from 'zod';
const schema=z.object({documentId:z.uuid(),basis:z.string().min(30).max(2000),evidence:z.string().min(20).max(2000),confirmed:z.literal(true)});
export async function POST(request:Request){const headers={'Cache-Control':'private, no-store'};if(!requireOrigin(request))return Response.json({error:'Same-origin request required'},{status:403,headers});let admin;try{admin=await requireAdmin();}catch{return Response.json({error:'MFA administrator required'},{status:401,headers});}try{const value=schema.parse(JSON.parse(new TextDecoder().decode(await boundedBody(request,16000))));const result=await admin.client.rpc('verify_source_permission',{p_document:value.documentId,p_basis:value.basis,p_evidence:value.evidence});if(result.error)throw result.error;return Response.json({reviewed:true},{headers});}catch{return Response.json({error:'Verified permission basis, evidence reference and confirmation are required'},{status:400,headers});}}
