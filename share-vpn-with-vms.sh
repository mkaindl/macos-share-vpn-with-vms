#!/bin/bash
# Use sed for consistency and readability
# shellcheck disable=SC2001

set -o errexit -o nounset -o pipefail

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
PF_SHARED_V4_NAT_CONF_OLD=$(pfctl -q -a com.apple.internet-sharing/shared_v4 -s nat 2>/dev/null)
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

# Try to parse the new PF NAT configuration before actually applying it
if ! echo "$PF_SHARED_V4_NAT_CONF_NEW" | pfctl -a com.apple.internet-sharing/shared_v4 -N -f- 2>/dev/null; then
  fail "Unexpected failure. New packet filter configuration could not be applied."
fi

# Apply the new PF NAT configuration
echo "$PF_SHARED_V4_NAT_CONF_NEW" | pfctl -a com.apple.internet-sharing/shared_v4 -N -f- 2>/dev/null
echo "New configuration was successfully applied."
