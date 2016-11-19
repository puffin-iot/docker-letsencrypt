FROM nginx

RUN apt-get update && apt-get install -y git wget cron bc

RUN mkdir -p /letsencrypt/challenges/.well-known/acme-challenge
RUN git clone https://github.com/certbot/certbot /letsencrypt/app
WORKDIR /letsencrypt/app
RUN ./letsencrypt-auto; exit 0

# You should see "OK" if you go to http://<domain>/.well-known/acme-challenge/health

RUN echo "OK" > /letsencrypt/challenges/.well-known/acme-challenge/health

# Install kubectl
RUN wget https://storage.googleapis.com/kubernetes-release/release/v1.3.6/bin/linux/amd64/kubectl
RUN chmod +x kubectl
RUN mv kubectl /usr/local/bin/

# Add our nginx config for routing through to the challenge results
RUN rm /etc/nginx/conf.d/*.conf
ADD nginx/nginx.conf /etc/nginx/
ADD nginx/letsencrypt.conf /etc/nginx/conf.d/

# Install the cloudflare DNS hooks
RUN \
  apt-get install -yy python-dev python-pip libffi-dev bc curl jq && \
  git clone https://github.com/puffin-iot/dehydrated && cd dehydrated && mkdir hooks && \
  git clone https://github.com/puffin-iot/letsencrypt-cloudflare-hook hooks/cloudflare && \
  pip install -r hooks/cloudflare/requirements-python-2.txt

# Add some helper scripts for getting and saving scripts later
ADD fetch_certs.sh /letsencrypt/
ADD save_certs.sh /letsencrypt/
ADD recreate_pods.sh /letsencrypt/
ADD refresh_certs.sh /letsencrypt/
ADD refresh_certs_cloudflare.sh /letsencrypt/
ADD start.sh /letsencrypt/

ADD nginx/letsencrypt.conf /etc/nginx/snippets/letsencrypt.conf

RUN ln -s /root/.local/share/letsencrypt/bin/letsencrypt /usr/local/bin/letsencrypt

WORKDIR /letsencrypt

ENTRYPOINT ./start.sh
