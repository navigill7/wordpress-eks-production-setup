# WordPress on EKS Deployment

Quick reference for deploying WordPress on Amazon EKS with monitoring.

## Setup Requirements

You'll need:
- AWS CLI (v2+)
- kubectl (1.28+)
- Helm 3
- Terraform 1.0+
- Docker

Configure AWS:
```bash
aws configure
aws sts get-caller-identity
```

## Part 1: Infrastructure

```bash
cd EKS_INFRA
terraform init
terraform plan
terraform apply -auto-approve
```

This takes about 15 minutes. Creates VPC, subnets, EKS cluster, node group, and EFS.

Update kubectl config:
```bash
aws eks update-kubeconfig --region us-east-1 --name wordpress-eks-cluster
kubectl get nodes
```

## Part 2: EFS Setup

Install CSI driver:
```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

ROLE_ARN=$(terraform output -raw efs_csi_driver_role_arn)

helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN
```

Create storage class:
```bash
EFS_ID=$(terraform output -raw efs_id)

cat > k8s/storage/efs-storageclass.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: ${EFS_ID}
  directoryPerms: "700"
  basePath: "/wordpress"
EOF

kubectl apply -f k8s/storage/efs-storageclass.yaml
```

## Part 3: Docker Images

Build images:
```bash
docker build -t wordpress-custom docker/wordpress
docker build -t mysql-custom docker/mysql
docker build -t nginx-openresty docker/nginx-openresty
```

Push to ECR:
```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

for repo in wordpress-custom mysql-custom nginx-openresty; do
  aws ecr create-repository --repository-name $repo --region $AWS_REGION 2>/dev/null || true
  docker tag $repo:latest $ECR_REGISTRY/$repo:latest
  docker push $ECR_REGISTRY/$repo:latest
done
```

## Part 4: Deploy WordPress

Update helm values with your ECR registry, then:
```bash
helm lint helm/wordpress
helm install my-release helm/wordpress

kubectl get pods -w
kubectl wait --for=condition=ready pod -l app=wordpress --timeout=300s
```

Get the URL:
```bash
kubectl get svc nginx
export NGINX_URL=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Access at: http://$NGINX_URL"
```

## Part 5: Monitoring

Install Prometheus stack:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin123
```

Expose Grafana:
```bash
kubectl patch svc prometheus-grafana -n monitoring -p '{"spec": {"type": "LoadBalancer"}}'

export GRAFANA_URL=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Grafana: http://$GRAFANA_URL (admin/admin123)"
```

Import these dashboard IDs in Grafana:
- 6417 (Kubernetes Cluster)
- 3119 (Pod Resources)
- 1860 (Node Exporter)

## Quick Checks

Test nginx metrics:
```bash
curl http://$NGINX_URL/metrics
```

View logs:
```bash
kubectl logs -l app=wordpress --tail=50
kubectl logs -l app=nginx --tail=50
```

Generate some traffic:
```bash
for i in {1..100}; do curl -s http://$NGINX_URL > /dev/null; done
```

## Common Issues

**Pods stuck pending:**
```bash
kubectl describe pod <pod-name>
kubectl get events --sort-by=.metadata.creationTimestamp
```

**PVC won't bind:**
```bash
kubectl describe pvc <pvc-name>
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
```

**LoadBalancer not working:**
```bash
kubectl describe svc nginx
aws elbv2 describe-load-balancers --region us-east-1
```

## Cleanup

```bash
helm uninstall my-release
helm uninstall prometheus -n monitoring
kubectl delete pvc --all
cd EKS_INFRA && terraform destroy -auto-approve
```

## Useful Prometheus Queries

Nginx request rate:
```
rate(nginx_requests_total[5m])
```

Pod CPU usage:
```
sum(rate(container_cpu_usage_seconds_total{pod=~"wordpress.*|nginx.*|mysql.*"}[5m])) by (pod)
```

Pod memory:
```
sum(container_memory_usage_bytes{pod=~"wordpress.*|nginx.*|mysql.*"}) by (pod)
```
