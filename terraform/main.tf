# --- Terraform Configuration ---
# This block defines the required providers for our infrastructure.
terraform {
  required_providers {
    # Kind provider for creating local Kubernetes clusters in Docker containers.
    kind = {
      source  = "tehcyx/kind"
      version = "0.7.0"
    }
    # Kubernetes provider for interacting with Kubernetes resources.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    # Helm provider for deploying applications using Helm charts.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    # Local provider for managing local files (used here for kubeconfig).
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# --- Provider Initialization ---

provider "kind" {}

# Save the kubeconfig from Kind cluster to a local file so other providers can use it.
resource "local_file" "kubeconfig" {
  content  = kind_cluster.default.kubeconfig
  filename = "${path.module}/kubeconfig"
}

# Configure the Kubernetes provider using the newly created kubeconfig file.
provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

# Configure the Helm provider using the same kubeconfig for K8s authentication.
provider "helm" {
  kubernetes {
    config_path = local_file.kubeconfig.filename
  }
}

# --- Infrastructure Definition ---

# Create the local Kubernetes cluster using Kind.
resource "kind_cluster" "default" {
  name = "devops-playground"
  
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Define the control-plane node with port mappings for external access.
    node {
      role = "control-plane"

      # Essential for Ingress Controller to identify this node for port-forwarding.
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
      
      # Port 80 mapping for HTTP ingress traffic.
      extra_port_mappings {
        container_port = 80
        host_port      = 80
        listen_address = "0.0.0.0"
      }
      # Port 443 mapping for HTTPS ingress traffic.
      extra_port_mappings {
        container_port = 443
        host_port      = 443
        listen_address = "0.0.0.0"
      }
    }

    # Define a worker node for application workloads.
    node {
      role = "worker"
    }
  }
}

# --- Ingress Layer ---

# Deploy Nginx Ingress Controller using Helm.
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  create_namespace = true
  version    = "4.12.0"

  # Kind-specific configurations to bind to the host ports.
  values = [
    yamlencode({
      controller = {
        hostPort = {
          enabled = true
        }
        terminationGracePeriodSeconds = 0
        service = {
          type = "NodePort"
        }
        nodeSelector = {
          "ingress-ready" = "true"
        }
        tolerations = [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Equal"
            effect   = "NoSchedule"
          },
          {
            key      = "node-role.kubernetes.io/master"
            operator = "Equal"
            effect   = "NoSchedule"
          }
        ]
      }
    })
  ]

  depends_on = [kind_cluster.default]
}

# --- Monitoring Layer ---

# Create a dedicated namespace for monitoring tools.
resource "kubernetes_namespace_v1" "monitoring" {
  depends_on = [kind_cluster.default]
  metadata {
    name = "monitoring"
  }
}

# Deploy the Kube-Prometheus-Stack (includes Prometheus, Grafana, Alertmanager).
resource "helm_release" "prometheus" {
  name       = "prometheus"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "69.7.2" # Stable Helm chart version

  values = [
    yamlencode({
      grafana = {
        enabled = true
      }
    })
  ]
}

# --- GitOps Layer (ArgoCD) ---

# Create a dedicated namespace for ArgoCD.
resource "kubernetes_namespace_v1" "argocd" {
  depends_on = [kind_cluster.default]
  metadata {
    name = "argocd"
  }
}

# Deploy ArgoCD using its official Helm chart.
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.8.2"

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }
}

# --- ArgoCD Application Registration ---

# Register our Frontend Application with ArgoCD for automated GitOps deployments.
resource "kubernetes_manifest" "frontend_app" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "frontend"
      namespace = "argocd"
    }
    spec = {
      # Use the default ArgoCD project.
      project = "default"
      # Define the source of the application (GitHub Repo + Path to Helm Chart).
      source = {
        repoURL        = "https://github.com/rameshsurapathi/DevOpsPlayground.git"
        targetRevision = "HEAD"
        path           = "charts/frontend-chart"
      }
      # Define where to deploy the application (Local Cluster + Default Namespace).
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      # Enable automated synchronization and self-healing.
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}

# --- Ingress Routes (The External "Map") ---

# Ingress for Grafana Dashboards
resource "kubernetes_ingress_v1" "grafana_ingress" {
  depends_on = [helm_release.prometheus]
  metadata {
    name      = "grafana-ingress"
    namespace = "monitoring"
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }
  spec {
    rule {
      host = "grafana.local"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "prometheus-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

# Ingress for Prometheus Expression Browser
resource "kubernetes_ingress_v1" "prometheus_ingress" {
  depends_on = [helm_release.prometheus]
  metadata {
    name      = "prometheus-ingress"
    namespace = "monitoring"
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }
  spec {
    rule {
      host = "prometheus.local"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "prometheus-kube-prometheus-prometheus"
              port {
                number = 9090
              }
            }
          }
        }
      }
    }
  }
}

# Ingress for ArgoCD UI
resource "kubernetes_ingress_v1" "argocd_ingress" {
  depends_on = [helm_release.argocd]
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
    annotations = {
      "kubernetes.io/ingress.class"      = "nginx"
      "nginx.ingress.kubernetes.io/ssl-passthrough" = "false"
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }
  spec {
    rule {
      host = "argocd.local"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}