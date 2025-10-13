# Configure the AWS Provider
provider "aws" {
    region = "us-east-1"
}

resource "aws_security_group" "kind_ec2_sg" {
    name        = "kind-ec2-sg"
    description = "Allow SSH and Kubernetes access"

    ingress {
        description      = "SSH"
        from_port        = 22
        to_port          = 22
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
    }
    
    ingress {
        description = "Allow NodePort 30080 from anywhere"
        from_port   = 30080
        to_port     = 30080
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port        = 0
        to_port          = 0
        protocol         = "-1"
        cidr_blocks      = ["0.0.0.0/0"]
    }

    tags = {
        Name = "kind-ec2-sg"
    }
}

resource "aws_instance" "kind_ec2" {
    ami           = "ami-0360c520857e3138f"
    instance_type = "t3.medium"
    key_name      = "demo_key_us_e_!" 
    associate_public_ip_address = true
    vpc_security_group_ids = [aws_security_group.kind_ec2_sg.id]


    user_data = <<-EOF
        #!/bin/bash
        # Update and install Docker
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

        # Write your config file
        cat <<EOT > /home/ubuntu/config.yml
        ${file("${path.module}/config.yml")}
        EOT
        sudo chown ubuntu:ubuntu /home/ubuntu/config.yml

        # Create kind cluster as ubuntu user
        sudo -u ubuntu kind create cluster  --config /home/ubuntu/config.yml

        # Write your deployment file
        cat <<EOT > /home/ubuntu/deployment.yml
        ${file("${path.module}/deployment.yml")}
        EOT
        sudo chown ubuntu:ubuntu /home/ubuntu/deployment.yml

        for i in {1..30}; do
            if sudo -u ubuntu kubectl get nodes &>/dev/null; then
                echo "Cluster ready!"
                break
            fi
            echo "Waiting for cluster..."
            sleep 10
        done

        sudo -u ubuntu kubectl apply -f /home/ubuntu/deployment.yml


    EOF

    tags = {
        Name = "kind-ec2-instance"
        Name = "club-malabari"
    }
}

# resource "aws_eip" "kind_ec2_eip" {
#     instance = aws_instance.kind_ec2.id
# }

# output "elastic_ip" {
#     description = "Elastic IP address of the EC2 instance"
#     value       = aws_eip.kind_ec2_eip.public_ip
# }

output "instance_public_ip" {
    description = "The public ip address of the EC2 instance"
    value = aws_instance.kind_ec2.public_ip
}