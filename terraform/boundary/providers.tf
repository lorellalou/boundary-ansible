
provider "boundary" {
  addr             = var.boundary_addr
  recovery_kms_hcl = var.boundary_recovery_kms_hcl
}
