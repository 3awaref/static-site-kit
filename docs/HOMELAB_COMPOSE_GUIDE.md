# Website deployment guide for the Homelab Compose stack

Copy this document into each website repository (for example,
`docs/HOMELAB_DEPLOYMENT.md`). An agent working in that repository should use it
to produce a production Compose fragment for the central Homelab
`docker-compose.yml`.

## Deployment contract

Traffic flows as follows:

```text
domain/subdomain → host ports 80/443 → npm-app → <website-service>:<container-port>
                                              on the backend Docker network
```

The central stack already defines `npm-app` (Nginx Proxy Manager), `frontend`,
and `backend`. NPM joins both networks; websites join `backend`. The production
reference service is `netdoc`, using `ghcr.io/3awaref/netdocwebsite:latest`,
listening on port `8080`, with an HTTP health endpoint at `/healthz`.

These fragments are merged into **one central Compose file**, not started as
independent website stacks. The central `backend` network is Compose-managed;
its actual Docker name normally includes the Compose project name. Do not
declare it `external`, rename it, or create another network named `backend`.
Running a separate Compose project with `networks: [backend]` does not connect
it to the central stack. Separate-project deployment requires an explicitly
agreed shared external network and is outside this guide.

## Instructions for the website agent

1. Inspect the website's Dockerfile, server configuration, runtime, and existing
   deployment files. Determine the real listening port, bind address, image
   reference, health endpoint, required variables, and persistent data paths.
   Do not invent environment variables or assume every website uses Node.
2. Use a unique, stable, lowercase service name such as `example-site`. Prefix
   supporting services, volume names, network keys, and host environment
   variables with the website name to avoid collisions in the central stack.
3. Use a published production `image:` that the host can pull. Document registry
   authentication for private images and the required host CPU architecture.
   Build the image in the website repository/CI; do not put `build: .` or source
   bind mounts into the central production fragment. Record the tag/update
   strategy: the current stack has Watchtower and uses `latest` for Netdoc;
   confirm whether automatic image updates are intended for this website.
4. Set `restart: unless-stopped`. Omit `container_name` by default; NPM can
   resolve the Compose service name. If one is necessary, it must be unique
   across the Docker host.
5. Make the server listen on `0.0.0.0` and its actual container port. Configure
   this using settings the application really supports, or its server config.
   A listener bound to `127.0.0.1` cannot receive NPM traffic.
6. List the HTTP container port under `expose` and attach the website to
   `networks: [backend]`. Do **not** add `ports:`, `network_mode: host`, static
   IPs, or `links`. Multiple websites may all listen on `8080` without conflicts.
   `expose` documents the port; it neither starts the server nor acts as a
   firewall. Containers sharing `backend` can reach other listening ports.
   The existing `backend` is not an `internal: true` network and does not isolate
   websites from one another.
7. Run the production server, not a development server. Serve static sites
   through their image's production web server; use that server's port (often
   `80`) instead of assuming `8080`.
8. Add a health check using a command available in the **final runtime image**.
   Probe a real, inexpensive unauthenticated endpoint on loopback that returns
   success when the app is ready. Do not assume `curl`, `wget`, or Node's
   `fetch` exists. Use a suitable timeout and startup grace period. Docker marks
   failing containers unhealthy; this alone does not restart them or make NPM
   stop routing to them.
9. Configure reverse-proxy support using the application's actual framework:
   NPM terminates public TLS and normally forwards HTTP internally. Configure
   the canonical public HTTPS URL, allowed hosts/origins, forwarded protocol,
   secure cookies, and proxy trust as needed. Trust the expected proxy path;
   do not blindly trust arbitrary forwarded headers. Netdoc's
   `TRUST_PROXY_HOPS: "1"` and `ENABLE_HSTS: "true"` are Netdoc-specific,
   not universal environment variables. Account for any additional upstream
   proxy when determining trust. Verify redirects and authentication behind NPM.
10. Supply only necessary environment variables. Quote values, including
    booleans and numbers. Reference required host-side secrets with namespaced
    interpolation, for example `${EXAMPLE_SITE_SESSION_SECRET:?Set EXAMPLE_SITE_SESSION_SECRET}`.
    Commit a sample with placeholders, never real secrets. Compose interpolation
    uses the central deployment's environment/`.env`; the website repository's
    `.env` is not automatically loaded. Use `$$` when a Compose command must
    pass a literal `$` to the container. Use file secrets only if the app supports
    them and document their central host files and top-level definitions.
11. Add persistence only for state that must survive recreation. Prefer named
    volumes with website-specific keys. Any relative bind mount or `env_file`
    path in the merged file resolves from the central Compose deployment, not
    the website repository. Document paths, permissions, backups, and any
    migration command. Log to stdout/stderr.
12. If databases or caches are required, give them unique service names and a
    website-specific private network. Attach the website to both `backend` and
    that private network; attach supporting services only to the private network,
    without host port mappings. Supply their image, health check, secrets, and
    persistence definitions. Use `depends_on` with `condition: service_healthy`
    where startup requires readiness, and retain app retry/reconnection logic.
    Do not add a dependency on `npm-app`; NPM is independently managed.

## Required deliverables in the website repository

- `deploy/homelab.compose.yml`: valid YAML containing a `services:` mapping and
  only this website's services. Include additional top-level `volumes:`,
  `networks:`, or `secrets:` mappings only when needed. Reference the existing
  `backend` network without redefining it. This is a **merge fragment**, not a
  standalone runnable Compose stack.
