#
# Dockerfile for curl-http3
#

FROM alpine:edge as builder

RUN set -ex \
  && apk add --update --no-cache \
     autoconf \
     automake \
     g++ \
     gcc \
     git \
     libc-dev \
     libev-dev \
     libtool \
     linux-headers \
     make \
     musl-dev \
     nghttp2-dev \
     nghttp3-dev \
     pcre-dev \
     perl \
     pkgconf \
     tree \
     util-linux \
     zlib-dev \
  && rm -rf /tmp/* /var/cache/apk/*

WORKDIR /tmp/wolfssl
RUN set -ex \
  && git clone https://github.com/wolfSSL/wolfssl.git . \
  && git checkout $(git tag | grep stable | sort -V | tail -1) \
  && autoreconf -fi \
  && ./configure --enable-quic --enable-session-ticket --enable-earlydata --enable-psk --enable-harden --enable-altcertchains \
  && make && make install

WORKDIR /tmp/ngtcp2
RUN set -ex \
  && git clone https://github.com/ngtcp2/ngtcp2.git . \
  && git checkout $(git tag | sort -V | tail -1) \
  && autoreconf -fi \
  && ./configure --enable-lib-only --with-wolfssl \
  && make && make install

WORKDIR /tmp/curl
RUN set -ex \
  && git clone https://github.com/curl/curl.git . \
  && git checkout $(git tag | egrep ^curl- | sort -V | tail -1) \
  && autoreconf -fi \
  && ./configure --with-wolfssl --with-nghttp3 --with-ngtcp2 \
  && make && make install

WORKDIR /build
RUN set -ex \
  && ldd /usr/local/bin/curl |cut -d ">" -f 2|grep lib|cut -d "(" -f 1|xargs tar -chvf /tmp/curl.tar \
  && tar -xvf /tmp/curl.tar -C /build \
  && cp --parents /usr/local/bin/* /build \
  && export runDeps="$( \
     scanelf --needed --nobanner usr/local/lib/* usr/local/bin/* \
      | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
      | xargs -r apk info --installed \
      | sort -u | grep -v libcurl \
     )" \
  && echo $runDeps > usr/local/run-deps \
  && tree

FROM alpine:edge
COPY --from=builder /build/usr/local /usr/local

RUN set -ex \
  && export runDeps="$(cat /usr/local/run-deps)" \
  && apk add --update --no-cache --virtual .run-deps $runDeps \
  && apk add --update --no-cache ca-certificates \
  && rm -rf /tmp/* /var/cache/apk/*
