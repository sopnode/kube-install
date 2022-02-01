#!/bin/bash

CERTS_DIR=${1:-$LOCAL_CERTS_DIR}
CA="${CERTS_DIR}"/ca.crt
CA_KEY="${CERTS_DIR}"/ca.key

if [[ ! -f ${CA} || ! -f ${CA_KEY} ]]; then
   echo "Error: CA files ${CA}  ${CA_KEY} are missing "
   exit 1
fi

if [ -z "${CERTS_DIR}" ]; then
   echo "Error: $0 needs a CERTS DIR (did you export LOCAL_CERTS_DIR?)"
   exit 1
fi

CLIENT_SUBJECT=${CLIENT_SUBJECT:-"/O=system:masters/CN=kubernetes-admin"}
CLIENT_CSR=${CERTS_DIR}/kubeadmin.csr
CLIENT_CERT=${CERTS_DIR}/kubeadmin.crt
CLIENT_KEY=${CERTS_DIR}/kubeadmin.key
CLIENT_CERT_EXTENSION=${CERTS_DIR}/cert-extension

# # We need faketime for cases when your client time is on UTC+
# type -p faketime >/dev/null 2>&1
# if [[ $? == 0 ]]; then
#   OPENSSL="faketime -f -1d openssl"
# else
#   echo "Warning, faketime is missing, you might have a problem if your server time is less tehn"
#   OPENSSL=openssl
# fi
OPENSSL=openssl

echo "Creating Client KEY $CLIENT_KEY "
$OPENSSL genrsa -out "$CLIENT_KEY" 2048

echo "Creating Client CSR $CLIENT_CSR "
$OPENSSL req -subj "${CLIENT_SUBJECT}" -sha256 -new -key "${CLIENT_KEY}" -out "${CLIENT_CSR}"

echo "--- create  ca extfile"
echo "extendedKeyUsage=clientAuth" > "$CLIENT_CERT_EXTENSION"

echo "--- sign  certificate ${CLIENT_CERT} "
$OPENSSL x509 -req -days 1096 -sha256 \
    -in "$CLIENT_CSR" -CA "$CA" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$CLIENT_CERT" -extfile "$CLIENT_CERT_EXTENSION" -passin pass:"$CA_PASS"

echo "(over)wrote $CLIENT_CERT"
