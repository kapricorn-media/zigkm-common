# zig-common

Common Zig modules for Kapricorn Media.

## New Server Setup

### HTTPS (nginx & certbot)

1. `sudo apt install nginx certbot python3-certbot-nginx`
2. Create & set up `/etc/nginx/sites-available/<domain>`
3. `sudo ln -s /etc/nginx/sites-available/<domain> /etc/nginx/sites-enabled/<domain>`
4. `sudo systemctl restart nginx`
5. `sudo certbot --nginx -d <domain1> -d <domain2> ...`

### systemctl

1. Create & set up `/etc/systemd/system/<server>.service`
2. `sudo systemctl enable <server>`
3. `sudo systemctl start <server>`
