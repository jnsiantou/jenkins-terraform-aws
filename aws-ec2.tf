# configured aws provider with proper credentials
provider "aws" {
  region    = var.aws_region
  profile   = "default"
}

# create default vpc if one does not exit
resource "aws_default_vpc" "default_vpc" {

  tags    = {
    Name  = "utrains default vpc"
  }
}

# use data source to get all avalablility zones in region
data "aws_availability_zones" "available_zones" {}

# create default subnet if one does not exit
resource "aws_default_subnet" "default_az1" {
  availability_zone = data.aws_availability_zones.available_zones.names[0]

  tags   = {
    Name = "utrains default subnet"
  }
}

# create security group for the ec2 instance
resource "aws_security_group" "jenkins_ec2_security_group" {
  name        = "ec2 security group"
  description = "allow access on ports 8080 and 22"
  vpc_id      = aws_default_vpc.default_vpc.id

  # allow access on port 8080 for Jenkins Server
  ingress {
    description      = "http proxy access"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  # allow access on port 22 ssh connection
  ingress {
    description      = "ssh access"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = -1
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags   = {
    Name = "utrains jenkins server security group"
  }
}

# use data source to get a registered amazon linux 2 ami
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

# Generates a secure private key and encodes it as PEM
resource "tls_private_key" "jenkins_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
# Create the Key Pair
resource "aws_key_pair" "jenkins_key" {
  key_name   = "jenkins_key_pair"  
  public_key = tls_private_key.jenkins_key.public_key_openssh
}
# Save file
resource "local_file" "ssh_key" {
  filename = "${aws_key_pair.jenkins_key.key_name}.pem"
  content  = tls_private_key.jenkins_key.private_key_pem
}

# launch the ec2 instance and install jenkis
resource "aws_instance" "ec2_instance" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.aws_instance_type
  subnet_id              = aws_default_subnet.default_az1.id
  vpc_security_group_ids = [aws_security_group.jenkins_ec2_security_group.id]
  key_name               = aws_key_pair.jenkins_key.key_name
  # user_data            = file("install_jenkins.sh")

  tags = {
    Name = "utrains Jenkins Server and ssh security group"
  }
}

# an empty resource block
resource "null_resource" "name" {

  # ssh into the ec2 instance 
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(local_file.ssh_key.filename)
    host        = aws_instance.ec2_instance.public_ip
  }

  # copy the install_jenkins.sh file from your computer to the ec2 instance 
  provisioner "file" {
    source      = "install-jenkins.sh"
    destination = "/tmp/install-jenkins.sh"
  }

  # set permissions and run the install_jenkins.sh file
  provisioner "remote-exec" {
    inline = [
        "sudo chmod +x /tmp/install-jenkins.sh",
        "sh /tmp/install-jenkins.sh"
        ]
  }

  # wait for ec2 to be created
  depends_on = [aws_instance.ec2_instance]
}

# print the url of the jenkins server
output "jenkins_url" {
  value     = join ("", ["http://", aws_instance.ec2_instance.public_dns, ":", "8080"])
}

# print the url of the jenkins server
output "ssh_connection_command" {
  value     = join ("", ["ssh -i jenkins_key_pair.pem ec2-user@", aws_instance.ec2_instance.public_dns])
}