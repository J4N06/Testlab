#!/bin/bash
set -e

eval $(ssh-agent -s)
ssh-add /root/.ssh/id_ed25519
terraform apply "$@"
ssh-agent -k
