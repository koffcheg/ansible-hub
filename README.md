# Ansible VPN Automation Hub

This repository provides a fully automated, production-grade system for managing VPN clients using OpenVPN, Ansible, and GCP Secret Manager. It supports full lifecycle operations: creation, rotation, deletion, and factory provisioning for Jetson or other factory clients.

---

## 📁 Directory Structure

```
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
│   ├── factory_pull.yaml
│   ├── update_and_install.yaml
│   ├── tasks/
│   │   ├── create_per_client.yaml
│   │   └── rotate_per_client.yaml
│   ├── templates/
│   │   └── install.sh.j2
├── roles/
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

---

## 💡 Tips

- Always pass vars using JSON (`-e '{"client_name": "client77"}'`)
- Use inventory in `inventory/production.ini` to define remote client connections
- Logs and extracted configs for factory stored in `~/factory_output/CLIENT_NAME`

---

## 🧠 License & Author

Production automation architecture designed by OpenAI ChatGPT (with Romek Wozniak).

MIT License.