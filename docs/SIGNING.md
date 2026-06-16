# Lokale Code-Signatur (TCC-stabil)

macOS bindet Automation-/Accessibility-Berechtigungen (TCC) an die **Designated Requirement**
der Code-Signatur. Eine **ad-hoc**-Signatur (`codesign --sign -`) basiert auf dem Binär-Hash und
ändert sich bei **jedem Build** → erteilte Berechtigungen werden jedes Mal ungültig.

Lösung: einmalig ein **stabiles, selbst-signiertes Code-Signing-Zertifikat** anlegen. `make-app.sh`
signiert damit automatisch (Name: `DiaRouter Local Signing`, überschreibbar via
`DIAROUTER_SIGN_IDENTITY`). So bleiben Berechtigungen über Rebuilds erhalten.

## Einmalige Einrichtung

```bash
cd /tmp
openssl req -x509 -newkey rsa:2048 -keyout k.pem -out c.pem -days 3650 -nodes \
  -subj "/CN=DiaRouter Local Signing" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -legacy -inkey k.pem -in c.pem -out id.p12 -passout pass:diapass
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P diapass -T /usr/bin/codesign
rm -f /tmp/k.pem /tmp/c.pem /tmp/id.p12
```

> Hinweis: `-legacy` ist für OpenSSL 3 nötig, sonst scheitert `security import` mit
> „MAC verification failed". Das Zertifikat ist **nicht** vertrauenswürdig signiert
> (kein Developer-ID/App-Store) — nur für den lokalen Eigengebrauch.

Danach `./scripts/make-app.sh` → signiert stabil. TCC-Freigaben (Automation + Accessibility)
müssen nur **einmal** erteilt werden.
