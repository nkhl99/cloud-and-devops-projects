# 🚀 CI Pipeline with Jenkins, SonarQube, Docker & GitHub

*End-to-End CI for a Python Flask Application*

This project implements a **complete CI pipeline** using:

* **Jenkins** (running in Docker)
* **SonarQube Community Edition** (running in Docker)
* **Docker Hub** for container images
* **GitHub** for source code & manifest repo
* **Python Flask app**
* **Kubernetes manifests** (deployment & service)

The pipeline:

1. Checks out source code from GitHub
2. Sets up Python virtual environment
3. Installs dependencies & runs syntax checks
4. Runs **SonarQube analysis**
5. Builds a Docker image with `${BUILD_NUMBER}` tag
6. Pushes it to Docker Hub
7. Updates Kubernetes deployment manifest with new tag
8. Commits & pushes updated manifest back to `main` branch
9. Archives updated manifests

---

# 📁 Project Structure

```
cloud-and-devops-projects/
 └── complete-cicd/
      ├── app/
      │    ├── Dockerfile
      │    ├── main.py
      │    └── requirements.txt
      ├── manifest/
      │    ├── deployment.yaml
      │    └── service.yaml
      ├── sonar-project.properties
      └── Jenkinsfile
```

---

# 🐳 Docker Infrastructure

## 1. Create a Docker Network

All CI services run in Docker, so a shared network is needed:

```bash
docker network create cicd-net
```

This allows containers to reach each other by container name
(e.g., `http://sonarqube:9000`).

---

## 2. Run SonarQube

```bash
docker run -d --name sonarqube \
  --network cicd-net \
  -p 9000:9000 \
  sonarqube:community
```

* Accessible on host: `http://localhost:9000`
* Accessible from Jenkins container: `http://sonarqube:9000`
  (because of Docker network DNS)

Create a user token in UI → **used by Jenkins** for authentication.

---

## 3. Build Custom Jenkins Image

Jenkins needs:

* docker CLI
* git
* python3 + venv
* sonar-scanner (installed by Jenkins itself)

Create Dockerfile:

```dockerfile
FROM jenkins/jenkins:lts

USER root

RUN apt-get update && \
    apt-get install -y docker.io git python3 python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
```

Build:

```bash
docker build -t my-jenkins .
```

---

## 4. Run Jenkins Container

```bash
docker run -d --name jenkins \
  --network cicd-net \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  my-jenkins
```

### Why these mounts?

* `jenkins_home`
  → persists Jenkins jobs, plugins, configs, credentials

* `/var/run/docker.sock`
  → lets Jenkins container control the **host** Docker engine
  → enables `docker build`, `docker push` inside Jenkins pipeline

---

# 🔐 Credentials Setup in Jenkins

---

## 1. Docker Hub Credentials (`dockerhub-creds`)

`Manage Jenkins → Credentials → Global → Add Credentials`

* Kind: **Username with password**
* ID: `dockerhub-creds`
* Username: `<dockerhub_username>`
* Password: `<dockerhub_password_or_token>`

Used for:

```groovy
docker login -u $DOCKER_USER --password-stdin
```

---

## 2. GitHub Credentials (`github-creds`)

Create GitHub **PAT (Personal Access Token)** with `repo` scope.

In Jenkins:

* Kind: Username with password
* ID: `github-creds`
* Username: GitHub username
* Password: GitHub PAT

Used for committing manifests back to repo.

---

## 3. SonarQube Token (`sonarqube-token`)

In SonarQube UI:

* Go to top-right profile → Security → Generate Token

In Jenkins:

* Kind: Secret text
* ID: `sonarqube-token`

---

# 🔧 SonarQube Configuration in Jenkins

---

## 1. SonarQube Server Config

`Manage Jenkins → System → SonarQube Servers`

Create:

* Name: `local-sonar`
* Server URL: `http://sonarqube:9000`

  > **NOT** localhost (localhost inside Jenkins container ≠ host machine)
* Authentication Token: `sonarqube-token`

This enables:

```groovy
withSonarQubeEnv('local-sonar')
```

Which injects:

* `SONAR_HOST_URL=http://sonarqube:9000`
* `SONAR_AUTH_TOKEN=<token>`

so the scanner can communicate with the SonarQube container.

---

## 2. Sonar Scanner Installation

`Manage Jenkins → Tools → SonarQube Scanner`

Add:

* Name: `sonar-scanner`
* Install automatically: YES

In the pipeline:

```groovy
${tool 'sonar-scanner'}/bin/sonar-scanner
```

This runs the installed scanner binary.

---

## 3. Sonar Project Config File

`sonar-project.properties`:

```properties
sonar.projectKey=flask-cicd
sonar.projectName=flask-cicd
sonar.sources=app
sonar.python.version=3
sonar.sourceEncoding=UTF-8
```

Tells scanner:

* which project to upload under
* where the source code lives
* what language to use

---

# 🚀 Jenkins Pipeline (Jenkinsfile) Explained

### 📌 Stage 1 – Checkout

```groovy
checkout scm
```

Pulls project from GitHub main.

---

### 📌 Stage 2 – Python Setup & Syntax Check

