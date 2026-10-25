import { AtlasApp as HisaabApp } from '@/components/atlas-app';
import { readCatalogue } from '@/lib/catalogue';
import { PublicPreviewGate } from '@/components/public-preview-gate';
export const dynamic = 'force-dynamic';
export default async function Page() { const catalogue = await readCatalogue(); return <PublicPreviewGate><HisaabApp catalogue={catalogue}/></PublicPreviewGate>; }
