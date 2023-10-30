resource "terraform_data" "cluster" {
  provisioner "local-exec" {
    command = <<EOF
echo "ASDASD"
EOF
  }
}

module "crossplane" {
  depends_on = [
    terraform_data.cluster
  ]

  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "1.1.0"

  create = true

  # https://github.com/crossplane/crossplane/tree/master/cluster/charts/crossplane
  name             = "crossplane"
  description      = "A Helm chart to deploy crossplane project"
  namespace        = "crossplane-system"
  create_namespace = true
  chart            = "crossplane"
  chart_version    = "1.13.2"
  repository       = "https://charts.crossplane.io/stable/"
}
locals {
  crossplane_namespace = "crossplane-system"
  upbound_aws_provider = {
    enable               = true
    version              = "v0.40.0"
    controller_config    = "upbound-aws-controller-config"
    provider_config_name = "aws-provider-config" 
    families = [
      "dynamodb"
    ]
  ddb_name = "upbound-ddb"
  }
}

module "upbound_irsa_aws" {
  # count = local.upbound_aws_provider.enable == true ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name_prefix = "ddb-upbound-aws-"
  assume_role_condition_test = "StringLike"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  }

  oidc_providers = {
    main = {
      provider_arn               = local.addon_context.eks_oidc_provider_arn
      namespace_service_accounts = ["${local.crossplane_namespace}:upbound-aws-provider-*"]
    }
  }
  tags = local.tags
}

resource "kubectl_manifest" "upbound_aws_controller_config" {
  count = local.upbound_aws_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/aws-upbound/controller-config.yaml", {
    iam-role-arn          = module.upbound_irsa_aws.iam_role_arn
    controller-config = local.upbound_aws_provider.controller_config
  })

  depends_on = [module.upbound_irsa_aws]
}

resource "kubectl_manifest" "upbound_aws_provider" {
  for_each = local.upbound_aws_provider.enable ? toset(local.upbound_aws_provider.families) : toset([])
  yaml_body = templatefile("${path.module}/providers/aws-upbound/provider.yaml", {
    family            = each.key
    version           = local.upbound_aws_provider.version
    controller-config = local.upbound_aws_provider.controller_config
  })
  wait = true

  depends_on = [kubectl_manifest.upbound_aws_controller_config]
}

# Wait for the Upbound AWS Provider CRDs to be fully created before initiating upbound_aws_provider_config
resource "time_sleep" "upbound_wait_60_seconds" {
  count           = local.upbound_aws_provider.enable == true ? 1 : 0
  create_duration = "60s"

  depends_on = [kubectl_manifest.upbound_aws_provider]
}

resource "kubectl_manifest" "upbound_aws_provider_config" {
  count = local.upbound_aws_provider.enable == true ? 1 : 0
  yaml_body = templatefile("${path.module}/providers/aws-upbound/provider-config.yaml", {
    provider-config-name = local.upbound_aws_provider.provider_config_name
  })

  depends_on = [kubectl_manifest.upbound_aws_provider, time_sleep.upbound_wait_60_seconds]
}

resource "aws_iam_policy" "carts_dynamo" {
  name        = "${local.addon_context.eks_cluster_id}-carts-dynamo"
  path        = "/"
  description = "DynamoDB policy for AWS Sample Carts Application"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllAPIActionsOnCart",
      "Effect": "Allow",
      "Action": "dynamodb:*",
      "Resource": [
        "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/items",
        "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/items/index/*",        
      ]
    }
  ]
}
EOF
  tags   = local.tags
}

module "eks_blueprints_addons" {
  source = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    wait = true
  }

  cluster_name      = local.addon_context.eks_cluster_id
  cluster_endpoint  = local.addon_context.aws_eks_cluster_endpoint
  cluster_version   = local.eks_cluster_version
  oidc_provider_arn = local.addon_context.eks_oidc_provider_arn
}

data "aws_vpc" "selected" {
  tags = {
    created-by = "eks-workshop-v2"
    env        = local.addon_context.eks_cluster_id
  }
}

data "aws_subnets" "private" {
  tags = {
    created-by = "eks-workshop-v2"
    env        = local.addon_context.eks_cluster_id
  }

  filter {
    name   = "tag:Name"
    values = ["*Private*"]
  }
}

output "environment" {
  value = <<EOF
export DYNAMODB_POLICY_ARN=${aws_iam_policy.carts_dynamo.arn}
EOF
}