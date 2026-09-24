FROM nginxinc/nginx-unprivileged:stable-alpine@sha256:daa17b944bac2b578e962da4c61ad72a59233b3c63abea17113acaf4e6b9aea4 AS runtime
USER root
# The pinned base contains libexpat 2.8.4-r0; require the security-fixed package.
RUN apk add --no-cache --upgrade 'libexpat>=2.8.5-r0'
RUN rm /etc/nginx/conf.d/default.conf
COPY containers/nginx/nginx.conf /etc/nginx/nginx.conf
USER 101:101
EXPOSE 8080
ENTRYPOINT ["nginx", "-g", "daemon off;"]

FROM runtime AS preview
COPY --chown=101:101 dist/ /site/
COPY containers/nginx/preview.conf /etc/nginx/conf.d/site.conf
