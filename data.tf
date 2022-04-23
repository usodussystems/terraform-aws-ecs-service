
data "aws_ecs_cluster" "cluster" {
  cluster_name = local.cluster_name
}

data "aws_lb" "load_balancer" {
  name = var.lb_name
}

data "aws_autoscaling_group" "asg" {
  name = var.asg_name
}

## POLICIES
data "aws_iam_policy_document" "reg_power_user" {
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        var.ecr_super_user_arn
      ]
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_task_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"

      values = [
        "arn:aws:ecs:*:${data.aws_caller_identity.current.account_id}:*"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"

      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }
}

data "aws_iam_policy_document" "task_role" {
  statement {
    actions = var.task_security.actions
    effect  = "Allow"
    resources = var.task_security.resources

    # condition {
    #   test     = "ArnLike"
    #   variable = "aws:SourceArn"

    #   values = [
    #     "aws:ecs:*:${data.aws_caller_identity.current.account_id}:*"
    #   ]
    # }

    # condition {
    #   test     = "StringEquals"
    #   variable = "aws:SourceAccount"

    #   values = [
    #     "aws:ecs.${data.aws_caller_identity.current.account_id}"
    #   ]
    # }
  }
}

data "aws_iam_policy_document" "assume_execution_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "execution_role" {
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    effect    = "Allow"
    resources = [aws_ecr_repository.repository.arn]
  }
}

data "aws_ecr_authorization_token" "token" {}