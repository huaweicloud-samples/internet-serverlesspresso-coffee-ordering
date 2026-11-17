# ============================================================================
# 输出
# ============================================================================

output "apig_domain" {
  description = "APIG 实例公网入口地址（绑定 EIP 后的公网 IP；未绑定时为空）"
  value       = huaweicloud_apig_instance.main.ingress_address
}

output "api_endpoint" {
  description = "点单 API 公网调用前缀（https://<公网IP>/release）"
  value       = "https://${huaweicloud_apig_instance.main.ingress_address}/release"
}

output "obs_bucket" {
  description = "承载函数代码包的 OBS 桶名"
  value       = huaweicloud_obs_bucket.assets.bucket
}

output "redis_address" {
  description = "DCS Redis 连接地址（会话与订单状态缓存）"
  value       = huaweicloud_dcs_instance.main.domain_name
  sensitive   = true
}

output "events_channel_id" {
  description = "订单事件通道 ID"
  value       = var.events_enabled ? huaweicloud_eg_custom_event_channel.orders[0].id : ""
}

output "iotda_space_id" {
  description = "IoTDA 资源空间 ID（设备接入）"
  value       = var.iotda_enabled ? huaweicloud_iotda_space.main[0].id : ""
}

output "smn_topic_urn" {
  description = "订单通知主题 URN"
  value       = var.events_enabled ? huaweicloud_smn_topic.orders[0].topic_urn : ""
  sensitive   = true
}