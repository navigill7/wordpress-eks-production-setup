terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "wordpress-eks-cluster"
}

# VPC Configuration
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Environment = "production"
    Project     = "wordpress-k8s"
  }
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    wordpress_nodes = {
      min_size     = 2
      max_size     = 4
      desired_size = 2

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      labels = {
        role = "wordpress"
      }

      tags = {
        Environment = "production"
      }
    }
  }

  # Enable IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  tags = {
    Environment = "production"
    Project     = "wordpress-k8s"
  }
}

# EFS File System
resource "aws_efs_file_system" "wordpress_efs" {
  creation_token = "${var.cluster_name}-efs"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name        = "${var.cluster_name}-efs"
    Environment = "production"
    Project     = "wordpress-k8s"
  }
}

# Security Group for EFS
resource "aws_security_group" "efs_sg" {
  name_prefix = "${var.cluster_name}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "NFS from EKS nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-efs-sg"
  }
}

# EFS Mount Targets (one per AZ)
resource "aws_efs_mount_target" "wordpress_efs_mt" {
  count = length(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.wordpress_efs.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs_sg.id]
}

# IAM Policy for EFS CSI Driver
resource "aws_iam_policy" "efs_csi_driver_policy" {
  name        = "${var.cluster_name}-efs-csi-driver-policy"
  description = "Policy for EFS CSI driver"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:CreateAccessPoint",
          "elasticfilesystem:DeleteAccessPoint",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      }
    ]
  })
}

# IRSA for EFS CSI Driver
module "efs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-efs-csi-driver"
  attach_efs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }

  tags = {
    Environment = "production"
  }
}

# Outputs
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "efs_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.wordpress_efs.id
}

output "efs_dns_name" {
  description = "EFS DNS name"
  value       = aws_efs_file_system.wordpress_efs.dns_name
}

output "efs_csi_driver_role_arn" {
  description = "ARN of IAM role for EFS CSI driver"
  value       = module.efs_csi_driver_irsa.iam_role_arn
}