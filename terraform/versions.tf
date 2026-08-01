terraform {
  required_version = ">= 1.10.0"

  # State lives in S3, not the repo (which is public). Configuration comes
  # from backend.hcl (gitignored) — scripts/bootstrap-state.sh creates the
  # bucket, writes backend.hcl, and runs terraform init.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.27"
    }
  }
}
