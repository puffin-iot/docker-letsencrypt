#!/bin/bash

# Add a cron line with details of the current user etc
minute=$(echo $RANDOM % 60 | bc)
hour=$(echo $RANDOM % 23 | bc)
# day=$(echo $RANDOM % 27 + 1 | bc)
day=*

CRON_FREQUENCY=${CRON_FREQUENCY:-"$minute $hour $day * *"}
NAMESPACE=${NAMESPACE:-default}
DEHYDRATED=app/dehydrated

if [ -n "${CF_KEY}" ]; then
  SCRIPT=refresh_certs_cloudflare.sh
else
  SCRIPT=refresh_certs.sh
fi

echo "Configuring cron..."
echo "DOMAINS: " $DOMAINS
echo "EMAIL: " $EMAIL
echo "DEPLOYMENTS: " $DEPLOYMENTS
echo "NAMESPACE: " $NAMESPACE
echo "SECRET_NAME: " $SECRET_NAME
echo "CRON frequency: " $CRON_FREQUENCY
# Once a month, fetch and save certs + restart pods.

# The process running under cron needs to know where the to find the kubernetes api
env_vars="PATH=$PATH KUBERNETES_PORT=$KUBERNETES_PORT KUBERNETES_PORT_443_TCP_PORT=$KUBERNETES_PORT_443_TCP_PORT KUBERNETES_SERVICE_PORT=$KUBERNETES_SERVICE_PORT KUBERNETES_SERVICE_HOST=$KUBERNETES_SERVICE_HOST KUBERNETES_PORT_443_TCP_PROTO=$KUBERNETES_PORT_443_TCP_PROTO KUBERNETES_PORT_443_TCP_ADDR=$KUBERNETES_PORT_443_TCP_ADDR KUBERNETES_PORT_443_TCP=$KUBERNETES_PORT_443_TCP"

line="$CRON_FREQUENCY $env_vars SECRET_NAME=$SECRET_NAME NAMESPACE=$NAMESPACE DEPLOYMENTS='$DEPLOYMENTS' DOMAINS='$DOMAINS' EMAIL=$EMAIL /bin/bash /letsencrypt/${SCRIPT} >> /var/log/cron-encrypt.log 2>&1"
(crontab -u root -l; echo "$line" ) | crontab -u root -

if [ -n "${LETSENCRYPT_ENDPOINT+1}" ]; then
  echo "server = $LETSENCRYPT_ENDPOINT" >> /etc/letsencrypt/cli.ini
  sed -i "s/acme-v01.api.letsencrypt.org/acme-staging.api.letsencrypt.org/g" $DEHYDRATED/dehydrated
fi

if [ -n "${CF_KEY}" ]; then
  echo "Starting cron with CLOUDFLARE integration..."
  cron -f
else
  # Start cron
  echo "Starting cron..."
  cron &
  echo "Starting nginx..."
  nginx -g 'daemon off;'
fi
