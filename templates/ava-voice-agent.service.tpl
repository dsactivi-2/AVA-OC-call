[Unit]
Description=AVA AI Voice Agent
After=network.target

[Service]
Type=simple
User=ava
WorkingDirectory=/opt/ava
EnvironmentFile=/opt/ava/.env
ExecStart=/opt/ava/venv/bin/python /opt/ava/main.py --config /opt/ava/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
