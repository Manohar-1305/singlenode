provider "aws" {
  region = "ap-south-1" # Correct region code for Asia South (Mumbai)
}


resource "aws_vpc" "dev_vpc" {
  cidr_block = "10.20.0.0/16"

  tags = {
    Name                               = "dev_vpc"
    "kubernetes.io/cluster/kubernetes" = "owned"

  }
}
resource "aws_internet_gateway" "dev_public_igw" {
  vpc_id = aws_vpc.dev_vpc.id

  tags = {
    Name                               = "dev_public_igw"
    "kubernetes.io/cluster/kubernetes" = "owned"
  }
}

resource "aws_subnet" "dev_subnet_public_1" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.20.4.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "dev_subnet_public_1"
  }
}
resource "aws_route_table" "dev_public_rt" {
  vpc_id = aws_vpc.dev_vpc.id
  tags = {
    Name                               = "dev_public_rt"
    "kubernetes.io/cluster/kubernetes" = "owned"
  }
}

resource "aws_route" "dev_route_1" {
  route_table_id         = aws_route_table.dev_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.dev_public_igw.id
}

resource "aws_route_table_association" "dev_public_route_1" {
  subnet_id      = aws_subnet.dev_subnet_public_1.id
  route_table_id = aws_route_table.dev_public_rt.id
}



resource "aws_subnet" "dev_subnet_private_1" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.20.5.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false

  tags = {
    Name                               = "dev_subnet_private_1"
    "kubernetes.io/cluster/kubernetes" = "owned"
  }
}


resource "aws_route_table_association" "dev_private_route" {
  subnet_id      = aws_subnet.dev_subnet_private_1.id
  route_table_id = aws_route_table.private_route_table.id

}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.dev_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name                               = "private_route_table"
    "kubernetes.io/cluster/kubernetes" = "owned"
  }
}

resource "aws_eip" "nat_eip" {

}

resource "aws_nat_gateway" "nat_gateway" {
  subnet_id     = aws_subnet.dev_subnet_public_1.id
  allocation_id = aws_eip.nat_eip.id
  depends_on    = [aws_internet_gateway.dev_public_igw]
}


# Fetch the existing IAM instance profile
data "aws_iam_instance_profile" "s3-access-profile" {
  name = "s3-access-profile"
}

# Kubernetes instance
resource "aws_instance" "Bastion_host" {
  ami                  = "ami-03bb6d83c60fc5f7c"
  instance_type        = "t2.medium"
  key_name             = "testing-dev-1"
  subnet_id            = aws_subnet.dev_subnet_public_1.id
  iam_instance_profile = data.aws_iam_instance_profile.s3-access-profile.name
  vpc_security_group_ids = [
    aws_security_group.ssh_web_traffic_sg.id,
    aws_security_group.kubernetes.id,
    aws_security_group.nat_gateway_sg.id,
    aws_security_group.open_access_within_vpc.id,
    aws_security_group.nat_gateway_sg.id,
  ]
  user_data = file("kube-containerd-install.sh")

  tags = {
    Name                               = "Bastion_host"
    "kubernetes.io/cluster/kubernetes" = "owned"
  }
}

# Delay resource: Introduce a 3-minute (180-second) pause after k8s_instance creation
resource "null_resource" "delay_between_instances" {
  provisioner "local-exec" {
    command = "sleep 120"
  }

  depends_on = [aws_instance.Bastion_host]
}
resource "aws_instance" "master" {
  ami                  = "ami-03bb6d83c60fc5f7c"
  instance_type        = "t2.medium"
  key_name             = "testing-dev-1"
  subnet_id            = aws_subnet.dev_subnet_private_1.id
  iam_instance_profile = data.aws_iam_instance_profile.s3-access-profile.name
  vpc_security_group_ids = [
    aws_security_group.ssh_web_traffic_sg.id,
    aws_security_group.kubernetes.id,
    aws_security_group.nat_gateway_sg.id,
    aws_security_group.open_access_within_vpc.id,
    aws_security_group.haproxy-sg.id
  ]
  user_data = file("nfs-setup.sh")

  tags = {
    Name                               = "master"
    "kubernetes.io/cluster/kubernetes" = "owned"
  }
  depends_on = [null_resource.delay_between_instances]
}
# Node instance: Created after delay
resource "aws_instance" "node" {
  ami                  = "ami-03bb6d83c60fc5f7c"
  instance_type        = "t2.medium"
  key_name             = "testing-dev-1"
  subnet_id            = aws_subnet.dev_subnet_private_1.id
  iam_instance_profile = data.aws_iam_instance_profile.s3-access-profile.name
  vpc_security_group_ids = [
    aws_security_group.ssh_web_traffic_sg.id,
    aws_security_group.kubernetes.id,
    aws_security_group.nat_gateway_sg.id,
    aws_security_group.open_access_within_vpc.id,
    aws_security_group.haproxy-sg.id
  ]
  user_data = file("nfs-setup.sh")

  tags = {
    Name                               = "node"
    "kubernetes.io/cluster/kubernetes" = "owned"
  }

  depends_on = [null_resource.delay_between_instances] # Ensures that the node waits for k8s_instance creation
}

