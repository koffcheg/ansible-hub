from flask import Flask, request, jsonify
import subprocess
import os

app = Flask(__name__)

def run_playbook(playbook, extra_vars=None):
    cmd = ["ansible-playbook", f"playbooks/{playbook}.yaml"]
    if extra_vars:
        for key, value in extra_vars.items():
            cmd += ["-e", f"{key}={value}"]
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return result.stdout

@app.route("/onboard", methods=["POST"])
def onboard():
    data = request.json
    name = data["name"]
    return run_playbook("handle_new_client", {"name": name})

@app.route("/rotate", methods=["POST"])
def rotate():
    data = request.json
    name = data["name"]
    return run_playbook("rotate_cert", {"name": name})

@app.route("/delete", methods=["POST"])
def delete():
    data = request.json
    name = data["name"]
    return run_playbook("delete_clients", {"name": name})

@app.route("/install", methods=["POST"])
def install():
    data = request.json
    name = data["name"]
    return run_playbook("install_clients", {"name": name})

@app.route("/factory-usb", methods=["POST"])
def factory_usb():
    data = request.json
    name = data["name"]
    return run_playbook("factory_usb", {"name": name})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
