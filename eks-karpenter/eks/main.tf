resource "aws_iam_role" "eks-cluster" {
  name = "eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "amazon-eks-cluster-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks-cluster.name
}

# VPC resources are expected to exist prior to deploying this Terraform module.
# Use subnet IDs from the provided variable, or fallback to remote state data if not specified.
locals {
  subnets_are_unspecified = anytrue([for value in values(var.subnet_ids) : value == ""])
}

data "terraform_remote_state" "vpc" {
  count   = local.subnets_are_unspecified ? 1 : 0
  backend = "s3"
  config = {
    bucket  = "terraform-states-opsfleet-assignment-495599757520-us-east-2"
    key     = "vpc/terraform.tfstate"
    region  = var.aws_region
    profile = var.aws_profile
  }
}

locals {
  private-subnet-az1 = (
    local.subnets_are_unspecified
    ? data.terraform_remote_state.vpc[0].outputs.private-subnet-az1
    : var.subnet_ids["private-subnet-az1"]
  )
  private-subnet-az2 = (
    local.subnets_are_unspecified
    ? data.terraform_remote_state.vpc[0].outputs.private-subnet-az2
    : var.subnet_ids["private-subnet-az2"]
  )
  public-subnet-az1 = (
    local.subnets_are_unspecified
    ? data.terraform_remote_state.vpc[0].outputs.public-subnet-az1
    : var.subnet_ids["public-subnet-az1"]
  )
  public-subnet-az2 = (
    local.subnets_are_unspecified
    ? data.terraform_remote_state.vpc[0].outputs.public-subnet-az2
    : var.subnet_ids["public-subnet-az2"]
  )
}

resource "aws_eks_cluster" "cluster" {
  name     = var.project_name
  role_arn = aws_iam_role.eks-cluster.arn
  # version  = "1.31"   # If not specified, the latest available version is used

  vpc_config {

    endpoint_private_access = false
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]

    subnet_ids = [
      local.private-subnet-az1,
      local.private-subnet-az2,
      local.public-subnet-az1,
      local.public-subnet-az2,
    ]
  }

  depends_on = [aws_iam_role_policy_attachment.amazon-eks-cluster-policy]

  provisioner "local-exec" {
    command = <<EOT
      aws eks update-kubeconfig \
          --region ${var.aws_region} \
          --name ${aws_eks_cluster.cluster.name} \
          --profile ${var.aws_profile}
    EOT
  }
}

# Nodes
resource "aws_iam_role" "nodes" {
  name = "eks-node-group"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "amazon-eks-worker-node-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "amazon-eks-cni-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "amazon-ec2-container-registry-read-only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes.name
}

resource "aws_eks_node_group" "private-nodes" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "private-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  # version         = "1.31" # Defaults to EKS Cluster Kubernetes version.

  subnet_ids = [
    local.private-subnet-az1,
    local.private-subnet-az2,
  ]

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.small"]

  scaling_config {
    desired_size = 1
    max_size     = 10
    min_size     = 0
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
  }

  depends_on = [
    aws_iam_role_policy_attachment.amazon-eks-worker-node-policy,
    aws_iam_role_policy_attachment.amazon-eks-cni-policy,
    aws_iam_role_policy_attachment.amazon-ec2-container-registry-read-only,
  ]

  # Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# OpenID Connect provider
data "tls_certificate" "eks" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# Karpenter controller role
data "aws_iam_policy_document" "karpenter_controller_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role_policy.json
  name               = "karpenter-controller"
}

resource "aws_iam_policy" "karpenter_controller" {
  policy = file("./controller-trust-policy.json")
  name   = "KarpenterController"
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_attach" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile"
  role = aws_iam_role.nodes.name
}

# Karpenter Helm
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  # version    = "v0.16.3" # If this is not specified, the latest version is installed.

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }

  set {
    name  = "clusterName"
    value = aws_eks_cluster.cluster.id
  }

  set {
    name  = "clusterEndpoint"
    value = aws_eks_cluster.cluster.endpoint
  }

  set {
    name  = "aws.defaultInstanceProfile"
    value = aws_iam_instance_profile.karpenter.name
  }

  depends_on = [aws_eks_node_group.private-nodes]
}

resource "helm_release" "karpenter-provisioner" {
  name  = "karpenter-provisioner"
  chart = "./karpenter-provisioner-chart"

  depends_on = [helm_release.karpenter]
}
