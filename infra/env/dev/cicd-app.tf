############################################
# Artifacts bucket for CodePipeline
############################################

resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket        = "${local.name}-codepipeline-artifacts"
  force_destroy = true

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

############################################
# IAM: CodeBuild role
############################################

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codebuild_app" {
  name               = "${local.name}-codebuild-app"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "codebuild_app" {
  # CloudWatch Logs
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }

  # ECR for building/pushing images
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:PutImage",
      "ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:InitiateLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
    ]
    resources = ["*"]
  }

  # S3 for frontend + artifacts
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      module.frontend_s3.bucket_arn,
      aws_s3_bucket.codepipeline_artifacts.arn,
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${module.frontend_s3.bucket_arn}/*",
      "${aws_s3_bucket.codepipeline_artifacts.arn}/*",
    ]
  }

  # ECS to trigger deployments
  statement {
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:DescribeClusters",
    ]
    resources = ["*"]
  }

  # STS identity (used in buildspec)
  statement {
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codebuild_app" {
  role   = aws_iam_role.codebuild_app.id
  policy = data.aws_iam_policy_document.codebuild_app.json
}

############################################
# CodeBuild project: build+deploy backend & frontend
############################################

resource "aws_codebuild_project" "app_build_deploy" {
  name         = "${local.name}-app-build-deploy"
  description  = "Build backend image, deploy to ECS, sync frontend to S3"
  service_role = aws_iam_role.codebuild_app.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true 

    environment_variable {
      name  = "AWS_REGION"
      value = var.region
    }

    environment_variable {
      name  = "BACKEND_ECR_REPO"
      value = aws_ecr_repository.backend.repository_url
    }

    # We know the names based on how you created them
    environment_variable {
      name  = "ECS_CLUSTER_NAME"
      value = "${local.name}-cluster"
    }

    environment_variable {
      name  = "ECS_SERVICE_NAME"
      value = "${local.name}-service"
    }

    environment_variable {
      name  = "FRONTEND_BUCKET"
      value = module.frontend_s3.bucket_name
}
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOF
      version: 0.2

      phases:
        pre_build:
          commands:
            - echo "Logging in to Amazon ECR..."
            - ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

        build:
          commands:
            - echo "Building backend Docker image..."
            - cd backend
            - docker build -t backend-app:latest .
            - docker tag backend-app:latest "$BACKEND_ECR_REPO:latest"
            - docker push "$BACKEND_ECR_REPO:latest"

        post_build:
          commands:
            - echo "Triggering ECS deployment..."
            - aws ecs update-service --cluster "$ECS_CLUSTER_NAME" --service "$ECS_SERVICE_NAME" --force-new-deployment --region $AWS_REGION

            - echo "Syncing frontend to S3..."
            - cd "$CODEBUILD_SRC_DIR/frontend"
            - aws s3 sync . "s3://$FRONTEND_BUCKET" --delete

      artifacts:
        files:
          - '**/*'
        discard-paths: no
    EOF
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/codebuild/${local.name}-app"
      stream_name = "build"
      status      = "ENABLED"
    }
  }

  tags = local.tags
}

############################################
# IAM: CodePipeline role
############################################

data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${local.name}-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
}

data "aws_iam_policy_document" "codepipeline" {
  # S3 artifacts bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.codepipeline_artifacts.arn,
      "${aws_s3_bucket.codepipeline_artifacts.arn}/*",
    ]
  }

  # CodeBuild
  statement {
    effect = "Allow"
    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds",
    ]
    resources = [
      aws_codebuild_project.app_build_deploy.arn,
    ]
  }

  # CodeStar connection (GitHub)
  statement {
    effect = "Allow"
    actions = [
      "codestar-connections:UseConnection",
    ]
    resources = [
      aws_codestarconnections_connection.github.arn,
    ]
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline.json
}

############################################
# CodeStar connection to GitHub
############################################

resource "aws_codestarconnections_connection" "github" {
  name          = "${local.name}-github"
  provider_type = "GitHub"

  tags = local.tags
}

############################################
# CodePipeline: Source (GitHub) -> Build/Deploy (CodeBuild)
############################################

resource "aws_codepipeline" "app" {
  name     = "${local.name}-app"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.codepipeline_artifacts.bucket
  }

  # Stage 1: Source from GitHub
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = "Ahtisham77/aws-java-ecs-s3-demo"
        BranchName           = "main"
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges        = "true"
      }
    }
  }

  # Stage 2: Build & Deploy via CodeBuild
  stage {
    name = "BuildAndDeploy"

    action {
      name             = "BuildAndDeploy"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.app_build_deploy.name
      }
    }
  }

  tags = local.tags
}
