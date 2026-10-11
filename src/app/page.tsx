import { AtlasApp as HisaabApp } from '@/components/atlas-app';
import { readCatalogue } from '@/lib/catalogue';
export const dynamic = 'force-dynamic';
export default async function Page() { const catalogue = await readCatalogue(); return <HisaabApp catalogue={catalogue}/>; }
