FROM @@BASE@@

# Only needed if the site loads anything from other hosts (see gen-csp):
# ARG CSP_EXTRA="connect-src 'self'; img-src https://cdn.example"

# Optional nginx additions (redirects, cache headers): put *.conf files in nginx/.
# COPY nginx/ /etc/nginx/site.d/

COPY site/ /usr/share/nginx/html/
RUN gen-csp
