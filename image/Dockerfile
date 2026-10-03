# Base image for static sites: hardened nginx, healthcheck and CSP generator.
# Site images build FROM this, copy their files in and run gen-csp.
FROM nginx:alpine

RUN apk add --no-cache openssl \
    && rm -rf /usr/share/nginx/html/* \
    && mkdir -p /etc/nginx/site.d

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --chmod=0755 gen-csp /usr/local/bin/gen-csp

# Default policy for the empty web root; site images regenerate it.
RUN gen-csp

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
