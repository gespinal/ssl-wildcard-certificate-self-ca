#!/bin/bash

# Wildcard SSL Certificate CA

# Domain validation
if [ "$#" -ne 1 ]; then
  echo "Usage: Must supply a domain in the format: example.com"
  exit 1
else
  DOMAIN=$1
fi

CERTS_DIR="${PWD}/certs"

echo "### Check if certificate already exists for ${DOMAIN}..."
EXISTS=`awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' < /etc/ssl/certs/ca-certificates.crt | grep ${DOMAIN}`
if [[ ! -z "$EXISTS" ]]; then
  echo "Certificate for ${DOMAIN} already exists on this system."
fi

echo "### Validating if ${CERTS_DIR} exists..."
[ ! -d "${CERTS_DIR}" ] && mkdir ${CERTS_DIR}

echo "### Install required packages..."
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  sudo apt-get install -y ca-certificates openssl
fi

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
DNS.2 = *.ha.${DOMAIN}
DNS.3 = *.k8s.${DOMAIN}
DNS.4 = *.lab.${DOMAIN}
DNS.5 = *.traefik.${DOMAIN}
DNS.6 = *.heraklion.${DOMAIN}
EOF

echo "### Create the ca's cert and key for ${DOMAIN}..."
openssl req \
 -nodes \
 -new \
 -x509 \
 -sha256 \
 -days 3650 \
 -keyout "${CERTS_DIR}/${DOMAIN}.key" \
 -out "${CERTS_DIR}/${DOMAIN}-CA.pem" \
 -subj "/C=DR/ST=SD/L=DR/O=${DOMAIN%.*}/OU=${DOMAIN%.*}/CN=*.${DOMAIN}/emailAddress=admin@${DOMAIN}"

echo "### Create csr for ${DOMAIN}..."
openssl req -new \
 -newkey rsa:2048 \
 -key "${CERTS_DIR}/${DOMAIN}.key" \
 -nodes \
 -out "${CERTS_DIR}/${DOMAIN}.csr" \
 -extensions v3_req \
 -config "${CERTS_DIR}/${DOMAIN}-csr.conf"

echo "### Sign the csr with our ca's cert..."
sudo openssl x509 -req \
 -in "${CERTS_DIR}/${DOMAIN}.csr" \
 -CA "${CERTS_DIR}/${DOMAIN}-CA.pem" \
 -CAkey "${CERTS_DIR}/${DOMAIN}.key" \
 -CAcreateserial \
 -out "${CERTS_DIR}/${DOMAIN}-CERT.pem" \
 -days 3650 \
 -sha256 \
 -extfile "${CERTS_DIR}/${DOMAIN}-csr.conf" \
 -extensions v3_req

echo "### Get ${DOMAIN}.crt data..."
openssl x509 -text -in "${CERTS_DIR}/${DOMAIN}-CERT.pem"

echo "### Re-check ${DOMAIN}.crt data..."
openssl req -in "${CERTS_DIR}/${DOMAIN}.csr" -noout -text

echo "### Create ${DOMAIN} fullchain..."
cat "${CERTS_DIR}/${DOMAIN}-CERT.pem" > "${CERTS_DIR}/${DOMAIN}-FULLCHAIN.pem"
cat "${CERTS_DIR}/${DOMAIN}-CA.pem" >> "${CERTS_DIR}/${DOMAIN}-FULLCHAIN.pem"

echo "### Create ${DOMAIN} key-server chain..."
cat "${CERTS_DIR}/${DOMAIN}.key" > "${CERTS_DIR}/${DOMAIN}-KEYCHAIN.pem"
cat "${CERTS_DIR}/${DOMAIN}-CERT.pem" >> "${CERTS_DIR}/${DOMAIN}-KEYCHAIN.pem"

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  echo "### Copy ${DOMAIN} cert file to system dir..."
  sudo cp ${CERTS_DIR}/${DOMAIN}-CA.pem /usr/local/share/ca-certificates/${DOMAIN}.CA.crt
  echo "### If on WSL: Copy ${DOMAIN} cert file into windows store..."
  if [[ $(uname -r) == *"WSL"* ]]; then
    cp "${CERTS_DIR}/${DOMAIN}-CA.pem" "${CERTS_DIR}/${DOMAIN}-FULLCHAIN.pem" "${CERTS_DIR}/${DOMAIN}-KEYCHAIN.pem" "${CERTS_DIR}/${DOMAIN}.key" /mnt/c/Windows/Temp
    echo "### If on WSL: Importing cert to windows"
    powershell.exe Start-Process powershell -Verb RunAs -ArgumentList "Import-Certificate, -FilePath, C:\\Windows\\Temp\\${DOMAIN}-CA.pem, -CertStoreLocation, Cert:\LocalMachine\Root"
    echo "### If on WSL: Update ExecutionPolicy for scripts"
    powershell.exe Start-Process powershell -Verb RunAs -ArgumentList "Set-ExecutionPolicy, Unrestricted, -force"
    echo "### If on WSL: Update /etc/hosts"
    cp ./win_update_hosts.ps1 /mnt/c/Windows/Temp && cd /mnt/c/Windows/Temp
    powershell.exe Start-Process powershell -Verb RunAs -ArgumentList "'-File C:\\Windows\\Temp\\win_update_hosts.ps1', ${DOMAIN}"
  fi
  echo "### Update OS certificates..."
  sudo update-ca-certificates
  echo "### Check installed certificate for ${DOMAIN}..."
  awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' < /etc/ssl/certs/ca-certificates.crt | grep ${DOMAIN}
  echo "### Echo removing cert file from system dir..."
  sudo rm /usr/local/share/ca-certificates/${DOMAIN}.CA.crt
elif [[ "$OSTYPE" == "darwin"* ]]; then
  if [[ $(security find-certificate -a -e "admin@${DOMAIN}") ]]; then
    echo "### Deleting old ${DOMAIN} certificate..."
    sudo security delete-certificate -c "*.${DOMAIN}"
  fi
  echo "### Adding ${DOMAIN} certificate..."
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./certs/${DOMAIN}-CA.pem
  echo "### Validating ${DOMAIN} certificate..."
  security find-certificate -a -e "admin@example.com"
fi

echo "### If using Firefox (Set system wide certificate validation)..."
echo "Go to: about:config"
echo "Set: security.enterprise_roots.enabled to true"
