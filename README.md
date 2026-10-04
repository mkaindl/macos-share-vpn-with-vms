# Share VPN with macOS VMs

Give Virtualization framework VMs with NAT networking on macOS access to the host's VPN.

## Usage

Run the script once the VPN is connected *and* at least one VM is running.
Re-run after a VM restart, as macOS then regenerates the NAT rules, and after a VPN reconnect, as the tunnel interface may change.

```shell
sudo ./share-vpn-with-vms.sh
```

The script handles:

* multiple running VMs
* uplink interfaces other than Wi-Fi, e.g. Ethernet or USB tethering
* split-tunnel and full-tunnel VPNs: VM traffic is translated on whichever interface it leaves through

Limitations:

* IPv4 only.
* Exactly one VPN tunnel (`utun` interface with a point-to-point IPv4 address) must be connected.

macOS discards the changes when it regenerates the NAT rules, e.g. on a VM restart.

## Background

VMs using `VZNATNetworkDeviceAttachment` are connected to a bridge interface (usually `bridge100`, subnet `192.168.64.0/24`).
When the first VM starts, macOS Internet Sharing enables the packet filter (pf) and loads NAT rules into the anchor `com.apple.internet-sharing/shared_v4`:

```
nat on en0 inet from 192.168.64.0/24 to any -> (en0:0) extfilter ei
no nat on bridge100 inet from 192.168.64.1 to 192.168.64.0/24
```

A `nat on <interface>` rule only translates packets leaving through that interface (see `man pf.conf`).
Internet Sharing creates these rules only for interfaces with a default route via a gateway, such as the uplink `en0`.
A VPN tunnel interface (`utunN`) typically has no such route and gets no rule.

Once the VPN routes traffic through `utunN`, VM packets match no NAT rule and enter the tunnel with their VM source address `192.168.64.x`.
The VPN server has no route back to that subnet.
Traffic from the host itself works because it uses the tunnel address as source address.

This can be observed by capturing traffic on the tunnel interface, e.g. `sudo tcpdump -n -i utunN`:
packets from the host carry the tunnel address, packets from a VM carry the VM address.

The script adds a copy of each uplink NAT rule for the tunnel interface, so VM traffic is translated to the tunnel address:

```
nat on utunN inet from 192.168.64.0/24 to any -> (utunN:0) extfilter ei
```

Internet Sharing regenerates the anchor when a VM restarts, which discards the added rule.
There is no API to customize the rules Internet Sharing loads.

## References

* Internet Sharing enabling pf and loading rules into `com.apple.internet-sharing/shared_v4` when a container's VM network comes up: https://github.com/apple/container/issues/2335
* No API to control how Internet Sharing is loaded: https://developer.apple.com/forums/thread/656877
* Default NAT rules for Virtualization framework VMs and adding a rule for the VPN tunnel: https://github.com/utmapp/UTM/issues/3238#issuecomment-1328338033
* NAT rules only for interfaces with a default route via a gateway: https://github.com/openai/tart/issues/384#issuecomment-1398990366
* Adding a VPN tunnel rule to the existing rules keeps VPN and non-VPN traffic working: https://github.com/openai/tart/issues/384#issuecomment-1406196317
* Internet Sharing pf anchors and adding a `utun` rule for a VM: https://github.com/fbion/macos.safe/issues/33
* Loading a VPN tunnel NAT rule for Docker Desktop on Apple Silicon: https://github.com/docker/for-mac/issues/7266
* Script replacing the NAT rules with a single VPN tunnel rule: https://github.com/NikushaKalatozi/MacOS-Big-Sur-Sharing-Host-VPN-with-Guest/blob/main/vpn_tunnel.sh
