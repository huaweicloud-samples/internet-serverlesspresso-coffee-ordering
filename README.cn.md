# internet-serverlesspresso-coffee-ordering

[English](README.md)

[![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-FunctionGraph-red.svg)](https://www.huaweicloud.com/)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](#)

> Serverlesspresso 咖啡点单：无服务器点单/排队/制作闭环（华为云版）
> Serverlesspresso coffee ordering: a serverless order/queue/make/complete loop on Huawei Cloud

---

## 1. 简介 / Overview

本实践重建 **Serverlesspresso——一个无服务器咖啡吧点单应用**：顾客通过 API 点单，系统做容量检查、
进入制作、完成后通知，咖啡机/设备经 IoTDA 收到订单状态。面向希望基于华为云 FunctionGraph 搭建
事件驱动无服务器应用的开发团队，可作为参考架构或学习样例。

### 核心能力

- **无服务器后端**：APIG + FunctionGraph，无需要常驻服务器
- **事件驱动闭环**：点单→容量→制作→完成，事件经事件网格流转、SMN 通知
- **信任与安全**：自建 JWT 认证（scrypt 哈希 + HS256），替代托管用户池
- **设备接入**：IoTDA 咖啡机产品模型，实时接收订单状态

---

## 2. 目录

- [1. 简介 / Overview](#1-简介--overview)
- [2. 目录](#2-目录)
- [3. 架构图](#3-架构图)
- [4. 方案亮点](#4-方案亮点)
- [5. 涉及云服务](#5-涉及云服务)
- [6. 前置条件](#6-前置条件)
- [7. 快速开始](#7-快速开始)
- [8. 分步部署](#8-分步部署)
- [9. 使用方法 / 验证](#9-使用方法--验证)
- [10. 清理资源](#10-清理资源)
- [11. 详细说明](#11-详细说明)
- [12. 依赖](#12-依赖)
- [13. FAQ / 故障排除](#13-faq--故障排除)
- [14. 贡献指南](#14-贡献指南)
- [15. 许可证](#15-许可证)
- [16. 联系方式 / 维护者](#16-联系方式--维护者)

---

## 3. 架构图

> 点单经 APIG 进入 FunctionGraph 微服务，状态经编排模块流转，事件经 EG 分发、SMN 通知、IoTDA 推送。

```
┌────────────────────────────────────────────────────────────────────┐
│            Web clients (3 apps) / IoTDA coffee machines            │
│                     REST API + device messages                     │
└──────────────────────────────────┬─────────────────────────────────┘
                                   │ HTTPS / MQTT
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                      APIG Gateway + JWT auth                       │
│           login / register / verify / orders / complete            │
└──────────────────────────────────┬─────────────────────────────────┘
                                   │ event
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                    FunctionGraph microservices                     │
│       auth / order-create / capacity-check / order-complete        │
│                      order-flow orchestrator                       │
└──────────────────────────────────┬─────────────────────────────────┘
                                   │ state + events
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│         DCS Redis (users / orders / capacity counters)             │
│            EventGrid (order events) + SMN notifications            │
│            OBS function code packages   IoTDA device model         │
└────────────────────────────────────────────────────────────────────┘
```

**关键组件说明**：

- APIG + 自建 JWT：注册/登录/验证码（`src/functions/auth/*`）
- FunctionGraph 微服务：点单/容量/完成（`src/functions/core/*`）
- 编排模块 `order-flow.js`：容量→制作→完成，对应状态机语义
- DCS Redis：用户 / 订单 / 容量状态（KV + hash 语义）
- EG → SMN：订单事件通知；IoTDA：咖啡机模型

---

## 4. 方案亮点

- **全托管无服务器**：无需管理服务器，函数按调用量伸缩
- **打包可复现**：一个脚本构建全部函数包，Terraform 负责上传与部署
- **认证可替换**：自建 JWT 清晰可审计，可平滑接入企业 IdP / MSGSMS 短信
- **端到端可验证**：注册→登录→点单→完成，一条 curl 链路跑通

---

## 5. 涉及云服务

| 服务 | 用途 | 备注 |
|---|---|---|
| 函数工作流 FunctionGraph | 认证与点单微服务、编排模块 | 核心计算 |
| API 网关 APIG | REST 入口（认证/点单/完成） | BASIC 实例 |
| DCS Redis | 用户 / 订单 / 容量状态（KV + hash） | 单机版，仅 VPC 内可达 |
| 事件网格 EG | 订单事件通道与订阅 | 自定义事件 |
| 消息通知 SMN | 订单状态通知 | 事件目标 |
| IoTDA | 咖啡机设备接入与产品模型 | 实时状态 |
| 对象存储 OBS | 函数代码包 | 私有桶，由 Terraform 自动创建 |

> 所有服务均可通过本仓库 Terraform 一键创建；清理见 [第 10 节](#10-清理资源)。

---

## 6. 前置条件

| 项 | 要求 | 说明 |
|---|---|---|
| **账号** | 已开通华为云账号并实名认证 | 个人/企业均可 |
| **权限** | IAM Tenant Administrator 或等效 | 创建 VPC/DCS/APIG/FGS/EG/SMN/IoTDA |
| **Region** | `cn-north-4` | 推荐区域 |
| **Terraform** | `>= 1.5` | IaC 工具 |
| **Node.js** | `>= 18`、npm | 本地构建函数代码包 |
| **访问密钥** | 「我的凭证」页面获取，配置环境变量 | 勿写入代码或配置文件 |

---

## 7. 快速开始

```bash
git clone <repo-https-url> internet-serverlesspresso-coffee-ordering
cd internet-serverlesspresso-coffee-ordering

cp infra/terraform.tfvars.example infra/terraform.tfvars
# 编辑：dcs_password / auth_jwt_secret / obs_bucket_name / project_name

export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"

# 构建函数代码包（产出 build/*.zip）
bash src/scripts/build-functions.sh

cd infra
terraform init && terraform plan && terraform apply -auto-approve
```

> 完整步骤见 [第 8 节](#8-分步部署)；函数包构建详见 `docs/deployment-guide.md` §3。

---

## 8. 分步部署

1. **构建函数包**：`bash src/scripts/build-functions.sh`（产出 `build/*.zip`，每函数一个）
2. **部署**：`cd infra && terraform apply -auto-approve`（预期 `Resources: N added`）；OBS 桶与代码包上传由 Terraform 自动完成
3. **读取入口**：`terraform output api_endpoint` 给出公网调用前缀

每步预期输出见 `docs/deployment-guide.md`。

---

## 9. 使用方法 / 验证

> 公网入口为 `https://<apig_domain>/release`（Terraform 输出 `api_endpoint`）。
> 下列命令在已部署实例上实测过；部署完成后请自行重跑验证（见 §6 前置）。

```bash
APIG=$(cd infra && terraform output -raw api_endpoint)

# 注册
curl -X POST $APIG/auth/register -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo1234"}'
# 验证码（演示固定码）
curl -X POST $APIG/auth/verify -H 'Content-Type: application/json' \
  -d '{"username":"demo","code":"123456"}'
# 登录拿 JWT
TOKEN=$(curl -s -X POST $APIG/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo1234"}' | jq -r .token)
# 点单
curl -X POST $APIG/orders -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"items":[{"name":"latte"}]}'
# 完成
curl -X POST $APIG/orders/<orderId>/complete -H "Authorization: Bearer $TOKEN"
# 容量检查
curl -X POST $APIG/orders/capacity -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"cafe":"main"}'
```

**预期结果**：注册 → 验证码校验 → 登录返回 token → 点单返回 `NEW` → 完成后订单状态 `COMPLETED`；
SMN 收到通知。

---

## 10. 清理资源

```bash
cd infra
terraform destroy -auto-approve
```

**预期输出**：`Destroy complete! Resources: N destroyed.`
> 注意：DCS Redis 为常驻实例，验证完成务必释放（OBS 桶 force_destroy 会自动清空）。

---

## 11. 详细说明

### 工作流程

注册/登录（JWT）→ 点单（写订单 NEW + 事件）→ 容量检查 → 制作/完成（COMPLETED + 事件）→
EG 订阅 → SMN 通知；IoTDA 咖啡机模型接收订单状态。

### 配置项

| 变量 | 默认值 | 说明 |
|---|---|---|
| `region` | `cn-north-4` | 区域 |
| `project_name` | `serverlesspresso` | 资源名前缀 |
| `obs_bucket_name` | （必填） | 存放函数代码包的 OBS 桶名（全局唯一） |
| `dcs_password` / `auth_jwt_secret` | （必填） | DCS Redis 密码 / JWT 签名密钥 |
| `dcs_flavor` | `redis.single.xu1.tiny.128` | DCS Redis 实例规格 |
| `apig_instance_edition` | `BASIC` | APIG 实例规格 |
| `events_enabled` / `iotda_enabled` | `true` | 是否创建 EG/SMN 与 IoTDA 资源 |

---

## 12. 依赖

| 名称 | 版本 | 用途 |
|---|---|---|
| Terraform | `>= 1.5` | IaC |
| huaweicloud Provider | `>= 1.72` | 华为云资源 |
| ioredis | `^5.4` | DCS Redis 客户端 |
| jsonwebtoken | `^9.0` | JWT 签发/校验 |

---

## 13. FAQ / 故障排除

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| apply 报代码包不存在 | 未先跑 build-functions.sh | 执行打包脚本后重新 apply |
| 网关返回 `APIG.0101` | API 未发布到环境 | 发布资源由 Terraform 创建，检查 `terraform apply` 输出 |
| 登录 401 | 未注册 / 哈希不匹配 | 先注册并完成验证码校验 |
| 函数访问 Redis 报 5xx | VPC 委托未生效 | 到 IAM 控制台检查 FunctionGraph 委托 |

---

## 14. 贡献指南

欢迎提交 Issue 与 PR：基于 `main` 建分支，提交前 `terraform validate` + `terraform fmt -check`。由 **[@<github-username>](https://github.com/<github-username>)** review 后合并。

## 15. 许可证

本实践采用 **MIT No Attribution** 许可证发布。详见 [`LICENSE`](LICENSE)。

```
MIT No Attribution
Copyright (c) Huawei Cloud
```

## 16. 联系方式 / 维护者

| 项 | 内容 |
|---|---|
| **创建者 / 维护者** | [@<github-username>](https://github.com/<github-username>) |
| **联系方式** | GitHub Issues / PR（见 [第 14 节](#14-贡献指南)） |