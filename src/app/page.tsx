import { AtlasApp as HisaabApp } from '@/components/atlas-app';
import { readCatalogue } from '@/lib/catalogue';
import { PublicPreviewGate } from '@/components/public-preview-gate';
import sourceCoverage from '../../data/public-jurisdiction-source-coverage.json';
export const dynamic = 'force-dynamic';
const historicalLocationRecords=sourceCoverage.jurisdictions.reduce((total,jurisdiction)=>total+jurisdiction.historicalMapRecords,0);
export default async function Page() { const catalogue = await readCatalogue(); return <PublicPreviewGate historicalLocationRecords={historicalLocationRecords} sourceReviewedProjectRecords={catalogue.totalWorks} odishaPhotoLocationDossiers={sourceCoverage.odishaAdditionalCollections.ppms.sourceLocationProjects} odishaDeepSourceReviews={sourceCoverage.odishaAdditionalCollections.ppms.deepSourceReviewedProjects}><HisaabApp catalogue={catalogue}/></PublicPreviewGate>; }
