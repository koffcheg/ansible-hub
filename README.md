# Ansible VPN Automation Hub

This repository provides a fully automated, production-grade system for managing VPN clients using OpenVPN, Ansible, and GCP Secret Manager. It supports full lifecycle operations: creation, rotation, deletion, and factory provisioning for Jetson or other factory clients.

Get to the dir: 

```bash
sudo -i -u koffcheg

cd ansible-hub
```

Enter a virtual environment:

```bash
source ~/.ansible-venv/bin/activate
```

Verify SSH connectivity to all hosts defined in your inventory:

```bash
ansible -i inventory/production.ini all -m ping
```

---

## 📁 Directory Structure

```text
.
├── ansible.cfg
├── collections/
│   └── requirements.yaml
├── group_vars/
│   ├── all.yaml
│   └── vpn/clients_index.yaml
├── inventory/
│   └── production.ini
├── playbooks/
│   ├── create_and_upload.yaml
│   ├── delete_clients.yaml
│   ├── deploy_aip.yaml
│   ├── factory_pull.yaml
│   ├── jetson_bootstrap.yaml
│   ├── monitoring_sync_jetsons.yaml
│   ├── sync_aip.yaml
│   ├── update_and_install.yaml
│   ├── tasks/
│   │   ├── create_per_client.yaml
│   │   └── rotate_per_client.yaml
│   └── templates/
│       └── install.sh.j2
├── roles/
│   ├── aip_content_sync/
│   ├── aip_local_kit_deploy/
│   ├── jetson_aip_prereqs/
│   ├── jetson_base/
│   ├── jetson_docker/
│   ├── monitoring_prometheus_config/
│   ├── vpn_cert/
│   │   ├── tasks/
│   │   │   ├── create.yaml
│   │   │   ├── revoke_pending.yaml
│   │   │   └── rotate.yaml
│   │   ├── templates/
│   │   │   └── base_client.conf.j2
│   │   └── files/
│   │       └── dns-hooks.sh
│   └── vpn_client/
│       └── tasks/
│           ├── delete.yaml
│           ├── download.yaml
│           ├── install_remote.yaml
│           ├── mark_installed.yaml
│           ├── read_meta.yaml
│           ├── upload.yaml
│           └── write_meta.yaml
├── tasks/
│   ├── activate_gcp_account.yaml
│   └── load_controller_vars.yaml
└── README.md
```

---

## 🚀 Main Playbooks

All playbooks are run from the repository root and target the inventory in `inventory/production.ini.` Replace the sample client names with your actual client identifiers.

### 1. `create_and_upload.yaml`

Creates a new client cert, uploads it to GCP Secret Manager.

```bash
ansible-playbook playbooks/create_and_upload.yaml -e "client_names=['client66','client67']"
```

### 2. `update_and_install.yaml`

Rotates cert, bumps version, uploads archive, and installs remotely.

```bash
ansible-playbook playbooks/update_and_install.yaml -e "client_names=['client66','client67']"
```

### 3. `delete_clients.yaml`

Deletes a client’s certs, metadata, and remote installation.

```bash
ansible-playbook playbooks/delete_clients.yaml -e "client_names=['client66','client67']"
```

### 4. `factory_pull.yaml`

Pulls the config from GCP, unpacks it, renders install.sh, and places it in USB-friendly structure.

```bash
ansible-playbook playbooks/factory_pull.yaml -e '{"client_name": "client77"}'
```

### 5. `monitoring_sync_jetsons.yaml`

Keeps the Prometheus scrape configuration on the monitoring server in sync with Jetson VPN clients defined in `group_vars/vpn/clients_index.yaml`.

- Regenerates `/etc/prometheus/prometheus.yml` via the `monitoring_prometheus` role
- Updates `nvidia_jetson`, `docker` (cAdvisor), and `mqtt` jobs for all Jetson IPs
- Can be safely dry-run before applying

Example usage:

```bash
# dry run
ansible-playbook -i inventory/production.ini playbooks/monitoring_sync_jetsons.yaml --check --diff

# apply
ansible-playbook -i inventory/production.ini playbooks/monitoring_sync_jetsons.yaml
```

### 6. `deploy_aip.yaml`

Deploys the AIP kit to clients. This playbook runs the aip_local_kit_deploy role on all hosts in the clients group with privilege escalation enabled

Example usage:

```bash
ansible-playbook -i inventory/production.ini playbooks/deploy_aip.yaml -l client51 -e "aip_kit_archive=aip-ecopod-2025.11.27-v1.0.1.tar.zst" -e "aip_store_id=115"
```

### 7. `sync_aip.yaml`

Synchronizes AIP content across clients. Facts gathering is disabled for speed, and the playbook simply invokes the aip_content_sync role on the clients group

Example usage:

```bash
ansible-playbook -i inventory/production.ini playbooks/aip_content_sync.yaml -l client51 -e "bundle_id=global-settings-v1
```

### 8. `jetson_bootstrap.yaml`

Bootstraps a Jetson client with the base environment, Docker engine and AIP prerequisites. This is a lightweight full provision for new Jetson eco‑boutique deployments: it applies the roles jetson_base, jetson_docker and jetson_aip_prereqs with privilege escalation

Example usage:

```bash
ansible-playbook -i inventory/production.ini playbooks/jetson_bootstrap.yaml -l client51
```

---

## ⚙️ Requirements

- Python 3.10+
- Ansible 2.15+
- `gcloud` CLI authenticated
- GCP project with Secret Manager enabled
- SSH access to VPN clients

Install Ansible requirements:

```bash
ansible-galaxy collection install -r collections/requirements.yaml
```

---

## 📦 Variable Config

Edit in `group_vars/all.yaml`:

```yaml
gcp_project_id: your-gcp-project
gcp_service_account: ansible-secret-manager@your-project.iam.gserviceaccount.com
gcp_credentials_file: /home/youruser/your-sa-key.json
```

Jetson VPN client IPs are defined centrally in:

```yaml
# group_vars/vpn/clients_index.yaml
clients:
  client1: 10.9.0.30
  client2: 10.9.0.31
  # ...
```

This list is used by both VPN lifecycle playbooks and the Prometheus monitoring sync.

---

## 💡 Tips

- Always pass vars using JSON (`-e '{"client_name": "client77"}'`)
- Use inventory in `inventory/production.ini` to define remote client connections
- You can dry‑run dangerous changes with `--check --diff` before applying.