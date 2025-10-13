locals {
  config_file     = filebase64("${path.module}/config.yml")
  deployment_file = filebase64("${path.module}/deployment.yml")
}

# Configure AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Fetch existing SG by name (safe to fail silently)
data "aws_security_groups" "existing_kind_sg" {
  filter {
    name   = "group-name"
    values = ["kind-ec2-sg"]
  }
}

# Create SG only if it doesn't exist
resource "aws_security_group" "kind_ec2_sg" {
  count       = length(data.aws_security_groups.existing_kind_sg.ids) == 0 ? 1 : 0
  name        = "kind-ec2-sg"
  description = "Allow SSH and Kubernetes access"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow NodePort 30080 from anywhere"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kind-ec2-sg"
  }
}

# EC2 instance
resource "aws_instance" "kind_ec2" {
  ami                    = "ami-0360c520857e3138f"
  instance_type          = "t3.medium"
  key_name               = "demo_key_us_e_!"
  associate_public_ip_address = true

  # Use existing SG if found, else use newly created one
  vpc_security_group_ids = [
    length(data.aws_security_groups.existing_kind_sg.ids) == 0 ?
    aws_security_group.kind_ec2_sg[0].id :
    data.aws_security_groups.existing_kind_sg.ids[0]
  ]

  user_data = <<-EOF
    #!/bin/bash
    set -e
    sudo su
    apt-get update -y
    apt-get install -y docker.io

    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu

    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl

    # Install kind
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
    chmod +x ./kind
    mv ./kind /usr/local/bin/kind

    # Decode and write config.yml
    echo "${local.config_file}" | base64 -d > /home/ubuntu/config.yml
    chown ubuntu:ubuntu /home/ubuntu/config.yml

    # Create kind cluster as ubuntu
    sudo -u ubuntu kind create cluster --config /home/ubuntu/config.yml --wait 300s

    # Verify cluster readiness (wait up to 5 minutes)
    for i in {1..30}; do
        if sudo -u ubuntu kubectl get nodes &>/dev/null; then
            echo "✅ Cluster ready!"
            break
        fi
        echo "⏳ Waiting for cluster to be ready..."
        sleep 10
    done

    # Decode and write deployment.yml
    echo "${local.deployment_file}" | base64 -d > /home/ubuntu/deployment.yml
    chown ubuntu:ubuntu /home/ubuntu/deployment.yml

    # Apply deployment with retries (handles API startup delay)
    for i in {1..10}; do
        if sudo -u ubuntu kubectl apply -f /home/ubuntu/deployment.yml; then
            echo "✅ Deployment applied successfully!"
            break
        else
            echo "⚠️ Retry $i: Waiting for API to stabilize..."
            sleep 15
        fi
    done
    
  EOF

  tags = {
    Name = "kind-ec2-instance"
    App  = "club-malabari"
  }
}

# Output the instance's public IP
output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.kind_ec2.public_ip
}
