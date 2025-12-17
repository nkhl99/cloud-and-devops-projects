Nice, let’s wire the whole thing cleanly end-to-end 👇

I’ll give you:

* **All containers to run** (Jenkins + SonarQube)
* **Every credential/secret** to create (names + where)
* **Repo structure**
* **Final Jenkinsfile** (including GitHub commit & push)
* **sonar-project.properties**

---

## 1️⃣ Prerequisites on your Ubuntu machine

You already have **Docker** ✅
Also make sure you have:

```bash
docker --version
```

Create a Docker network for Jenkins + SonarQube:

```bash
docker network create cicd-net
```

---

## 2️⃣ Run SonarQube (Community Edition)

Use the `community` image as you prefer:

```bash
docker run -d --name sonarqube \
  --network cicd-net \
  -p 9000:9000 \
  sonarqube:community
```

Then open in browser: `http://localhost:9000`

* Login: `admin / admin`
* It will prompt you to change password → do that.

### 2.1 Create a Sonar token (secret)

Inside SonarQube:

1. Click your user icon (top right) → **My Account** → **Security** (or Tokens).
2. Generate a new token, name like: `jenkins-token`.
3. Copy the token string somewhere safe (you’ll use it in Jenkins).

We’ll call this **`sonarqube-token`** inside Jenkins.

---

## 3️⃣ Run Jenkins (with docker + git installed)

Create a folder for Jenkins image:

```bash
mkdir -p ~/jenkins-docker
cd ~/jenkins-docker
```

Create `Dockerfile` (or `Dockerfile.jenkins`) with:

```Dockerfile
FROM jenkins/jenkins:lts

USER root

# Install docker client and git in the Jenkins image
RUN apt-get update && \
    apt-get install -y docker.io git && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
```

Build the image:

```bash
docker build -t my-jenkins .
```

Run Jenkins:

```bash
docker run -d --name jenkins \
  --network cicd-net \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  my-jenkins
```

* `jenkins_home` = persistent Jenkins data
* `/var/run/docker.sock` = lets Jenkins use host Docker

Open Jenkins: `http://localhost:8080`

Get initial password:

```bash
docker exec -it jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Paste into browser, install **Suggested plugins**.

---

## 4️⃣ Jenkins: install required plugins

In Jenkins UI:

* **Manage Jenkins → Plugins → Available**

  * Install:

    * **Pipeline** (if not already)
    * **Git plugin**
    * **SonarQube Scanner for Jenkins**

Restart Jenkins if it asks.

---

## 5️⃣ Jenkins: create all credentials (secrets)

We need **3 secrets**:

1. Docker Hub credentials
2. SonarQube token
3. GitHub credentials (PAT)

Go to: **Manage Jenkins → Credentials → System → Global credentials (unrestricted)** → **Add Credentials**.

---

### 5.1 Docker Hub credentials

* **Kind**: `Username with password`
* **ID**: `dockerhub-creds`  ← **important, used in Jenkinsfile**
* **Username**: `nikhil230`
* **Password**: your Docker Hub password or access token

Save.

---

### 5.2 SonarQube token

* **Kind**: `Secret text`
* **ID**: `sonarqube-token`  ← used in Sonar server config
* **Secret**: `<token you generated in SonarQube>`

Save.

---

### 5.3 GitHub credentials (for pushing back to main)

1. In **GitHub**, create a **Personal Access Token** (PAT)

   * Permissions: `repo` (for your own repos, that’s enough).

2. In Jenkins, add:

* **Kind**: `Username with password`
* **ID**: `github-creds`  ← used in Jenkinsfile
* **Username**: your GitHub username (e.g. `nikhil230`)
* **Password**: the GitHub PAT

Save.

---

## 6️⃣ Jenkins: configure SonarQube server + scanner

### 6.1 SonarQube server

* **Manage Jenkins → System**
* Find **SonarQube servers**

  * Add:

    * Name: `local-sonar`
    * Server URL: `http://sonarqube:9000`
    * Server authentication token: choose `sonarqube-token`
