#!/bin/bash
set -e

docker build -t wordpress-custom docker/wordpress
docker build -t mysql-custom docker/mysql
docker build -t nginx-openresty docker/nginx-openresty
