from flask import Flask, request, jsonify
import subprocess

app = Flask(__name__)

@app.route('/onboard', methods=['POST'])
def onboard():
    name = request.json.get('name')
    if not name:
        return jsonify({"error": "name required"}), 400
    result = subprocess.run(["ansible-playbook", "playbooks/handle_new_client.yaml", "-l", name])
    return jsonify({"status": "done", "code": result.returncode})

@app.route('/revoke', methods=['POST'])
def revoke():
    name = request.json.get('name')
    if not name:
        return jsonify({"error": "name required"}), 400
    result = subprocess.run(["ansible-playbook", "playbooks/revoke_client.yaml", "-l", name])
    return jsonify({"status": "revoked", "code": result.returncode})