* Tick “Environment variables” (if present) so `withSonarQubeEnv` works.
* Save.

### 6.2 SonarQube Scanner

* **Manage Jenkins → Tools**
* Under **SonarQube Scanner**:

  * Add a new installation:

    * Name: `sonar-scanner`
    * Check “Install automatically” (latest version is fine).
* Save.

---

## 7️⃣ Repo structure & project files

On your GitHub repo, structure should be like:

```text
your-repo/
  app/
    Dockerfile
    main.py
    requirements.txt
  manifest/
    deployment.yaml
    service.yaml
  sonar-project.properties
  Jenkinsfile
```

### 7.1 `sonar-project.properties` at repo root

Create this file at the root of your repo:

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

Commit & push it.

---

## 8️⃣ Final Jenkinsfile (complete CI + GitHub push)

Create **`Jenkinsfile`** at the repo root with this content:

```groovy
pipeline {
    agent any

    environment {
        IMAGE_NAME      = "nikhil230/ci-cd"
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

                # Basic syntax check for now
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
                # Update image tag in deployment.yaml
                sed -i "s/replaceImageTag/${BUILD_NUMBER}/g" manifest/deployment.yaml

                echo "Updated deployment.yaml:"
                cat manifest/deployment.yaml
                '''
            }
        }

        stage('Commit & Push Manifests') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-creds',
                                                  usernameVariable: 'GIT_USER',
                                                  passwordVariable: 'GIT_TOKEN')]) {
                    sh '''
                    # Configure Git identity for Jenkins
                    git config user.name "Jenkins CI"
                    git config user.email "jenkins@example.com"

                    # Show current status
                    git status

                    # Add only the changed manifest file
                    git add manifest/deployment.yaml || echo "Nothing to add"

                    # Commit changes if any
                    git commit -m "Update image tag to ${BUILD_NUMBER}" || echo "No changes to commit"

                    # Prepare repo URL with credentials for push
                    REPO_URL=$(git config --get remote.origin.url)

                    # Ensure it's HTTPS
                    if echo "$REPO_URL" | grep -q "^git@github.com"; then
                        echo "Remote is SSH; converting to HTTPS"
                        REPO_URL="https://github.com/${REPO_URL#*:}"
                    fi

                    REPO_URL_WITH_CREDS=${REPO_URL/https:\/\//https://$GIT_USER:$GIT_TOKEN@}

                    # Push to main branch
                    git push "$REPO_URL_WITH_CREDS" HEAD:main || echo "Push failed"
                    '''
                }
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

> Assumptions:
>
> * Your main branch is `main` (change `HEAD:main` to `HEAD:master` if needed).
> * Your GitHub remote is HTTPS (if it’s SSH, the script converts it to HTTPS).

Commit & push this Jenkinsfile to your repo.

---

## 9️⃣ Create Jenkins Pipeline job

In Jenkins UI:

1. **New Item → Pipeline**
2. Name: `flask-cicd-pipeline` (or any name)
3. Type: **Pipeline**
4. Under **Pipeline**:

   * Definition: **Pipeline script from SCM**
   * SCM: **Git**
   * Repository URL: `https://github.com/<your-user>/<your-repo>.git`
   * Credentials: (none) – repo is public
   * Branch: `*/main`
5. Save.

---

## 🔟 Run your first build

* Click your job → **Build Now**
* Watch the stages:

  * Checkout
  * Install deps & basic checks
  * SonarQube Analysis
  * Build Docker Image
  * Push to Docker Hub
  * Update Kubernetes Manifest
  * Commit & Push Manifests
  * Archive Manifests

After it finishes:

* Docker Hub should show `nikhil230/ci-cd:<build-number>`.
* GitHub:

  * `manifest/deployment.yaml` should now have `image: nikhil230/ci-cd:<build-number>`.
* SonarQube:

  * You should see project `flask-cicd` with analysis results.

---

If you want next, you can paste:

* A screenshot or copy of any Jenkins error log (if a stage fails),
  and I’ll debug just that stage with you. After CI is solid, we’ll move on to **ArgoCD + minikube** for CD.
