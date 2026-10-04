#!/bin/bash
# Use sed for consistency and readability
# shellcheck disable=SC2001

set -o errexit -o nounset -o pipefail

PF_ANCHOR=com.apple.internet-sharing/shared_v4

fail() {
  echo "$*" >&2
  exit 1
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

# Get existing packet filter NAT configuration for shared networking
PF_SHARED_V4_NAT_CONF_OLD=$(pfctl -q -a "$PF_ANCHOR" -s nat 2>/dev/null)
# Get name of active ethernet interface (WiFi, Thunderbolt, etc.) from NAT configuration
ACTIVE_ETHERNET_INTERFACE=$(echo "$PF_SHARED_V4_NAT_CONF_OLD" | sed -n 's/^nat on \(.*\) inet from \(.*\)/\1/p;q')
if [[ -z "$ACTIVE_ETHERNET_INTERFACE" ]]; then
  fail "Could not detect VM-related NAT configuration. The Virtualization framework may not be running."
fi

echo "Current packet filter NAT configuration for network sharing:"
echo "$PF_SHARED_V4_NAT_CONF_OLD" | sed 's/^/│ /'
echo

# Adapt NAT configuration by replacing the default interface with the VPN interface
PF_SHARED_V4_NAT_CONF_NEW=$(echo "$PF_SHARED_V4_NAT_CONF_OLD" | sed "s/$ACTIVE_ETHERNET_INTERFACE/$VPN_INTERFACE/g")
if [[ "$PF_SHARED_V4_NAT_CONF_OLD" == "$PF_SHARED_V4_NAT_CONF_NEW" ]]; then
  echo "No changes to apply. The script may have been run before."
  exit
fi

echo "New packet filter NAT configuration for network sharing:"
echo "$PF_SHARED_V4_NAT_CONF_NEW" | sed 's/^/│ /'
echo

# pfctl parses the complete ruleset before loading it, so an invalid ruleset leaves the current one in place
if ! PFCTL_OUTPUT=$(echo "$PF_SHARED_V4_NAT_CONF_NEW" | pfctl -a "$PF_ANCHOR" -N -f- 2>&1); then
  fail "New packet filter configuration could not be applied:"$'\n'"$PFCTL_OUTPUT"
fi
echo "New configuration was successfully applied."
