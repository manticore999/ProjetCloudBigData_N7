# Boîte à outils commune : les 4 membres utilisent EXACTEMENT les mêmes
# versions de Terraform et d'Ansible, quel que soit leur OS (Windows, macOS, Linux).
FROM python:3.13-slim

ARG TARGETARCH=amd64
ARG TERRAFORM_VERSION=1.17.2
ARG ANSIBLE_CORE_VERSION=2.22.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-client make curl unzip git jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Terraform (binaire officiel, empreinte SHA256 vérifiée)
RUN set -eux; \
    cd /tmp; \
    f="terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip"; \
    curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${f}"; \
    curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"; \
    grep " ${f}\$" "terraform_${TERRAFORM_VERSION}_SHA256SUMS" | sha256sum -c -; \
    unzip -q "${f}" terraform -d /usr/local/bin; \
    rm -f /tmp/terraform_*

# Ansible + collections
RUN pip install --no-cache-dir "ansible-core==${ANSIBLE_CORE_VERSION}"
COPY ansible-requirements.yml /tmp/ansible-requirements.yml
RUN ansible-galaxy collection install -r /tmp/ansible-requirements.yml -p /usr/share/ansible/collections

COPY entrypoint.sh /usr/local/bin/toolbox-entrypoint
RUN chmod +x /usr/local/bin/toolbox-entrypoint

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/toolbox-entrypoint"]
CMD ["bash"]
