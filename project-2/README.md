## 0. What you already have

Repo layout (simplified):

```text
app/
  Dockerfile
  main.py
  requirements.txt   # contains: flask
manifest/
  deployment.yaml
  service.yaml
```

Your `deployment.yaml` already uses a placeholder tag: 

```yaml
containers:
- name: flask-app-cicd
  image: nikhil230/ci-cd:replaceImageTag
  ports:
  - containerPort: 5000
```

Service exposes it as NodePort on 8080 → 5000. 

---

## 1. Target CI flow (what we’re building)

**On each Jenkins build:**

1. Checkout repo
2. (Optional but recommended) run Python tests / basic checks
3. Run **SonarQube** analysis on code
4. Build Docker image:

   * `nikhil230/ci-cd:${BUILD_NUMBER}`
5. Push image to Docker Hub
6. Update `manifest/deployment.yaml` image tag to `nikhil230/ci-cd:${BUILD_NUMBER}`
7. Archive updated manifest for CD (ArgoCD/minikube later)

We’ll use:

* **Jenkins in Docker**
* **SonarQube in Docker (community edition)**
* Your host Docker to build/push images.

---

## 2. Start SonarQube (Docker, localhost)

On Ubuntu (with Docker installed):

```bash
# Create a Docker network for Jenkins + Sonar to talk easily
docker network create cicd-net

# Run SonarQube (community)
docker run -d --name sonarqube \
  --network cicd-net \
  -p 9000:9000 \
  sonarqube:community
```

Then open: `http://localhost:9000`

* Default login: `admin / admin`
* It will ask you to change password.
* Create a **new project** (we’ll wire it to Jenkins later).
* Generate a **User Token** (Administration → Security → Users → Tokens).
  Save it (we’ll put this in Jenkins credentials as `sonar-token` or similar).


---

## 3. Jenkins in Docker (with Docker CLI inside)

Create a folder, e.g. `~/jenkins-docker`, with this **Dockerfile**:

```Dockerfile
# Dockerfile.jenkins
FROM jenkins/jenkins:lts

USER root

# Install docker client so Jenkins can run `docker build`, `docker push`
RUN apt-get update && \
    apt-get install -y docker.io && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
```

Build and run:

```bash
cd ~/jenkins-docker
docker build -t my-jenkins .

docker run -d --name jenkins \
  --network cicd-net \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  my-jenkins
```

* Jenkins UI: `http://localhost:8080`
* Get initial admin password (inside container):

```bash
docker exec -it jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Install **Suggested plugins**.

---

## 4. Configure Jenkins (one-time setup)

### 4.1 Install plugins

In Jenkins UI:

* **Manage Jenkins → Plugins → Available**

  * Install:

    * *Pipeline*
    * *Git*
    * *SonarQube Scanner for Jenkins*

Restart if asked.

### 4.2 Add credentials

**Docker Hub credentials**

* Manage Jenkins → Credentials → System → Global credentials
* Add:

  * Kind: **Username with password**
  * ID: `dockerhub-creds`
  * Username: `nikhil230`
  * Password: `dckr_pat_oDvDWpwRnz6xEICGviNnkjykVQc`

**SonarQube token**

* Kind: **Secret text**
* ID: `sonarqube-token`
* Secret: squ_84e79d774accbc58667d58fd52f49e0e7a333c61

**github token** - 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

### 4.3 Configure SonarQube server in Jenkins

* Manage Jenkins → System

* Find **SonarQube servers**

  * Add server, e.g.:

    * Name: `local-sonar`
    * Server URL: `http://sonarqube:9000` (because they are on same Docker network `cicd-net`)
    * Server authentication token: select `sonarqube-token`

* Manage Jenkins → Tools → SonarQube Scanner

  * Add a scanner:

    * Name: `sonar-scanner`
    * Let Jenkins auto-install a version.

---

## 5. Add `sonar-project.properties` to your repo

At repo root, create **sonar-project.properties**:

```properties
sonar.projectKey=flask-cicd
sonar.projectName=flask-cicd
sonar.projectVersion=1.0

# Source code location
sonar.sources=app

# Python specifics
sonar.language=py
sonar.python.version=3
sonar.sourceEncoding=UTF-8
```

Later we can tune rules; this is enough to start.

---

## 6. Add Jenkinsfile to your repo (CI pipeline)

At the root of your repo, add a file named **Jenkinsfile**:

```groovy
pipeline {
    agent any

    environment {
        IMAGE_NAME = "nikhil230/ci-cd"
        DOCKERHUB_CREDS = credentials('dockerhub-creds')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install deps & basic checks') {
            steps {
                sh '''
                cd app
                python3 -m venv venv
                . venv/bin/activate
                pip install --upgrade pip
                pip install -r requirements.txt
                # TODO: add real tests here; for now just syntax check
                python -m py_compile main.py
                '''
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('local-sonar') {
                    sh '''
                    sonar-scanner \
                      -Dsonar.projectBaseDir=. \
                      -Dsonar.sources=app
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                cd app
                docker build -t ${IMAGE_NAME}:${BUILD_NUMBER} .
                '''
            }
        }

        stage('Push to Docker Hub') {
            steps {
                sh '''
                echo "${DOCKERHUB_CREDS_PSW}" | docker login -u "${DOCKERHUB_CREDS_USR}" --password-stdin
                docker push ${IMAGE_NAME}:${BUILD_NUMBER}
                docker logout
                '''
            }
        }

        stage('Update Kubernetes Manifest') {
            steps {
                sh '''
                # Replace placeholder tag in deployment.yaml
                sed -i "s/replaceImageTag/${BUILD_NUMBER}/g" manifest/deployment.yaml

                echo "Updated deployment.yaml:"
                cat manifest/deployment.yaml
                '''
            }
        }

        stage('Archive Manifests') {
            steps {
                archiveArtifacts artifacts: 'manifest/*.yaml', fingerprint: true
            }
        }
    }
}
```

Notes:

* Uses your placeholder `replaceImageTag` in `deployment.yaml` and replaces it with `${BUILD_NUMBER}`. 
* Builds Docker image from `app/Dockerfile` and pushes it to `nikhil230/ci-cd:${BUILD_NUMBER}`.
* Sonar stage uses the scanner we configured and the Sonar server `local-sonar`.

---

## 7. Create a Jenkins Pipeline job

In Jenkins UI:

1. **New Item → Pipeline**
2. Name: e.g. `flask-cicd-pipeline`
3. Pipeline → Definition: **Pipeline script from SCM**

   * SCM: Git
   * Repo URL: your Git repo (GitHub/GitLab/whatever)
   * Branch: `*/main` (or your branch)
4. Save.
5. Click **Build Now**.

If everything’s wired correctly, you should see stages:

* Checkout
* Install deps & basic checks
* SonarQube Analysis
* Build Docker Image
* Push to Docker Hub
* Update Kubernetes Manifest
* Archive Manifests

After a successful run:

* Docker Hub: `nikhil230/ci-cd:<build-number>` should exist.
* In Jenkins build page → **Artifacts**: updated `deployment.yaml` & `service.yaml` for use by ArgoCD/minikube.

---

## 8. What we can do next (after CI works once)

Once you confirm:

* Jenkins container + SonarQube up
* Pipeline runs end-to-end
* Image appears in Docker Hub
* Manifest updated

Then we’ll:

* Set up **minikube** + **ArgoCD** on your machine
* Point ArgoCD to your Git repo so that **CD** is fully GitOps (it will pull the updated manifest with the new image tag and sync).

