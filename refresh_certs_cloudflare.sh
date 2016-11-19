#!/bin/bash

set -e

export DOMAINS
export SECRET_NAME
export NAMESPACE

DOMAINS=(${DOMAINS})
RENEW_DAYS=30
NAMESPACE=${NAMESPACE:-default}
CERT=/tmp/fullchain.pem

if [ -z "$DOMAINS" ]; then
    echo "ERROR: Domain list is empty or unset"
    exit 1
fi

if [ -z "$SECRET_NAME" ]; then
    echo "ERROR: Secret Name is empty or unset"
    exit 1
fi

domain_args=""
for i in "${DOMAINS[@]}"
do
   domain_args="$domain_args -d $i"
done

# Get the current certificate from the secrets and decode
echo `kubectl get secret --namespace $NAMESPACE $SECRET_NAME -o json | jq -r '.data["tls.crt"]'` | base64 -d > $CERT

# Check how many days the certificate is valid for
exp=$(date -d "`openssl x509 -in $CERT -text -noout|grep "Not After"|cut -c 25-`" +%s)
datenow=$(date -d "now" +%s)
DAYS_EXP=$(echo \( $exp - $datenow \) / 86400 |bc)

function deploy {
  if [ -z "$DEPLOYMENTS" ]; then
    echo "WARNING: DEPLOYMENTS not provided. Secret changes may not be reflected."
    exit 0
  fi

  DEPLOYMENTS=(${DEPLOYMENTS})
  DATE=$(date)
  NAMESPACE=${NAMESPACE:-default}

  for DEPLOYMENT in "${DEPLOYMENTS[@]}"
  do
    NAME=$(kubectl get deployments --namespace $NAMESPACE $DEPLOYMENT -o=template --template='{{index .spec.template.spec.containers 0 "name"}}')
    PATCH=$(NAME=$NAME DATE=$DATE echo "{\"spec\": {\"template\": {\"spec\": {\"containers\": [{\"name\": \"$NAME\", \"env\": [{\"name\": \"LETSENCRYPT_CERT_REFRESH\", \"value\": \"$DATE\"}]}]}}}}")
    echo "PATCHING ${DEPLOYMENT}: ${PATCH}"
    kubectl patch deployment --namespace $NAMESPACE $DEPLOYMENT --type=strategic -p "$PATCH"
  done
}

function save_and_deploy {
  DOMAIN=${DOMAINS[0]}
  CERT_LOCATION=/letsencrypt/app/dehydrated/certs/
  echo Removing existing secret "${SECRET_NAME}" for $DOMAIN
  kubectl delete secret $SECRET_NAME
  echo Creating new secret $SECRET_NAME
  kubectl create secret tls ${SECRET_NAME} --key=$CERT_LOCATION/$DOMAIN/privkey.pem --cert=$CERT_LOCATION/$DOMAIN/fullchain.pem
  deploy
}

function update {
  echo Getting new certificates......
  app/dehydrated/dehydrated -c $domain_args -t dns-01 -k 'app/dehydrated/hooks/cloudflare/hook.py'
  save_and_deploy
  exit 0;
}

function check {
  echo "Checking expiration date for $DOMAINS..."
  if [ "$DAYS_EXP" -gt "$RENEW_DAYS" ] ; then
    echo "The certificate is up to date, no need for renewal ($DAYS_EXP days left)."
    exit 0;
  else
    update
  fi
}

if [ ! -f $CERT ]; then
  echo "[ERROR] certificate file not found for domain $DOMAIN."
  update
else
  echo "CHECKING THE CERTIFICATES"
  check
  rm -rf $CERT
fi
