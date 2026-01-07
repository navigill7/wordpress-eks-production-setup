cat > README.md <<'EOF'
# WordPress on EKS - Production Setup

[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.31-blue)](https://kubernetes.io/)
[![Terraform](https://img.shields.io/badge/Terraform-1.0+-purple)](https://terraform.io/)
[![Helm](https://img.shields.io/badge/Helm-3-blue)](https://helm.sh/)

Complete production-grade WordPress deployment on Amazon EKS with monitoring and alerting.

![WordPress Architecture](screenshots/04-wordpress-running.png)

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Monitoring](#monitoring)
- [Screenshots](#screenshots)
- [Cleanup](#cleanup)

## 🎯 Overview

This project demonstrates a production-ready WordPress deployment on AWS EKS that includes:

- **Custom Docker Images**: WordPress, MySQL, and Nginx with OpenResty + Lua
- **Shared Storage**: AWS EFS with ReadWriteMany access mode for WordPress uploads
- **Kubernetes Orchestration**: Deployed using Helm charts
- **Monitoring**: Prometheus & Grafana with custom metrics and alerts
- **High Availability**: Multi-pod WordPress deployment with load balancing

## 🏗️ Architecture



## ✨ Features

### Infrastructure
- ✅ EKS Cluster managed by Terraform
- ✅ Auto-scaling node group (2-4 nodes)
- ✅ EFS with encryption for shared storage
- ✅ VPC with public/private subnets across 3 AZs
- ✅ IAM Roles for Service Accounts (IRSA)

### Application
- ✅ Nginx with OpenResty and Lua support
- ✅ Custom metrics endpoint (`/metrics`)
- ✅ WordPress with horizontal scaling (2 replicas)
- ✅ MySQL 8.0 with persistent storage
- ✅ ReadWriteMany PVCs using EFS

### Monitoring
- ✅ Prometheus for metrics collection
- ✅ Grafana dashboards for visualization
- ✅ Custom metrics: Nginx requests, Pod CPU, Pod Memory
- ✅ Automated alerts for resource usage
- ✅ ServiceMonitor for automatic scraping

## 📦 Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl (v1.28+)
- Helm 3
- Terraform (v1.0+)
- Docker
- Git

## 🚀 Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/yourusername/wordpress-eks-production-setup.git
cd wordpress-eks-production-setup
```

### 2. Deploy Infrastructure
```bash
cd EKS_INFRA
terraform init
terraform apply -auto-approve
```

### 3. Configure kubectl
```bash
aws eks update-kubeconfig --region us-east-1 --name wordpress-eks-cluster
kubectl get nodes
```

### 4. Install EFS CSI Driver
```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
ROLE_ARN=$(cd EKS_INFRA && terraform output -raw efs_csi_driver_role_arn)
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN
```

### 5. Deploy WordPress
```bash
cd ..
helm install my-release helm/wordpress
kubectl get pods -w
```

### 6. Install Monitoring
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin123
```

### 7. Access Applications
```bash
# WordPress
kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Grafana
kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## 📁 Project Structure
```
wordpress-eks-production-setup/
├── EKS_INFRA/              
│   ├── main.tf             
│   └── outputs.tf          
├── docker/                 
│   ├── nginx-openresty/    
│   │   ├── Dockerfile
│   │   ├── nginx.conf
│   │   └── lua/metrics.lua
│   ├── wordpress/         
│   │   └── Dockerfile
│   └── mysql/              
│       └── Dockerfile
├── helm/wordpress/         
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── wordpress-deployment.yaml
│       ├── mysql-deployment.yaml
│       ├── nginx-deployment.yaml
│       ├── services.yaml
│       ├── pvc.yaml
│       ├── mysql-pvc.yaml
│       ├── secrets.yaml
│       ├── nginx-servicemonitor.yaml
│       └── alert-rules.yaml
├── k8s/storage/
│   └── efs-storageclass.yaml
├── screenshots/            # Documentation screenshots
├── DEPLOYMENT_GUIDE.md     # Detailed deployment guide
├── METRICS_DOCUMENTATION.md # Monitoring documentation
└── README.md               # This file
```

## 📊 Monitoring

### Grafana Access
- **URL**: Get from `kubectl get svc prometheus-grafana -n monitoring`
- **Username**: `admin`
- **Password**: `admin123`

### Available Metrics
- **Nginx Request Rate**: Total HTTP requests per second
- **Pod CPU Utilization**: CPU usage across all application pods
- **Pod Memory Usage**: Memory consumption per pod
- **Pod Status**: Running/Failed pods count

### Dashboards
1. **Kubernetes Cluster Monitoring** (ID: 6417)
2. **Kubernetes Pod Resources** (ID: 3119)
3. **Node Exporter** (ID: 1860)
4. **WordPress Application Metrics** (Custom)

### Alerts
- **HighPodCPU**: Fires when CPU > 80% for 5 minutes
- **HighPodMemory**: Fires when memory > 80% for 5 minutes
- **PodRestarting**: Fires when pods restart unexpectedly

![Grafana Dashboard](screenshots/09-grafana-wordpress-dashboard.png)

## 📸 Screenshots

### 1. EKS Cluster
![EKS Nodes](screenshots/01-eks-cluster-nodes.png)

### 2. Storage Configuration
![PVC Status](screenshots/02-storage-pvc.png)

### 3. Running Pods
![Pods Running](screenshots/03-running-pods-services.png)

### 4. WordPress Application
![WordPress Running](screenshots/04-wordpress-running.png)

### 5. Prometheus Targets
![Prometheus Targets](screenshots/06-prometheus-targets.png)

### 6. Grafana Monitoring
![Grafana Dashboard](screenshots/07-grafana-cluster-dashboard.png)

## 🧪 Testing

### Generate Traffic
```bash
export NGINX_URL=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in {1..100}; do curl -s http://$NGINX_URL; done
```

### Check Metrics
```bash
curl http://$NGINX_URL/metrics
```

### View Logs
```bash
kubectl logs -l app=wordpress --tail=50
kubectl logs -l app=nginx --tail=50
kubectl logs -l app=mysql --tail=50
```

## 🧹 Cleanup
```bash
# Delete Helm releases
helm uninstall my-release
helm uninstall prometheus -n monitoring
helm uninstall aws-efs-csi-driver -n kube-system

# Delete infrastructure
cd EKS_INFRA
terraform destroy -auto-approve
```

## 💰 Cost Estimation

Monthly costs (us-east-1 region):
- EKS Cluster: ~$73
- EC2 (2x t3.medium): ~$60
- EFS Storage (5GB): ~$1.50
- Load Balancer: ~$16
- **Total**: ~$150/month

## ✅ Assignment Requirements Checklist

- [x] Production-grade WordPress on Kubernetes
- [x] PersistentVolumeClaims with ReadWriteMany (EFS)
- [x] Custom Dockerfiles (WordPress, MySQL, Nginx)
- [x] Nginx compiled with OpenResty + Lua
- [x] Deployment using Helm chart (`helm install`)
- [x] Clean removal using `helm delete`
- [x] Prometheus & Grafana monitoring stack
- [x] Pod CPU utilization monitoring
- [x] Nginx total request count
- [x] Nginx 5xx error monitoring capability
- [x] Complete documentation
- [x] GitHub repository

## 📚 Documentation

- [Deployment Guide](DEPLOYMENT_GUIDE.md) - Detailed step-by-step instructions
- [Metrics Documentation](METRICS_DOCUMENTATION.md) - Monitoring and alerting details

## 🤝 Contributing

This is an assignment project. For issues or questions, please open an issue.

## 📝 License

MIT License

## 👤 Author

**Your Name**  
DevOps Engineer Intern Assignment - Syfe 2022

---

**Repository**: [GitHub Link]  
**Assignment**: Syfe Infrastructure Intern - 2022
EOF

echo "✅ README.md created"