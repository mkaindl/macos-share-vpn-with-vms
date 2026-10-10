#!/bin/bash

set -o errexit -o nounset -o pipefail

PF_ANCHOR=com.apple.internet-sharing/shared_v4

fail() {
  echo "$*" >&2
  exit 1
}

# Parameter expansion cannot prefix every line of a multi-line string
print_rules() {
  # shellcheck disable=SC2001
  sed 's/^/│ /' <<<"$1"
}

if [[ $EUID -ne 0 ]]; then
  fail "Must be run as root, e.g. via sudo."
fi

# VPN tunnels are utun interfaces with a point-to-point IPv4 address ("inet <local> --> <remote>")
VPN_INTERFACE=$(ifconfig -u | awk '
  /^[^ \t]/ { interface_name = $1; sub(/:$/, "", interface_name) }
  $1 == "inet" && $3 == "-->" && interface_name ~ /^utun/ { print interface_name }
' | sort -u)
if [[ -z "$VPN_INTERFACE" ]]; then
  fail "Could not detect VPN tunnel interface. The VPN may not be connected."
fi
if [[ "$VPN_INTERFACE" == *$'\n'* ]]; then
  fail "Detected multiple VPN tunnel interfaces: ${VPN_INTERFACE//$'\n'/ }"
fi

PF_NAT_RULES_OLD=$(pfctl -q -a "$PF_ANCHOR" -s nat 2>/dev/null)
if ! grep -q '^nat on ' <<<"$PF_NAT_RULES_OLD"; then
  fail "Could not detect VM-related NAT configuration. The Virtualization framework may not be running."
fi

echo "Current packet filter NAT configuration for network sharing:"
print_rules "$PF_NAT_RULES_OLD"
echo

# Add a copy of each uplink NAT rule for the VPN interface. pf applies a "nat on <interface>" rule only to packets
# leaving through that interface, so traffic routed through the VPN and traffic routed past it are both translated.
PF_NAT_RULES_NEW=$(echo "$PF_NAT_RULES_OLD" | awk -v vpn_interface="$VPN_INTERFACE" '
  { print; existing[$0] = 1 }
  $1 == "nat" && $2 == "on" && $3 !~ /^utun/ {
    uplink_interface = $3
    $3 = vpn_interface
    for (i = 4; i <= NF; i++) {
      if (index($i, "(" uplink_interface ")") == 1 || index($i, "(" uplink_interface ":") == 1) {
        $i = "(" vpn_interface substr($i, length(uplink_interface) + 2)
      }
    }
    copies[++copy_count] = $0
  }
  END {
    for (i = 1; i <= copy_count; i++) {
      if (!(copies[i] in existing)) {
        existing[copies[i]] = 1
        print copies[i]
      }
    }
  }
')
if [[ "$PF_NAT_RULES_OLD" == "$PF_NAT_RULES_NEW" ]]; then
  echo "No changes to apply. The script may have been run before."
  exit
fi

echo "New packet filter NAT configuration for network sharing:"
print_rules "$PF_NAT_RULES_NEW"
echo

# pfctl parses the complete ruleset before loading it, so an invalid ruleset leaves the current one in place
if ! PFCTL_OUTPUT=$(echo "$PF_NAT_RULES_NEW" | pfctl -a "$PF_ANCHOR" -N -f- 2>&1); then
  fail "New packet filter configuration could not be applied:"$'\n'"$PFCTL_OUTPUT"
fi
echo "New configuration was successfully applied."
