#!/bin/bash
set -e

kubectl apply -f k8s/storage/
kubectl apply -f k8s/ingress/

helm install my-release helm/wordpress
