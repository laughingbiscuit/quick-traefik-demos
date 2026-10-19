#!/bin/sh
# crd2file: print a running Traefik's dynamic config as file-provider YAML.
# Traefik has already translated the CRDs; we read /api/rawdata and tidy it.
#
#   crd2file [-c CONTEXT] URL|FILE [SERVICE=BACKEND[,BACKEND]...] > dynamic.yaml
#
#   -c CONTEXT       also read what rawdata lacks with kubectl: ServersTransports,
#                    TLSOptions and the TLS certificates routes use (inlined as PEM)
#   SERVICE=BACKEND  replace a service's pod IPs, e.g. demo-whoami-80=http://vm1:8080
#                    (TCP and UDP services take host:port)
set -eu

ctx=
if [ "${1-}" = -c ]; then ctx=$2; shift 2; fi
src=${1:?usage: crd2file [-c CONTEXT] URL|FILE [SERVICE=BACKEND...]}
shift

case $src in
http*) raw=$(curl -fsS "${src%/}/api/rawdata") ;;
*) raw=$(cat "$src") ;;
esac

backends=$(printf '%s\n' "$@" | jq -Rn '
  [inputs | select(length > 0) | capture("^(?<key>[^=]+)=(?<value>.+)$") | .value |= split(",")] | from_entries')

k8s='{"items": []}' certs='{"items": []}'
if [ -n "$ctx" ]; then
  k8s=$(kubectl --context "$ctx" get -A -o json serverstransports.traefik.io,serverstransporttcps.traefik.io,tlsoptions.traefik.io,ingressroutes.traefik.io,ingresses)
  certs=$(kubectl --context "$ctx" get -A -o json secrets --field-selector type=kubernetes.io/tls)
fi

json=$(printf '%s' "$raw" | jq --argjson b "$backends" --argjson k8s "$k8s" --argjson certs "$certs" '
  # "tcpRouters" -> ["tcp", "routers"], "routers" -> ["http", "routers"]
  def section: capture("^(?<p>tcp|udp)?(?<k>.+)") | [.p // "http", (.k[:1] | ascii_downcase) + .k[1:]];
  def where: {ServersTransport: ["http", "serversTransports"],
              ServersTransportTCP: ["tcp", "serversTransports"], TLSOption: ["tls", "options"]}[.kind];
  def nosecrets: delpaths([paths | select(.[-1] | tostring | test("[Ss]ecret"))]);

  [to_entries[] | .key as $s | .value | objects | to_entries[]
   | (.key | split("@")) as [$n, $p] | select($p != "internal") | {s: $s, k: .key, $n, $p, v: .value}] as $all
  | ($all | map({key: .k}) | from_entries) as $keys
  | ($all | map({key: .p}) | from_entries) as $providers
  # Names that two providers both use keep the provider: x@kubernetes -> x-kubernetes.
  | ($all | group_by(.n) | map(select(map(.p) | unique | length > 1) | {key: .[0].n}) | from_entries) as $clash
  # Same-provider references omit the suffix; add it so every reference is renamed alike.
  | def qualify($p): walk(if type == "string" and ("\(.)@\($p)" | in($keys)) then "\(.)@\($p)" else . end);
    def rename: walk(if type == "string" then
        (capture("^(?<n>.+)@(?<p>[a-z]+)$") // {}) as $m
        | if ($m.p // "" | in($providers) | not) then . elif ($m.n | in($clash)) then "\($m.n)-\($m.p)" else $m.n end
      else . end);

  reduce $all[] as $o ({};
    ($o.k | rename) as $name
    | setpath($o.s | section + [$name];
        $o.v | del(.status, .error, .using, .usedBy, .serverStatus, .observability.metadata)
        | qualify($o.p) | rename
        | if $b[$name] and ($o.s | endswith("ervices")) then .loadBalancer.servers = [$b[$name][] | if $o.s == "services" then {url: .} else {address: .} end]
          else . end))

  # Same names as the CRD provider gives them.
  | reduce ($k8s.items[] | select(where)) as $i (.;
      setpath($i | where + [if $i.metadata.name == "default" then "default" else "\($i.metadata.namespace)-\($i.metadata.name)" end];
        $i.spec | nosecrets))

  # Certificates named by IngressRoutes (spec.tls.secretName) and Ingresses (spec.tls[].secretName).
  | ([$k8s.items[] | .metadata.namespace as $ns | [.spec.tls | .. | .secretName? | strings][] | "\($ns)/\(.)"]) as $used
  | ([$certs.items[] | select(IN("\(.metadata.namespace)/\(.metadata.name)"; $used[]))
      | {certFile: (.data["tls.crt"] | @base64d), keyFile: (.data["tls.key"] | @base64d)}]) as $pem
  | if $pem == [] then . else .tls.certificates = $pem end

  | ([.http.services, .tcp.services, .udp.services | objects | keys[]]) as $names
  | ($b | keys - $names) as $typos
  | if $typos == [] then . else error("unknown services: \($typos | join(", "))") end
  | {config: .,
     warnings: ([.http.services, .tcp.services, .udp.services | objects | to_entries[]
                 | select(.value.loadBalancer.servers and (.key | in($b) | not)) | "still on pod IPs: \(.key)"]
               + [$k8s.items[] | select(where) | select(.spec != (.spec | nosecrets))
                  | "dropped Secret fields of \(.kind) \(.metadata.namespace)/\(.metadata.name)"])}
')

printf '%s' "$json" | jq -r '.warnings[] | "crd2file: " + .' >&2
printf '%s' "$json" | jq '.config' | yq -p json -o yaml

