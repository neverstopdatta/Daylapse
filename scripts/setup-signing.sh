#!/bin/sh
set -eu

NAME="Daylapse Local Signing"
security find-identity -p codesigning | grep -q "$NAME" && exit 0
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$T/k.pem" -out "$T/c.pem" \
  -subj "/CN=$NAME" -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "keyUsage=critical,digitalSignature" -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -legacy -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/c.p12" -passout pass:tmp \
  || openssl pkcs12 -export -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/c.p12" -passout pass:tmp
security import "$T/c.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P tmp -T /usr/bin/codesign
