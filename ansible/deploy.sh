#! /bin/sh

umask 0077

KEYFILE="/root/.id_ec"
VAULTPASS="/root/.vault_pass"
CONNECTION_TIMEOUT=120

echo "${VAULT_PASS}" > "${VAULTPASS}"
ansible-vault view --vault-password-file="${VAULTPASS}" ansible/id_ec_robot.secret > "${KEYFILE}"
chmod 0400 "${KEYFILE}"

python3 ansible/build_inventory.py --keyfile "${KEYFILE}" \
                                   --timeout "${CONNECTION_TIMEOUT}" \
                                   --eventlog "${GITHUB_EVENT_PATH}" > ansible/hosts.yml

export ANSIBLE_HOST_KEY_CHECKING="False"
export ANSIBLE_SSH_RETRIES=5
ansible-playbook --timeout="${CONNECTION_TIMEOUT}" \
                 --key-file "${KEYFILE}" \
                 --vault-password-file "${VAULTPASS}" \
                 --inventory ansible/hosts.yml \
                 --extra-vars "build_sha=${GITHUB_SHA}" \
                 ansible/deploy.yml
