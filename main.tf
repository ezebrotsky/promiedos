### Main
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

### ECR
resource "aws_ecr_repository" "promiedos" {
  name                 = "promiedos"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

### Lambda
resource "aws_s3_bucket" "lambda" {
  bucket = "promiedos-lambda"
}

data "aws_iam_policy_document" "assume_lambda_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda_role.json
}

resource "aws_lambda_function" "promiedos_lambda" {
  function_name = "promiedos"
  role          = aws_iam_role.iam_for_lambda.arn
  package_type  = "Image" 
  image_uri     = "${aws_ecr_repository.promiedos.repository_url}:latest"
}

### Trigger Lambda every 2 hours
resource "aws_cloudwatch_event_rule" "every_2_hours" {
  name        = "promiedos_lambda_every_2_hours"
  description = "Trigger promiedos Lambda every 2 hours"

  schedule_expression = "rate(2 hours)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.every_2_hours.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.promiedos_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.promiedos_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_2_hours.arn
}


### Pipeline
resource "aws_codepipeline" "codepipeline" {
  name     = "promiedos"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.personal.arn
        FullRepositoryId = "ezebrotsky/promiedos"
        BranchName       = "main"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build_promiedos_lambda.name
      }
    }
  }
}

resource "aws_codestarconnections_connection" "personal" {
  name          = "personal"
  provider_type = "GitHub"
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "promiedos-codepipeline"
}

resource "aws_s3_bucket_public_access_block" "codepipeline_bucket_pab" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
}

data "aws_iam_policy_document" "assume_pipeline_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.assume_pipeline_role.json
}

data "aws_iam_policy_document" "codepipeline_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObjectAcl",
      "s3:PutObject",
    ]

    resources = [
      aws_s3_bucket.codepipeline_bucket.arn,
      "${aws_s3_bucket.codepipeline_bucket.arn}/*"
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["codestar-connections:UseConnection"]
    resources = [aws_codestarconnections_connection.personal.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name   = "codepipeline_policy"
  role   = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.codepipeline_policy.json
}



data "aws_iam_policy_document" "assume_codebuild_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codebuild_promiedos_role" {
  name               = "codebuild_promiedos_role"
  assume_role_policy = data.aws_iam_policy_document.assume_codebuild_role.json
}

data "aws_iam_policy_document" "codebuild_promiedos_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ecr:GetAuthorizationToken",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecs:RunTask",
      "iam:PassRole",
      "s3:GetObject",
      "lambda:UpdateFunctionCode"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codebuild_promiedos_role_policy" {
  name   = "codebuild_promiedos_role_policy"
  role   = aws_iam_role.codebuild_promiedos_role.id
  policy = data.aws_iam_policy_document.codebuild_promiedos_policy_document.json
}


resource "aws_codebuild_project" "build_promiedos_lambda" {
  name          = "codebuild_promiedos_lambda"
  build_timeout = "15"
  service_role  = "${aws_iam_role.codebuild_promiedos_role.arn}"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    // https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-available.html
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = templatefile(
      "./buildspecs/promiedos_lambda.yml",
      {
        account          = var.aws_account_id
        telegram_token   = var.telegram_token
        telegram_chat_id = var.telegram_chat_id
      }
    )
  }
}
