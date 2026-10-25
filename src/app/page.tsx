import { AtlasApp as HisaabApp } from '@/components/atlas-app';
import { readCatalogue } from '@/lib/catalogue';
import { PublicPreviewGate } from '@/components/public-preview-gate';
import assetAcquisition from '../../data/geosadak-acquisition.json';
import projectDataCount from '../../data/project-data-count.json';
export const dynamic = 'force-dynamic';
export default async function Page() { const catalogue = await readCatalogue(); return <PublicPreviewGate assetRecordTotal={assetAcquisition.assetRows} projectDataSourceRecords={projectDataCount.projectDataSourceRecords}><HisaabApp catalogue={catalogue}/></PublicPreviewGate>; }
