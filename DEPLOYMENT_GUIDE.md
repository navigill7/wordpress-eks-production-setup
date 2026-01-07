# WordPress on EKS - Complete Deployment Guide

This guide provides step-by-step instructions to deploy the WordPress application on Amazon EKS.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Infrastructure Setup](#infrastructure-setup)
3. [Docker Images](#docker-images)
4. [Application Deployment](#application-deployment)
5. [Monitoring Setup](#monitoring-setup)
6. [Verification](#verification)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools
```bash
# Check versions
aws --version        # AWS CLI 2.x
kubectl version      # v1.28+
helm version         # v3.x
terraform version    # v1.0+
docker --version     # 20.x+
```

### AWS Configuration
```bash
# Configure AWS credentials
aws configure

# Verify access
aws sts get-caller-identity
```

---

## Infrastructure Setup

### Step 1: Deploy EKS Cluster
```bash
# Navigate to infrastructure directory
cd EKS_INFRA

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration (takes ~15 minutes)
terraform apply -auto-approve
```

**What gets created:**
- VPC with 3 public and 3 private subnets
- NAT Gateway for private subnets
- EKS Cluster (v1.31)
- Managed Node Group (2x t3.medium)
- EFS File System (encrypted)
- Security Groups
- IAM Roles and Policies

### Step 2: Configure kubectl
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name wordpress-eks-cluster

# Verify connection
kubectl get nodes
kubectl cluster-info
```

### Step 3: Install EFS CSI Driver
```bash
# Add Helm repository
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

# Get IAM role ARN from Terraform
ROLE_ARN=$(terraform output -raw efs_csi_driver_role_arn)

# Install CSI driver
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN

# Verify installation
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
```

### Step 4: Create StorageClass
```bash
# Get EFS ID
EFS_ID=$(terraform output -raw efs_id)

# Create StorageClass
cd ..
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
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
  basePath: "/wordpress"
reclaimPolicy: Retain
volumeBindingMode: Immediate
EOF

# Apply StorageClass
kubectl apply -f k8s/storage/efs-storageclass.yaml

# Verify
kubectl get storageclass
```

---

## Docker Images

### Step 1: Build Images
```bash
# Build all images
docker build -t wordpress-custom docker/wordpress
docker build -t mysql-custom docker/mysql
docker build -t nginx-openresty docker/nginx-openresty

# Verify builds
docker images | grep -E "wordpress|mysql|nginx"
```

### Step 2: Push to ECR
```bash
# Get AWS account details
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-east-1
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Create repositories
for repo in wordpress-custom mysql-custom nginx-openresty; do
  aws ecr create-repository --repository-name $repo --region $AWS_REGION 2>/dev/null || true
done

# Tag and push images
for img in wordpress-custom mysql-custom nginx-openresty; do
  docker tag $img:latest $ECR_REGISTRY/$img:latest
  docker push $ECR_REGISTRY/$img:latest
done

# Verify images in ECR
aws ecr describe-images --repository-name wordpress-custom --region $AWS_REGION
```

### Step 3: Update Helm Values
```bash
# Update values.yaml with ECR URLs
cat > helm/wordpress/values.yaml <<EOF
replicaCount: 2

images:
  wordpress: ${ECR_REGISTRY}/wordpress-custom:latest
  mysql: ${ECR_REGISTRY}/mysql-custom:latest
  nginx: ${ECR_REGISTRY}/nginx-openresty:latest

storage:
  className: efs-sc
  size: 5Gi
EOF

# Verify
cat helm/wordpress/values.yaml
```

---

## Application Deployment

### Step 1: Validate Helm Chart
```bash
# Lint the chart
helm lint helm/wordpress

# Dry run
helm install my-release helm/wordpress --dry-run --debug
```

### Step 2: Deploy Application
```bash
# Install Helm release
helm install my-release helm/wordpress

# Watch pods start
kubectl get pods -w
```

### Step 3: Verify Deployment
```bash
# Check all resources
kubectl get pods
kubectl get pvc
kubectl get svc

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod -l app=wordpress --timeout=300s
kubectl wait --for=condition=ready pod -l app=mysql --timeout=300s
kubectl wait --for=condition=ready pod -l app=nginx --timeout=300s
```

### Step 4: Get Application URL
```bash
# Get LoadBalancer URL (may take 2-3 minutes)
kubectl get svc nginx -w

# Get URL directly
export NGINX_URL=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "WordPress URL: http://$NGINX_URL"

# Test access
curl -I http://$NGINX_URL
```

---

## Monitoring Setup

### Step 1: Install Prometheus Stack
```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin123

# Wait for pods
kubectl get pods -n monitoring -w
```

### Step 2: Expose Grafana
```bash
# Change to LoadBalancer
kubectl patch svc prometheus-grafana -n monitoring -p '{"spec": {"type": "LoadBalancer"}}'

# Get Grafana URL
kubectl get svc prometheus-grafana -n monitoring -w

export GRAFANA_URL=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Grafana URL: http://$GRAFANA_URL"
echo "Username: admin"
echo "Password: admin123"
```

### Step 3: Import Dashboards

1. Open Grafana URL in browser
2. Login with admin/admin123
3. Go to Dashboards → Import
4. Import dashboard ID: **6417** (Kubernetes Cluster)
5. Import dashboard ID: **3119** (Pod Resources)
6. Import dashboard ID: **1860** (Node Exporter)

### Step 4: Create Custom Dashboard

Create panels with these queries:

**Nginx Requests:**
```promql
nginx_requests_total
rate(nginx_requests_total[5m])
```

**Pod CPU:**
```promql
sum(rate(container_cpu_usage_seconds_total{pod=~"wordpress.*|nginx.*|mysql.*",container!=""}[5m])) by (pod)
```

**Pod Memory:**
```promql
sum(container_memory_usage_bytes{pod=~"wordpress.*|nginx.*|mysql.*",container!=""}) by (pod)
```

---

## Verification

### Test Nginx Metrics
```bash
curl http://$NGINX_URL/metrics
```

Expected output:
```
# TYPE nginx_requests_total counter
nginx_requests_total 123
```

### Generate Traffic
```bash
# Send 100 requests
for i in {1..100}; do
  curl -s http://$NGINX_URL > /dev/null
  echo -ne "Request $i/100\r"
done
```

### Check Prometheus Targets
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```
Open: http://localhost:9090/targets

### View Application Logs
```bash
kubectl logs -l app=wordpress --tail=50
kubectl logs -l app=nginx --tail=50
kubectl logs -l app=mysql --tail=50
```

---

## Troubleshooting

### Pods Not Starting
```bash
# Describe pod
kubectl describe pod <pod-name>

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp

# Check logs
kubectl logs <pod-name>
```

### PVC Not Binding
```bash
# Check PVC status
kubectl describe pvc <pvc-name>

# Check StorageClass
kubectl describe sc efs-sc

# Verify EFS CSI driver
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
```

### LoadBalancer Not Ready
```bash
# Check service
kubectl describe svc nginx

# Check AWS Load Balancer
aws elbv2 describe-load-balancers --region us-east-1
```

### Metrics Not Showing
```bash
# Check ServiceMonitor
kubectl get servicemonitor
kubectl describe servicemonitor nginx-metrics

# Check Prometheus logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus
```

---

## Cleanup
```bash
# Delete applications
helm uninstall my-release
helm uninstall prometheus -n monitoring
helm uninstall aws-efs-csi-driver -n kube-system

# Delete PVCs
kubectl delete pvc --all

# Destroy infrastructure
cd EKS_INFRA
terraform destroy -auto-approve
```

---

## Next Steps

- [View Metrics Documentation](METRICS_DOCUMENTATION.md)
- [Return to README](README.md)
