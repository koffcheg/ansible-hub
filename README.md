# Ansible Hub: VPN Client Automation

## 📦 Overview

This repository provides a centralized automation system to:
- Onboard new OpenVPN clients with automatic cert generation
- Sync configs securely to Google Secret Manager
- Install `.ovpn` configs remotely onto clients
- Rotate or revoke client access on demand
- Trigger flows using a REST API (Flask-based)
- Optionally prepare factory USB payloads

## 📁 Structure

```
ansible-hub/
├── playbooks/
│   ├── handle_new_client.yaml
│   ├── rotate_cert.yaml
│   ├── revoke_client.yaml
│   ├── delete_clients.yaml
│   ├── upload_clients.yaml
│   ├── install_clients.yaml
│   └── factory_usb.yaml
├── roles/
│   ├── vpn_cert/         # Handles cert generation, rotation, revocation
│   ├── vpn_client/       # Handles upload, download, install, delete
│   ├── gcp_secret_sync/  # Uploads secrets to GCP Secret Manager
│   └── factory_usb/      # Creates USB provisioning payloads
├── rest_gateway/
│   ├── app.py            # Flask API
│   ├── requirements.txt
│   └── docker-compose.yaml
└── group_vars/
    └── all.yaml          # GCP project, region, etc.
```

## 🚀 Usage

### 🔧 Run REST Gateway

```bash
cd rest_gateway
docker-compose up --build
```

### 🌐 API Endpoints

| Method | URL              | Action                 |
|--------|------------------|------------------------|
| POST   | `/onboard`       | Onboard new client     |
| POST   | `/rotate`        | Rotate client cert     |
| POST   | `/delete`        | Revoke client cert     |
| POST   | `/install`       | Install config remotely|
| POST   | `/factory-usb`   | Prepare USB payload    |

Body (JSON):
```json
{ "name": "client22" }
```

## 🔐 GCP Setup

Ensure the VM running this repo has Secret Manager access scope enabled. Auth via:

```bash
gcloud auth login
gcloud config set project your-project-id
```

## 📊 Monitoring

Use Prometheus/Grafana to monitor client tunnel uptime and ping metrics separately.

---

© 2025 Ansible Hub Automation | Powered by OpenVPN, Ansible, and GCP