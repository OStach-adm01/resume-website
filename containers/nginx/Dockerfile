FROM nginxinc/nginx-unprivileged:stable-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03 AS runtime
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
