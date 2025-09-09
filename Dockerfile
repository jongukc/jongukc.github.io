FROM ubuntu:24.04 AS base

# Install prerequisites
RUN apt update \
    && apt install -y --no-install-recommends \
    sudo \
    make \
    python3 \
    python3-pip \
    pandoc \
    imagemagick \
    vim \
    apache2 \
    ca-certificates

RUN echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu

# Apache setting
RUN mkdir -p /var/run/apache2 /var/lock/apache2 /var/log/apache2
RUN chown -R ubuntu:ubuntu /var/run/apache2 /var/lock/apache2 /var/log/apache2
RUN printf 'Listen 0.0.0.0:11880\n' > /etc/apache2/ports.conf
RUN cat >/etc/apache2/sites-available/localhost-11880.conf <<'EOF'
<VirtualHost *:11880>
    ServerName localhost
    DocumentRoot "/home/ubuntu/workspace/site"

    <Directory "/home/ubuntu/workspace/site">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    AddDefaultCharset UTF-8
    AddType "text/plain; charset=UTF-8" .txt .log .cfg .conf .ini
    AddType "text/markdown; charset=UTF-8" .md
    AddType "text/csv; charset=UTF-8" .csv
    AddType "text/tab-separated-values; charset=UTF-8" .tsv
    AddType application/json .json .jsonl
    AddType image/webp .webp
    AddType image/avif .avif
    <FilesMatch "^[^.]+$">
        ForceType text/plain
    </FilesMatch>

    ErrorLog /var/log/apache2/localhost-11880_error.log
    CustomLog /var/log/apache2/localhost-11880_access.log combined
</VirtualHost>
EOF

RUN a2dissite 000-default \
    && a2ensite localhost-11880 \
    && a2enmod mime mime_magic \
    && a2enmod autoindex

RUN sed -i 's/APACHE_RUN_USER=www-data/APACHE_RUN_USER=ubuntu/g' /etc/apache2/envvars \
    && sed -i 's/APACHE_RUN_GROUP=www-data/APACHE_RUN_GROUP=ubuntu/g' /etc/apache2/envvars

# Set user
RUN su ubuntu
USER ubuntu:ubuntu
WORKDIR /home/ubuntu/workspace

# Run Apache
CMD ["sudo", "apache2ctl", "-D", "FOREGROUND"]
