import {NextResponse,type NextRequest} from 'next/server';
import {authorizedPreview} from '@/lib/security';
export function proxy(request:NextRequest){
 if(process.env.HISAAB_PUBLIC_RELEASE==='true'){
  // Explicitly fail closed until the signed release-gate integration is implemented.
  return new NextResponse('Public release is not yet enabled. Complete the release audit first.',{status:503});
 }
 if(!authorizedPreview(request))return new NextResponse('Hisaab private preview. Administrator credentials required.',{status:401,headers:{'WWW-Authenticate':'Basic realm="Hisaab private preview"','Cache-Control':'no-store'}});
 return NextResponse.next();
}
export const config={matcher:['/((?!_next/static|_next/image|favicon.ico).*)']};
