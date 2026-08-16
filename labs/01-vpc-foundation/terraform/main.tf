terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "aws-cloud-network"
  }
}

resource "aws_subnet" "public_az1" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "public-az1"
  }
}
resource "aws_subnet" "public_az2" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "public-az2"
  }
}
resource "aws_subnet" "private_az1" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = "10.10.11.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-az1"
  }
}
resource "aws_subnet" "private_az2" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = "10.10.12.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-az2"
  }
}