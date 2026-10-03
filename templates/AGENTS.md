# Agent instructions

This repo is a static website deployed with the shared
[static-site-kit](https://github.com/@@KIT@@). The web server, security
headers, Content-Security-Policy and CI live in the kit, not here.

## How this repo is organized

- `site/` is the website. Everything in it is served as-is; `site/index.html`
  is the home page. There is no build step: put finished HTML, CSS, JS and
  images here. Keep source or working files (drafts, design files, generated
  image batches) outside `site/`.
- `Dockerfile` builds `FROM @@BASE@@` (the kit's hardened nginx image),
  copies `site/` in and runs `gen-csp`. Keep it that way.
- `.github/workflows/publish-container.yml` only calls the kit's reusable
  workflow. On push to `main` it builds, smoke-tests and publishes
  `@@IMAGE@@`. The homelab server then updates automatically.
- `deploy/homelab.*` describe how the image runs on the homelab server
  (service `@@NAME@@`). Details are in `deploy/homelab.md`.

## Rules for website changes

- Inline `<script>` blocks are fine: `gen-csp` allows each one by its hash,
  recomputed on every build.
- Do not use inline event handlers (`onclick="..."`, `onload=...`) or
  `javascript:` links. The build fails on them; use `addEventListener` in a
  script instead.
- Same-origin files (`/style.css`, `/img/x.jpg`, `/font.woff2`) and `data:`
  images work. Anything from another domain (Google Fonts, CDNs, analytics,
  embeds, `fetch` calls) is blocked by the CSP unless it is added to
  `CSP_EXTRA` in the `Dockerfile`. Prefer copying assets into `site/`.
- The server only answers GET/HEAD. Forms cannot POST anywhere; there is no
  backend.

## Changing deployment behaviour

Do not add nginx configs, CSP scripts or build steps to this repo to work
around the kit. Per-site nginx additions (redirects, cache headers) go in
`nginx/*.conf`, enabled by the commented `COPY nginx/` line in the
`Dockerfile`. Anything that should apply to all sites is a change to the kit
repo (`../static-site-kit` locally); every site picks it up on its next
build, including the automatic weekly rebuild.
