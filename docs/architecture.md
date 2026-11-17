# 架构说明

本文档描述「Serverlesspresso 咖啡点单」实践在华为云上的部署形态：无服务器后端 + 事件驱动 +
设备接入，重建一个可运行的咖啡吧点单/排队/制作/完成闭环。

## 架构图

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

## 组件职责

| 组件 | 华为云服务 | 职责 |
|---|---|---|
| 认证 | APIG + FunctionGraph（自建 JWT，scrypt 密码哈希） | 注册/登录/验证码 |
| 点单 API | APIG + FunctionGraph | POST /orders 创建订单、POST /orders/capacity 容量检查、POST /orders/{id}/complete 完成 |
| 编排 | FunctionGraph（`src/functions/order-orchestrator/order-flow.js`） | 容量检查 → 制作 → 完成（状态机语义） |
| 存储 | DCS Redis | 用户（hash）、订单（string）、容量计数（string）；单机版，仅 VPC 内可达 |
| 事件 | 事件网格 EG | 订单事件自定义通道 + 订阅到 SMN |
| 通知 | SMN | 订单状态通知 |
| 设备 | IoTDA | 资源空间 + 咖啡机产品模型（属性 orderStatus） |
| 对象存储 | OBS | 各函数代码包（Terraform 自动建桶并上传） |

## 工作流程

1. 用户注册（APIG → auth-register）：生成盐值，scrypt 哈希后写入 Redis 用户 hash，状态置 `UNVERIFIED`。
2. 验证码校验（APIG → auth-verify）：校验通过后状态置 `VERIFIED`（演示固定码 `123456`）。
3. 登录（APIG → auth-login）：比对 scrypt 哈希，签发 HS256 JWT（有效期 8 小时）。
4. 点单（APIG → order-create）：校验 JWT → 写入 Redis 订单记录（状态 `NEW`）→ 触发订单事件。
5. 容量检查（APIG → orders/capacity）：编排模块读取容量计数，判断是否达到并发上限 5。
6. 制作/完成（APIG → orders/{id}/complete）：状态流转 `NEW`→`PREPARING`→`COMPLETED`，触发订单事件。
7. 事件经 EG 订阅转发到 SMN 通知；IoTDA 提供咖啡机产品模型承载设备侧属性。

## 设计要点

- **状态统一在 Redis**：用户、订单、容量三类状态都用 DCS Redis 承载（hash / string 语义），
  不引入额外数据库实例，部署与验证都更轻量；生产环境如需关系型查询可替换为
  GeminiDB 或 RDS，函数侧只需改数据访问层。
- **函数自包含打包**：每个函数包内含入口 `index.js`、公共编排模块与第三方依赖
  （`ioredis` / `jsonwebtoken`），由 `src/scripts/build-functions.sh` 统一构建，
  保证 6 个包结构一致、可复现。
- **Terraform 全托管**：OBS 桶由 Terraform 创建并上传代码包；APIG 的 API 通过
  `huaweicloud_apig_api_publishment` 显式发布到 RELEASE 环境——API 创建后不会自动发布，
  漏掉发布资源会导致网关返回 `APIG.0101`。
- **认证自建**：JWT（HS256）+ scrypt；验证码为演示模式，接入 MSGSMS 后可短信下发。
- **公网入口**：APIG 专享版默认只有 VPC 内网入口，本实践通过绑定 EIP 开启公网访问；
  公网调用路径需带环境段 `/release`（即 `https://<公网IP>/release/<path>`）。