# NFS instance: Created after delay
resource "aws_instance" "nfs" {
  ami                  = "ami-03bb6d83c60fc5f7c"
  instance_type        = "t2.medium"
  key_name             = "testing-dev-1"
  subnet_id            = aws_subnet.dev_subnet_private_1.id
  iam_instance_profile = data.aws_iam_instance_profile.s3-access-profile.name
  vpc_security_group_ids = [
    aws_security_group.ssh_web_traffic_sg.id,
    aws_security_group.nat_gateway_sg.id,
    aws_security_group.open_access_within_vpc.id,
    aws_security_group.nfs.id
  ]
  user_data = file("nfs-setup.sh")

  tags = {
    Name                               = "nfs"
    "kubernetes.io/cluster/kubernetes" = "owned"
  }

  depends_on = [null_resource.delay_between_instances] # Ensures that the NFS waits for k8s_instance creation
}

# Outputs for the public IPs
output "bastion_host_public_ip" {
  description = "The public IP address of the Kubernetes instance"
  value       = aws_instance.Bastion_host.public_ip
}

output "node_public_ip" {
  description = "The private IP address of the Node instance"
  value       = aws_instance.node.private_ip
}

output "master_ip" {
  description = "The private IP address of the NFS instance"
  value       = aws_instance.master.private_ip
}
resource "aws_security_group" "ssh_web_traffic_sg" {
  name        = "Combined-Security-Group"
  description = "Allow SSH, HTTP, and HTTPS traffic"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow Everything Outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Allow_ssh-web_Traffic"
  }
}


resource "aws_security_group" "kubernetes" {
  name        = "Kubernetes"
  description = "Allow kubernetes API server, kubelet, etcd"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    description = "Allow port 6443"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow kubelet communiction"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow kubelet communiction"
    from_port   = 10251
    to_port     = 10251
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow kubelet communiction"
    from_port   = 10252
    to_port     = 10252
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow Everything Outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Allow_kubernetes_components"
  }
}
resource "aws_security_group" "nat_gateway_sg" {
  name        = "NAS-GATEWAY-SG"
  description = "Allow NAT GARTEWAY"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    description = "Allow inbound traffic from VPC CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.20.0.0/16"]
  }
  egress {
    description = "Allow Everything Outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Allow_nat_gateway_components"
  }
}

resource "aws_security_group" "open_access_within_vpc" {
  name        = "open_access_within_vpc"
  description = "security group to open access within vpc"
  vpc_id      = aws_vpc.dev_vpc.id
  ingress {
    description = "Allow inbound traffic within VPC CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.20.0.0/16"]
  }
  egress {
    description = "Allow  Outbound within vpc"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.20.0.0/16"]
  }
  tags = {
    Name = "open_access_vpc_security_Group"
  }
}

resource "aws_security_group" "haproxy-sg" {
  name        = "haproxy-sg"
  description = "security group for haproxy server"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    description = "allow port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow port 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow internal health check"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["10.20.0.0/16"]
  }

  tags = {
    Name = "haproxy_security_Group"
  }
}

resource "aws_security_group" "node_port_group" {
  name        = "my_security_group"
  description = "allow traffic on ports 30000-32767"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["10.20.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allows all outbound traffic
    cidr_blocks = ["10.20.0.0/16"]
  }
  tags = {
    Name = "node_port_Group"
  }
}
resource "aws_security_group" "nfs" {
  name        = "nfs-sg"
  description = "allow nfs traffic"
  vpc_id      = aws_vpc.dev_vpc.id
  ingress {
    description = "Allow NFS traffic"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 111
    to_port     = 111
    protocol    = "udp"
    cidr_blocks = ["10.20.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "nfs_security_Group"
  }
}
resource "aws_security_group" "etcd_sg" {
  name        = "etcd-sg"
  description = "SEcurity Group for etcd"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    description = "allow etcd client and peer communication"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["10.20.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "etcd_security_Group"
  }
}





