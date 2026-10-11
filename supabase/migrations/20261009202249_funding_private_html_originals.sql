-- Preserve official HTML originals privately. No browser rendering, public access or upload policy is added.
update storage.buckets set allowed_mime_types=array_append(allowed_mime_types,'text/html') where id='source-originals' and public=false and allowed_mime_types is not null and not ('text/html'=any(allowed_mime_types));
