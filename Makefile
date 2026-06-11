## Notes on variables and how they load
## := is eager loading and vars get interpreted on each make call
## = is lazy loading and only get called when used by a make subcommand
DATE := $(shell date +%FT%T%Z)
EXPECTED_CONTEXT := k3d-lab
CLUSTER_NAME := lab
ADMIN_PASSWORD = $$2a$$10$$fHMjO5gJhVg1fSU/lUwubO96tr4OiaKp9TdHTAjYm4z8eIfLNJOgK # admin
WEBHOOK_POD = $(shell kubectl -n argo-events get pod -l eventsource-name=webhook -o name)
WEBHOOK_MULTI = $(shell kubectl -n argo-events get pod -l eventsource-name=test-api-eventsource -o name)
CI_POD = $(shell kubectl -n ci get pod -l eventsource-name=webhook-deps-es -o name)
CI_POD_CACHE = $(shell kubectl -n ci-cache get pod -l eventsource-name=workflow-cache-es -o name)

#### CONTEXT GUARD ####
check-context:
	@[ "$$(kubectl config current-context)" = "$(EXPECTED_CONTEXT)" ] || \
	  (echo "ERROR: wrong context. Expected $(EXPECTED_CONTEXT), got $$(kubectl config current-context)" && exit 1)
	@echo "✓ Context verified: $$(kubectl config current-context)"

#### CLUSTER ####
build-cluster:
	kind create cluster --name $(CLUSTER_NAME) --config ./config/kind-cluster.yaml

build-k3d:
	k3d cluster create $(CLUSTER_NAME) --config ./config/k3d-cluster.yaml

build-cluster-self-signed:
	kind create cluster --name $(CLUSTER_NAME) --config ./config/kind-cluster-self-signed.yaml

build-k3d-self-signed:
	k3d cluster create $(CLUSTER_NAME) --config ./config/k3d-cluster-self-signed.yaml

delete-cluster: check-context
	@read -p "Delete cluster $(CLUSTER_NAME)? [y/N] " confirm && [ "$$confirm" = "y" ]
	kind delete cluster -n $(CLUSTER_NAME)

delete-k3d: check-context
	@read -p "Delete k3d cluster $(CLUSTER_NAME)? [y/N] " confirm && [ "$$confirm" = "y" ]
	k3d cluster delete $(CLUSTER_NAME)

#### TRUST CA ####
trust-ca:
	docker exec lab-control-plane bash -c "chmod 644 /usr/local/share/ca-certificates/corporate.crt && update-ca-certificates"
	docker exec lab-worker bash -c "chmod 644 /usr/local/share/ca-certificates/corporate.crt && update-ca-certificates"
	docker exec lab-worker2 bash -c "chmod 644 /usr/local/share/ca-certificates/corporate.crt && update-ca-certificates"

trust-ca-k3d:
	for node in k3d-lab-server-0 k3d-lab-agent-0 k3d-lab-agent-1; do \
		docker exec $$node sh -c "cat /usr/local/share/ca-certificates/corporate.crt >> /etc/ssl/certs/ca-certificates.crt"; \
	done

trust-ca-podman:
	podman exec lab-control-plane bash -c "chmod 644 /usr/local/share/ca-certificates/corporate.crt && update-ca-certificates"
	podman exec lab-worker bash -c "chmod 644 /usr/local/share/ca-certificates/corporate.crt && update-ca-certificates"
	podman exec lab-worker2 bash -c "chmod 644 /usr/local/share/ca-certificates/corporate.crt && update-ca-certificates"

trust-ca-k3d-podman:
	for node in k3d-lab-server-0 k3d-lab-agent-0 k3d-lab-agent-1; do \
		podman exec $$node sh -c "cat /usr/local/share/ca-certificates/corporate.crt >> /etc/ssl/certs/ca-certificates.crt"; \
	done

#### NAMESPACES ####
create-namespaces:
	kubectl create namespace argo
	kubectl create namespace argocd
	kubectl create namespace argo-events

#### FLUX ####
flux-up: create-namespace-flux install-flux install-flux-instance

create-namespace-flux:
	kubectl create namespace flux-system

install-flux:
	kubectl apply -f ./bootstrap/flux-operator/install.yaml -n flux-system

install-flux-instance:
	kubectl apply -f ./bootstrap/flux-operator/flux-instance.yaml -n flux-system

install-flux-git-repo:
	kubectl apply -f ./infra/sources/github-helm-source.yaml -n flux-system

flux-down: check-context
	@echo "Current context: $$(kubectl config current-context)"
	@read -p "Delete flux? [y/N] " confirm && [ "$$confirm" = "y" ]
	kubectl delete -f ./bootstrap/flux-operator/flux-instance.yaml -n flux-system || true
	kubectl delete -f ./bootstrap/flux-operator/install.yaml -n flux-system || true
	kubectl delete namespace flux-system || true

#### ARGOCD ####
argocd-2-10:
	kubectl apply -f ./bootstrap/argocd/install-2.10.yaml -n argocd

