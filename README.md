# zig-common

Common Zig modules for Kapricorn Media.

## New Server Setup

### HTTPS (nginx & certbot)

1. `sudo apt install nginx certbot python3-certbot-nginx`
2. Create & set up `/etc/nginx/sites-available/<domain>`
3. `sudo ln -s /etc/nginx/sites-available/<domain> /etc/nginx/sites-enabled/<domain>`
4. `sudo systemctl restart nginx`
5. `sudo certbot --nginx -d <domain1> -d <domain2> ...`

nginx starter config file
```
server {
    listen 80;
    server_name <domain1> <domain2> ...;

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
