#!/bin/bash
# How to found https://technicallyrambling.calmatlas.com/samba-dc-in-a-linux-container-or-incus-vm/
if [ ! "$1" ]; then
	echo "Usage: ./install_sambadc.sh DOMAIN-CONTROLLER-FQDN [SERVERIP]"
	echo "If you do not specify an IP address the ip will be determined by the command:"
	echo "ip -br -4 addr |grep "UP""
	exit 1
fi

echo "Set the fqdn"
fqdn="$1"
hostnamectl set-hostname "$fqdn"
defaultRealm="$(echo $1|cut -d . -f 2-|tr [:lower:] [:upper:])"
domain="$(echo $defaultRealm|tr [:upper:] [:lower:])"
kdc="$1"
adminServer="$1"
friendlyName="$(echo $1|cut -d . -f 1)"
domainName="$(echo $defaultRealm|cut -d . -f 1)"

echo "Get the active IP"
if [ "$2" ]; then
	activeIP="$2"
else
	activeIP="$(ip -br -4 addr |grep "UP" \
	|grep -Eo '(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])')"
fi

echo "Rewrite /etc/host with fqdn"
mv /etc/hosts /etc/hosts.bak
cat << EOF > /etc/hosts
127.0.0.1 localhost
$activeIP $fqdn $friendlyName
EOF

echo "Disable resolvconf"
systemctl disable systemd-resolved
systemctl stop systemd-resolved

echo "Rewrite /etc/resolv.conf google dns"
mv /etc/resolv.conf /etc/resolv.conf.bak
echo "nameserver 8.8.8.8" > /etc/resolv.conf

echo "Install samba"
apt update -yq
apt upgrade -yq
apt install acl attr samba winbind libpam-winbind libnss-winbind dnsutils python3-setproctitle -yq

echo "Install krb5"
export DEBIAN_FRONTEND=noninteractive
apt install krb5-config krb5-user -yq
export DEBIAN_FRONTEND=""

echo "Remove smb.conf before provisioning"
rm /etc/samba/smb.conf

echo "Stop samba services and disable"
systemctl stop smbd nmbd winbind
systemctl mask smbd nmbd winbind
systemctl disable smbd nmbd winbind

echo "Generate Password"
adminPass="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32;echo;)"
#echo "$adminPass"
echo "$adminPass" > /root/samba.pass
chmod 400 /root/samba.pass

echo "Rewrite /etc/resolv.conf self"
mv /etc/resolv.conf /etc/resolv.conf.bak
echo "search $domain" > /etc/resolv.conf
echo "nameserver $activeIP" >> /etc/resolv.conf

echo "Provision"
samba-tool domain provision --use-rfc2307 \
--realm="$defaultRealm" \
--domain="$domainName" \
--server-role=dc \
--dns-backend=SAMBA_INTERNAL \
--adminpass="$adminPass"

echo "Copy krb5.conf"
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

echo "Setup dns forwarder"
grep "dns forwarder" /etc/samba/smb.conf > /dev/null
sed -i 's/dns forwarder.*$/dns forwarder = 8.8.8.8/g' /etc/samba/smb.conf

echo "Restart ad service"
killall samba
systemctl start samba-ad-dc.service