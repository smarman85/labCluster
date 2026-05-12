---
marp: true
title: Argoproj
theme: uncover
paginate: true
size: 4K
class:
  - lead
  - invert

---
# Argo Ecosystem

## Tools used:
- ArgoCd
- Argo Workflows
- Argo Events
- Kind

---

## Usage:
This implements a basic kind cluster. Running `make init` will build a new kind cluster and install a base implementation of Argo Events, workflows, and CD. 

---
# Argo Worklows
> A open source container-native workflow engine
* Defines workflows where each step is a container
* Multi-step Directed Acyclic Graph (DAG)
* CNCF Graduated Project

---
## Why use Argo Workflows
![bg right](https://argoproj.github.io/static/6e944804f836bce176feffed44a8bf7e/a2f3f/workflows.avif)

* Most popular workflow execution engine for Kubernetes
* Light-weight and scaleable
* Designed for Containers
* Cloud Agnostic

---
## Argo Workflows Vs K8s Jobs

---
## Workflow

```YAML
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: hello-world-
  labels:
    workflows.argoproj.io/archive-strategy: "false"
  annotations:
    workflows.argoproj.io/description: |
      This is a simple hello world example.
spec:
  entrypoint: whalesay
  templates:
  - name: whalesay
    container:
      image: docker/whalesay:latest
      command: [cowsay]
      args: ["hello world"]
```

---

## Jobs

```YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
spec:
  template:
    spec:
      containers:
      - name: pi
        image: perl:5.34.0
        command: ["perl",  "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      restartPolicy: Never
  backoffLimit: 4

```

---
# Why use Workflows over Jobs?

* Argo Provides a higher level of abstraction
* Argo Allows for the coordination of multiple dependent steps

---
# Example Time: (Argo Workflows )

```SHELL
# Initialize Cluster:
# - install argocd, workflows, argo-events
$ make init 

# Bring up Argo Workflows UI (demo mode - no auth)
$ make argo-workflows-ui

# Deploy basic workflow example:
$ make demo-workflow
```

---

## Workflow DAG

```SHELL
# Deploy Dag Application:
$ make demo-dag
```

---

## Workflow Cron
### Similar to K8s CronJobs

```SHELL
# Deploy Cron App:
$ make demo-cron
```

---
## More examples:

* https://github.com/argoproj/argo-workflows/tree/main/examples

---

# Going Deeper in the Argo Ecosystem
### Arogo Events

---
# What is it and why do we need it?
![bg left](https://argoproj.github.io/static/5f6b445ccaaac8b3f883e81fe96107ef/a2f3f/events.avif)
* Event Driven workflow framework
* Allows us to trigger k8s objects from many different events

---
# Main Components

* Event Source 
	* Event to consume (AWS, Webhooks, GIT,...)
* Sensor - event dependencies and triggers
* Event Bus - Transport layer
* Trigger - workload to execute

---
# Demo Time - Webhook

```SHELL
# Apply the webhook demo
$ make demo-webhook

# Hit the webhook
$ make demo-webhook-run
```

---
# Using local podman images in kind
> [!NOTE]
> The following steps are specific to podman and use some experimental features
Save your tagged image to a tar.gz file and load it into your named kind cluster

---
```BASH
# show clusters:
kind get clusters
using podman due to KIND_EXPERIMENTAL_PROVIDER
enabling experimental podman provider
lab

# save image and pipe it into your cluster:
podman save localhost/jq-image:v1 -o jq-imagev1.tar && \
  kind load image-archive jq-imagev1.tar --name lab
```

---
> [!IMPORTANT]
> Now you should be able to use the exact tag in your local but you have to set
> the image pull policy to `Never` or `IfNotPresent`. This will keep the container
> runtime from trying to pull images from an outside source

ex container spec:
```YAML
  container:
    image: localhost/statusreport:latest
    imagePullPolicy: Never ### use local cached image
    command: ["/app/report"]
    args:
      - do
      - some
      - work
```

---
##  More examples:
[Argo workflows](https://github.com/argoproj/argo-workflows/blob/main/examples/cron-workflow.yaml)
[Argo events](https://github.com/argoproj/argo-events/tree/master/examples)

# kindSampleCluster


---
# Linux install Docker + Podman

```BASH
echo >> "nameserver 8.8.8.8" >> /etc/resolv.conf
```

```JSON
### Docker Only
# add 8.8.8.8 to the dns section in /etc/docker/daemon.json
# /etc/docker/daemon.json
{
  ...
  "dns": ["<corp_ip>", "<corp_ip>", "8.8.8.8"],
  ...
}
```

---
# Continued (PODMAN)

 Add 8.8.8.8 to /etc/containers/containers.conf
```TOML
# Corp self signed cert WSL + Linux (PODMAN)

## Add 8.8.8.8 to /etc/containers/containers.conf
```
```BASH
cat /etc/containers/containers.conf
[engine]
cgroup_manager = "systemd"

[network]
dns_servers = ["<corp_ip>","<corp_ip>", "8.8.8.8"]
```

---

### WSL chagne boot to systemd=true
```TOML
[boot]
systemd=true
```

restart wsl and podman and docker should run