- `deploy/homelab.env.example`: the additions needed in the central host's
  environment, with placeholders and descriptions; omit if none are needed.
- `deploy/homelab.md`: exact merge instructions, the NPM settings below, image
  build/publish instructions, required initialization/migrations/persistence,
  validation results, and any unresolved deployment input. Do not claim an
  image, endpoint, or deployment was verified without actually checking it.

Merge the fragment's service entries under the existing central `services:` key.
Merge any additional resource entries into the existing top-level mappings;
never append a second `services:`, `networks:`, or `volumes:` key. Preserve all
existing infrastructure and production service entries.

If the domain or registry destination is missing, produce the fragment and
clearly list that input as unresolved. Do not substitute a made-up production
domain or claim that a placeholder image can be pulled.

## Example: Node website with a verified port and health endpoint

This example assumes the app implements `HOST`, `PORT`, and `NODE_ENV`, exposes
`/healthz`, and its runtime includes Node with global `fetch`. Replace the service
and image with the real website identifiers. Adjust every runtime-specific
setting to match the inspected codebase.

```yaml
services:
  example-site:
    image: ghcr.io/your-org/your-website:latest
    restart: unless-stopped
    environment:
      NODE_ENV: "production"
      HOST: "0.0.0.0"
      PORT: "8080"
    expose:
      - "8080"
    networks:
      - backend
    healthcheck:
      test:
        - CMD
        - node
        - -e
        - "fetch('http://127.0.0.1:8080/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
```

No extra `backend` declaration is needed when merging this example into Homelab.

## Nginx Proxy Manager handoff

Creating a Compose service does not create an NPM Proxy Host or DNS record.
Record these values in `deploy/homelab.md` for each domain/subdomain:

| NPM setting | Value |
| --- | --- |
| Domain Names | Actual domain(s), e.g. `example.com`, `www.example.com` |
| Scheme | `http`, unless the website actually serves TLS internally |
| Forward Hostname / IP | Compose service name, e.g. `example-site` |
| Forward Port | Container listening port, e.g. `8080` |
| Websockets Support | Enable if the application requires WebSockets |
| SSL Certificate | Request/select a certificate for the public domains |
| Force SSL | Enable after certificate and HTTPS behavior are verified |

Use the same pattern for Netdoc: `http` → `netdoc` → `8080`. Its production
domain is not specified in the central Compose file.

Point public DNS to the host's public ingress address, including a working IPv6
route if an AAAA record is used. Ensure public ingress reaches NPM on ports
80/443. Use the existing VPN-bound admin endpoint
`http://<INTERNAL_VPN_IP>:<NGINX_MANAGEMENT_PORT_HTTP>` to configure Proxy Hosts.
Do not use `localhost`, the public domain, a container IP, or a host port as the
upstream. Domains and subdomains are selected in NPM, not via Compose labels or
`VIRTUAL_HOST` variables. Document custom locations/timeouts only when the app
requires them.

## Validation before deployment handoff

Run these on the deployment host from the central Compose directory, after
merging the fragment and supplying its environment. Replace `example-site`
and the test URL with the actual service, port, and endpoint.

```sh
# Validate without printing the expanded configuration (which may contain secrets).
docker compose -f docker-compose.yml config --quiet
docker compose -f docker-compose.yml pull example-site
docker compose -f docker-compose.yml up -d example-site
docker compose -f docker-compose.yml ps example-site
docker compose -f docker-compose.yml logs --tail=100 example-site

# Verify connectivity from NPM using Node already available in the NPM image.
# If that image lacks Node/fetch, use an available HTTP client on the same network.
docker compose -f docker-compose.yml exec npm-app node -e "fetch('http://example-site:8080/healthz').then(r=>{console.log(r.status);process.exit(r.ok?0:1)}).catch(e=>{console.error(e);process.exit(1)})"

# After DNS and the NPM Proxy Host/certificate have been configured:
curl -I https://example.com
```

Check health status, no website host port bindings, and shared `backend`
membership with NPM. The `PORTS` column may show `8080/tcp`; that is not a host
mapping. Verify the actual public website, redirects, assets, authentication,
and WebSockets where applicable. For databases or caches, pull and validate
those services too. Do not run `docker compose down` on the shared production
stack as part of a website deployment. If deployment access is unavailable,
report the checks that remain unrun and provide the commands.

## Agent completion checklist

- [ ] Real published image, correct runtime architecture, and update policy documented.
- [ ] Unique service name; production process listens on all container interfaces.
- [ ] Correct `expose` port; website joins `backend`; no website `ports` mappings.
- [ ] Health check matches the endpoint and tools shipped in the runtime image.
- [ ] Framework proxy settings and public URL match the intended NPM deployment.
- [ ] Required environment/secrets and persistent resources documented without secrets.
- [ ] Fragment merges without changing existing services or duplicating top-level keys.
- [ ] NPM hostname, port, domains, TLS, and any WebSocket requirements documented.
- [ ] Validation evidence and outstanding inputs/checks recorded honestly.

## Reference documentation

Service-name discovery and container-port routing follow
[Docker Compose networking](https://docs.docker.com/compose/how-tos/networking/).
For `expose`, health checks, and service options, see the
[Compose service reference](https://docs.docker.com/reference/compose-file/services/).
NPM's recommended shared-network routing is described in
[Nginx Proxy Manager advanced configuration](https://nginxproxymanager.com/advanced-config/).
