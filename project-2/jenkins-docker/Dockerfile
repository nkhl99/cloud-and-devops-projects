FROM jenkins/jenkins:lts

# Run everything as root (OK for local lab)
USER root

RUN apt-get update && \
    apt-get install -y docker.io git python3 python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*
