FROM ruby:2.5.5-alpine
LABEL maintainer="VolgaCTF"

ARG BUILD_DATE
ARG BUILD_VERSION
ARG VCS_REF

LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.name="volgactf-final-backend"
LABEL org.label-schema.description="VolgaCTF Final Backend - main application"
LABEL org.label-schema.url="https://volgactf.ru/en"
LABEL org.label-schema.vcs-url="https://github.com/VolgaCTF/volgactf-final-backend"
LABEL org.label-schema.vcs-ref=$VCS_REF
LABEL org.label-schema.version=$BUILD_VERSION

WORKDIR /app
COPY VERSION config.ru Gemfile* Rakefile scheduler.rb entrypoint.sh .
COPY lib ./lib
COPY logo ./logo
COPY migrations ./migrations

RUN apk add --no-cache --virtual .build-deps make g++ gcc musl-dev && apk add postgresql-dev graphicsmagick && gem install bundler -v 2.0.1 && bundle && apk del .build-deps
RUN addgroup volgactf && adduser --disabled-password --gecos "" --ingroup volgactf --no-create-home volgactf && chown -R volgactf:volgactf .
USER volgactf
ENTRYPOINT ["/bin/sh", "entrypoint.sh"]
