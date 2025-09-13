terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws   = { source = "hashicorp/aws",   version = "~> 5.55" }
    random= { source = "hashicorp/random",version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.region
}

locals {
  name        = "${var.project_name}-${var.env}"
  tags_common = { Project = var.project_name, Env = var.env }
}

data "aws_availability_zones" "available" {}

locals {
  # take the first two AZs in the region (or change slice to however many you need)
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)
  az_index = { a = 0, b = 1 } # maps your for_each keys to indices in local.azs
}

# ---------------- VPC ----------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags_common, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags_common, { Name = "${local.name}-igw" })
}

resource "aws_subnet" "public" {
  for_each = {
    a = var.public_subnet_cidrs[0]
    b = var.public_subnet_cidrs[1]
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = local.azs[local.az_index[each.key]]

  tags = merge(local.tags_common, {
    Name                     = "${local.name}-public-${each.key}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  for_each = {
    a = var.private_subnet_cidrs[0]
    b = var.private_subnet_cidrs[1]
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = local.azs[local.az_index[each.key]]

  tags = merge(local.tags_common, {
    Name                            = "${local.name}-private-${each.key}"
    Tier                            = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_eip" "nat" {
  count  = 1
  domain = "vpc"
  tags   = merge(local.tags_common, { Name = "${local.name}-nat-eip" })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public["a"].id
  tags          = merge(local.tags_common, { Name = "${local.name}-nat" })
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.tags_common, { Name = "${local.name}-rt-public" })
}


resource "aws_route_table_association" "pub_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge(local.tags_common, { Name = "${local.name}-rt-private" })
}

resource "aws_route_table_association" "pri_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# ---------------- ECR ----------------
resource "aws_ecr_repository" "repo" {
  name                 = "${local.name}-repo"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  tags = merge(local.tags_common, { Name = "${local.name}-ecr" })
}

# ---------------- Secrets Manager (DB password) ----------------
resource "random_password" "db" {
  length  = 20
  special = true
}

resource "aws_secretsmanager_secret" "db" {
  name = "${local.name}/db"
  tags = local.tags_common
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({ password = random_password.db.result })
}

# ---------------- RDS PostgreSQL ----------------
resource "aws_db_subnet_group" "db" {
  name       = "${local.name}-db-subnet-group"
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags       = merge(local.tags_common, { Name = "${local.name}-db-subnet-group" })
}

resource "aws_security_group" "rds_sg" {
  name   = "${local.name}-rds-sg"
  vpc_id = aws_vpc.main.id
  egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags_common, { Name = "${local.name}-rds-sg" })
}

resource "aws_db_instance" "postgres" {
  identifier                   = "${local.name}-db"
  engine                       = "postgres"
  engine_version               = var.db_engine_version
  instance_class               = var.db_instance_class
  allocated_storage            = 20
  max_allocated_storage        = 100
  db_subnet_group_name         = aws_db_subnet_group.db.name
  vpc_security_group_ids       = [aws_security_group.rds_sg.id]
  db_name                      = var.db_name
  username                     = var.db_username
  password                     = random_password.db.result
  backup_retention_period      = 7
  deletion_protection          = false
  skip_final_snapshot          = true
  multi_az                     = var.db_multi_az
  publicly_accessible          = false
  storage_encrypted            = true
  apply_immediately            = true
  performance_insights_enabled = true
  tags = merge(local.tags_common, { Name = "${local.name}-rds" })
}

# ---------------- EKS Cluster ----------------
resource "aws_iam_role" "eks_cluster_role" {
  name = "${local.name}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "eks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.tags_common
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = "${local.name}-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat([for s in aws_subnet.public : s.id], [for s in aws_subnet.private : s.id])
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = local.tags_common

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy
  ]
}

# Allow RDS from EKS cluster security group (pods/nodes path to DB)
resource "aws_security_group_rule" "rds_from_cluster" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_sg.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# ---------------- Node Group ----------------
resource "aws_iam_role" "eks_node_role" {
  name = "${local.name}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.tags_common
}

resource "aws_iam_role_policy_attachment" "worker_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "worker_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "worker_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name}-ng"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [for s in aws_subnet.private : s.id]

  scaling_config {
    desired_size = var.node_desired
    max_size     = var.node_max
    min_size     = var.node_min
  }
  ami_type       = "AL2_x86_64"
  capacity_type  = var.node_capacity_type # SPOT or ON_DEMAND
  instance_types = var.node_instance_types
  tags           = local.tags_common
}

# ---------------- OIDC Provider for IRSA ----------------
data "aws_eks_cluster" "this" { name = aws_eks_cluster.this.name }
data "aws_eks_cluster_auth" "this" { name = aws_eks_cluster.this.name }

resource "aws_iam_openid_connect_provider" "oidc" {
  url             = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  # Public root CA thumbprint for EKS OIDC (Amazon)
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0ecd4e0f1"]
}

# ---------------- IRSA for AWS Load Balancer Controller ----------------
data "aws_iam_policy_document" "alb_sa_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
 	type        = "Federated"
  	identifiers = [aws_iam_openid_connect_provider.oidc.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_sa_role" {
  name               = "${local.name}-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_sa_assume.json
  tags               = local.tags_common
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${local.name}-alb-controller-policy"
  policy = file("/home/nagendra/Assessment_gic/iac/terraform-eks/policies/aws-load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "alb_attach" {
  role       = aws_iam_role.alb_sa_role.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# ---------------- IRSA for app to read Secrets Manager ----------------
data "aws_iam_policy_document" "app_sa_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
  	type        = "Federated"
  	identifiers = [aws_iam_openid_connect_provider.oidc.arn]
   }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:banking:bank-app"]
    }
  }
}

resource "aws_iam_role" "app_sa_role" {
  name               = "${local.name}-app-sa-role"
  assume_role_policy = data.aws_iam_policy_document.app_sa_assume.json
  tags               = local.tags_common
}

data "aws_iam_policy_document" "app_sm" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_policy" "app_sm" {
  name   = "${local.name}-app-sm-policy"
  policy = data.aws_iam_policy_document.app_sm.json
}

resource "aws_iam_role_policy_attachment" "app_attach" {
  role       = aws_iam_role.app_sa_role.name
  policy_arn = aws_iam_policy.app_sm.arn
}

# ---------------- Outputs ----------------
output "cluster_name"        { value = aws_eks_cluster.this.name }
output "region"              { value = var.region }
output "vpc_id"              { value = aws_vpc.main.id }
output "subnets_public"      { value = [for s in aws_subnet.public : s.id] }
output "subnets_private"     { value = [for s in aws_subnet.private : s.id] }
output "db_endpoint"         { value = aws_db_instance.postgres.address }
output "db_secret_name"      { value = aws_secretsmanager_secret.db.name }
output "ecr_repo_url"        { value = aws_ecr_repository.repo.repository_url }
output "app_sa_role_arn"     { value = aws_iam_role.app_sa_role.arn }
output "alb_controller_role" { value = aws_iam_role.alb_sa_role.arn }
