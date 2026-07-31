# Share VPN with macOS VMs

Give Virtualization framework VMs on macOS access to the host's VPN.

## Usage

Run the script once the VPN is connected *and* at least one VM is running.
Re-run if required, e.g. after VM start/stop or VPN reconnect.

```shell
sudo ./share-vpn-with-vms.sh
```

Limitations:

* Assumes a full-tunnel VPN: all VM traffic is NAT'd onto the tunnel.
* IPv4 only.

## Background

Debugged this issue by capturing traffic on the tunnel interface:
* for traffic from the host system, the tunnel IP address is used as source address (NAT)
* for traffic from the VM, the VM IP address is used as source address (not NAT) --> not way back

## References

* https://github.com/NikushaKalatozi/MacOS-Big-Sur-Sharing-Host-VPN-with-Guest/blob/main/vpn_tunnel.sh
* https://github.com/utmapp/UTM/issues/3238#issuecomment-1328338033
* https://github.com/cirruslabs/tart/issues/384#issuecomment-1418942546

This script also covers the following edge cases:
* Multiple VMs are running
* A non-default Ethernet interface is used (e.g. USB Tethering)