variable "prefix" {
  type    = string
  default = "bookstore"
}

variable "image_retention_count" {
  description = "Number of images to keep per repository"
  type        = number
  default     = 10
}
