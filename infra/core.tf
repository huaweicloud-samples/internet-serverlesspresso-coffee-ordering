# ============================================================================
# 计算层：FunctionGraph 函数（认证 + 核心点单链路）
# ============================================================================
# 函数代码包由 src/scripts/build-functions.sh 本地打包（入口 index.js + 公共依赖
# node_modules 一起进包），Terraform 上传到 OBS 后由本文件引用。
# 订单与用户状态统一存放在 DCS Redis（KV / hash 承载表语义）。

locals {
  fgs_common = {
    memory_size = 256
    timeout     = 30
    runtime     = "Node.js18.15"
  }
  fgs_env_raw = {
    REDIS_HOST      = huaweicloud_dcs_instance.main.domain_name
    REDIS_PORT      = "6379"
    REDIS_PASSWORD  = var.dcs_password
    AUTH_JWT_SECRET = var.auth_jwt_secret
    SMS_SIGNER      = var.sms_signer
  }
  fgs_env = { for k, v in local.fgs_env_raw : k => v if v != "" }

  # 函数代码包清单：build/<object_name> 由 build-functions.sh 生成
  function_code_files = {
    auth-register  = { object_name = "auth-register.zip", src = "src/functions/auth/register.js" }
    auth-login     = { object_name = "auth-login.zip", src = "src/functions/auth/login.js" }
    auth-verify    = { object_name = "auth-verify.zip", src = "src/functions/auth/verify.js" }
    order-create   = { object_name = "order-create.zip", src = "src/functions/core/order-create.js" }
    capacity-check = { object_name = "capacity-check.zip", src = "src/functions/core/capacity-check.js" }
    order-complete = { object_name = "order-complete.zip", src = "src/functions/core/order-complete.js" }
  }
}

# ---- 认证：注册 / 登录 / 验证码 ----
resource "huaweicloud_fgs_function" "auth_register" {
  name        = "${var.project_name}-auth-register"
  app         = "default"
  agency      = huaweicloud_identity_agency.fgs_vpc.name
  handler     = "index.handler"
  memory_size = local.fgs_common.memory_size
  timeout     = local.fgs_common.timeout
  runtime     = local.fgs_common.runtime
  vpc_id      = huaweicloud_vpc.main.id
  network_id  = huaweicloud_vpc_subnet.main.id

  code_type = "obs"
  code_url  = "https://${huaweicloud_obs_bucket.assets.bucket}.obs.${var.region}.myhuaweicloud.com/code/auth-register.zip"
  user_data = jsonencode(merge(local.fgs_env, { MODE = "register" }))
}

resource "huaweicloud_fgs_function" "auth_login" {
  name        = "${var.project_name}-auth-login"
  app         = "default"
  agency      = huaweicloud_identity_agency.fgs_vpc.name
  handler     = "index.handler"
  memory_size = local.fgs_common.memory_size
  timeout     = local.fgs_common.timeout
  runtime     = local.fgs_common.runtime
  vpc_id      = huaweicloud_vpc.main.id
  network_id  = huaweicloud_vpc_subnet.main.id

  code_type = "obs"
  code_url  = "https://${huaweicloud_obs_bucket.assets.bucket}.obs.${var.region}.myhuaweicloud.com/code/auth-login.zip"
  user_data = jsonencode(merge(local.fgs_env, { MODE = "login" }))
}

resource "huaweicloud_fgs_function" "auth_verify" {
  name        = "${var.project_name}-auth-verify"
  app         = "default"
  agency      = huaweicloud_identity_agency.fgs_vpc.name
  handler     = "index.handler"
  memory_size = local.fgs_common.memory_size
  timeout     = local.fgs_common.timeout
  runtime     = local.fgs_common.runtime
  vpc_id      = huaweicloud_vpc.main.id
  network_id  = huaweicloud_vpc_subnet.main.id

  code_type = "obs"
  code_url  = "https://${huaweicloud_obs_bucket.assets.bucket}.obs.${var.region}.myhuaweicloud.com/code/auth-verify.zip"
  user_data = jsonencode(merge(local.fgs_env, { MODE = "verify" }))
}

