#!/bin/bash 

# Wildcard SSL Certificate CA

# Domain validation
if [ "$#" -ne 1 ]; then
  echo "Usage: Must supply a domain in the format: example.com"
  exit 1
else
  DOMAIN=$1
fi

echo "### Check if certificate already exists for ${DOMAIN}..."
EXISTS=`awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' < /etc/ssl/certs/ca-certificates.crt | grep ${DOMAIN}`
if [[ ! -z "$EXISTS" ]]; then
  echo "Certificate for ${DOMAIN} already exists on this system."
  exit 1;
fi

# Vars
CERTS_DIR=./certs

echo "### Validating if ${CERTS_DIR} exists..."
[ ! -d "${CERTS_DIR}" ] && mkdir ${CERTS_DIR}

echo "### Install required packages..."
sudo apt-get install -y ca-certificates openssl
 
echo "### Create the config file to sign the ${DOMAIN} csr..."
cat > ${CERTS_DIR}/${DOMAIN}-csr.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
C   =  DR
ST  =  SD
L   =  DN
O   =  ${DOMAIN%.*}
OU  =  ${DOMAIN%.*}
CN  =  *.${DOMAIN}
[v3_req]
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = *.${DOMAIN}
DNS.2 = *.lab.${DOMAIN}
EOF

echo "### Create the ca's cert and key for ${DOMAIN}..."
openssl req \
 -nodes \
 -new \
 -x509 \
 -sha256 \
 -days 1825 \
 -keyout ${CERTS_DIR}/${DOMAIN}.key \
 -out ${CERTS_DIR}/${DOMAIN}.pem \
 -subj "/C=DR/ST=SD/L=DR/O=${DOMAIN%.*}/OU=${DOMAIN%.*}/CN=*.${DOMAIN}/emailAddress=admin@${DOMAIN}"

echo "### Create csr for ${DOMAIN}..."
openssl req -new \
 -newkey rsa:2048 \
 -key ${CERTS_DIR}/${DOMAIN}.key \
 -nodes \
 -out ${CERTS_DIR}/${DOMAIN}.csr \
 -extensions v3_req \
 -config ${CERTS_DIR}/${DOMAIN}-csr.conf
 
 echo "### Sign the csr with our ca's cert..."
openssl x509 -req \
 -in ${CERTS_DIR}/${DOMAIN}.csr \
 -CA ${CERTS_DIR}/${DOMAIN}.pem \
 -CAkey ${CERTS_DIR}/${DOMAIN}.key \
 -CAcreateserial \
 -out ${CERTS_DIR}/${DOMAIN}.crt \
 -days 1825 \
 -sha256 \
 -extfile ${CERTS_DIR}/${DOMAIN}-csr.conf \
 -extensions v3_req
 
echo "### Get ${DOMAIN}.crt data..."
openssl x509 -text -in ${CERTS_DIR}/${DOMAIN}.crt
 
echo "### Re-check ${DOMAIN}.crt data..."
openssl req -in ${CERTS_DIR}/${DOMAIN}.csr -noout -text
 
echo "### Copy ${DOMAIN} cert file to system dir..."
sudo cp ${CERTS_DIR}/${DOMAIN}.pem /usr/local/share/ca-certificates/${DOMAIN}.CA.crt
 
echo "### Update OS certificates..."
sudo update-ca-certificates

echo "### Check installed certificate for ${DOMAIN}..." 
awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' < /etc/ssl/certs/ca-certificates.crt | grep ${DOMAIN}
