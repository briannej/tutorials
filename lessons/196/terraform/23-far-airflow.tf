# Optional since we already init helm provider (just to make it self contained)
data "aws_eks_cluster" "eks_v2" {
  name = aws_eks_cluster.eks.name
}

# Optional since we already init helm provider (just to make it self contained)
data "aws_eks_cluster_auth" "eks_v2" {
  name = aws_eks_cluster.eks.name
}

# Optional since we already init helm provider (just to make it self contained)
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks_v2.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_v2.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks_v2.token
}

# I needed to add this to create a deafult storageclass. airflow pvc use the default storageclass
resource "kubernetes_storage_class_v1" "ebs-airflow" {
  metadata {
    name = "ebs-airflow"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "kubernetes.io/aws-ebs"

  #provisioner          = "kubernetes.io/aws-ebs"
  reclaim_policy       = "Delete"
  volume_binding_mode  = "WaitForFirstConsumer"
  allow_volume_expansion = false

  parameters = {
    type = "gp2"
    fsType = "ext4"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}


resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  namespace        = "keda"
  create_namespace = true
  version    = "2.16.1"

}

resource "helm_release" "airflow" {
  name = "airflow"

  repository       = "https://airflow.apache.org"
  chart            = "airflow"
  namespace        = "airflow"
  create_namespace = true
  version          = "1.15.0"
  timeout    = 600

  values = [file("${path.module}/values/airflow.yaml")]

  depends_on = [aws_eks_addon.ebs_csi_driver, kubernetes_storage_class_v1.ebs-airflow, helm_release.keda]
}