```groovy
python3 -m venv venv
pip install -r requirements.txt
python -m py_compile main.py
```

Catches syntax errors early.

---

### 📌 Stage 3 – SonarQube Analysis

Uses:

```groovy
withSonarQubeEnv('local-sonar')
${tool 'sonar-scanner'}/bin/sonar-scanner
```

* Reads `sonar-project.properties`
* Analyzes source code under `app/`
* Uploads results to SonarQube

---

### 📌 Stage 4 – Docker Build

```groovy
docker build -t nikhil230/ci-cd:${BUILD_NUMBER} .
```

Creates versioned image using Jenkins build number.

---

### 📌 Stage 5 – Docker Push

Logs in using credentials and pushes:

```text
docker.io/nikhil230/ci-cd:<BUILD_NUMBER>
```

---

### 📌 Stage 6 – Update Kubernetes Manifest

`sed` replaces placeholder:

```yaml
image: nikhil230/ci-cd:replaceImageTag
```

with:

```yaml
image: nikhil230/ci-cd:<BUILD_NUMBER>
```

---

### 📌 Stage 7 – Commit & Push Back to GitHub

```groovy
git add complete-cicd/manifest/deployment.yaml
git commit -m "Update image tag to ${BUILD_NUMBER}"
git push https://$GIT_USER:$GIT_TOKEN@github.com/... HEAD:main
```

This keeps the manifest always up-to-date.

---

### 📌 Stage 8 – Archive Manifests

Store the updated manifest as a Jenkins artifact.

---

# ⭐ Why `http://sonarqube:9000` Works Instead of `localhost:9000`

Simple:

* Jenkins runs **inside a container**
* SonarQube runs **inside a different container**

So from Jenkins:

| Address          | Meaning                          |
| ---------------- | -------------------------------- |
| `localhost:9000` | Jenkins container itself (wrong) |
| `sonarqube:9000` | SonarQube container (correct)    |

Because both are on the same network → Docker DNS maps `sonarqube` → SonarQube container IP.

---

# 🎉 Final Result

What you now have:

* Fully automated CI pipeline
* Automated Docker builds
* Automated code scanning with SonarQube
* Automatic manifest update & Git push
* Container-based Jenkins & SonarQube
* Clean separation of concerns
* High-quality DevOps practice for real-world workloads

---


# 🧠 CD Pipeline (ArgoCD + Minikube)

## 1️⃣ Start Minikube

```bash
minikube start --driver=docker
kubectl get nodes
```

---

## 2️⃣ Install ArgoCD

```bash
kubectl create namespace agcd
kubectl apply -n agcd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

## 3️⃣ Expose ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n agcd 8081:443
```

Open: **[https://localhost:8081](https://localhost:8081)**

Get initial password:

```bash
kubectl -n agcd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

---

## 4️⃣ Fix ArgoCD RBAC (minikube convenience)

```bash
kubectl create clusterrolebinding argocd-application-controller-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=agcd:argocd-application-controller
```

This allows ArgoCD to read cluster resources.

---

## 5️⃣ Kustomization for Manifests

`manifest/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default

commonAnnotations:
  owner: Nikhil-Kumar

resources:
- deployment.yaml
- service.yaml
```

ArgoCD will automatically detect and use Kustomize.

---

## 6️⃣ ArgoCD Application (GitOps)

`flask-cicd-application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: flask-cicd
  namespace: agcd
spec:
  project: default

  source:
    repoURL: https://github.com/nkhl99/cloud-and-devops-projects.git
    targetRevision: main
    path: complete-cicd/argocd-application

  destination:
    server: https://kubernetes.default.svc
    namespace: default

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Apply:

```bash
kubectl apply -f flask-cicd-application.yaml
```

ArgoCD will now:

* Watch GitHub repo
* Automatically detect new image tag commits
* Auto-sync & deploy to Minikube

---

# 🔍 Verify Deployment

```bash
kubectl get deployment
kubectl get svc
```

To access service via NodePort:

```bash
minikube service flask-app-service --url
```

You’ll get something like:

```
http://127.0.0.1:64239
```

To access via port-forward:

```bash
kubectl port-forward svc/flask-app-service 8082:8080
```

Visit:

> [http://localhost:8082](http://localhost:8082)

---

# 🎉 Full GitOps Flow (End-to-End)

1. Developer pushes code → GitHub
2. Jenkins pipeline starts
3. SonarQube static analysis
4. Build & push Docker image: `ci-cd:BUILD_NUMBER`
5. Update manifest image tag
6. Commit & push manifest to GitHub
7. ArgoCD detects commit
8. ArgoCD syncs to Minikube
9. Minikube rolls out new deployment
10. App accessible instantly

---

# 🏁 Final Result

You now have:

* Fully automated CI/CD using **GitHub → Jenkins → Docker Hub → ArgoCD → Minikube**
* Zero-click CD thanks to **ArgoCD auto-sync**
* Clean manifest management using **Kustomize**
* Code quality enforced by **SonarQube**
* Real GitOps: the **Git repo *is* the source of truth**

This is a **professional-grade workflow**, identical to real enterprise DevOps pipelines.
