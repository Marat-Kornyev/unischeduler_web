#!/bin/bash
# Must be logged in as non-root sudo user
sudo apt update
sudo apt install nginx python3 python3-pip python3-dev ufw git
# Configure firewall
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
pip3 install --user pipenv
cd ~
# # To use python packages from console
echo "PYTHON_BIN_PATH='$(python3 -m site --user-base)/bin'
PATH='$PATH:$PYTHON_BIN_PATH'" >> .bashrc 
# Source .bashrc won't work in a script

cd unischeduler_web
mkdir .venv # Sets pipenv to put everything in .venv
python3 -m pipenv install -e . # install from setup.py
cd ..
# gunicorn --preload means that we load our app before launching workers. This makes workers share multiprocessing locks
echo "[Unit]
Description=Gunicorn instance to serve unischeduler_web
After=network.target

[Service]
User=$USER
Group=www-data
WorkingDirectory=/home/$USER/unischeduler_web
Environment="PATH=/home/$USER/unischeduler_web/.venv/bin"
ExecStart=/home/$USER/unischeduler_web/.venv/bin/gunicorn --preload --workers 3 --bind unix:unischeduler_web.sock -m 007 wsgi:app

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/unischeduler_web.service # Create service to run app on startup
echo "server {
    listen 443 ssl;
    listen [::]:443 ssl;
    ssl_certificate /etc/letsencrypt/live/scheduler.oatmeal.cc/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/scheduler.oatmeal.cc/privkey.pem;
    server_name scheduler.oatmeal.cc;

    location / {
        include proxy_params;
        proxy_pass http://unix:/home/$USER/unischeduler_web/unischeduler_web.sock;
    }

}
server {
    listen 80;
    listen [::]:80;

    server_name scheduler.oatmeal.cc;

    return 302 https://$server_name$request_uri;
}" | sudo tee /etc/nginx/sites-available/unischeduler_web # Nginx will catch all requests and forward them to unischeduler_web
sudo ln -s /etc/nginx/sites-available/unischeduler_web /etc/nginx/sites-enabled
sudo rm /etc/nginx/sites-enabled/default
sudo systemctl start unischeduler_web
sudo systemctl enable unischeduler_web
sudo systemctl restart nginx
