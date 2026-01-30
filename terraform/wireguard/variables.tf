variable "aws_agent_count" {
  description = "Number of AWS agents"
  type        = number
  default     = 1
}

variable "wireguard_aws_cp_ip" {
  description = "WireGuard IP for AWS Control Plane"
  type        = string
  default     = "192.168.10.1/32"
}

variable "wireguard_gcp_ip" {
  description = "WireGuard IP for GCP"
  type        = string
  default     = "192.168.10.2/32"
}

variable "wireguard_subnet" {
  description = "WireGuard network subnet for all peers"
  type        = string
  default     = "192.168.10.0/24"
}
