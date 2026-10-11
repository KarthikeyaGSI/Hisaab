import {hostedAssetDetail,hostedGeographyEnabled} from '@/lib/hosted-geography';
import {assetDetail} from '@/lib/asset-geography';
export const runtime='nodejs';
export async function GET(_request:Request,{params}:{params:Promise<{id:string}>}){const {id}=await params;if(!/^[a-f0-9]{20}:\d+$/.test(id))return Response.json({error:'Invalid asset identifier'},{status:400});try{const asset=hostedGeographyEnabled()?await hostedAssetDetail(id):assetDetail(id);return asset?Response.json({asset},{headers:{'Cache-Control':'no-store'}}):Response.json({error:'Asset not found'},{status:404});}catch{return Response.json({error:'Asset geography unavailable'},{status:503});}}
