// Local-only recognition. Models/runtime are pinned in the private collector
// directory; no source images or extracted text are sent to an external service.
import {createRequire} from 'node:module';
import {readFile,writeFile,chmod} from 'node:fs/promises';
import path from 'node:path';
const base=path.resolve('data/acquisition/state-development');
const require=createRequire(path.join(base,'ocr-runtime/package.json'));
const {createWorker}=require('tesseract.js');
const manifest=JSON.parse(await readFile(process.argv[2],'utf8'));
const worker=await createWorker(['hin','eng'],1,{cachePath:path.join(base,'ocr-runtime')});
try{
 for(const item of manifest){
  if(!path.resolve(item.image).startsWith(base+path.sep)||!path.resolve(item.output).startsWith(base+path.sep))throw new Error('Private collector paths required');
  const {data}=await worker.recognize(item.image,{}, {text:true,tsv:true});
  await writeFile(item.output,JSON.stringify({sourceSha256:item.hash,page:item.page,engine:'tesseract.js/7.0.0',languages:['hin','eng'],confidence:data.confidence,text:data.text,tsv:data.tsv,reviewStatus:'ocr_unverified'},null,2)+'\n',{mode:0o600});
  await chmod(item.output,0o600);
  process.stdout.write(JSON.stringify({page:item.page,status:'ocr_unverified'})+'\n');
 }
}finally{await worker.terminate();}
