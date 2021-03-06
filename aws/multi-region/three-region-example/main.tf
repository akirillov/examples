provider "aws" {
  # Change your default region here
  region = "us-east-1"
  alias  = "local"
}

provider "aws" {
  # Change your default region here
  region = "us-west-2"
  alias  = "usw2"
}

provider "aws" {
  # Change your default region here
  region = "ca-central-1"
  alias  = "cac1"
}

// lets define variables which are shared between all regions
locals {
  ssh_public_key_file = "~/.ssh/id_rsa.pub"
  cluster_name        = "3-region-dcos-demo"
  admin_ips           = ["${data.http.whatismyip.body}/32"]

  region_networks = {
    // dont use 172.17/26 as its used by docker.
    "local" = "172.16.0.0/16" // this is the default
    "usw2"   = "10.128.0.0/16"
    "cac1"   = "10.129.0.0/16"
  }

  num_masters              = "1"
  num_local_private_agents = "2"
  num_local_public_agents  = "1"
  num_cac1_private_agents  = "2"
  num_cac1_public_agents   = "0"
  num_usw2_private_agents  = "2"
  num_usw2_public_agents   = "0"
}

module "dcos" {
  source  = "dcos-terraform/dcos/aws"
  version = "~> 0.2.0"

  cluster_name        = "${local.cluster_name}"
  ssh_public_key_file = "${local.ssh_public_key_file}"
  admin_ips           = ["${local.admin_ips}"]
  subnet_range        = "${local.region_networks["local"]}"

  num_masters        = "${local.num_masters}"
  num_private_agents = "${local.num_local_private_agents}"
  num_public_agents  = "${local.num_local_public_agents}"

  dcos_version = "1.12.3"

  dcos_instance_os = "centos_7.5"

  accepted_internal_networks   = "${values(local.region_networks)}"
  additional_private_agent_ips = ["${module.dcos-usw2.private_agents.private_ips}", "${module.dcos-cac1.private_agents.private_ips}"]

  providers = {
    aws = "aws.local"
  }

  dcos_variant              = "ee"
  dcos_license_key_contents = "${file("./license.txt")}"
}

# Used to determine your public IP for forwarding rules
data "http" "whatismyip" {
  url = "http://whatismyip.akamai.com/"
}

output "masters-ips" {
  value = "${module.dcos.masters-ips}"
}

output "cluster-address" {
  value = "${module.dcos.masters-loadbalancer}"
}

output "public-agents-loadbalancer" {
  value = "${module.dcos.public-agents-loadbalancer}"
}

module "dcos-usw2" {
  source  = "dcos-terraform/infrastructure/aws"
  version = "~> 0.2.0"

  admin_ips   = ["${local.admin_ips}"]
  name_prefix = "usw2"

  cluster_name               = "${local.cluster_name}"
  accepted_internal_networks = "${values(local.region_networks)}"

  num_masters        = 0
  num_private_agents = "${local.num_usw2_private_agents}"
  num_public_agents  = "${local.num_usw2_public_agents}"

  lb_disable_public_agents = true
  lb_disable_masters       = true

  ssh_public_key_file = "${local.ssh_public_key_file}"
  subnet_range        = "${local.region_networks["usw2"]}"

  providers = {
    aws = "aws.usw2"
  }
}

module "vpc-connection-local-usw2" {
  source  = "dcos-terraform/vpc-peering/aws" // module init the peering
  version = "~> 1.0.0"

  providers = {
    "aws.local"  = "aws.local"
    "aws.remote" = "aws.usw2"
  }

  local_vpc_id        = "${module.dcos.infrastructure.vpc.id}"
  local_subnet_range  = "${local.region_networks["local"]}"
  remote_vpc_id       = "${module.dcos-usw2.vpc.id}"
  remote_subnet_range = "${local.region_networks["usw2"]}"
}

module "dcos-cac1" {
  source  = "dcos-terraform/infrastructure/aws"
  version = "~> 0.2.0"

  admin_ips   = ["${local.admin_ips}"]
  name_prefix = "cac1"

  cluster_name               = "${local.cluster_name}"
  accepted_internal_networks = "${values(local.region_networks)}"

  num_masters        = 0
  num_private_agents = "${local.num_cac1_private_agents}"
  num_public_agents  = "${local.num_cac1_public_agents}"

  lb_disable_public_agents = true
  lb_disable_masters       = true

  ssh_public_key_file = "${local.ssh_public_key_file}"
  subnet_range        = "${local.region_networks["cac1"]}"

  providers = {
    aws = "aws.cac1"
  }
}

module "vpc-connection-local-cac1" {
  source  = "dcos-terraform/vpc-peering/aws" // module init the peering
  version = "~> 1.0.0"

  providers = {
    "aws.local"  = "aws.local"
    "aws.remote" = "aws.cac1"
  }

  local_vpc_id        = "${module.dcos.infrastructure.vpc.id}"
  local_subnet_range  = "${local.region_networks["local"]}"
  remote_vpc_id       = "${module.dcos-cac1.vpc.id}"
  remote_subnet_range = "${local.region_networks["cac1"]}"
}

module "vpc-connection-cac1-usw2" {
  source  = "dcos-terraform/vpc-peering/aws" // module init the peering
  version = "~> 1.0.0"

  providers = {
    "aws.local"  = "aws.cac1"
    "aws.remote" = "aws.usw2"
  }

  local_vpc_id        = "${module.dcos-cac1.vpc.id}"
  local_subnet_range  = "${local.region_networks["cac1"]}"
  remote_vpc_id       = "${module.dcos-usw2.vpc.id}"
  remote_subnet_range = "${local.region_networks["usw2"]}"
}
