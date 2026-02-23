variable "region" {
  default = "eu-north-1" # Estocolmo (puedes cambiarla)
}

variable "user_email" {
  description = "Tu correo para recibir alertas de CloudWatch"
  type        = string
  default     = "tu-correo@ejemplo.com" # CAMBIA ESTO
}