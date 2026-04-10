#cloud-config
package_update: true
packages:
  - wireguard
  - iptables
  - iptables-persistent

write_files:
  - path: /etc/sysctl.d/99-wireguard-ip-forward.conf
    permissions: "0644"
    content: |
      net.ipv4.ip_forward=1
  - path: /root/bootstrap-wireguard.sh
    permissions: "0700"
    content: |
      #!/usr/bin/env bash
      set -euo pipefail
      umask 077

      SERVER_PRIV="$(wg genkey)"
      SERVER_PUB="$(echo "$${SERVER_PRIV}" | wg pubkey)"
      CLIENT_PRIV="$(wg genkey)"
      CLIENT_PUB="$(echo "$${CLIENT_PRIV}" | wg pubkey)"

      cat >/etc/wireguard/wg0.conf <<EOF
      [Interface]
      Address = ${wireguard_server_private_cidr}
      ListenPort = ${wireguard_port}
      PrivateKey = $${SERVER_PRIV}
      SaveConfig = false
      PostUp = sysctl -w net.ipv4.ip_forward=1; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -s ${wireguard_client_ip}/32 -o eth0 -j MASQUERADE
      PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -s ${wireguard_client_ip}/32 -o eth0 -j MASQUERADE

      [Peer]
      PublicKey = $${CLIENT_PUB}
      AllowedIPs = ${wireguard_client_ip}/32
      EOF

      EXTERNAL_IP="$(curl -sSf -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip || true)"

      cat >/root/wg-client.conf <<EOF
      [Interface]
      PrivateKey = $${CLIENT_PRIV}
      Address = ${wireguard_client_ip}/32
      DNS = ${wireguard_client_dns}

      [Peer]
      PublicKey = $${SERVER_PUB}
      Endpoint = $${EXTERNAL_IP}:${wireguard_port}
      AllowedIPs = ${wireguard_client_allowed_ips}
      PersistentKeepalive = 25
      EOF

runcmd:
  - sysctl --system
  - /root/bootstrap-wireguard.sh
  - systemctl enable --now wg-quick@wg0
