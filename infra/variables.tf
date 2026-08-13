terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "provenance-lab"
}

variable "github_repo" {
  description = "owner/repo — scopes the OIDC trust so only this repo can assume the deploy role"
  type        = string
}

variable "allowed_cidr" {
  description = "Who can reach the ALB. Default is open; set to <your-ip>/32 for a private lab."
  type        = string
  default     = "0.0.0.0/0"
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  description = "Set to 0 to park the lab and stop paying for compute."
  type        = number
  default     = 2
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
