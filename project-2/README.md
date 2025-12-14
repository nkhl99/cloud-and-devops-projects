- install docker
- install jenkins as container
docker run -d \
  --name jenkins \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts

Let’s break this line by line.

🔹 docker run -d

Starts a container

-d = detached (runs in background)

🔹 --name jenkins

Container name = jenkins

Easier than using container ID

🔹 -p 8080:8080

Host port 8080 → Jenkins web UI

Access: http://VM-IP:8080

🔹 -p 50000:50000

Used for Jenkins agents

Safe to expose, common default

🔹 -v jenkins_home:/var/jenkins_home

Persistent Jenkins data:

jobs

plugins

configs

Without this → data lost on restart

🔹 -v /var/run/docker.sock:/var/run/docker.sock ⭐ MOST IMPORTANT

This is the key.

Mounts host Docker socket into Jenkins container

Jenkins uses host’s Docker daemon

Jenkins container itself does NOT run Docker daemon

👉 This is Docker-outside-of-Docker (DooD)

🔹 jenkins/jenkins:lts

Official Jenkins LTS image

Stable, recommended


“What does mounting docker.sock do?”

Answer:

“It allows the Jenkins container to communicate with the host Docker daemon, enabling it to build and push images without running a Docker daemon inside the container.”

sonarqube

docker run -d \
  --name sonarqube \
  -p 9000:9000 \
  sonarqube:lts
