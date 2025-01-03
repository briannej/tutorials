data "aws_iam_policy_document" "efs_csi_driver" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

resource "aws_iam_role" "efs_csi_driver" {
  name               = "${aws_eks_cluster.eks.name}-efs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_driver.json
}

resource "aws_iam_role_policy_attachment" "efs_csi_driver" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.efs_csi_driver.name
}


# Optional: only if you want to encrypt the EBS drives
resource "aws_iam_policy" "efs_csi_driver_encryption" {
  name = "${aws_eks_cluster.eks.name}-efs-csi-driver-encryption"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })
}

# Optional: only if you want to encrypt the EBS drives
resource "aws_iam_role_policy_attachment" "efs_csi_driver_encryption" {
  policy_arn = aws_iam_policy.efs_csi_driver_encryption.arn
  role       = aws_iam_role.efs_csi_driver.name
}

resource "aws_eks_pod_identity_association" "efs_csi_driver" {
  cluster_name    = aws_eks_cluster.eks.name
  namespace       = "kube-system"
  service_account = "efs-csi-controller-sa"
  role_arn        = aws_iam_role.efs_csi_driver.arn
}

resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name             = aws_eks_cluster.eks.name
  addon_name               = "aws-efs-csi-driver"
  addon_version            = "v2.1.2-eksbuild.1"
  service_account_role_arn = aws_iam_role.efs_csi_driver.arn

  depends_on = [
    aws_eks_node_group.general,
    aws_efs_mount_target.zone_a,
    aws_efs_mount_target.zone_b
  ]
}


resource "aws_efs_file_system" "eks" {
  creation_token = "eks"

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  # lifecycle_policy {
  #   transition_to_ia = "AFTER_30_DAYS"
  # }
}

resource "aws_efs_mount_target" "zone_a" {
  file_system_id  = aws_efs_file_system.eks.id
  subnet_id       = aws_subnet.private_zone1.id
  security_groups = [aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id]
}

resource "aws_efs_mount_target" "zone_b" {
  file_system_id  = aws_efs_file_system.eks.id
  subnet_id       = aws_subnet.private_zone2.id
  security_groups = [aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id]
}


# Optional since we already init helm provider (just to make it self contained)
data "aws_eks_cluster" "eks_v2" {
  name = aws_eks_cluster.eks.name
}

# Optional since we already init helm provider (just to make it self contained)
data "aws_eks_cluster_auth" "eks_v2" {
  name = aws_eks_cluster.eks.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks_v2.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_v2.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks_v2.token
}

resource "kubernetes_storage_class_v1" "efs" {
  metadata {
    name = "efs"
  }

  storage_provisioner = "efs.csi.aws.com"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.eks.id
    directoryPerms   = "700"
  }

  mount_options = ["iam"]

  depends_on = [aws_eks_addon.efs_csi_driver]
}