argocd-2-11:
	kubectl apply -f ./bootstrap/argocd/install-2.11.yaml -n argocd

argocd-patch-secret:
	kubectl patch secret argocd-secret -n argocd -p '{"stringData": {"admin.password": "$(ADMIN_PASSWORD)", "admin.passwordMtime": "$(DATE)"}}'

argocd-ui:
	kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=60s
	open /Applications/Google\ Chrome.app/ "https://0.0.0.0:30080/applications"

argocd-upgrade-2-10: argocd-2-10 argocd-patch-secret
argocd-upgrade-2-11: argocd-2-11 argocd-patch-secret

traefik:
	kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
	kubectl patch configmap argocd-cmd-params-cm -n argocd \
		--patch '{"data":{"server.basehref":"/","server.rootpath":"/","server.insecure":"true"}}'
	kubectl rollout restart deployment argocd-server -n argocd
	kubectl rollout status deployment argocd-server -n argocd
	kubectl apply -f config/argocd-traefik/traefik-updates.yaml

# run where traefik is port forwarded to:
hosts:
	grep -qF "argocd.localhost" /etc/hosts || echo "127.0.0.1 argocd.localhost" | sudo tee -a /etc/hosts
	grep -qF "dashboard.localhost" /etc/hosts || echo "127.0.0.1 dashboard.localhost" | sudo tee -a /etc/hosts

tunnel-stop:
	pkill -f "ssh -NfL 8080"

#### ARGO WORKFLOWS ####
argo-workflows:
	kubectl apply -f ./bootstrap/argo-workflows/install.yaml -n argo
	kubectl patch deployment argo-server --namespace argo --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": [ "server", "--auth-mode=server" ]}]'

argo-workflows-ui:
	kubectl wait --for=condition=available deployment/argo-server -n argo --timeout=60s
	open /Applications/Google\ Chrome.app/ "https://0.0.0.0:32746/workflows/undefined?&limit=50"

#### ARGO EVENTS ####
argo-events:
	kubectl apply -f ./bootstrap/argo-events/install.yaml -n argo-events
	kubectl apply -n argo-events -f ./bootstrap/argo-events/native.yaml
	kubectl apply -n argo-events -f ./bootstrap/argo-events/sensor-rbac.yaml
	kubectl apply -n argo-events -f ./bootstrap/argo-events/workflow-rbac.yaml

argocd-notifications:
	kubectl apply -n argocd -f ./bootstrap/argocd/notifications.yaml
	kubectl apply -n argocd -f ./bootstrap/argocd/triggers.yaml

#### INGRESS ####
ingress:
	kubectl apply -f ./bootstrap/ingress-nginx/deploy.yaml
	kubectl wait --namespace ingress-nginx \
	--for=condition=ready pod \
	--selector=app.kubernetes.io/component=controller \
	--timeout=90s

#### INFRA ####
metrics-server:
	kubectl apply -f ./infra/metrics-server/metrics-server.yaml

keda-install:
	kubectl apply -f ./infra/keda/keda.yaml

prometheus:
	kubectl apply -f ./infra/prometheus/prometheus.yaml
	kubectl wait --for=condition=available deployment/prometheus-server -n monitoring --timeout=60s
	kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &

grafana:
	kubectl apply -f ./infra/grafana/grafana.yaml
	kubectl wait --for=condition=available deployment/grafana -n monitoring --timeout=60s
	kubectl port-forward -n monitoring svc/grafana 3000:80 &

sealed-secrets:
	kubectl apply -f ./infra/sealed-secrets/sealed-secrets.yaml
	kubectl apply -f ./infra/sealed-secrets/sealed-secrets-web.yaml

eso-install:
	kubectl apply -f ./infra/eso/eso.yaml

eso-demo:
	kubectl apply -f ./infra/eso/eso-app.yaml

csi-driver:
	kubectl apply -f ./infra/csi-driver/csi-driver.yaml

csi-driver-aws:
	kubectl apply -f ./infra/csi-driver/aws-addon.yaml

localstack-apply:
	kubectl apply -f ./infra/localstack/localstack.yaml

localstack-portforward:
	kubectl -n localstack port-forward svc/localstack 4566:4566 &

ollama:
	kubectl apply -f ./infra/ollama/local-path.yaml
	kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
	kubectl apply -f ./infra/ollama/ollama.yaml

#### EXPERIMENTS ####
## Blue-Green Rollouts
rollout-infra:
	kubectl create ns argo-rollouts
	kubectl apply -f ./bootstrap/argo-rollouts/install.yaml

rollout-blue-green:
	kubectl apply -f ./experiments/blue-green/rollouts-blue-green.yaml

rollouts-watch:
	kubectl argo rollouts get rollout rollout-bluegreen -n blue-green --watch

rollout-deploy-yellow:
	kubectl argo rollouts set image rollout-bluegreen rollouts-demo=argoproj/rollouts-demo:yellow -n blue-green

rollout-svcs-active:
	kubectl port-forward svc/rollout-bluegreen-active -n blue-green 13001:80 &