# ---- 核心点单链路 ----
resource "huaweicloud_fgs_function" "order_create" {
  name        = "${var.project_name}-order-create"
  app         = "default"
  agency      = huaweicloud_identity_agency.fgs_vpc.name
  handler     = "index.handler"
  memory_size = local.fgs_common.memory_size
  timeout     = local.fgs_common.timeout
  runtime     = local.fgs_common.runtime
  vpc_id      = huaweicloud_vpc.main.id
  network_id  = huaweicloud_vpc_subnet.main.id

  code_type = "obs"
  code_url  = "https://${huaweicloud_obs_bucket.assets.bucket}.obs.${var.region}.myhuaweicloud.com/code/order-create.zip"
  user_data = jsonencode(local.fgs_env)
}

resource "huaweicloud_fgs_function" "capacity_check" {
  name        = "${var.project_name}-capacity-check"
  app         = "default"
  agency      = huaweicloud_identity_agency.fgs_vpc.name
  handler     = "index.handler"
  memory_size = local.fgs_common.memory_size
  timeout     = local.fgs_common.timeout
  runtime     = local.fgs_common.runtime
  vpc_id      = huaweicloud_vpc.main.id
  network_id  = huaweicloud_vpc_subnet.main.id

  code_type = "obs"
  code_url  = "https://${huaweicloud_obs_bucket.assets.bucket}.obs.${var.region}.myhuaweicloud.com/code/capacity-check.zip"
  user_data = jsonencode(local.fgs_env)
}

resource "huaweicloud_fgs_function" "order_complete" {
  name        = "${var.project_name}-order-complete"
  app         = "default"
  agency      = huaweicloud_identity_agency.fgs_vpc.name
  handler     = "index.handler"
  memory_size = local.fgs_common.memory_size
  timeout     = local.fgs_common.timeout
  runtime     = local.fgs_common.runtime
  vpc_id      = huaweicloud_vpc.main.id
  network_id  = huaweicloud_vpc_subnet.main.id

  code_type = "obs"
  code_url  = "https://${huaweicloud_obs_bucket.assets.bucket}.obs.${var.region}.myhuaweicloud.com/code/order-complete.zip"
  user_data = jsonencode(local.fgs_env)
}

# ============================================================================
# 事件：事件网格 EG（订单事件自定义通道 + 订阅到 SMN）
# ============================================================================

resource "huaweicloud_eg_custom_event_channel" "orders" {
  count       = var.events_enabled ? 1 : 0
  name        = "${var.project_name}-orders"
  description = "Order workflow events"
}

resource "huaweicloud_eg_event_subscription" "orders" {
  count       = var.events_enabled ? 1 : 0
  name        = "${var.project_name}-order-metrics"
  channel_id  = var.events_enabled ? huaweicloud_eg_custom_event_channel.orders[0].id : ""
  description = "Route order events to SMN notification"

  sources {
    id            = uuid()
    provider_type = "CUSTOM"
    name          = "${var.project_name}-order-source"
    filter_rule = jsonencode({
      source = [{
        op     = "StringIn"
        values = ["${var.project_name}"]
      }]
    })
  }

  targets {
    id            = uuid()
    provider_type = "OFFICIAL"
    name          = "HC.SMN"
    detail_name   = "smn_detail"
    detail = jsonencode({
      urn = var.events_enabled ? huaweicloud_smn_topic.orders[0].topic_urn : ""
    })
    transform = jsonencode({
      type  = "ORIGINAL"
      value = ""
    })
  }
}

# ============================================================================
# 通知：SMN（订单状态通知）
# ============================================================================

resource "huaweicloud_smn_topic" "orders" {
  count        = var.events_enabled ? 1 : 0
  name         = "${var.project_name}-order-events"
  display_name = "Order event notifications"
}

# ============================================================================
# 设备：IoTDA（咖啡机/设备实时消息，替代 IoT Core 发布链路）
# ============================================================================

resource "huaweicloud_iotda_space" "main" {
  count = var.iotda_enabled ? 1 : 0
  name  = "${var.project_name}-space"
}

resource "huaweicloud_iotda_product" "coffee_machine" {
  count       = var.iotda_enabled ? 1 : 0
  name        = "coffee-machine"
  device_type = "coffee_machine"
  data_type   = "json"
  protocol    = "MQTT"
  space_id    = var.iotda_enabled ? huaweicloud_iotda_space.main[0].id : ""
  description = "Coffee machine that receives order events via IoTDA"

  services {
    id          = "orderStatus"
    description = "Order status property pushed to the coffee machine"
  }
}

