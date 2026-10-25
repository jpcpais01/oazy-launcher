#!/usr/bin/env bash
# Authenticode-signs the exe with osslsigncode.
# Uses the WINDOWS_CERT_PFX (base64) / WINDOWS_CERT_PASSWORD secrets when present,
# otherwise a self-signed code-signing certificate generated for this build.
set -euo pipefail
exe="$1"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ -n "${WINDOWS_CERT_PFX:-}" ]]; then
  echo "Signing with the provided certificate."
  echo "$WINDOWS_CERT_PFX" | base64 -d > "$work/cert.pfx"
  pass="${WINDOWS_CERT_PASSWORD:-}"
else
  echo "No signing secret configured: using a self-signed certificate."
  pass="oazy-$(openssl rand -hex 8)"
  openssl req -x509 -newkey rsa:3072 -sha256 -days 1095 -nodes \
    -keyout "$work/key.pem" -out "$work/cert.pem" \
    -subj "/CN=Oazy Launcher/O=Oazy/C=PT" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1
  openssl pkcs12 -export -out "$work/cert.pfx" -inkey "$work/key.pem" -in "$work/cert.pem" \
    -passout "pass:$pass" -name "Oazy Launcher"
fi

sign() {
  osslsigncode sign -pkcs12 "$work/cert.pfx" -pass "$pass" \
    -n "Oazy Launcher" -i "https://github.com/jpcpais01/oazy-launcher" \
    -h sha256 "$@" -in "$exe" -out "$work/signed.exe"
}
# Timestamp so the signature outlives the certificate; fall back if the TSA is down.
if ! sign -ts http://timestamp.digicert.com; then
  if ! sign -ts http://timestamp.sectigo.com; then
    echo "::warning::Timestamp servers unreachable, signing without a timestamp."
    sign
  fi
fi
mv "$work/signed.exe" "$exe"
osslsigncode verify -in "$exe" 2>&1 | grep -E "Signature|Message digest|Signer" || true
