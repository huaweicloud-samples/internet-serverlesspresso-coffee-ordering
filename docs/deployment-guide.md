# 部署指导书

本文档说明如何从零部署「Serverlesspresso 咖啡点单」华为云实践，并完成一次点单端到端验证。

## 1. 部署前置

| 项 | 要求 |
|---|---|
| 华为云账号 | 已实名认证，具备创建 VPC/DCS/APIG/FunctionGraph/EG/SMN/IoTDA 权限 |
| Terraform | `>= 1.5` |
| Node.js | `>= 18`、npm（构建函数代码包） |
| 访问密钥 | 「我的凭证」页面获取，配置环境变量 `HW_ACCESS_KEY` / `HW_SECRET_KEY` |

> 请勿把真实访问密钥写入任何代码或配置文件。

## 2. 准备参数

复制 `infra/terraform.tfvars.example` 为 `infra/terraform.tfvars`，设置：
`dcs_password`（8-32 位复杂密码）、`auth_jwt_secret`（随机长串）、`obs_bucket_name`（OBS 桶名全局唯一，
建议加短随机后缀）、`project_name`（如带个人后缀的 `slpresso-<name>`，用于资源前缀）。

> `terraform.tfvars` 含密码与密钥，已被 `.gitignore` 排除，切勿提交。

## 3. 构建函数代码包

```bash
bash src/scripts/build-functions.sh
```

预期输出：6 个 zip 生成在 `build/` 目录（`auth-register.zip`、`auth-login.zip`、`auth-verify.zip`、
`order-create.zip`、`capacity-check.zip`、`order-complete.zip`），每个包内含入口 `index.js`、
公共编排模块 `order-orchestrator/order-flow.js` 与第三方依赖 `node_modules/`。

> 打包使用纯 Node 实现（`src/scripts/zip.js`），不依赖系统 `zip` 命令，Windows / Linux 通用。
> `build/` 目录已被 `.gitignore` 排除，属本地构建产物，无需提交。

## 4. 部署基础设施

```bash
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```

预期输出：`Apply complete! Resources: N added`，并列出 `apig_domain` / `api_endpoint` /
`obs_bucket` / `events_channel_id` / `iotda_space_id` / `smn_topic_urn`。

Terraform 会自动完成：创建 OBS 桶 → 上传 6 个函数代码包 → 创建 FunctionGraph 函数 →
创建 APIG 实例/分组/6 个 API → 将 6 个 API 发布到 RELEASE 环境。

> APIG 专享版实例创建约需 8 分钟，请耐心等待。

## 5. 获取公网调用入口

```bash
cd infra
terraform output api_endpoint
```

预期输出：`https://<公网IP>/release`

> 公网入口来自 APIG 实例绑定的 EIP（`ingress_address`）；公网调用必须带环境段 `/release`。
> 专享实例的内网分组域名形如 `<分组ID>.apic.<region>.huaweicloudapis.com`，**仅 VPC 内可达**，
> 公网 DNS 不可解析。

## 6. 端到端验证

```bash
APIG=$(cd infra && terraform output -raw api_endpoint)

# 1) 注册
curl -X POST $APIG/auth/register -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo1234"}'
# 2) 验证码（演示固定 123456）
curl -X POST $APIG/auth/verify -H 'Content-Type: application/json' \
  -d '{"username":"demo","code":"123456"}'
# 3) 登录获取 JWT
TOKEN=$(curl -s -X POST $APIG/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo1234"}' | jq -r .token)
# 4) 点单
curl -X POST $APIG/orders -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"items":[{"name":"latte"}]}'
# 5) 容量检查
curl -X POST $APIG/orders/capacity -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"cafe":"main"}'
# 6) 完成订单（拿上一步 orderId）
curl -X POST $APIG/orders/<orderId>/complete -H "Authorization: Bearer $TOKEN"
```

预期结果：注册返回 `UNVERIFIED` → 验证码校验后 `VERIFIED` → 登录返回 token →
点单返回 `NEW` 订单 → 容量检查返回 `capacityAvailable` → 完成后订单状态 `COMPLETED`；
SMN 收到通知（如有订阅者）。

## 7. 清理资源

```bash
cd infra
terraform destroy -auto-approve
```

预期输出：`Destroy complete! Resources: N destroyed.`
本地构建的 `build/*.zip` 为本地构建产物，无需保留，可直接删除。

> 注意事项：DCS Redis 与 APIG 专享实例为常驻资源，验证完成务必释放；
> OBS 桶设了 `force_destroy`，随 destroy 自动清空。
