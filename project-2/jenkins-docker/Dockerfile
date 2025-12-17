FROM jenkins/jenkins:lts

USER root

# Install docker client and git in the Jenkins image
RUN apt-get update && \
    apt-get install -y docker.io git python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
