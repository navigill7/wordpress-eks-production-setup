FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    libpcre3 libpcre3-dev \
    libssl-dev \
    zlib1g-dev \
    libpq-dev \
    libc6-dev \
    curl wget git \
    ca-certificates \
    make \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /usr/local/src

RUN wget https://openresty.org/download/openresty-1.21.4.1.tar.gz && \
    tar -xzf openresty-1.21.4.1.tar.gz

WORKDIR /usr/local/src/openresty-1.21.4.1

RUN ./configure \
    --prefix=/opt/openresty \
    --with-pcre-jit \
    --with-ipv6 \
    --without-http_redis2_module \
    --with-http_iconv_module \
    --with-http_postgres_module \
    -j8 && \
    make && make install

ENV PATH="/opt/openresty/nginx/sbin:$PATH"

COPY nginx.conf /opt/openresty/nginx/conf/nginx.conf
COPY lua /opt/openresty/nginx/lua

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
