# DevOps Playground: AI News Portal 🚀

Welcome to the **DevOps Playground**, a complete end-to-end journey from frontend development to automated CI/CD and Infrastructure as Code. 

This repository serves as a hands-on tutorial for learning modern DevOps practices.

---

## 🏗️ Project Architecture
- **Frontend**: Static AI News Portal (HTML5/CSS3)
- **Containerization**: Docker (Nginx Alpine)
- **CI/CD**: GitHub Actions (Linting, Build, Security Scan)
- **Registry**: GitHub Container Registry (GHCR)
- **Infrastructure**: Kubernetes (Kind) managed by Terraform

---

## 📖 Step-by-Step Tutorial

### Step 1: Frontend Development
We built a premium, responsive **AI News Portal** featuring:
- **Glassmorphism UI**: Modern, translucent design.
- **Dark Mode**: Sleek tech aesthetic.
- **Dynamic Grid**: Company-specific card themes (Google, Microsoft, OpenAI).

Files: `Frontend/index.html`, `Frontend/style.css`

### Step 2: Containerization (Docker)
To make the application portable, we packaged it using a professional **Dockerfile**.
- **Base Image**: `nginx:alpine` (Tiny and secure).
- **Security Patching**: We learned to use `apk upgrade` during build to fix critical vulnerabilities (like CVE-2026-22184).

```dockerfile
FROM nginx:alpine
RUN apk update && apk upgrade --no-cache
COPY Frontend /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### Step 3: CI/CD Pipeline (GitHub Actions)
We automated the entire lifecycle in `.github/workflows/main.yml` with three key stages:

1. **Linting**: Using `htmlhint` to catch HTML syntax errors before they are built.
2. **Build & Push**:
   - **Authentication**: Used the built-in `${{ secrets.GITHUB_TOKEN }}`.
   - **Normalization**: Learned that Docker repository names **must be lowercase**, even if the GitHub repo name has capitals.
3. **Security Scan**: Using **Trivy** to scan the final image. We configured it with `exit-code: 1` to fail the build if any "Critical" or "High" bugs are found.

### Step 4: Infrastructure as Code (Terraform)
Instead of manually creating a Kubernetes cluster, we used **Terraform** to provision a **Kind** (Kubernetes in Docker) cluster locally on a Mac.

**Why Terraform?** It makes your infrastructure repeatable, documented, and version-controlled.

**Cluster Config (`terraform/main.tf`):**
- **Nodes**: 1 Control Plane + 1 Worker Node.
- **Port Mapping**: Mapped ports 80/443 from your laptop into the cluster nodes for external web access.

---

## 🛠️ Getting Started Locally

### 1. Build and Run via Docker
```bash
docker build -t ai-news-portal .
docker run -p 8080:80 ai-news-portal
```

### 2. Spinning up the K8s Infrastructure
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 3. Verify the Cluster
```bash
kubectl get nodes
kubectl cluster-info
```

---

## 🎓 DevOps Lessons Learned
- **The "uses" Keyword**: Learned that GitHub Actions are modular "Lego blocks" shared by the community.
- **Shift-Left Security**: We fixed a CRITICAL vulnerability in our pipeline before it ever left the develop branch.
- **Idempotency**: Terraform ensures that running the same command twice doesn't create two clusters—it only creates what's missing.

---

**Next Phase**: Deploying the AI News Portal *inside* our new Kind cluster using Kubernetes Manifests (Pods, Services, and Ingress)!
