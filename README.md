# internet-serverlesspresso-coffee-ordering

[中文版](README.cn.md)

[![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-FunctionGraph-red.svg)](https://www.huaweicloud.com/)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](#)

> Serverlesspresso coffee ordering: a serverless order/queue/make/complete loop on Huawei Cloud

---

## 1. Overview

This practice rebuilds **Serverlesspresso — a serverless coffee bar ordering workload**: customers order
through an API, the system checks capacity, enters preparation, notifies on completion, and coffee
machines/IoT devices receive order status via IoTDA. Built for development teams who want an event-driven
serverless reference on FunctionGraph.

### Core capabilities

- **Serverless backend**: APIG + FunctionGraph, no servers to manage
- **Event-driven loop**: order → capacity → make → complete, events flow via EventGrid and SMN
- **Trust & security**: self-built JWT auth (scrypt + HS256) instead of a managed user pool
- **Device access**: IoTDA coffee-machine product model with real-time order status

---

## 2. Table of Contents

- [1. Overview](#1-overview)
- [2. Table of Contents](#2-table-of-contents)
- [3. Architecture](#3-architecture)
- [4. Highlights](#4-highlights)
- [5. Cloud Services](#5-cloud-services)
- [6. Prerequisites](#6-prerequisites)
- [7. Quick Start](#7-quick-start)
- [8. Step-by-step Deployment](#8-step-by-step-deployment)
- [9. Usage / Verification](#9-usage--verification)
- [10. Cleanup](#10-cleanup)
- [11. Details](#11-details)
- [12. Dependencies](#12-dependencies)
- [13. FAQ / Troubleshooting](#13-faq--troubleshooting)
- [14. Contributing](#14-contributing)
- [15. License](#15-license)
- [16. Contact / Maintainers](#16-contact--maintainers)

---

## 3. Architecture

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

**Key components**:

- APIG + self-built JWT: register/login/verify (`src/functions/auth/*`)
- FunctionGraph services: order-create / capacity-check / order-complete (`src/functions/core/*`)
- Orchestration module `order-flow.js`: capacity → prepare → complete (state-machine semantics)
- DCS Redis: user / order / capacity state (KV + hash semantics)
- EG → SMN: order event notifications; IoTDA: coffee-machine model

---

## 4. Highlights

- **Fully-managed serverless**: no servers, pay per invocation
- **Reproducible packaging**: one script builds every function zip; Terraform uploads and provisions them
- **Replaceable auth**: clear JWT implementation, portable to enterprise IdP / MSGSMS SMS
- **End-to-end verifiable**: register → login → order → complete via curl

---

## 5. Cloud Services

| Service | Purpose | Notes |
|---|---|---|
| FunctionGraph | Auth and ordering microservices, orchestration | Core compute |
| API Gateway (APIG) | REST entry (auth/order/complete) | BASIC instance |
| DCS Redis | User / order / capacity state (KV + hash) | Single-node, VPC-internal |
| EventGrid (EG) | Order event channel and subscription | Custom events |
| Simple Message Notification (SMN) | Order status notifications | Event target |
| IoTDA | Coffee-machine device access and product model | Real-time status |
| OBS | Function code packages | Private bucket, auto-created by Terraform |

> All services are created by Terraform in this repository. See [Cleanup](#10-cleanup).

---

## 6. Prerequisites

| Item | Requirement | Note |
|---|---|---|
| **Account** | Huawei Cloud account with real-name verification | Individual or enterprise |
| **Permissions** | IAM Tenant Administrator or equivalent | VPC/DCS/APIG/FGS/EG/SMN/IoTDA |
| **Region** | `cn-north-4` | Recommended |
| **Terraform** | `>= 1.5` | IaC tool |
| **Node.js** | `>= 18`, npm | Local function packaging |
| **Access keys** | From "My Credentials" page, as env vars | Never write into code or config files |

---

## 7. Quick Start

```bash
git clone <repo-https-url> internet-serverlesspresso-coffee-ordering
cd internet-serverlesspresso-coffee-ordering

cp infra/terraform.tfvars.example infra/terraform.tfvars
# set dcs_password / auth_jwt_secret / obs_bucket_name / project_name

export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"

# build the function code packages (produces build/*.zip)
bash src/scripts/build-functions.sh

cd infra
terraform init && terraform plan && terraform apply -auto-approve
```

Full steps: [8. Step-by-step Deployment](#8-step-by-step-deployment) and `docs/deployment-guide.md`.

---

## 8. Step-by-step Deployment

1. **Build function packages**: `bash src/scripts/build-functions.sh` (produces `build/*.zip`, one per function)
2. **Deploy**: `cd infra && terraform apply -auto-approve` (expect `Resources: N added`); Terraform creates the OBS bucket and uploads the packages for you
3. **Read the endpoint**: `terraform output api_endpoint` gives the public call prefix

Expected output per step: see `docs/deployment-guide.md`.

---

## 9. Usage / Verification

> The public endpoint is `https://<apig_domain>/release` (Terraform output `api_endpoint`).
> Commands below were exercised against a deployed instance; re-run them yourself after deployment.

```bash
APIG=$(cd infra && terraform output -raw api_endpoint)

curl -X POST $APIG/auth/register -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo1234"}'
curl -X POST $APIG/auth/verify -H 'Content-Type: application/json' \
  -d '{"username":"demo","code":"123456"}'
TOKEN=$(curl -s -X POST $APIG/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo1234"}' | jq -r .token)
curl -X POST $APIG/orders -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"items":[{"name":"latte"}]}'
curl -X POST $APIG/orders/<orderId>/complete -H "Authorization: Bearer $TOKEN"
# capacity check
curl -X POST $APIG/orders/capacity -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"cafe":"main"}'
```

**Expected**: register → verify → login returns token → order returns `NEW` → complete → order state `COMPLETED`; SMN notification delivered.

---

## 10. Cleanup

```bash
cd infra
terraform destroy -auto-approve
```

**Expected**: `Destroy complete! Resources: N destroyed.` DCS Redis is a running instance — destroy it when done.

---

## 11. Details

### Workflow

Register/login (JWT) → order (write NEW + event) → capacity check → prepare/complete (COMPLETED + event)
→ EG subscription → SMN notification; IoTDA coffee-machine model receives order status.

### Configuration

| Variable | Default | Description |
|---|---|---|
| `region` | `cn-north-4` | Region |
| `project_name` | `serverlesspresso` | Resource name prefix |
| `obs_bucket_name` | (required) | OBS bucket for function code packages (globally unique) |
| `dcs_password` / `auth_jwt_secret` | (required) | DCS Redis password / JWT signing secret |
| `dcs_flavor` | `redis.single.xu1.tiny.128` | DCS Redis instance flavor |
| `apig_instance_edition` | `BASIC` | APIG instance edition |
| `events_enabled` / `iotda_enabled` | `true` | Toggle EG/SMN and IoTDA resources |

---

## 12. Dependencies

| Name | Version | Purpose |
|---|---|---|
| Terraform | `>= 1.5` | IaC |
| huaweicloud Provider | `>= 1.72` | Huawei Cloud resources |
| ioredis | `^5.4` | DCS Redis client |
| jsonwebtoken | `^9.0` | JWT sign/verify |

---

## 13. FAQ / Troubleshooting

| Symptom | Possible cause | How to check |
|---|---|---|
| apply fails: package not found | `build-functions.sh` not run | Run it, then re-apply |
| gateway returns `APIG.0101` | API not published to the environment | Publishment resources are created by Terraform — check `terraform apply` output |
| login 401 | unregistered / hash mismatch | Register and verify first |
| function returns 5xx on Redis access | VPC agency not effective | Check the FunctionGraph agency in the IAM console |

---

## 14. Contributing

Issues and PRs welcome: branch from `main`, run `terraform validate` + `terraform fmt -check`.
Merged after review by **[@<github-username>](https://github.com/<github-username>)**.

## 15. License

Released under the **MIT No Attribution** license. See [`LICENSE`](LICENSE).

## 16. Contact / Maintainers

| Item | Content |
|---|---|
| **Creator / Maintainer** | [@<github-username>](https://github.com/<github-username>) |
| **Contact** | GitHub Issues / PR (see [Contributing](#14-contributing)) |