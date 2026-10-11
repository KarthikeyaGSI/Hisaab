import 'server-only';
import {createHmac} from 'node:crypto';
import {isIP} from 'node:net';
import {reportClient} from './reports';
import {rateLimit} from './security';
export async function operatingLimit(request:Request,scope:string,limit=20){
 const key=process.env.HISAAB_CAPABILITY_SECRET;
 if(process.env.HISAAB_DATA_MODE!=='supabase')return process.env.NODE_ENV!=='production'&&rateLimit(scope,limit);
 if(!key)return false;
 // Trust Netlify's connection header only in its configured deployment. Do
 // not accept X-Forwarded-For or caller-selected user-agent as an identity.
 let caller='local-preview';
 if(process.env.NODE_ENV==='production'){
  if(process.env.HISAAB_TRUST_NETLIFY_IP!=='true')return false;
  caller=request.headers.get('x-nf-client-connection-ip')??'';if(!isIP(caller))return false;
 }
 const digest=createHmac('sha256',key).update(`${scope}:${caller}`).digest('hex');
 try{const result=await reportClient().rpc('consume_request_limit',{p_key:digest,p_limit:limit});return !result.error&&result.data===true;}catch{return false;}
}
