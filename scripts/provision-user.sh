#!/bin/bash -e

# Create runner user

user=runner
useradd --home-dir "/home/$user" --create-home --gid docker --uid 1001 --groups adm,systemd-journal --shell /bin/bash "$user"
echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/runner
echo "RUNNER_USER=$user" | tee -a /etc/environment
user_id=$(id -u $user)
echo "d /run/user/$user_id 0700 $user $user" >> /tmp/1001-users.conf
systemd-tmpfiles --create /tmp/1001-users.conf
echo "XDG_RUNTIME_DIR=/run/user/$user_id" | tee -a /etc/environment
rm /tmp/1001-users.conf