# ============================================================================
# API 接入：APIG（实例 + 分组 + 核心 API）
# ============================================================================

# 公网入口 EIP（APIG 调用；启用前请确认公网出口的访问权限）
resource "huaweicloud_vpc_eip" "apig" {
  publicip { type = "5_bgp" }
  bandwidth {
    name        = "${var.project_name}-apig-eip"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}
resource "huaweicloud_apig_instance" "main" {
  name              = "${var.project_name}-apig"
  eip_id            = huaweicloud_vpc_eip.apig.id
  edition           = var.apig_instance_edition
  available_zones   = [data.huaweicloud_availability_zones.main.names[0]]
  vpc_id            = huaweicloud_vpc.main.id
  subnet_id         = huaweicloud_vpc_subnet.main.id
  security_group_id = huaweicloud_networking_secgroup.main.id
  maintain_begin    = "02:00:00"
  tags              = local.common_tags
}

resource "huaweicloud_apig_group" "main" {
  name        = "${var.project_name}-api"
  instance_id = huaweicloud_apig_instance.main.id
  description = "Serverlesspresso REST APIs"
}

# 专享实例内置 RELEASE 环境，其环境 ID 为固定常量，不可重复创建
locals {
  release_env_id = "DEFAULT_ENVIRONMENT_RELEASE_ID"
}

# POST /auth/register 注册
resource "huaweicloud_apig_api" "auth_register" {
  name             = "auth-register"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "POST"
  request_path     = "/auth/register"
  request_protocol = "HTTPS"

  func_graph {
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
    function_urn     = replace(huaweicloud_fgs_function.auth_register.urn, ":latest", "")
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

# POST /auth/verify 验证码校验
resource "huaweicloud_apig_api" "auth_verify" {
  name             = "auth-verify"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "POST"
  request_path     = "/auth/verify"
  request_protocol = "HTTPS"

  func_graph {
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
    function_urn     = replace(huaweicloud_fgs_function.auth_verify.urn, ":latest", "")
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

resource "huaweicloud_apig_api" "auth_login" {
  name             = "auth-login"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "POST"
  request_path     = "/auth/login"
  request_protocol = "HTTPS"

  func_graph {
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
    function_urn     = replace(huaweicloud_fgs_function.auth_login.urn, ":latest", "")
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

resource "huaweicloud_apig_api" "order_create" {
  name             = "order-create"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "POST"
  request_path     = "/orders"
  request_protocol = "HTTPS"

  func_graph {
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
    function_urn     = replace(huaweicloud_fgs_function.order_create.urn, ":latest", "")
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

resource "huaweicloud_apig_api" "order_complete" {
  name             = "order-complete"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "POST"
  request_path     = "/orders/{id}/complete"
  request_protocol = "HTTPS"

  func_graph {
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
    function_urn     = replace(huaweicloud_fgs_function.order_complete.urn, ":latest", "")
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

# POST /orders/capacity 容量检查
resource "huaweicloud_apig_api" "capacity_check" {
  name             = "capacity-check"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "POST"
  request_path     = "/orders/capacity"
  request_protocol = "HTTPS"

  func_graph {
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
    function_urn     = replace(huaweicloud_fgs_function.capacity_check.urn, ":latest", "")
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

# ============================================================================
# API 发布：apig_api 创建后不会自动发布，必须显式 publishment 到 RELEASE 环境，
# 否则网关返回 APIG.0101（API 不存在或未发布到环境）
# ============================================================================

resource "huaweicloud_apig_api_publishment" "auth_register" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.auth_register.id
  env_id      = local.release_env_id
}

resource "huaweicloud_apig_api_publishment" "auth_login" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.auth_login.id
  env_id      = local.release_env_id
}

resource "huaweicloud_apig_api_publishment" "auth_verify" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.auth_verify.id
  env_id      = local.release_env_id
}

resource "huaweicloud_apig_api_publishment" "order_create" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.order_create.id
  env_id      = local.release_env_id
}

resource "huaweicloud_apig_api_publishment" "capacity_check" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.capacity_check.id
  env_id      = local.release_env_id
}

resource "huaweicloud_apig_api_publishment" "order_complete" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.order_complete.id
  env_id      = local.release_env_id
}