# AWS Cloud Infrastructure for Uptime Kuma

![CI/CD](https://github.com/MisaelTox/uptime-kuma/actions/workflows/ci-cd.yml/badge.svg?branch=main)
![AWS](https://img.shields.io/badge/AWS-ECS%20Fargate-orange?logo=amazon-aws)
![Terraform](https://img.shields.io/badge/IaC-Terraform-purple?logo=terraform)
![Node.js](https://img.shields.io/badge/Tests-Node.js-green?logo=node.js)

This project deploys a highly available **Uptime Kuma** instance on **AWS ECS Fargate** using **Terraform**, with a fully automated CI/CD pipeline via **GitHub Actions**.

---

## 🏗️ Architecture

| Component | Technology |
|-----------|-----------|
| Compute | AWS ECS Fargate |
| Storage | Amazon EFS (mounted to `/app/data`) |
| Networking | Custom VPC, 2 public subnets across AZs |
| Monitoring | CloudWatch + SNS email alerts |
| IaC | Terraform |
| CI/CD | GitHub Actions |

---

## 🔄 CI/CD Pipeline

Every push to `main` automatically triggers two parallel jobs:
```
Push to main
      ↓
✅ App CI (parallel)         ✅ Terraform CI (parallel)
   → npm install                → terraform fmt
   → backend tests              → terraform validate
                                → terraform plan → AWS
      ↓                              ↓
      └──────────── both pass ───────┘
                      ↓
           ⏸️ Manual approval gate
                      ↓
            🚀 Deploy to Production
               → terraform apply
```

AWS credentials are stored as **GitHub Secrets** — never hardcoded.

---

## 📸 Dashboard Preview

![Uptime Kuma Dashboard](img/kumademo.png)

---

## 🛠️ Deployment Instructions

### Prerequisites
- Terraform installed
- AWS CLI configured

### Steps
```bash
cd terraform
terraform init
terraform apply
```

Access the dashboard at `http://<TASK_IP>:3001` — get the Task Public IP from the ECS console.

---

## 📝 Lessons Learned

- **CI/CD with GitHub Actions** — parallel CI jobs for app tests and infrastructure validation, with a manual approval gate before any AWS changes
- **Flaky test management** — identified and excluded infrastructure-dependent tests (MQTT, database) from CI, running only self-contained tests reliably
- **EFS Connectivity** — resolved `ResourceInitializationError` by opening port 2049 in the Security Group for Fargate-to-EFS communication
- **Network Routing** — configured Internet Gateways and Route Tables within the VPC module for public access

---

*Fork of [louislam/uptime-kuma](https://github.com/louislam/uptime-kuma). Terraform infrastructure layer and CI/CD pipeline added for AWS cloud deployment.*
