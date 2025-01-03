data "aws_iam_policy_document" "mountpoint_s3_csi_driver" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:s3-csi-driver-sa"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "mountpoint_s3_csi_driver" {
  name               = "${aws_eks_cluster.eks.name}-mountpoint-s3-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.mountpoint_s3_csi_driver.json
}

## FOR FUTURE POD IDENTITY ASSOCIATION
# data "aws_iam_policy_document" "mountpoint_s3_csi_driver" {
#   statement {
#     effect = "Allow"

#     principals {
#       type        = "Service"
#       identifiers = ["pods.eks.amazonaws.com"]
#     }

#     actions = [
#       "sts:AssumeRole",
#       "sts:TagSession"
#     ]
#   }
# }

## FOR FUTURE POD IDENTITY ASSOCIATION
# resource "aws_iam_role" "mountpoint_s3_csi_driver" {
#   name               = "${aws_eks_cluster.eks.name}-mountpoint-s3-csi-driver"
#   assume_role_policy = data.aws_iam_policy_document.mountpoint_s3_csi_driver.json
# }


#delete this
# resource "aws_iam_role" "mountpoint_s3_csi_driver" {
#   name = "${aws_eks_cluster.eks.name}-mountpoint-s3-csi-driver"

#   assume_role_policy = jsonencode({
#     "Version": "2012-10-17",
#     "Statement": [
#       {
#         "Effect": "Allow",
#         "Principal": {
#           "Service": "eks.amazonaws.com"
#         },
#         "Action": "sts:AssumeRole"
#       }
#     ]
#   })
# }


resource "aws_iam_policy" "custom_s3_access" {
  name = "${aws_eks_cluster.eks.name}-custom-s3-access"

  policy = jsonencode(
    
{
   "Version": "2012-10-17",
   "Statement": [
        {
            "Sid": "MountpointFullBucketAccess",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::farzad-eks-bucket"
            ]
        },
        {
            "Sid": "MountpointFullObjectAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::farzad-eks-bucket/*"
            ]
        }
   ]
}
  )
}





resource "aws_iam_role_policy_attachment" "mountpoint_s3_csi_driver" {
  policy_arn = aws_iam_policy.custom_s3_access.arn
  role       = aws_iam_role.mountpoint_s3_csi_driver.name
}



# Optional: only if you want to encrypt the EBS drives
resource "aws_iam_policy" "mountpoint_s3_csi_driver_encryption" {
  name = "${aws_eks_cluster.eks.name}-mountpoint-s3-csi-driver-encryption"

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
resource "aws_iam_role_policy_attachment" "mountpoint_s3_csi_driver_encryption" {
  policy_arn = aws_iam_policy.mountpoint_s3_csi_driver_encryption.arn
  role       = aws_iam_role.mountpoint_s3_csi_driver.name
}

## FOR FUTURE POD IDENTITY ASSOCIATION
# resource "aws_eks_pod_identity_association" "mountpoint_s3_csi_driver" {
#   cluster_name    = aws_eks_cluster.eks.name
#   namespace       = "kube-system"
#   service_account = "s3-csi-driver-sa"
#   role_arn        = aws_iam_role.mountpoint_s3_csi_driver.arn
# }

resource "aws_eks_addon" "mountpoint_s3_csi_driver" {
  cluster_name             = aws_eks_cluster.eks.name
  addon_name               = "aws-mountpoint-s3-csi-driver"
  addon_version            = "v1.11.0-eksbuild.1"
  service_account_role_arn = aws_iam_role.mountpoint_s3_csi_driver.arn

  depends_on = [
    aws_eks_node_group.general
  ]
}


