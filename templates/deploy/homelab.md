# @@NAME@@: Homelab deployment

This site is deployed with [static-site-kit](https://github.com/@@KIT@@). The
web server, security headers, CSP generation and CI live in the kit. This repo
holds only `site/` plus a few lines of glue. Fix deployment issues in the kit,
not here.

## What lives where

| Path | Purpose |
| --- | --- |
| `site/` | Everything served. `site/index.html` is the root document. |
| `Dockerfile` | `FROM @@BASE@@`, copies `site/`, runs `gen-csp`. |
| `nginx/*.conf` | Optional nginx additions, copied to `/etc/nginx/site.d/`. |
| `.github/workflows/publish-container.yml` | Calls the kit's reusable publish workflow. |
| `deploy/homelab.compose.yml` | Merge fragment for the central Compose file. |

## Site contract

- Inline `<script>` blocks are allowed by hash, recomputed on every build. Use
  `addEventListener`: inline `on...=` handlers and `javascript:` URLs fail
  the build.
- Same-origin scripts, styles, images, fonts and media are allowed, as are
  `data:` images. Anything loaded from another host, or `fetch`/XHR
  (`connect-src`), must be added through `CSP_EXTRA` in the `Dockerfile`.
- Only GET and HEAD are served. There is no backend.

## Image build and publish

GitHub Actions builds and smoke-tests the image on every push and pull request.
On pushes to `main`, `v*` tags, manual runs and a weekly schedule (Mondays
04:00 UTC, after the base image's weekly rebuild), it publishes
`@@IMAGE@@` for `linux/amd64` and `linux/arm64`. The default branch receives
`latest`; branch, version and commit SHA tags are also published.
`GITHUB_TOKEN` is enough. The package must be public for unauthenticated host
pulls; otherwise authenticate the host to GHCR. GitHub disables scheduled
workflows in public repositories after 60 days without activity. Re-enable it
in the Actions tab if that happens.

Watchtower picks up the new `latest`. Dependabot opens PRs when a new major
version of the base image or the reusable workflow is available.

## Merge into the central Compose file

Merge the `@@NAME@@` entry from `deploy/homelab.compose.yml` under the
existing `services:` key in the central `docker-compose.yml`. Keep the central
`backend` network definition; no network declaration or host port is needed.
No environment variables, secrets, persistent data or migrations are required.
`container_name` is set so the container isn't named after the central Compose
project, and it must be unique on the Docker host.

```sh
docker compose -f docker-compose.yml config --quiet
docker compose -f docker-compose.yml pull @@NAME@@
docker compose -f docker-compose.yml up -d @@NAME@@
docker compose -f docker-compose.yml ps @@NAME@@
docker compose -f docker-compose.yml logs --tail=100 @@NAME@@
```

## Nginx Proxy Manager and DNS

Point DNS for the domain at the server's public ingress address (add AAAA
only if IPv6 ingress works). Then create the Proxy Host through the VPN-bound
NPM admin endpoint:

| NPM setting | Value |
| --- | --- |
| Domain Names | @@DOMAIN@@ |
| Scheme | `http` |
| Forward Hostname / IP | `@@NAME@@` |
| Forward Port | `80` |
| Websockets Support | Off |
| SSL Certificate | Request/select a certificate for the domain(s) |
| Force SSL | Enable after HTTPS is verified |

HSTS belongs on NPM, which terminates TLS.

## Launch checklist

- [ ] Domain supplied, DNS and NPM Proxy Host configured.
- [ ] `og:image` / `og:url` use absolute `https://` URLs if link previews matter.
- [ ] `<meta name="robots" content="noindex">` removed if indexing is wanted.
- [ ] GHCR package visibility confirmed after the first publish.

## Validation status

Not yet deployed. Record here what was actually run and verified.
