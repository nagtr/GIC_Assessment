variable "project_name" {
  type    = string
  default = "apps-crud-bank"
}

variable "env" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "node_min" {
  type    = number
  default = 1
}

variable "node_desired" {
  type    = number
  default = 2
}

variable "node_max" {
  type    = number
  default = 3
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND" # or "SPOT"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.micro"]
}

variable "db_engine_version" {
  type    = string
  default = "15.14"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "crudbank"
}

variable "db_username" {
  type    = string
  default = "crudbankapp"
}

variable "db_multi_az" {
  type    = bool
  default = true
}

# Optional: used by K8s Ingress (not directly by TF here)
variable "acm_certificate_arn" {
  type    = string
  default = ""
}

