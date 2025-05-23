# zig-common

Common Zig modules for Kapricorn Media.

## New Server Setup

### HTTPS (nginx & certbot)

1. `sudo apt install nginx certbot python3-certbot-nginx`
2. Create & set up `/etc/nginx/sites-available/<domain>`
    - Make sure you use `<domain>` as the file name here, so `certbot` can pick it out.
4. `sudo ln -s /etc/nginx/sites-available/<domain> /etc/nginx/sites-enabled/<domain>`
5. `sudo systemctl restart nginx`
6. `sudo certbot --nginx -d <domain> -d <domain2> ...`
    - Use `<domain>` as the first one to match the nginx config. You can follow up with additional ones (e.g. `-d example.com -d www.example.com -d api.example.com`).

nginx starter config file
```
server {
    listen 80;
    server_name <domain> <domain2> ...;

    location / {
        proxy_pass http://localhost:<port>;
        proxy_set_header Host $host;
    }
}
```

### systemctl

1. Create & set up `/etc/systemd/system/<server>.service`
2. `sudo systemctl enable <server>`
3. `sudo systemctl start <server>`

systemctl starter config file
```
[Unit]
Description=<description>
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
WorkingDirectory=<workdir>
ExecStart=<cmd>

[Install]
WantedBy=multi-user.target
```

### Upgrades from GitHub artifacts

Make sure the names of the deployed repo, systemctl service, and the "install" directory in the server machine all match. If so, use the [upgrade.sh](./scripts/upgrade.sh) script.
