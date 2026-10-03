# static-site-kit

Shared deployment for static websites: one hardened nginx base image, one
reusable GitHub Actions workflow, and a scaffolder that wires a site repo onto
both. Site repos contain only their content plus about 15 lines of glue, so
hardening and CI fixes are made once here.

```
site repo                              this repo
─────────                              ─────────
site/            (the website)         image/       → ghcr.io/3awaref/static-site-kit:1
Dockerfile       FROM …kit:1           .github/workflows/publish-site.yml  (reusable, @v1)
.github/workflows/publish-container.yml  ──uses──┘
deploy/homelab.*  (generated)          templates/ + new-site.sh
```

## Starting or migrating a site

```sh
~/Projects/static-site-kit/new-site.sh ~/Projects/my-site --domain example.com
```

This writes `AGENTS.md` (instructions for coding agents, imported by a
one-line `CLAUDE.md`), the `Dockerfile`, `.dockerignore`, the publish workflow,
`dependabot.yml` and `deploy/homelab.{compose.yml,env.example,md}`, filling in
the service name, the image (from the `origin` remote) and the domain. It
creates a placeholder `site/index.html` only if `site/` doesn't exist. Existing
files are skipped unless `--force` is given. If the repo already has its own
`CLAUDE.md`, add an `@AGENTS.md` line to it. Then put the website in `site/`
(`site/index.html` is the root document) and push to `main`.

Merge `deploy/homelab.compose.yml` into the central Compose file and set up
NPM/DNS as described in the generated `deploy/homelab.md`.
[`docs/HOMELAB_COMPOSE_GUIDE.md`](docs/HOMELAB_COMPOSE_GUIDE.md) is the full
contract for the central stack.

## What the base image provides

- `nginx:alpine` serving `/usr/share/nginx/html` on port 80, GET/HEAD only, a
  1 KB body limit, short timeouts, no version banner, dotfiles return 404.
- Security headers: CSP, `X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy`, `Permissions-Policy`, `Cross-Origin-Opener-Policy`. HSTS
  belongs on NPM, which terminates TLS.
- `/healthz` (200 `ok`) and a Docker `HEALTHCHECK` using BusyBox `wget`.
- `gen-csp`, run by each site's `Dockerfile` after copying its files in:
  - Every inline `<script>` in every `.html` file is allowed by its SHA-256
    hash. `<script src>` adds `'self'`.
  - Inline `on...=` handlers and `javascript:` URLs fail the build.
  - Same-origin styles, images, fonts and media are allowed, as are `data:`
    images. Everything else is `'none'`.
  - Other origins go in `ARG CSP_EXTRA="connect-src 'self'; img-src https://…"`.
    These are merged into the policy and replace a directive's `'none'`.
- `/etc/nginx/site.d/*.conf` is included at server level, for per-site
  redirects or cache headers (`COPY nginx/ /etc/nginx/site.d/`). An
  `add_header` inside a `location` there drops the security headers for that
  location.

## Updates and versioning

The **base image** (`image/`) is published by `base-image.yml` as
`ghcr.io/3awaref/static-site-kit:<MAJOR>` on pushes to `main` and every Monday
at 03:00 UTC, which picks up nginx/Alpine patches. Site workflows rebuild every
Monday at 04:00 UTC, so fixes reach every site within a week (sooner after a
push), and Watchtower redeploys them.

The **reusable workflow** is referenced by site repos as `@v1`. After changing
it, move the tag:

```sh
git tag -f v1 && git push -f origin v1
```

For **breaking changes** to nginx behaviour, gen-csp rules or workflow
inputs, bump `MAJOR` in `base-image.yml` and `KIT_MAJOR` in `new-site.sh`, and
start a `v2` tag. The old major stops being rebuilt. Dependabot in each site
opens PRs for the new image tag and workflow ref, so sites can be upgraded one
at a time.

**Access.** This repo is private, with *Settings → Actions → Access* allowing
repositories owned by the user, so site repos can call the reusable workflow.
The base image package must be readable by each site's workflow: either make
the `static-site-kit` package public (it contains nothing secret), or add each
site repo under the package's *Package settings → Manage Actions access*
(role: Read). Site image packages must be public, or the homelab host must be
logged in to GHCR.

## Tests

`test/run.sh` checks `gen-csp` against hashes computed independently in Node.
CI runs it inside the built image (BusyBox awk) and smoke-tests the container
(`nginx -t`, `/healthz`, CSP header, POST → 405). The reusable workflow runs
the same smoke test on every site image before publishing. Locally, without
Docker:

```sh
GEN_CSP=image/gen-csp sh test/run.sh
```
