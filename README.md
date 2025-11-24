# AWS Java ECS + S3 Demo

Small demo application that shows how to:

- Run a **Java backend** in a Docker container on **ECS Fargate**, behind an **Application Load Balancer (ALB)**.
- Use **RDS MySQL** as the backend database (wired via env vars).
- Host a **static frontend** in **S3 static website hosting** which calls the backend through the ALB.
- Manage all infrastructure with **Terraform**.
- Use **GitHub Actions** for Terraform CI/CD (plan on PR, apply on merge).
- Use **AWS CodePipeline + CodeBuild** to build and deploy the app (backend image + frontend sync) – currently **triggered manually from AWS**.

---

## 1. Repository layout

```text
.
├── backend/                # Java HTTP backend
│   ├── src/Main.java
│   └── Dockerfile          # Multi-stage build using Amazon Corretto 21
├── frontend/               # Static frontend (HTML + JS)
│   └── index.html
├── infra/
│   ├── bootstrap-dev/      # (optional) backend/bootstrap for remote state, etc.
│   ├── env/
│   │   ├── dev/            # Dev environment Terraform
│   │   │   ├── main.tf     # VPC, ECS, ALB, S3, RDS wiring
│   │   │   ├── backend.tf  # RDS bits
│   │   │   ├── cicd-app.tf # CodePipeline + CodeBuild for app
│   │   │   ├── providers.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── staging/        # placeholders
│   │   └── prod/           # placeholders
│   └── modules/            # Reusable Terraform modules
│       ├── aws-vpc/
│       ├── aws-ecs/
│       ├── aws-rds/
│       └── aws-frontend-s3/
└── .github/
    └── workflows/          # Terraform plan/apply via GitHub Actions
