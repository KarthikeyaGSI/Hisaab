# Public preview launch readiness — 25 October 2026

The private source repository is `https://github.com/theadiram/Hisaab`. It was created empty and attached as `origin`; creation alone does not upload the workspace or deploy the application.

The existing frontend target is `https://hisaab-private-staging.netlify.app` (site ID `b13de9ab-22e9-4743-9a44-8cc385dcef2c`). At the read-only inspection it had no deployments, connected repository, custom domain or environment variables. Existing Netlify account authentication and GitHub keyring authentication both worked. No new paid plan or DNS change is needed to use the existing Netlify subdomain.

## Source packaging

- Private acquisition/original folders, local database state, environment files and Netlify account state are ignored. Only `.env.example` is tracked among environment files.
- Local `output/` exports and `videos/` production sources are now explicitly ignored. They contain approximately 484 MiB and 1.42 GiB respectively and must not enter a website commit.
- The current eligible source scan found no GitHub token, Supabase secret-key or private-key patterns. This is a bounded pattern scan, not proof against every possible secret.
- The largest currently tracked file is approximately 4.28 MiB. Intended public map geometry and clearly labelled demonstration images are ordinary website assets.
- Source review packages and original documents stay in private acquisition/storage paths. A source-code push does not make them public and does not publish reviewed projects.

## Validation and delivery

The public preview entry has a dedicated first-visit browser check on desktop and mobile. Existing map journeys use an explicit returning-visitor acknowledgement fixture; their behavior assertions remain intact. The initial funding journey and both first-entry checks passed using installed Chrome. Type checking passed. CI continues to use Playwright's installed Chromium by default; `HISAAB_BROWSER_CHANNEL=chrome` is an optional local override.

The remaining delivery order is a reviewed source commit and push, passing GitHub validation, production environment setup, repository-connected Netlify build, and public checks. The existing workflow runs disposable database/security tests, type checking, application and Python tests, production compilation and browser checks. It has a 30-minute timeout.

The existing GitHub integration can be reused if it has access to the newly created private repository. The official Netlify API supports a `PATCH /sites/{site_id}` request with repository settings. Environment variables use the separate account-scoped environment endpoint, not the deprecated `repo.env` field. Build-time public Supabase settings and server-only credentials require correct scopes. The production app origin and trusted Netlify request-address handling must be checked against the actual deployed URL.

A deployment must retain owner MFA, private originals, source-specific reuse decisions and per-claim review. A public preview notice does not authorize publication of unreviewed evidence or establish payment, completion or current physical condition.

## Hosting configuration checkpoint

The existing Netlify project is now connected to the private Hisaab repository on `codex/three-screen-rebuild`, using the account's existing GitHub app installation. Automatic builds are explicitly stopped and build logs are private. Linking the repository scheduled an initial attempt despite the repository setup's stop flag; the persisted build setting was then corrected, the initial empty-repository attempt ended in error, and no published deployment exists.

Sixteen allowlisted environment settings were configured without exposing their values: hosted Supabase client/server configuration, capability secret, hosted geography, preview/release flags, app origin, trusted Netlify address handling, and disabled AI/email/retention switches. `HISAAB_PUBLIC_PREVIEW=true` and `HISAAB_PUBLIC_RELEASE=false` retain the read-only preview distinction. No shared legacy administrator token was configured. Netlify's free plan does not support granular scopes; standard team-managed environment storage is used. Server credential names have no `NEXT_PUBLIC_` prefix. An optional Mapbox browser token was not copied because its hostname restrictions were not established; the existing free map fallback remains available.

After the reviewed commit passes CI, enable builds on this project and request a build of the reviewed repository branch/commit. Verify the public page, geography delivery, source-labelled cards, entry notice, read-only behavior, private endpoint denial and owner MFA on the actual Netlify origin before announcing it. No DNS or paid-plan change has occurred.
