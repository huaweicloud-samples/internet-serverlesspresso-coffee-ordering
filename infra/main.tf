# ============================================================================
# Serverlesspresso 华为云版 —— Terraform 主入口
# ============================================================================
# 架构：APIG(REST) + 自建 JWT 认证 → FunctionGraph 微服务 → DCS Redis(状态存储)
#       → 事件网格 EG(订单事件) → SMN/IoTDA
# ============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.72"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
  backend "local" {}
}

provider "huaweicloud" {
  region = var.region
  # 访问密钥通过环境变量 HW_ACCESS_KEY / HW_SECRET_KEY 提供（provider 原生读取，
  # 使用 STS 临时凭据时额外提供 HW_SECURITY_TOKEN）。切勿把访问密钥写入任何代码或配置文件。
}

locals {
  common_tags = {
    Project     = "serverlesspresso"
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "platform-team"
  }
}

# ============================================================================
# 变量
# ============================================================================

variable "region" {
  description = "部署区域"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "资源命名前缀"
  type        = string
  default     = "serverlesspresso"
}

variable "environment" {
  description = "环境：dev/staging/prod"
  type        = string
  default     = "dev"
}

variable "dcs_password" {
  description = "DCS Redis 实例密码"
  type        = string
  sensitive   = true
}

variable "dcs_flavor" {
  description = "DCS Redis 规格（显式决策；单机 0.125GB 最低档）"
  type        = string
  default     = "redis.single.xu1.tiny.128"
}

variable "auth_jwt_secret" {
  description = "自建 JWT 签名密钥（测试账号临时密钥，勿提交 git）"
  type        = string
  sensitive   = true
}

variable "sms_signer" {
  description = "短信签名（MSGSMS，可选；适用于验证码发送，未配置则验证码仅在日志显示）"
  type        = string
  default     = ""
}

variable "obs_bucket_name" {
  description = "OBS 桶名（全局唯一，建议用项目名-assets-环境名 加短随机后缀）；承载各函数代码包"
  type        = string
}

variable "events_enabled" {
  description = "是否启用事件通知目标（EG 订阅 + SMN，需 EG 委托；验证核心链路可置 false）"
  type        = bool
  default     = true
}

variable "iotda_enabled" {
  description = "是否启用 IoTDA 设备接入（需账号已订阅 IoTDA；未订阅时置 false 跳过）"
  type        = bool
  default     = true
}

variable "apig_instance_edition" {
  description = "APIG 实例规格（BASIC/STANDARD 等，显式决策）"
  type        = string
  default     = "BASIC"
}

# ============================================================================
# 网络 → DCS Redis 专用 VPC
# ============================================================================

data "huaweicloud_availability_zones" "main" {}

resource "huaweicloud_vpc" "main" {
  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"
  tags = local.common_tags
}

resource "huaweicloud_vpc_subnet" "main" {
  name       = "${var.project_name}-subnet"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = "10.0.1.0/24"
  gateway_ip = "10.0.1.1"
}

resource "huaweicloud_networking_secgroup" "main" {
  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name}"
}

resource "huaweicloud_networking_secgroup_rule" "redis_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6379
  port_range_max    = 6379
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.main.id
}

# ============================================================================
# 存储：DCS Redis（承载用户/订单/容量计数等状态）
# ============================================================================

# 函数委托：FGS 接入 VPC 需要 VPC Administrator（docs/09 §14 坑）
resource "huaweicloud_identity_agency" "fgs_vpc" {
  name                  = "${var.project_name}-fgs-agency"
  description           = "Agency for FunctionGraph VPC access"
  duration              = "FOREVER"
  delegated_domain_name = "op_svc_cff"

  project_role {
    project = var.region
    roles = [
      "VPC Administrator",
    ]
  }
}

resource "huaweicloud_dcs_instance" "main" {
  name           = "${var.project_name}-redis"
  engine         = "Redis"
  engine_version = "5.0"
  capacity       = 0.125
  flavor         = var.dcs_flavor
  vpc_id         = huaweicloud_vpc.main.id
  subnet_id      = huaweicloud_vpc_subnet.main.id
  # DCS 单机版不支持安全组关联（白名单模式），不传 security_group_id
  availability_zones = ["cn-north-4b"]
  password           = var.dcs_password
  tags               = local.common_tags
}

# ============================================================================
# 函数代码：各函数代码包由 src/scripts/build-functions.sh 本地打包到 build/，
# Terraform 负责建桶并上传到 OBS（code/<name>.zip），再由 core.tf 引用。
# ============================================================================

resource "huaweicloud_obs_bucket" "assets" {
  bucket        = var.obs_bucket_name
  acl           = "private"
  force_destroy = true
  tags          = local.common_tags
}

# 各函数代码包 → OBS
resource "huaweicloud_obs_bucket_object" "function_code" {
  for_each = local.function_code_files

  bucket = huaweicloud_obs_bucket.assets.bucket
  key    = "code/${each.value.object_name}"
  source = "${path.module}/../build/${each.value.object_name}"
}
