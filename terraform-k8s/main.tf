
resource "kubernetes_namespace" "staging" {
  metadata {
    name = "staging"
  }
}

resource "kubernetes_namespace" "prod" {
  metadata {
    name = "prod"
  }
}

resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = "jenkins"
  }
}


# backend - flask 

resource "kubernetes_deployment" "backend" {
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "backend"
      }
    }

    template {
      metadata {
        labels = {
          app = "backend"
        }
      }

      spec {
        container {
          name  = "flask-backend"
          image = "nginx"  # Placeholder image
          port {
            container_port = 5000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "backend" {
  metadata {
    name      = "backend-service"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  spec {
    selector = {
      app = "backend"
    }

    port {
      port        = 5000
      target_port = 5000
    }

    type = "ClusterIP"
  }
}

# frontend - react

resource "kubernetes_deployment" "frontend" {
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "frontend"
      }
    }

    template {
      metadata {
        labels = {
          app = "frontend"
        }
      }

      spec {
        container {
          name  = "react-frontend"
          image = "nginx"  # Placeholder image
          port {
            container_port = 3000
          }
        }
      }
    }
  }
}

# database - mongodb

resource "kubernetes_deployment" "mongodb" {
  metadata {
    name      = "mongodb"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "mongodb"
      }
    }

    template {
      metadata {
        labels = {
          app = "mongodb"
        }
      }

      spec {
        container {
          name  = "mongo"
          image = "nginx"  # Placeholder image
          port {
            container_port = 27017
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "mongodb" {
  metadata {
    name      = "mongodb-service"
    namespace = kubernetes_namespace.staging.metadata[0].name
  }

  spec {
    selector = {
      app = "mongodb"
    }

    port {
      port        = 27017
      target_port = 27017
    }

    type = "ClusterIP"
  }
}

# jenkins using the devopsjourney1/jenkins-blueocean:2.332.3-1 image

# deployment resource
resource "kubernetes_deployment" "jenkins" {
  metadata {
    name      = "jenkins-resource"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "jenkins"
      }
    }

    template {
      metadata {
        labels = {
          app = "jenkins"
        }
      }

      spec {
        container {
          name             = "jenkins"
          image            = "jenkins/jenkins:lts-jdk17" # Or a specific LTS version you prefer
          image_pull_policy = "Always"
          port {
            container_port = 8080 # Jenkins default port
          }
          resources { # Important to set resource limits and requests
            requests = {
              cpu    = "500m" # Adjust as needed
              memory = "1Gi"  # Adjust as needed
            }
            limits = {
              cpu    = "1"    # 1 CPU core
              memory = "2Gi"  # 2 GiB of memory
            }
          }
           # Add a volume mount for persistence (Highly Recommended!)
          volume_mount {
            mount_path = "/var/jenkins_home"
            name       = "jenkins-data" # Matches the volume name below
          }
        }
        # Define the persistent volume
        volume {
          name = "jenkins-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.jenkins.metadata[0].name
          }
        }

      }
    }
  }
}

resource "kubernetes_service" "jenkins" {
  metadata {
    name      = "jenkins-service"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  spec {
    selector = {
      app = "jenkins"
    }

    port {
      port        = 8080  # Service port (can be anything)
      target_port = 8080    # Container port
      node_port   = 31635 # Explicitly set the NodePort (important!)
    }

    type = "NodePort"
  }
}


resource "kubernetes_persistent_volume_claim" "jenkins" {
  metadata {
    name      = "jenkins-pvc"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"] # Or ReadWriteMany if your storage supports it
    resources {
      requests = {
        storage = "10Gi" # Adjust as needed
      }
    }
  }
}