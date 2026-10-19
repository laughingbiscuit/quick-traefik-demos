m4_changequote([[[,]]])m4_dnl
<!--
title: Traefik Hub Workshop
author: laughingbiscuit
date: m4_esyscmd([[[date +%d/%m/%y]]])
-->

# Traefik Hub Workshop

---

# Introduction

Traefik provides a self-configuring layer to route, secure and observe
  traffic across VMs, K8s, APIs, MCP and LLMs in a single binary

A request arrives. Each part of this session answers one question about it

---

# The plan

m4_esyscmd([[[for c in $SLIDES; do grep -m1 '^# ' chapters/$c/slides.md | sed 's/^# /- /'; done]]])

---

# Lab Environment

TL;DR:

- Kubernetes with k3d
- VM with Lima
- GitOps with Gitea + Flux
- Testing with curl, hurl and hey
- Redis, Keycloak, OPA and Toxiproxy also available

You can verify the test results and try yourself with this [repo](https://github.com/laughingbiscuit/quick-traefik-demos)

---

# Installing Traefik

One binary that runs on:

- Kubernetes via Helm
- Docker / Docker Compose
- Hashicorp Nomad
- Linux under systemd (connected or fully air-gapped)
- Cloud marketplaces
- Also available as a FIPS 140-3 Hardened Image

This demo uses Flux/Helm for Kubernetes and the binary in systemd on VM

m4_esyscmd([[[for c in $SLIDES; do cat chapters/$c/slides.md; printf '\n\n'; done]]])

---

# Try it yourself

Every example here is in the [repo](https://github.com/laughingbiscuit/quick-traefik-demos), with tests

`./demo.sh up` builds the lab, `./demo.sh test` checks it

