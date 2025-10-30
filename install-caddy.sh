#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "Need sudo or root user"
	exit 1
fi

if [[ $# -ne 1 ]]; then
	echo "Usage: $0 <domain_or_addr:port>"
	exit 1
fi

CADDY_PATH="/opt/caddy"
CADDYFILE_PATH="$CADDY_PATH/Caddyfile"
SITE="$1"

mkdir -p "$CADDY_PATH" /var/www/public

if [[ ! -f "$CADDY_PATH/caddy" ]]; then
	curl -f --output "$CADDY_PATH/caddy" 'https://caddyserver.com/api/download?os=linux&arch=amd64&idempotency=94716010224341'
	chmod +x "$CADDY_PATH/caddy"
fi

if [[ ! -f "$CADDYFILE_PATH" ]]; then
	cat >"$CADDYFILE_PATH" <<EOF
$SITE {
    root * /var/www/public
    encode zstd gzip
    file_server
}
EOF
fi

if ! id "caddy" &>/dev/null; then
	# Caddy 会使用它的HOME目录进行ACME，所以让HOME目录直接使用它的目录即可
	useradd --system --home-dir $CADDY_PATH --shell /usr/sbin/nologin caddy
	chown -R caddy:caddy $CADDY_PATH
fi

if [[ ! -f "/etc/systemd/system/caddy.service" ]]; then
	cat >/etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy HTTP(S) Service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$CADDY_PATH/caddy start --config $CADDYFILE_PATH
ExecReload=$CADDY_PATH/caddy reload --config $CADDYFILE_PATH
ExecStop=$CADDY_PATH/caddy stop

Restart=always
RestartSec=5s

User=caddy
Group=caddy
WorkingDirectory=$CADDY_PATH

ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

NoNewPrivileges=true
# 还是需要绑定80和443的
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

ReadWritePaths=/var/www/public $CADDY_PATH /run

ProtectClock=true
ProtectHostname=true

[Install]
WantedBy=multi-user.target

EOF
fi
