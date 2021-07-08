#######################################################################################
# VARIABLES
#######################################################################################
variable "region" {
    type = string
    default = "us-east-1"
}


variable "vpc_cidr_range" {
    type = string
    default = "10.0.0.0/16"
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
resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    instance_tenancy = "default"
    
  tags = {
    Name = "ubuntu-vpc"
  }
}

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.main.cidr_block]
    ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ubuntu-sg"
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

resource "aws_iam_instance_profile" "ubuntu_profile" {
  name = "ubuntu_profile"
  role = aws_iam_role.ubuntu_role.name
}

resource "aws_iam_role_policy" "ubuntu_policy" {
  name = "ubuntu_policy"
  role = aws_iam_role.ubuntu_role.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_instance" "ubuntu" {
    ami = data.aws_ami.ubuntu.id
    instance_type = "t2.micro"

    root_block_device {
    volume_size = 8
  }

  user_data = <<-EOF
    #!/bin/bash
    set -ex
    sudo yum update -y
    sudo amazon-linux-extras install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user
    sudo curl -L https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  EOF

    vpc_security_group_ids = [
   aws_security_group.allow_tls.id
  ]

    iam_instance_profile = aws_iam_instance_profile.ubuntu_profile.name

    tags = {
        Name = "ubuntu"
    }

    monitoring              = true
    disable_api_termination = false
    ebs_optimized           = true
}

#######################################################################################
# OUTPUTS
#######################################################################################

