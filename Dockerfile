FROM ruby:3.2-slim-trixie
LABEL maintainer="VolgaCTF"

ARG UID=1337
ARG GID=1337
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

ENV BUNDLE_USER_HOME=/tmp/bundler
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
	&& apt-get install --no-install-recommends -y build-essential libpq-dev graphicsmagick ca-certificates \
	&& gem install bundler -v 2.4.22 \
	&& bundle install \
	&& apt-get purge -y --auto-remove build-essential \
	&& rm -rf /var/lib/apt/lists/*
RUN groupadd --gid ${GID} volgactf \
	&& useradd --uid ${UID} --gid volgactf --no-create-home --shell /usr/sbin/nologin volgactf \
	&& chown -R volgactf:volgactf .
USER volgactf
ENTRYPOINT ["/bin/sh", "entrypoint.sh"]
