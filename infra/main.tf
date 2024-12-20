### Main
terraform {
  cloud { 
    organization = "Promiedos" 

    workspaces { 
      name = "promiedos" 
    } 
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.76"
    }

    postgresql = {
      source = "cyrilgdn/postgresql"
      version = "1.24.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

### Resources
resource "random_password" "promiedos_db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "new_promiedios_db_password" {
  length  = 20
  special = false
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
  
  environment {
    variables = {
      TELEGRAM_TOKEN    = local.telegram_token
      TELEGRAM_CHAT_ID  = local.telegram_chat_id
      # PROMIEDOS_DB_USER = local.promiedos_db_user
      # PROMIEDOS_DB_PASS = local.promiedos_db_user_pass
      # PROMIEDOS_DB_HOST = local.promiedos_db_host
    } 
  }
}

### Trigger Lambda every 4 hours
resource "aws_cloudwatch_event_rule" "every_4_hours" {
  name        = "promiedos_lambda_every_4_hours"
  description = "Trigger promiedos Lambda every 4 hours"

  schedule_expression = "rate(4 hours)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.every_4_hours.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.promiedos_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.promiedos_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_4_hours.arn
}


### Pipeline
### Codepipeline
resource "aws_codepipeline" "codepipeline" {
  name          = "promiedos"
  role_arn      = aws_iam_role.codepipeline_role.arn
  pipeline_type = "V2"

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
        DetectChanges    = true
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

  trigger {
    provider_type = "CodeStarSourceConnection"
    
    git_configuration {
      source_action_name = "Source"

      push {
        branches {
          includes = ["main"]
        }
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


### Codebuild
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
      "lambda:UpdateFunctionCode",
      "secretsmanager:GetSecretValue"
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
        account = var.aws_account_id
      }
    )
  }
}

### Secrets
resource "aws_secretsmanager_secret" "secret" {
  name = "promiedos"
}

data "aws_secretsmanager_secret_version" "secret_version" {
  secret_id = aws_secretsmanager_secret.secret.id
}

### RDS
# resource "aws_db_instance" "promiedos_db" {
#   allocated_storage           = 20
#   max_allocated_storage       = 20
#   db_name                     = "promiedos_db"
#   engine                      = "postgres"
#   engine_version              = "16.3"
#   instance_class              = "db.t4g.micro"
#   username                    = local.promiedos_db_user
#   password                    = random_password.promiedos_db_password.result
#   # manage_master_user_password = false
#   skip_final_snapshot         = true
#   publicly_accessible         = true
# }

# provider "postgresql" {
#   scheme          = "awspostgres"
#   host            = "terraform-20241118215129952800000001.cfcoae6kkkd4.us-east-1.rds.amazonaws.com"
#   port            = 5432
#   database        = "promiedos_db"
#   username        = local.promiedos_db_user
#   password        = local.promiedos_db_pass
#   connect_timeout = 15
#   superuser       = false
# }

# resource "postgresql_role" "promiedos_user_role" {
#   name     = "promiedos_user"
#   login    = true
#   password = local.promiedos_db_user_pass
# }

# resource "postgresql_default_privileges" "promiedos_user_role_privileges" {
#   role        = postgresql_role.promiedos_user_role.name
#   database    = aws_db_instance.promiedos_db.db_name
#   schema      = "public"
#   owner       = local.promiedos_db_user
#   object_type = "table"
#   privileges  = ["SELECT", "UPDATE", "INSERT"]
# }

# resource "postgresql_grant" "promiedos_user_create_tables_privilege" {
#   database    = aws_db_instance.promiedos_db.db_name
#   role        = postgresql_role.promiedos_user_role.name
#   schema      = "public"
#   object_type = "schema"
#   privileges  = ["CREATE"]
# }

locals {
  telegram_token         = jsondecode(data.aws_secretsmanager_secret_version.secret_version.secret_string).TELEGRAM_TOKEN
  telegram_chat_id       = jsondecode(data.aws_secretsmanager_secret_version.secret_version.secret_string).TELEGRAM_CHAT_ID
  # promiedos_db_user      = jsondecode(data.aws_secretsmanager_secret_version.secret_version.secret_string).PROMIEDOS_DB_USER
  # promiedos_db_pass      = random_password.promiedos_db_password.result
  # promiedos_db_user_pass = random_password.new_promiedios_db_password.result
  # promiedos_db_host      = aws_db_instance.promiedos_db.endpoint
}

