# AWS Cloud Infrastructure for Uptime Kuma

This project deploys a highly available **Uptime Kuma** instance on **AWS Fargate (ECS)** using **Terraform**. It features persistent storage, automated monitoring, and an email notification system.

## 🚀 Project Overview

The goal of this project was to move from a basic container deployment to a production-ready cloud architecture. I implemented a persistent data layer using **Amazon EFS** to ensure that monitoring data is never lost, even if the container restarts.

### Key Features

* **Serverless Computing:** Run on AWS Fargate (No EC2 instances to manage).
* **Persistent Storage:** Amazon EFS integration for database persistence.
* **Security:** Isolated VPC with specific Security Group rules (Port 3001 for Web, 2049 for EFS).
* **Infrastructure as Code:** 100% managed via Terraform.
* **Alerting:** Integrated with Amazon SNS for email notifications.
* **Remote State:** Terraform state stored in S3 with file-based locking for team collaboration.
* **CI/CD:** GitHub Actions pipeline for automatic format check and validation on every push.

## 🏗 Architecture Diagram

![Uptime Kuma Diagram](img/kuma-arc.drawio.png)

The infrastructure consists of:

1. **VPC:** 2 Public Subnets across different Availability Zones.
2. **ECS Fargate:** Task definition optimized for performance and cost.
3. **EFS:** Elastic File System mounted to `/app/data` inside the container.
4. **CloudWatch & SNS:** CPU usage monitoring and email alerts.

## 📸 Dashboard Preview

![Uptime Kuma Dashboard](img/kumademo.png)
*(My active monitoring dashboard showing real-time service status)*

---

## 🛠 Deployment Instructions

### Prerequisites

* Terraform installed.
* AWS CLI configured with appropriate credentials.

### Steps

1. **Bootstrap remote state** *(first time only — creates the S3 bucket for Terraform state):*

   ```bash
   cd terraform/bootstrap
   terraform init
   terraform apply
   ```

2. **Initialize Terraform:**

   ```bash
   cd ..
   terraform init
   ```

3. **Apply Configuration:**

   ```bash
   terraform apply
   ```

4. **Access the Dashboard:**
   Get the Public IP from the ECS Task console and open `http://<TASK_IP>:3001` in your browser.

---

## 🗄 Remote State

Terraform state is stored remotely in **Amazon S3** with file-based locking (`use_lockfile = true`), ensuring safe collaboration and preventing concurrent state corruption.

```
terraform/
├── bootstrap/
│   └── bootstrap.tf   ← provisions S3 bucket (run once)
├── backend.tf         ← configures remote state
└── ...
```

The S3 bucket is configured with:
* **Versioning enabled** — full history of every state file, allowing rollback if needed.
* **AES-256 encryption at rest** — state files are never stored in plaintext.
* **Public access blocked** — bucket is fully private.

---

## ⚙️ CI/CD Pipeline

A GitHub Actions workflow runs automatically on every push to `main` and on pull requests.

```
.github/workflows/terraform-ci.yml
```

| Step | What it does |
|------|-------------|
| `terraform fmt -check` | Fails if code is not properly formatted |
| `terraform init -backend=false` | Initializes without connecting to S3 |
| `terraform validate` | Checks for syntax and configuration errors |

---

## 📝 Lessons Learned

* **EFS Connectivity:** Resolved `ResourceInitializationError` by opening port 2049 in the Security Group to allow communication between the Fargate task and the file system.
* **Network Routing:** Configured Internet Gateways and Route Tables within the VPC module to enable public access to the service.
* **Remote State Bootstrap:** The S3 backend cannot provision itself — a separate `bootstrap/` module is required to create the bucket before initializing the backend.
* **CI/CD without credentials:** Using `terraform init -backend=false` allows format and validation checks to run in GitHub Actions without needing AWS credentials.

---

*Note: This project is a fork of [louislam/uptime-kuma](https://github.com/louislam/uptime-kuma). I have added the Terraform infrastructure layer to automate its deployment on AWS.*

## ☸️ Kubernetes Deployment

This project includes a full Kubernetes deployment in addition to the AWS Fargate setup.

### Structure
- `k8s/manifests/` — Raw Kubernetes manifests (Deployment, Service, PVC, ConfigMap, Ingress)
- `k8s/helm/` — Helm chart for multi-environment deployments
- `k8s/terraform/` — EKS cluster provisioning with Terraform

### Quick Start (local)
```bash
# Start minikube
minikube start

# Create namespace
kubectl create namespace monitoring

# Deploy with Helm
helm install uptime-kuma ./k8s/helm -n monitoring

# Access the app
kubectl port-forward service/uptime-kuma 3001:3001 -n monitoring
```

### Production (AWS EKS)
```bash
# Provision EKS cluster
cd k8s/terraform && terraform init && terraform apply

# Configure kubectl
aws eks update-kubeconfig --region eu-central-1 --name uptime-kuma-cluster

# Deploy with Helm
kubectl create namespace monitoring
helm install uptime-kuma ./k8s/helm -n monitoring
```
