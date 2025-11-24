# AWS Java ECS + S3 Demo

Small demo application that shows how to:

- Run a **Java backend** in a Docker container on **ECS Fargate**, behind an **Application Load Balancer (ALB)**.
- Use **RDS MySQL** as the backend database (wired via env vars).
- Host a **static frontend** in **S3 static website hosting** which calls the backend through the ALB.
- Manage all infrastructure with **Terraform**.
- Use **GitHub Actions** for Terraform CI/CD (plan on PR, apply on merge).
- Use **AWS CodePipeline + CodeBuild** to build and deploy the app (backend image + frontend sync) – currently **triggered manually from AWS**.

---

2. What the app does
Backend

Plain Java HTTP server using com.sun.net.httpserver.HttpServer

Listens on port 8080

Endpoints:

GET /health → OK (ALB health check)

GET /message?name=XYZ → Hello XYZ

Runs as an ECS Fargate task using an image in Amazon ECR

Frontend

Single static page frontend/index.html

Simple form + button

JS calls backend:

const backendBase = '<BACKEND_ALB_URL>'; // You will set this
const url = backendBase + '/message?name=' + encodeURIComponent(name);


Shows response in a <pre> block

3. Prerequisites

You’ll need:

AWS account + IAM permissions for VPC, ECS, ECR, RDS, S3, IAM, CloudWatch, CodeBuild, CodePipeline, CodeStar

Tools:

git

terraform (v1.x)

awscli v2 (configured profile, e.g. dev)

docker

Java 21 (only if running backend locally)

Default region used: us-east-1

4. Clone the repo
git clone https://github.com/Ahtisham77/aws-java-ecs-s3-demo.git
cd aws-java-ecs-s3-demo

5. Run locally (optional)
5.1 Backend
cd backend

# Compile
javac src/Main.java -d out

# Run
java -cp out Main


Server runs at http://localhost:8080.

Quick test:

curl http://localhost:8080/health
curl "http://localhost:8080/message?name=world"

5.2 Frontend

Edit frontend/index.html and set:

const backendBase = 'http://localhost:8080';


Then:

cd frontend
python3 -m http.server 8081


Open http://localhost:8081, type a name, click Send.

6. Deploy infra with Terraform (dev)

Assumes AWS_PROFILE=dev and AWS_REGION=us-east-1:

export AWS_PROFILE=dev
export AWS_REGION=us-east-1

cd infra/env/dev

terraform init
terraform plan
terraform apply


This creates (dev):

VPC with public/private subnets, IGW, NAT, routes

RDS MySQL instance

ECS cluster + Fargate service + ALB (HTTP on :80, health check /health)

S3 bucket for frontend (static website hosting)

ECR repo for backend image

CodeBuild project + CodePipeline for app build/deploy

Needed IAM roles/policies and CloudWatch logs

To see key values:

terraform output


Look for:

alb_dns_name

frontend_bucket_name

frontend_website_endpoint

7. Wire frontend to deployed backend

Once ALB + ECS service are healthy:

Get ALB DNS:

From terraform output alb_dns_name, or

AWS Console → EC2 → Load Balancers → your ALB → DNS name

In frontend/index.html, update:

// const backendBase = 'http://localhost:8080';
const backendBase = 'http://<your-alb-dns-name>';
// e.g.
// const backendBase = 'http://aws-java-ecs-s3-demo-dev-alb-123456.us-east-1.elb.amazonaws.com';


Commit and push to main so CodePipeline picks it up.

8. App CI/CD (CodePipeline + CodeBuild)
What CodeBuild does

From the config in cicd-app.tf, a build run roughly:

Logs in to ECR

Builds the backend Docker image from backend/

Pushes image to the ECR repo

Forces ECS service to do a new deployment with the latest image

Syncs frontend/ to the frontend S3 bucket:

aws s3 sync frontend/ "s3://<frontend-bucket>" --delete


Result: one build = new backend image + new ECS deployment + updated frontend.

How CodePipeline works

Stages:

Source (GitHub via CodeStar Connection) – pulls code from main

BuildAndDeploy (CodeBuild) – runs the steps above

Trigger (currently manual)

Right now there is no Git auto-trigger; pipeline is started manually:

AWS Console → CodePipeline → aws-java-ecs-s3-demo-dev-app

Click Release change

Wait for Source and Build stages to succeed

9. Infra CI/CD (GitHub Actions)

Under .github/workflows:

On pull request (e.g. to main):

Run terraform fmt, terraform init, terraform plan for infra/env/dev

Attach plan output to the PR checks

On merge/push to main:

Run terraform apply for infra/env/dev

AWS auth uses GitHub→AWS OIDC, with secrets like:

AWS_ROLE_ARN

AWS_REGION

Note: app deployment (Docker + S3) is via CodePipeline/CodeBuild, not via these workflows.

10. Access the deployed app

After:

terraform apply is done

At least one successful CodePipeline run

You should have:

Backend health:

http://<alb-dns-name>/health


Returns OK.

Frontend website:

http://<frontend-bucket>.s3-website-<region>.amazonaws.com/


On the frontend:

Enter a name

Click Send

You should see Hello <name> from the backend.

11. Clean up

To avoid ongoing AWS costs:

cd infra/env/dev
terraform destroy


This removes:

VPC, subnets, gateways

ALB, ECS cluster/service

RDS instance

S3 buckets (frontend + artifacts)

ECR repo

IAM roles/policies

CodeBuild + CodePipeline

Any other dev resources created by this stack

12. Notes / limitations

TLS/HTTPS (ACM) is not configured; demo runs on plain HTTP.

Only dev is implemented; staging and prod folders are placeholders.