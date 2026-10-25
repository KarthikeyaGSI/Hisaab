import { AtlasApp as HisaabApp } from '@/components/atlas-app';
import { readCatalogue } from '@/lib/catalogue';
import { PublicPreviewGate } from '@/components/public-preview-gate';
import assetAcquisition from '../../data/geosadak-acquisition.json';
export const dynamic = 'force-dynamic';
export default async function Page() { const catalogue = await readCatalogue(); return <PublicPreviewGate assetRecordTotal={assetAcquisition.assetRows} recordsWithAdditionalDetails={assetAcquisition.assetRowsWithLocationAndSourceDetails}><HisaabApp catalogue={catalogue}/></PublicPreviewGate>; }
