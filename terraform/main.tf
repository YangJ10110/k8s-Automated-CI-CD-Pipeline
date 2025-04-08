provider "aws" {
  region = "us-west-1" # Change as needed
}

resource "aws_ecr_repository" "ojt_project" {
  name = "ojt_project"  # Changed from "OJT-PROJECT" to lowercase
}


resource "null_resource" "push_ecr_image" {
  provisioner "local-exec" {
    command = <<EOT
      aws ecr get-login-password --region us-west-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.ojt_project.repository_url}
      docker build -t OJT-PROJECT -f ./Dockerfile ./
      docker tag OJT-PROJECT:latest ${aws_ecr_repository.ojt_project.repository_url}:latest
      sleep 10 # Ensuring ECR repository readiness
      docker push ${aws_ecr_repository.ojt_project.repository_url}:latest
    EOT
  }
  depends_on = [aws_ecr_repository.ojt_project]
}


resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_pass_role_policy" {
  name        = "lambda-pass-role-policy"
  description = "Allow Lambda to pass ECS task execution role"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.ecs_task_role.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_pass_role_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_pass_role_policy.arn
}



resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_ecs_ecr_policy" {
  name        = "lambda-ecs-ecr-policy"
  description = "Allow Lambda to access ECS and ECR"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:StopTask"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ecs_ecr_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_ecs_ecr_policy.arn
}

resource "aws_ecs_cluster" "ojt_cluster" {
  name = "ojt-cluster"
}

resource "aws_ecs_task_definition" "ojt_task" {
  family                   = "ojt-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([
    {
      name      = "ojt-container"
      image     = "${aws_ecr_repository.ojt_project.repository_url}:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
        }
      ]
    }
  ])
}

resource "aws_security_group" "ecs_sg" {
  name_prefix = "ecs-sg-"
  description = "Allow inbound traffic for ECS"
  vpc_id      = data.aws_vpc.default.id
  
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_ecs_service" "ojt_staging" {
  name            = "ojt-staging"
  cluster         = aws_ecs_cluster.ojt_cluster.id
  task_definition = aws_ecs_task_definition.ojt_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  force_new_deployment = true
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

resource "aws_ecs_service" "ojt_production" {
  name            = "ojt-production"
  cluster         = aws_ecs_cluster.ojt_cluster.id
  task_definition = aws_ecs_task_definition.ojt_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  force_new_deployment = true
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

resource "aws_lambda_function" "ojt_lambda" {
  function_name    = "ojt_lambda"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.8"
  filename        = "../lambda/lambda.zip"
  source_code_hash = filebase64sha256("../lambda/lambda.zip")
  environment {
    variables = {
      CLUSTER     = aws_ecs_cluster.ojt_cluster.name
      OJT_STAGING = aws_ecs_service.ojt_staging.name
      MAINSERVICE = aws_ecs_service.ojt_production.name
    }
  }
}

output "lambda_url" {
  value = aws_lambda_function.ojt_lambda.invoke_arn
}
