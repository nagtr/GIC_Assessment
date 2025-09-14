This document describes the architecture of a secure and scalable Banking Application deployed
on Amazon Web Services (AWS) using Elastic Kubernetes Service (EKS). The solution
demonstrates how to handle secure and efficient CRUD operations (Create, Read, Update, Delete)
for banking accounts with high availability, observability, and security.

Key Components
=================
1. Amazon VPC: Provides network isolation with public and private subnets across multiple
Availability Zones.
2. Public Subnets: Host the Application Load Balancer (ALB) and NAT Gateway.
3. Private Subnets: Host the EKS worker nodes (pods running the banking app) and the Amazon
RDS PostgreSQL database.
4. Amazon EKS: Orchestrates Kubernetes pods running the Banking REST API (GET balance,
POST deposit, POST withdraw).
5. Amazon RDS (PostgreSQL): Provides secure and durable relational data storage in Multi-AZ
configuration.
6. IAM & IRSA: Ensures fine-grained access control using IAM roles for service accounts.
7. AWS Secrets Manager: Stores and manages database credentials securely, accessible by
application pods.
8. Amazon CloudWatch: Centralized logging and monitoring for observability of cluster and
application metrics.
9. GitHub Actions (Self-hosted Runner): Automates CI/CD pipeline for container build, push to
Amazon ECR, and deployment to EKS.

High-Level Architecture Diagram
=================================

<img width="533" height="343" alt="image" src="https://github.com/user-attachments/assets/96adad0b-2dc3-4910-afcd-8b5e143937b2" />

Solution Flow
====================

1. User Traffic enters via the Application Load Balancer hosted in the public subnet.
2. Requests are forwarded to the EKS cluster pods running the Banking REST API in private
subnets.
3. Pods authenticate with IAM Roles for Service Accounts (IRSA) to fetch database credentials
securely from Secrets Manager.
4. Banking CRUD operations are executed against the Amazon RDS PostgreSQL instance.
5. All application and infrastructure logs and metrics are sent to Amazon CloudWatch for
observability.
6. The CI/CD pipeline with GitHub Actions (self-hosted runner: nagendra) builds Docker
images, pushes them to Amazon ECR, and deploys them to EKS automatically


Prerequisites
=====================
A) Accounts, access & permissions - AWS and Github
B) Local tools (versions that work well)
   Terraform ≥ 1.6
   AWS CLI ≥ 2.9 (aws --version)
   kubectl matching your cluster’s Kubernetes version (kubectl version --client)
   helm ≥ 3.12
   Docker (engine/desktop) to build images
   jq, curl, psql (for quick tests)
C) Terraform variables/inputs
D) Kubernetes add-ons (via Helm/kubectl)
E) CI/CD (GitHub Actions on self-hosted

Getting started
=====================

**Terraform: terraform init && terraform apply**
(VPC/NAT, EKS, node group, ECR, RDS, IAM/IRSA, outputs)

**Kubeconfig:**
aws eks update-kubeconfig --name <cluster> --region <region>

**ALB Controller** (Helm install with your cluster/vpc/region + IRSA SA).

**Secrets:**

Dev: create Secret bank-db with password: <value>

Prod: install Secrets Store CSI + create SecretProviderClass.

**App manifests:**

kubectl apply -f k8s/namespace.yaml

kubectl apply -f k8s/sa-irsa.yaml (if needed for app)

kubectl apply -f k8s/deployment.yaml

kubectl apply -f k8s/service.yaml

kubectl apply -f k8s/ingress.yaml

**Verify:**

kubectl -n banking get pods -o wide (pods Running/Ready)

kubectl -n banking get ing (ALB address present)

curl http://<ALB-DNS>/healthz → 200

**CI/CD:** push to main → runner builds/pushes to ECR → kubectl apply runs.
