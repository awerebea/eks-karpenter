provider "aws" {
  region = local.region
}

provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_availability_zones" "available" {}
data "aws_ecrpublic_authorization_token" "token" { provider = aws.virginia }
data "aws_caller_identity" "current" {}

locals {
  name   = "opsfleet-assignment"
  region = "us-east-2"

  # Provide VPC data here, or leave it empty to retrieve it from the remote state (see details below).
  vpc_id          = ""
  private_subnets = []
  intra_subnets   = []

  # If VPC data is left empty, a remote state bucket must be specified.
  vpc_remote_state_bucket = "terraform-states-opsfleet-assignment-${
    data.aws_caller_identity.current.account_id
  }-us-east-2"

  network_is_unspecified = (
    local.vpc_id == "" || length(local.private_subnets) == 0 || length(local.intra_subnets) == 0
  )

  tags = {
    project    = local.name
    managed_by = "Terraform"
  }
}

################################################################################
# EKS Module
################################################################################

# VPC resources are expected to exist prior to deploying this Terraform module.
# Use subnet IDs from the provided locals, or fallback to remote state data if not specified.
data "terraform_remote_state" "vpc" {
  count   = local.network_is_unspecified ? 1 : 0
  backend = "s3"
  config = {
    bucket = local.vpc_remote_state_bucket
    key    = "vpc/terraform.tfstate"
    region = local.region
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name = local.name
  # cluster_version = "1.31" # Use latest

  # Gives Terraform identity admin access to cluster which will
  # allow deploying resources (Karpenter) into the cluster
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  vpc_id = (
    local.network_is_unspecified
    ? data.terraform_remote_state.vpc[0].outputs.vpc_id
    : local.vpc_id
  )
  subnet_ids = (
    local.network_is_unspecified
    ? data.terraform_remote_state.vpc[0].outputs.private_subnets
    : local.private_subnets
  )
  control_plane_subnet_ids = (
    local.network_is_unspecified
    ? data.terraform_remote_state.vpc[0].outputs.intra_subnets
    : local.intra_subnets
  )

  eks_managed_node_groups = {
    karpenter = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.small"]

      min_size     = 0
      max_size     = 3
      desired_size = 1

      taints = {
        # This Taint aims to keep just EKS Addons and Karpenter running on this MNG
        # The pods that do not tolerate this taint should run on nodes created by Karpenter
        addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
      }
    }
  }

  # cluster_tags = merge(local.tags, {
  #   NOTE - only use this option if you are using "attach_cluster_primary_security_group"
  #   and you know what you're doing. In this case, you can remove the "node_security_group_tags" below.
  #  "karpenter.sh/discovery" = local.name
  # })

  node_security_group_tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  })

  tags = local.tags
}

################################################################################
# Karpenter
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

################################################################################
# Karpenter Helm chart & manifests
################################################################################

resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  # version             = "1.0.8" # Use latest
  wait = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]

  depends_on = [module.eks]
}

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiSelectorTerms:
      - alias: al2023@latest
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
  YAML

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: "kubernetes.io/arch"
              operator: In
              values: ["arm64", "amd64"]
            - key: "karpenter.k8s.aws/instance-family"
              operator: In
              values: ["t4g", "t3"]
            - key: "karpenter.k8s.aws/instance-cpu"
              operator: In
              values: ["1", "2"]
            - key: "karpenter.k8s.aws/instance-hypervisor"
              operator: In
              values: ["nitro"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
      limits:
        cpu: 1000
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 30s
        expireAfter: 720h # 1 month
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}

# Update the kubeconfig after deploying EKS to enable local machine access to the cluster for
# subsequent manual deployments.
resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = <<EOT
      aws eks update-kubeconfig --region ${local.region} --name ${local.name}
    EOT
  }
  triggers = { cluster_id = module.eks.cluster_id }

  depends_on = [kubectl_manifest.karpenter_node_pool]
}
