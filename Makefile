# À lancer DANS la toolbox (docker compose run --rm toolbox).
SHELL   := /bin/bash
TF      := terraform -chdir=infra/terraform
PLAY    := cd infra/ansible && ansible-playbook
KEY     := $(HOME)/.ssh/cluster_key
SSH     := ssh -i $(KEY) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
SSHUSER ?= ubuntu
MASTER   = $(shell $(TF) output -raw master_public_ip 2>/dev/null)

.DEFAULT_GOAL := help
.PHONY: help check keys init plan up provision smoke fingerprint cluster ssh tunnel down

help: ## Liste des commandes
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

check: ## Vérifie les prérequis (identifiants GCP, tfvars)
	@test -f .secrets/gcp-adc.json || { echo "Manque .secrets/gcp-adc.json (voir README, étape 2)"; exit 1; }
	@test -f infra/terraform/terraform.tfvars || { echo "Manque infra/terraform/terraform.tfvars (copier terraform.tfvars.example)"; exit 1; }
	@echo "Prérequis OK"

keys: ## Génère la clé SSH du cluster (.secrets/id_ed25519), une seule fois
	@mkdir -p .secrets
	@test -f .secrets/id_ed25519 || ssh-keygen -q -t ed25519 -N "" -C cbench -f .secrets/id_ed25519
	@install -d -m 700 $(HOME)/.ssh && install -m 600 .secrets/id_ed25519 $(KEY)
	@echo "Clé prête : .secrets/id_ed25519"

init: ## terraform init
	$(TF) init

plan: check keys ## Affiche ce que Terraform va créer
	$(TF) plan

up: check keys ## Crée les VMs, le réseau et les disques
	$(TF) apply

provision: keys ## Installe et configure Hadoop, Spark, monitoring (idempotent)
	$(PLAY) site.yml

smoke: ## Vérifie HDFS, YARN, libs natives et tous les codecs
	$(PLAY) smoke.yml

fingerprint: ## Empreinte matérielle/logicielle du cluster (JSON)
	@$(SSH) $(SSHUSER)@$(MASTER) cluster-fingerprint

cluster: up provision smoke ## Tout en une commande : up + provision + smoke

ssh: ## Shell sur le master
	$(SSH) $(SSHUSER)@$(MASTER)

tunnel: ## UIs web en local (lancer la toolbox avec --service-ports)
	@echo "HDFS http://localhost:9870 | YARN http://localhost:8088 | Spark http://localhost:18080 | Prometheus http://localhost:9090 | Grafana http://localhost:3000"
	$(SSH) -N \
	  -L 0.0.0.0:9870:localhost:9870 -L 0.0.0.0:8088:localhost:8088 \
	  -L 0.0.0.0:18080:localhost:18080 -L 0.0.0.0:9090:localhost:9090 \
	  -L 0.0.0.0:3000:localhost:3000 $(SSHUSER)@$(MASTER)

down: ## DÉTRUIT le cluster (à faire après chaque session : on paie à l'heure)
	$(TF) destroy
