# EC2 Proxy Server for HTTPS Tunneling
resource "aws_instance" "proxy" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.nano"  # 最小構成・低コスト
  
  vpc_security_group_ids = [aws_security_group.proxy.id]
  subnet_id              = aws_subnet.public[0].id
  
  # IAMロール付与
  iam_instance_profile = aws_iam_instance_profile.proxy.name
  
  # 自動起動スクリプト
  user_data = base64encode(templatefile("${path.module}/proxy-userdata.sh", {
    alb_dns_name = aws_lb.main.dns_name
    app_name     = var.app_name
  }))

  tags = merge(var.tags, {
    Name = "${var.app_name}-proxy"
    Role = "HTTPS-Proxy"
  })
}

# Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Proxy用セキュリティグループ
resource "aws_security_group" "proxy" {
  name_description = "${var.app_name}-proxy-sg"
  vpc_id           = aws_vpc.main.id

  # SSH接続 (管理用)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ips
  }
  
  # プロキシポート (localtunnel用)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # localtunnel経由のみ
  }

  # アウトバウンド全許可
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.app_name}-proxy-sg"
  })
}

# IAM Role for EC2 Proxy
resource "aws_iam_role" "proxy" {
  name = "${var.app_name}-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.app_name}-proxy-role"
  })
}

# CloudWatch Logs 権限
resource "aws_iam_role_policy" "proxy_logs" {
  name = "${var.app_name}-proxy-logs"
  role = aws_iam_role.proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/ec2/${var.app_name}-proxy:*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "proxy" {
  name = "${var.app_name}-proxy-profile"
  role = aws_iam_role.proxy.name
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/aws/ec2/${var.app_name}-proxy"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.app_name}-proxy-logs"
  })
}