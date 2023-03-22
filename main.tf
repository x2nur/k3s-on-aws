terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.48.0"
    }
  }
  required_version = ">= 1.0.1"
}


provider "aws" {
  region = "eu-north-1" # Stockholm
  default_tags {
    tags = {
      Project = "k3s"
    }
  }
}


data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


variable "settings" {
  description = "Settings of cluster"
  type = object({
    token       = string
    master_name = string
    worker_name = string
  })
}


output "master_ip" {
  description = "Master public IP"
  value       = aws_instance.master.public_ip
}


output "worker_ip" {
  description = "Worker public IP"
  value       = aws_spot_instance_request.worker.public_ip
}


resource "aws_key_pair" "k8s_key" {
  public_key = file("key.pub")
}


resource "aws_security_group" "master" {
  name        = "master"
  description = "Allow SSH, API server inbound traffic"
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group_rule" "worker_to_master_flannel" {
  type                     = "ingress"
  from_port                = 8472
  to_port                  = 8472
  protocol                 = "udp"
  security_group_id        = aws_security_group.master.id
  source_security_group_id = aws_security_group.worker.id
}


resource "aws_security_group" "worker" {
  name        = "worker"
  description = "Allow SSH inbound traffic"
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group_rule" "master_to_worker_kublet" {
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 10250
  to_port                  = 10250
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.master.id
}


resource "aws_security_group_rule" "master_to_worker_flannel" {
  type                     = "ingress"
  from_port                = 8472
  to_port                  = 8472
  protocol                 = "udp"
  security_group_id        = aws_security_group.worker.id
  source_security_group_id = aws_security_group.master.id
}


resource "aws_security_group_rule" "worker_to_worker_flannel" {
  type              = "ingress"
  from_port         = 8472
  to_port           = 8472
  protocol          = "udp"
  self              = true
  security_group_id = aws_security_group.worker.id
}


resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.k8s_key.id
  vpc_security_group_ids = [aws_security_group.master.id]
  credit_specification {
    cpu_credits = "standard"
  }
  tags = {
    Name = var.settings.master_name
  }
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = self.public_ip
    private_key = file("key")
  }
  provisioner "file" {
    source      = "master.sh"
    destination = "/tmp/master.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/master.sh",
      "sudo /tmp/master.sh ${var.settings.token} ${var.settings.master_name}"
    ]
  }
}


resource "aws_spot_instance_request" "worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.k8s_key.id
  availability_zone      = aws_instance.master.availability_zone
  vpc_security_group_ids = [aws_security_group.worker.id]
  wait_for_fulfillment   = true
  credit_specification {
    cpu_credits = "standard"
  }
  tags = {
    Name = var.settings.worker_name
  }
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = self.public_ip
    private_key = file("key")
  }
  provisioner "file" {
    source      = "worker.sh"
    destination = "/tmp/worker.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/worker.sh",
      "sudo /tmp/worker.sh ${aws_instance.master.private_ip} ${var.settings.token} ${var.settings.worker_name}"
    ]
  }
}

