terraform {
  required_version = ">= 1.5"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.6"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "helm" {
  kubernetes {
    host                    = kind_cluster.default.endpoint
    cluster_ca_certificate  = kind_cluster.default.cluster_ca_certificate
    client_certificate      = kind_cluster.default.client_certificate
    client_key              = kind_cluster.default.client_key
  }
}

provider "kubernetes" {
  host                    = kind_cluster.default.endpoint
  cluster_ca_certificate  = kind_cluster.default.cluster_ca_certificate
  client_certificate      = kind_cluster.default.client_certificate
  client_key              = kind_cluster.default.client_key
}

provider "kubectl" {
  host                    = kind_cluster.default.endpoint
  cluster_ca_certificate  = kind_cluster.default.cluster_ca_certificate
  client_certificate      = kind_cluster.default.client_certificate
  client_key              = kind_cluster.default.client_key
  load_config_file        = false
}