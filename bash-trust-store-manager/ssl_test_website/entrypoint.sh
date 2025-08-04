#!/bin/sh

# Start Python Flask application in background
python3 /usr/share/nginx/html/app.py &

# Start nginx in foreground
nginx -g 'daemon off;' 