rollout-svcs-preview:
	kubectl port-forward svc/rollout-bluegreen-preview -n blue-green 13002:80 &

rollouts-dashboard:
	kubectl argo rollouts dashboard -n blue-green
	open /Applications/Google\ Chrome.app/ "http://localhost:3100/rollouts"

rollout-promote:
	kubectl argo rollouts promote rollout-bluegreen -n blue-green

## CI
ci:
	kubectl apply -f ./experiments/ci/ci.yaml
	kubectl wait -n ci --for=condition=ready pod -l eventsource-name=webhook-deps-es
	kubectl -n ci port-forward $(CI_POD) 12000:12000 &

ci-cache:
	kubectl apply -f ./experiments/ci/ci-cache.yaml
	kubectl wait -n ci-cache --for=condition=ready pod -l eventsource-name=workflow-cache-es
	kubectl -n ci-cache port-forward $(CI_POD_CACHE) 12000:12000 &

test-ci:
	curl -d '{"repo": "https://github.com/golang/example.git", "sha": "40afcb705d05179afce97d51b6677e46b5b48bf5", "filename": "/go/bin/hello"}' -H "Content-Type: application/json" -X POST http://localhost:12000/ci

## Webhooks
webhook-tf:
	kubectl apply -n argo-events -f ./config/webhook-cm.yaml
	kubectl apply -n argo-events -f ./experiments/webhooks/webhook-tf-install.yaml
	kubectl wait -n argo-events --for=condition=ready pod -l eventsource-name=webhook
	kubectl -n argo-events port-forward $(WEBHOOK_POD) 12000:12000 &

webhook-demo:
	curl -d '{"vControl":"bitbucket.org","repoOwner":"instadevelopers", "repo": "n1-iac","sha": "6051b943b22b04f7fe92b64e0c7694ea4832d0b1"}' -H "Content-Type: application/json" -X POST http://localhost:12000/tf

curl-runner:
	kubectl apply -f ./experiments/webhooks/curl-runner.yaml
	kubectl apply -f ./experiments/webhooks/curl-workflow.yaml
	kubectl port-forward svc/workflow-cache-es-eventsource-svc -n curl-workflow 12000:80 &

curl-runner-test:
	curl -X POST http://0.0.0.0:12000/api-call -H "Content-Type: application/json" -d '{"api_url": "localhost","pr_number": "testing-1234","payload": {"message": "hello_there","recipient": "you_there"}}'

## RabbitMQ
rabbitmq-ns:
	kubectl create namespace rabbitmq

rabbitmq:
	kubectl apply -f ./experiments/rabbitmq/rabbitmq.yaml
	kubectl wait --for=condition=available deployment/rmq -n rabbitmq --timeout=60s
	kubectl port-forward -n rabbitmq svc/rmq-svc 5672:5672 &

rabbitmq-ui:
	kubectl wait --for=condition=available deployment/rmq -n rabbitmq --timeout=60s
	kubectl port-forward -n rabbitmq svc/rmq-svc 15672:15672 &
	open /Applications/Google\ Chrome.app/ "http://0.0.0.0:15672"

rabbitmq-send:
	./demo/rabbitMQ/sender/sender

rabbitmq-receive:
	./demo/rabbitMQ/receiver/receiver

## Uptime
uptime-build:
	kubectl apply -f ./experiments/uptime/uptime-kuma.yaml
	kubectl apply -f ./experiments/uptime/uptimeApp.yaml
	kubectl apply -f ./experiments/uptime/statusReport.yaml

## Multi-sensor
multi-sensor:
	kubectl apply -n argo-events -f ./bootstrap/argo-events/workflow-rbac.yaml
	kubectl apply -f ./experiments/argo-events/multi-sensor.yaml

multi-sensor-portforward:
	kubectl wait -n argo-events --for=condition=ready pod -l eventsource-name=test-api-eventsource
	kubectl -n argo-events port-forward $(WEBHOOK_MULTI) 12000:12000 &
	kubectl -n argo-events port-forward $(WEBHOOK_MULTI) 13000:13000 &
	kubectl -n argo-events port-forward $(WEBHOOK_MULTI) 14000:14000 &

#### INIT TARGETS ####
init: build-cluster create-namespaces argocd-2-10 argocd-patch-secret argo-workflows argo-events
init-basic: build-cluster create-namespaces argocd-2-10 argocd-patch-secret
init-self-signed-docker: build-cluster-self-signed trust-ca create-namespaces argocd-2-10 argocd-patch-secret argo-workflows argo-events
init-self-signed-podman: build-cluster-self-signed trust-ca-podman create-namespaces argocd-2-10 argocd-patch-secret argo-workflows argo-events
init-self-signed-k3d-podman: build-k3d-self-signed trust-ca-k3d-podman
init-self-signed-k3d-docker: build-k3d-self-signed trust-ca-k3d
init-k3d-podman: build-k3d trust-ca-k3d-podman
init-k3d-docker: build-k3d trust-ca-k3d
init-flux: build-k3d trust-ca-k3d flux-up
