#######################################################################################
# VARIABLES
#######################################################################################
variable "region" {
    type = string
    default = "us-east-1"
}

#######################################################################################
# PROVIDER
#######################################################################################

provider "aws" {
    region = var.region
}

#######################################################################################
# DATA SOURCES
#######################################################################################

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}
#######################################################################################
# RESOURCES
#######################################################################################
#create vpc
resource "aws_vpc" "project" {
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "dev"
    }
}
resource "aws_instance" "my-first" {
    ami = data.aws_ami.ubuntu.id
    instance_type = "t2.micro"

    tags = {
        Name = "ubuntu"
    }
}

# We need a repo to store containers, the plan is our server only runs containers. So we build these containers in CI, push to the repo and have our EC2 only run containers.
resource "aws_ecr_repository" "docker_repo" {
  name                 = "container"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

   tags = {
    project = "docker_repo"
  }
}

# For our ec2 instance to pull containers from ECR we need an IAM profile for granting access to ECR, and later attach this profile to the EC2 instance.
resource "aws_iam_role" "ubuntu_role" {
  name = "ubuntu_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    tag-key = "ubuntu_role"
  }
}

# resource "aws_security_group" "allow_web" {
#     name = "allow_web_traffic"
#     description = "Allow Web inbound traffic"
#     vpc_id = aws_vpc.project.id

#     ingress {
#         description = "HTTPS"
#         from_port = 443
#         to_port = 443
#         protocol = "tcp"
#         cidr_blocks = ["0.0.0.0/0"]
#     }

#     ingress {
#         description = "HTTP"
#         from_port = 80
#         to_port = 80
#         protocol = "tcp"
#         cidr_blocks = ["0.0.0.0/0"]
#     }

#     ingress {
#             description = "SSH"
#             from_port = 22
#             to_port = 22
#             protocol = "tcp"
#             cidr_blocks = ["0.0.0.0/0"]
#     }


#     egress {
#         from_port = 0
#         to_port = 0
#         protocol = "-1"
#         #-1 means any protocol
#         cidr_blocks = ["0.0.0.0/0"]
#     }

#     tags = {
#         Name = "allow_web"
#     }
# }