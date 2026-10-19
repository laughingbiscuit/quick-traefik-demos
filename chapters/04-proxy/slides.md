---

# Proxy: TLS from ACME

*How do I serve HTTPS without managing certificates by hand?*

ACME (RFC 8555) lets software get a certificate from a CA with no human in the loop

Three parties:

- __Traefik__ is the ACME client: it does the work
- __CA__ (e.g. DigiCert, Let's Encrypt, or whatever the customer uses today; in this demo step-ca): it decides what to trust
  Any CA that speaks ACME works the same way. You change `caServer`, add `caCertificates` for a private CA, and add `eab` if the CA needs external account binding (DigiCert does)
- __You__ are the operator: you say which CA, which names and which challenge

---

## The scenario

__The cast__

- a service, `whoami`, that should be reachable over HTTPS at `api.traefik-hub.test`
- Traefik, which gets the certificate itself: it is the ACME client
- a CA: `step-ca` here, DigiCert or Let's Encrypt in real life

__We will__ open the service over HTTPS and look at the certificate

__You will see__ whoami answer over HTTPS, a certificate issued to exactly that name by the CA, and plain HTTP sent on to HTTPS

---

## ACME - who owns which step

1. __Register__ - *Traefik* makes an account key pair and registers it with the *CA*
2. __Order__ - *Traefik* asks for a certificate for the `Host()` names on a router that has `tls.certResolver`
3. __Authorize__ - the *CA* sets a challenge, *Traefik* answers it on `:80`, the *CA* checks the answer
4. __Issue__ - *Traefik* sends a CSR, the *CA* signs it
5. __Install__ - *Traefik* loads the certificate and serves it by SNI, with no restart
6. __Renew__ - *Traefik* repeats 2-5 before expiry. The account from step 1 is reused, not re-registered. Revocation is not automated: *you* do it with the CA's tools

*You* own the setup: email, CA address, challenge type, and a `:80` that the CA can reach

---

## ACME - the HTTP-01 challenge

```
 Traefik                                 CA
    |  1. new account, new order          |
    |------------------------------------>|
    |  2. challenge: serve token on :80   |
    |<------------------------------------|
    |  (Traefik answers on /.well-known/  |
    |   acme-challenge/ by itself)        |
    |  3. GET Host: api.traefik-hub.test  |
    |<------------------------------------|
    |  4. token + account key thumbprint  |
    |------------------------------------>|
    |  5. CSR                             |
    |------------------------------------>|
    |  6. signed certificate              |
    |<------------------------------------|
```

Proof of control = being the one who answers on port 80 for that name

---

## ACME - what you configure

```
certificatesResolvers:            # static: the install (platform/k8s/00-traefik-hub.yaml)
  step:
    acme:
      email: demo@example.com
      caServer: https://<your CA>/acme/directory
      storage: /data/acme.json
      httpChallenge:
        entryPoint: web

tls:                              # dynamic: on the route (chapters/04-proxy/manifests.yaml)
  certResolver: step
```

One line on the route is the trigger. No Certificate object, no Secret, no cert-manager

---

## ACME - restarts, renewal and the first request

- `storage` holds the account and the certificates. On a persistent volume, a restart reuses them. Lose it and Traefik registers and orders again
- Traefik renews before expiry by itself (here: 24h certificates, renewed in the last 6h)
- The challenge token is served only while the challenge is pending, but `:80` must be reachable at every renewal
- Until the CA has issued the certificate, `sniStrict: true` refuses the handshake instead of serving Traefik's self-signed one
