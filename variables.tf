variable "project" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "environment" {
  description = "The environment, and also used as a identifier"
  type        = string
  validation {
    condition     = try(length(regex("dev|prd|hml", var.environment)) > 0,false)
    error_message = "Define envrionment as one that follows: dev, hml or prd."
  }
}

variable "region" {
  description = "Region AWS where deploy occurs"
  type        = string
  default     = "us-east-1"
}

variable "application" {
  type = string
  description = "Name application"
}

#######################

variable "ecr_super_user_arn" {
  type = string
  description = "ECR management user"
  default = "*"
}

variable "service" {
  type = object({
    name        = string
    type        = string
    memory      = number
    cpu         = number
    action_type = string
    container_definition = object({
      hostPort      = number
      containerPort = number
      protocol      = string
    })
    health = object({
      retries     = number
      timeout     = number
      interval    = number
      startPeriod = number
    })
  })
}

variable "vpc_id" {
  type = string
}

variable "task_role_arn" {
  type        = string
  default     = ""
  description = ""
}


variable "execution_role_arn" {
  type        = string
  default     = ""
  description = ""
}

variable "minimum_tasks" {
  description = "Set a minimum amount task setup to this service"
  type        = number
  default     = 5
}

variable "desired_count" {
  description = "Set a minimum amount task setup to this service"
  type        = number
  default     = 10
}


variable "maximum_tasks" {
  description = "Set a minimum amount task setup to this service"
  type        = number
  default     = 50
}

variable "health_path" {
  type        = string
  description = "Path to service and load balancer validation"
  default     = "health"
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag name for image selection deploy"
}

variable "task_volumes" {
  description = "Describe this dynamic block for map "
  type = list(object({
    name = string
    efs_repo = list(object({
      efs_config = object({
      file_system_id = string
      root_directory = string
      })
    }))
  }))
  default = []
}

variable "mount_points" {
  type = list(object({
    containerPath = string
    sourceVolume  = string
  }))
  default = []
}


variable "environment_variables"{
  type = list(object({
    name = string
    value = string
  }))
  default = []
}

variable "cluster_name" {
  
}

variable "asg_name" {
  
}
variable "capacity_provider" {
  
}

variable "lb_name" {
  
}

variable "task_security" {
  type = object({
    resources = list(string)
    actions = list(string)
  })
  default = {
    actions = [ "*" ]
    resources = [ "*" ]
  }
}

variable "path_to_dockerfile" {
  type = string
  description = "Full path to files from root path /"
}