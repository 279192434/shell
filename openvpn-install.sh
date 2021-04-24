#!/bin/bash

# Secure OpenVPN server installer for Debian, Ubuntu, CentOS, Fedora and Arch Linux
# https://github.com/angristan/openvpn-install

function isRoot () {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
}

function tunAvailable () {
	if [ ! -e /dev/net/tun ]; then
		return 1
	fi
}

function checkOS () {
	if [[ -e /etc/debian_version ]]; then
		OS="debian"
		source /etc/os-release

		if [[ "$ID" == "debian" ]]; then
			if [[ ! $VERSION_ID =~ (8|9) ]]; then
				echo "⚠️ 当前脚本不支持此Debian版本."
				echo ""
				echo "但是，如果你使用的Debian系统版本 >= 9 那么你可以尝试继续."
				echo "请注意他们不被支持"
				echo ""
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "是否继续? [y/n]: " -e CONTINUE
				done
				if [[ "$CONTINUE" = "n" ]]; then
					exit 1
				fi
			fi
		elif [[ "$ID" == "ubuntu" ]];then
			OS="ubuntu"
			if [[ ! $VERSION_ID =~ (16.04|18.04) ]]; then
				echo "⚠️ 当前脚本不支持此Ubuntu版本."
				echo ""
				echo "但是，如果你使用的Ubuntu系统版本 > 17 or beta, 你可以继续安装."
				echo "请注意他们不被支持"
				echo ""
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "是否继续? [y/n]: " -e CONTINUE
				done
				if [[ "$CONTINUE" = "n" ]]; then
					exit 1
				fi
			fi
		fi
	elif [[ -e /etc/fedora-release ]]; then
		OS=fedora
	elif [[ -e /etc/centos-release ]]; then
		if ! grep -qs "^CentOS Linux release 7" /etc/centos-release; then
			echo "你的 CentOS 版本无法运行此脚本."
			echo "此脚本只能在 CentOS 7 中运行."
			echo ""
			unset CONTINUE
			until [[ $CONTINUE =~ (y|n) ]]; do
				read -rp "是否继续? [y/n]: " -e CONTINUE
			done
			if [[ "$CONTINUE" = "n" ]]; then
				echo "好吧,再见!"
				exit 1
			fi
		fi
		OS=centos
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	else
		echo "发现你运行的Linux版本不在以下范围内: Debian, Ubuntu, Fedora, CentOS or Arch Linux system"
		exit 1
	fi
}

function initialCheck () {
	if ! isRoot; then
		echo "请使用root来进行操作"
		exit 1
	fi
	if ! tunAvailable; then
		echo "TUN 不可用"
		exit 1
	fi
	checkOS
}

function installUnbound () {
	if [[ ! -e /etc/unbound/unbound.conf ]]; then

		if [[ "$OS" =~ (debian|ubuntu) ]]; then
			apt-get install -y unbound

			# Configuration
			echo 'interface: 10.8.0.1
access-control: 10.8.0.1/24 allow
hide-identity: yes
hide-version: yes
use-caps-for-id: yes
prefetch: yes' >> /etc/unbound/unbound.conf

		elif [[ "$OS" = "centos" ]]; then
			yum install -y unbound

			# Configuration
			sed -i 's|# interface: 0.0.0.0$|interface: 10.8.0.1|' /etc/unbound/unbound.conf
			sed -i 's|# access-control: 127.0.0.0/8 allow|access-control: 10.8.0.1/24 allow|' /etc/unbound/unbound.conf
			sed -i 's|# hide-identity: no|hide-identity: yes|' /etc/unbound/unbound.conf
			sed -i 's|# hide-version: no|hide-version: yes|' /etc/unbound/unbound.conf
			sed -i 's|use-caps-for-id: no|use-caps-for-id: yes|' /etc/unbound/unbound.conf

		elif [[ "$OS" = "fedora" ]]; then
			dnf install -y unbound

			# Configuration
			sed -i 's|# interface: 0.0.0.0$|interface: 10.8.0.1|' /etc/unbound/unbound.conf
			sed -i 's|# access-control: 127.0.0.0/8 allow|access-control: 10.8.0.1/24 allow|' /etc/unbound/unbound.conf
			sed -i 's|# hide-identity: no|hide-identity: yes|' /etc/unbound/unbound.conf
			sed -i 's|# hide-version: no|hide-version: yes|' /etc/unbound/unbound.conf
			sed -i 's|# use-caps-for-id: no|use-caps-for-id: yes|' /etc/unbound/unbound.conf

		elif [[ "$OS" = "arch" ]]; then
			pacman -Syu --noconfirm unbound

			# Get root servers list
			curl -o /etc/unbound/root.hints https://www.internic.net/domain/named.cache

			mv /etc/unbound/unbound.conf /etc/unbound/unbound.conf.old
			
			echo 'server:
	use-syslog: yes
	do-daemonize: no
	username: "unbound"
	directory: "/etc/unbound"
	trust-anchor-file: trusted-key.key
	root-hints: root.hints
	interface: 10.8.0.1
	access-control: 10.8.0.1/24 allow
	port: 53
	num-threads: 2
	use-caps-for-id: yes
	harden-glue: yes
	hide-identity: yes
	hide-version: yes
	qname-minimisation: yes
	prefetch: yes' > /etc/unbound/unbound.conf
		fi

		if [[ ! "$OS" =~ (fedora|centos) ]];then
			# DNS Rebinding fix
			echo "private-address: 10.0.0.0/8
private-address: 172.16.0.0/12
private-address: 192.168.0.0/16
private-address: 169.254.0.0/16
private-address: fd00::/8
private-address: fe80::/10
private-address: 127.0.0.0/8
private-address: ::ffff:0:0/96" >> /etc/unbound/unbound.conf
		fi
	else # Unbound is already installed
		echo 'include: /etc/unbound/openvpn.conf' >> /etc/unbound/unbound.conf

		# Add Unbound 'server' for the OpenVPN subnet
		echo 'server:
interface: 10.8.0.1
access-control: 10.8.0.1/24 allow
hide-identity: yes
hide-version: yes
use-caps-for-id: yes
prefetch: yes
private-address: 10.0.0.0/8
private-address: 172.16.0.0/12
private-address: 192.168.0.0/16
private-address: 169.254.0.0/16
private-address: fd00::/8
private-address: fe80::/10
private-address: 127.0.0.0/8
private-address: ::ffff:0:0/96' > /etc/unbound/openvpn.conf
	fi

		systemctl enable unbound
		systemctl restart unbound
}

function installQuestions () {
	echo "欢迎使用OpenVPN一键安装脚本"
	echo "由于脚本安装文件源于OpenVPN官网，大陆地区服务器安装可能不正常"
	echo "脚本原作者: https://github.com/angristan/openvpn-install"
	echo "脚本汉化以及修改: 白菜 QQ:773609275"

	echo "将会询问您一些必要的安装用的信息."
	echo "你可以修改默认选项或者一直按回车使用这些默认选项."
	echo ""
	echo "我需要获取当前网络的 IPv4 地址 确保OpenVPN的正常安装."
	echo "除非你想要使用局域网，你需要有一个公网IP."

	# Detect public IPv4 address and pre-fill for the user
	IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
	read -rp "IP address: " -e -i "$IP" IP
	# If $IP is a private IP address, the server must be behind NAT
	if echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
		echo ""
		echo "这看起来像是局域网，你的公网IP地址什么?"
		echo "我们需要它来确保你的客户端连接此服务端."
		until [[ "$PUBLICIP" != "" ]]; do
			read -rp "公网IPv4地址或者域名: " -e PUBLICIP
		done
	fi

	echo ""
	echo "检查IPv6连通性..."
	echo ""
	# "ping6" and "ping -6" availability varies depending on the distribution
	if type ping6 > /dev/null 2>&1; then
		PING6="ping6 -c3 ipv6.google.com > /dev/null 2>&1"
	else
		PING6="ping -6 -c3 ipv6.google.com > /dev/null 2>&1"
	fi
	if eval "$PING6"; then
		echo "当前host IPv6 连通性正常."
		SUGGESTION="y"
	else
		echo "当前host IPv6 连通性不正常."
		SUGGESTION="n"
	fi
	echo ""
	# Ask the user if they want to enable IPv6 regardless its availability.
	until [[ $IPV6_SUPPORT =~ (y|n) ]]; do
		read -rp "是否启用 IPv6 支持 (NAT)? [y/n]: " -e -i $SUGGESTION IPV6_SUPPORT
	done
	echo ""
	echo "请选择 OpenVPN 监听的端口?"
	echo "   1) 默认: 1194"
	echo "   2) 输入"
	echo "   3) 随机 [49152-65535]"
	until [[ "$PORT_CHOICE" =~ ^[1-3]$ ]]; do
		read -rp "端口选项 [1-3]: " -e -i 1 PORT_CHOICE
	done
	case $PORT_CHOICE in
		1)
			PORT="1194"
		;;
		2)
			until [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; do
				read -rp "输入端口 [1-65535]: " -e -i 1194 PORT
			done
		;;
		3)
			# Generate random number within private ports range
			PORT=$(shuf -i49152-65535 -n1)
			echo "随机端口: $PORT"
		;;
	esac
	echo ""
	echo "OpenVPN 使用什么协议 UDP/TCP?"
	echo "UDP 十分快速. 除非UDP无法使用，不推荐使用TCP."
	echo "   1) UDP"
	echo "   2) TCP"
	until [[ "$PROTOCOL_CHOICE" =~ ^[1-2]$ ]]; do
		read -rp "Protocol [1-2]: " -e -i 1 PROTOCOL_CHOICE
	done
	case $PROTOCOL_CHOICE in
		1)
			PROTOCOL="udp"
		;;
		2)
			PROTOCOL="tcp"
		;;
	esac
	echo ""
	echo "您希望将哪个DNS解析服务用于VPN ?"
	echo "   1) 正确的系统解析器 (from /etc/resolv.conf)"
	echo "   2) 当前host DNS 解析器 (Unbound)"
	echo "   3) Cloudflare (Anycast: worldwide)"
	echo "   4) Quad9 (Anycast: worldwide)"
	echo "   5) Quad9 uncensored (Anycast: worldwide)"
	echo "   6) FDN (France)"
	echo "   7) DNS.WATCH (Germany)"
	echo "   8) OpenDNS (Anycast: worldwide)"
	echo "   9) Google (Anycast: worldwide)"
	echo "   10) Yandex Basic (Russia)"
	echo "   11) AdGuard DNS (Russia)"
	until [[ "$DNS" =~ ^[0-9]+$ ]] && [ "$DNS" -ge 1 ] && [ "$DNS" -le 11 ]; do
		read -rp "DNS [1-10]: " -e -i 3 DNS
			if [[ $DNS == 2 ]] && [[ -e /etc/unbound/unbound.conf ]]; then
				echo ""
				echo "Unbound 已经安装."
				echo "您可以允许脚本对其进行配置，以便从OpenVPN客户端使用它"
				echo "我们将简单的添加一个服务端在 /etc/unbound/unbound.conf 对于OpenVPN子网."
				echo "没有对当前配置进行任何更改."
				echo ""

				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "将配置更改应用于Unbound? 推荐默认回车 [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE = "n" ]];then
					# Break the loop and cleanup
					unset DNS
					unset CONTINUE
				fi
			fi
	done
	echo ""
	echo "你想使用压缩吗？ 由于VORACLE攻击使用它，因此不推荐使用它。"
	until [[ $COMPRESSION_ENABLED =~ (y|n) ]]; do
		read -rp"启用压缩 推荐默认回车? [y/n]: " -e -i n COMPRESSION_ENABLED
	done
	if [[ $COMPRESSION_ENABLED == "y" ]];then
		echo "选择一个压缩算法:"
		echo "   1) LZ4 (更加效率)"
		echo "   2) LZ0"
		until [[ $COMPRESSION_CHOICE =~ ^[1-2]$ ]]; do
			read -rp"压缩算法 [1-2]: " -e -i 1 COMPRESSION_CHOICE
		done
		case $COMPRESSION_CHOICE in
			1)
			COMPRESSION_ALG="lz4"
			;;
			2)
			COMPRESSION_ALG="lzo"
			;;
		esac
	fi
	echo ""
	echo "是否要自定义加密设置?"
	echo "Unless you know what you're doing, you should stick with the default parameters provided by the script."
	echo "除非你知道自己在做什么，否则你应该使用脚本提供的默认参数"
	echo "参考 https://github.com/angristan/openvpn-install#security-and-encryption 来了解更多."
	echo ""
	until [[ $CUSTOMIZE_ENC =~ (y|n) ]]; do
		read -rp "自定义加密设置? [y/n]: " -e -i n CUSTOMIZE_ENC
	done
	if [[ $CUSTOMIZE_ENC == "n" ]];then
		# Use default, sane and fast parameters
		CIPHER="AES-128-GCM"
		CERT_TYPE="1" # ECDSA
		CERT_CURVE="prime256v1"
		CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
		DH_TYPE="1" # ECDH
		DH_CURVE="prime256v1"
		HMAC_ALG="SHA256"
		TLS_SIG="1" # tls-crypt
	else
		echo ""
		echo "选择要用于数据通道的加密方式:"
		echo "   1) AES-128-GCM (recommended)"
		echo "   2) AES-192-GCM"
		echo "   3) AES-256-GCM"
		echo "   4) AES-128-CBC"
		echo "   5) AES-192-CBC"
		echo "   6) AES-256-CBC"
		until [[ "$CIPHER_CHOICE" =~ ^[1-6]$ ]]; do
			read -rp "加密方式 [1-6]: " -e -i 1 CIPHER_CHOICE
		done
		case $CIPHER_CHOICE in
			1)
				CIPHER="AES-128-GCM"
			;;
			2)
				CIPHER="AES-192-GCM"
			;;
			3)
				CIPHER="AES-256-GCM"
			;;
			4)
				CIPHER="AES-128-CBC"
			;;
			5)
				CIPHER="AES-192-CBC"
			;;
			6)
				CIPHER="AES-256-CBC"
			;;
		esac
		echo ""
		echo "选择您要使用的证书类型:"
		echo "   1) ECDSA (recommended)"
		echo "   2) RSA"
		until [[ $CERT_TYPE =~ ^[1-2]$ ]]; do
			read -rp"证书类型 [1-2]: " -e -i 1 CERT_TYPE
		done
		case $CERT_TYPE in
			1)
				echo ""
				echo "选择要用于证书密钥的协议:"
				echo "   1) prime256v1 (recommended)"
				echo "   2) secp384r1"
				echo "   3) secp521r1"
				until [[ $CERT_CURVE_CHOICE =~ ^[1-3]$ ]]; do
					read -rp"Curve [1-3]: " -e -i 1 CERT_CURVE_CHOICE
				done
				case $CERT_CURVE_CHOICE in
					1)
						CERT_CURVE="prime256v1"
					;;
					2)
						CERT_CURVE="secp384r1"
					;;
					3)
						CERT_CURVE="secp521r1"
					;;
				esac
			;;
			2)
				echo ""
				echo "选择要用于证书的RSA密钥的大小:"
				echo "   1) 2048 bits (recommended)"
				echo "   2) 3072 bits"
				echo "   3) 4096 bits"
				until [[ "$RSA_KEY_SIZE_CHOICE" =~ ^[1-3]$ ]]; do
					read -rp "RSA key size [1-3]: " -e -i 1 RSA_KEY_SIZE_CHOICE
				done
				case $RSA_KEY_SIZE_CHOICE in
					1)
						RSA_KEY_SIZE="2048"
					;;
					2)
						RSA_KEY_SIZE="3072"
					;;
					3)
						RSA_KEY_SIZE="4096"
					;;
				esac
			;;
		esac
		echo ""
		echo "选择要用于控制通道的加密方式:"
		case $CERT_TYPE in
			1)
				echo "   1) ECDHE-ECDSA-AES-128-GCM-SHA256 (recommended)"
				echo "   2) ECDHE-ECDSA-AES-256-GCM-SHA384"
				until [[ $CC_CIPHER_CHOICE =~ ^[1-2]$ ]]; do
					read -rp"Control channel cipher [1-2]: " -e -i 1 CC_CIPHER_CHOICE
				done
				case $CC_CIPHER_CHOICE in
					1)
						CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
					;;
					2)
						CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384"
					;;
				esac
			;;
			2)
				echo "   1) ECDHE-RSA-AES-128-GCM-SHA256 (recommended)"
				echo "   2) ECDHE-RSA-AES-256-GCM-SHA384"
				until [[ $CC_CIPHER_CHOICE =~ ^[1-2]$ ]]; do
					read -rp"Control channel cipher [1-2]: " -e -i 1 CC_CIPHER_CHOICE
				done
				case $CC_CIPHER_CHOICE in
					1)
						CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256"
					;;
					2)
						CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384"
					;;
				esac
			;;
		esac
		echo ""
		echo "选择您要使用的Diffie-Hellman口令:"
		echo "   1) ECDH (recommended)"
		echo "   2) DH"
		until [[ $DH_TYPE =~ [1-2] ]]; do
			read -rp"DH 口令类型 [1-2]: " -e -i 1 DH_TYPE
		done
		case $DH_TYPE in
			1)
				echo ""
				echo "选择要用于ECDH口令:"
				echo "   1) prime256v1 (recommended)"
				echo "   2) secp384r1"
				echo "   3) secp521r1"
				while [[ $DH_CURVE_CHOICE != "1" && $DH_CURVE_CHOICE != "2" && $DH_CURVE_CHOICE != "3" ]]; do
					read -rp"Curve [1-3]: " -e -i 1 DH_CURVE_CHOICE
				done
				case $DH_CURVE_CHOICE in
					1)
						DH_CURVE="prime256v1"
					;;
					2)
						DH_CURVE="secp384r1"
					;;
					3)
						DH_CURVE="secp521r1"
					;;
				esac
			;;
			2)
				echo ""
				echo "选择要使用的Diffie-Hellman键的大小:"
				echo "   1) 2048 bits (recommended)"
				echo "   2) 3072 bits"
				echo "   3) 4096 bits"
				until [[ "$DH_KEY_SIZE_CHOICE" =~ ^[1-3]$ ]]; do
					read -rp "DH key size [1-3]: " -e -i 1 DH_KEY_SIZE_CHOICE
				done
				case $DH_KEY_SIZE_CHOICE in
					1)
						DH_KEY_SIZE="2048"
					;;
					2)
						DH_KEY_SIZE="3072"
					;;
					3)
						DH_KEY_SIZE="4096"
					;;
				esac
			;;
		esac
		echo ""
		# The "auth" options behaves differently with AEAD ciphers
		if [[ "$CIPHER" =~ CBC$ ]]; then
			echo "摘要算法验证来自控制信道的数据信道分组和tls-auth分组."
		elif [[ "$CIPHER" =~ GCM$ ]]; then
			echo "摘要算法验证来自控制信道的tls-auth数据包."
		fi
		echo "哪种摘要算法用于你的 HMAC?"
		echo "   1) SHA-256 (recommended)"
		echo "   2) SHA-384"
		echo "   3) SHA-512"
		until [[ $HMAC_ALG_CHOICE =~ ^[1-3]$ ]]; do
			read -rp "Digest algorithm [1-3]: " -e -i 1 HMAC_ALG_CHOICE
		done
		case $HMAC_ALG_CHOICE in
			1)
				HMAC_ALG="SHA256"
			;;
			2)
				HMAC_ALG="SHA384"
			;;
			3)
				HMAC_ALG="SHA512"
			;;
		esac
		echo ""
		echo "您可以使用tls-auth和tls-crypt向控制通道添加额外的安全层"
		echo "tls-auth对数据包进行身份验证，而tls-crypt对其进行身份验证和加密."
		echo "   1) tls-crypt (recommended)"
		echo "   2) tls-auth"
		until [[ $TLS_SIG =~ [1-2] ]]; do
				read -rp "Control channel additional security mechanism [1-2]: " -e -i 1 TLS_SIG
		done
	fi
	echo ""
	echo "安装信息收集完成，现在准备好设置您的OpenVPN服务器."
	echo "您将能够在安装结束时生成客户端."
	read -n1 -r -p "按下任意键继续..."
}

function installOpenVPN () {
	# Run setup questions first
	installQuestions

	# Get the "public" interface from the default route
	NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

	if [[ "$OS" =~ (debian|ubuntu) ]]; then
		apt-get update
		apt-get -y install ca-certificates gnupg
		# We add the OpenVPN repo to get the latest version.
		if [[ "$VERSION_ID" = "8" ]]; then
			echo "deb http://build.openvpn.net/debian/openvpn/stable jessie main" > /etc/apt/sources.list.d/openvpn.list
			wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
			apt-get update
		fi
		if [[ "$VERSION_ID" = "16.04" ]]; then
			echo "deb http://build.openvpn.net/debian/openvpn/stable trusty main" > /etc/apt/sources.list.d/openvpn.list
			wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
			apt-get update
		fi
		# Ubuntu > 16.04 and Debian > 8 have OpenVPN >= 2.4 without the need of a third party repository.
		apt-get install -y openvpn iptables openssl wget ca-certificates curl
	elif [[ "$OS" = 'centos' ]]; then
		yum install -y epel-release
		yum install -y openvpn iptables openssl wget ca-certificates curl
	elif [[ "$OS" = 'fedora' ]]; then
		dnf install -y openvpn iptables openssl wget ca-certificates curl
	elif [[ "$OS" = 'arch' ]]; then
		echo ""
		echo "警告：当您使用ArchLinux时，我需要更新系统上的软件包以安装我需要的软件包."
		echo "不这样做可能会导致依赖关系之间出现问题，或者丢失存储库中的文件（Arch Linux不支持部分升级）."
		echo ""
		echo "继续将更新您安装的软件包并安装所需的软件包."
		echo ""
		unset CONTINUE
		until [[ $CONTINUE =~ (y|n) ]]; do
			read -rp "继续? [y/n]: " -e -i y CONTINUE
		done
		if [[ "$CONTINUE" = "n" ]]; then
			echo "终止安装 是用户不允许更新系统."
			exit 4
		fi

		# Install required dependencies and upgrade the system
		pacman --needed --noconfirm -Syu openvpn iptables openssl wget ca-certificates curl
	fi

	# Find out if the machine uses nogroup or nobody for the permissionless group
	if grep -qs "^nogroup:" /etc/group; then
		NOGROUP=nogroup
	else
		NOGROUP=nobody
	fi

	# An old version of easy-rsa was available by default in some openvpn packages
	if [[ -d /etc/openvpn/easy-rsa/ ]]; then
		rm -rf /etc/openvpn/easy-rsa/
	fi

	# Install the latest version of easy-rsa from source
	local version="3.0.5"
	wget -O ~/EasyRSA-nix-${version}.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v${version}/EasyRSA-nix-${version}.tgz
	tar xzf ~/EasyRSA-nix-${version}.tgz -C ~/
	mv ~/EasyRSA-${version}/ /etc/openvpn/
	mv /etc/openvpn/EasyRSA-${version}/ /etc/openvpn/easy-rsa/
	chown -R root:root /etc/openvpn/easy-rsa/
	rm -f ~/EasyRSA-nix-${version}.tgz

	cd /etc/openvpn/easy-rsa/
	case $CERT_TYPE in
		1)
			echo "set_var EASYRSA_ALGO ec" > vars
			echo "set_var EASYRSA_CURVE $CERT_CURVE" >> vars
		;;
		2)
			echo "set_var EASYRSA_KEY_SIZE $RSA_KEY_SIZE" > vars
		;;
	esac

	# Generate a random, alphanumeric identifier of 16 characters for CN and one for server name
	SERVER_CN="cn_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
	SERVER_NAME="server_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
	echo "set_var EASYRSA_REQ_CN $SERVER_CN" >> vars
	# Create the PKI, set up the CA, the DH params and the server certificate
	./easyrsa init-pki
	./easyrsa --batch build-ca nopass

	if [[ $DH_TYPE == "2" ]]; then
		# ECDH keys are generated on-the-fly so we don't need to generate them beforehand
		openssl dhparam -out dh.pem $DH_KEY_SIZE
	fi
	
	./easyrsa build-server-full "$SERVER_NAME" nopass
	EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
	
	case $TLS_SIG in
		1)
			# Generate tls-crypt key
			openvpn --genkey --secret /etc/openvpn/tls-crypt.key
		;;
		2)
			# Generate tls-auth key
			openvpn --genkey --secret /etc/openvpn/tls-auth.key
		;;
	esac
	
	# Move all the generated files
	cp pki/ca.crt pki/private/ca.key "pki/issued/$SERVER_NAME.crt" "pki/private/$SERVER_NAME.key" /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn
	if [[ $DH_TYPE == "2" ]]; then
		cp dh.pem /etc/openvpn
	fi
	
	# Make cert revocation list readable for non-root
	chmod 644 /etc/openvpn/crl.pem

	# Generate server.conf
	echo "port $PORT" > /etc/openvpn/server.conf
	if [[ "$IPV6_SUPPORT" = 'n' ]]; then
		echo "proto $PROTOCOL" >> /etc/openvpn/server.conf
	elif [[ "$IPV6_SUPPORT" = 'y' ]]; then
		echo "proto ${PROTOCOL}6" >> /etc/openvpn/server.conf
	fi

	echo "dev tun
user nobody
group $NOGROUP
persist-key
persist-tun
keepalive 10 120
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt" >> /etc/openvpn/server.conf

	# DNS resolvers
	case $DNS in
		1)
			# Locate the proper resolv.conf
			# Needed for systems running systemd-resolved
			if grep -q "127.0.0.53" "/etc/resolv.conf"; then
				RESOLVCONF='/run/systemd/resolve/resolv.conf'
			else
				RESOLVCONF='/etc/resolv.conf'
			fi
			# Obtain the resolvers from resolv.conf and use them for OpenVPN
			grep -v '#' $RESOLVCONF | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read -r line; do
				echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server.conf
			done
		;;
		2)
			echo 'push "dhcp-option DNS 10.8.0.1"' >> /etc/openvpn/server.conf
		;;
		3) # Cloudflare
			echo 'push "dhcp-option DNS 1.0.0.1"' >> /etc/openvpn/server.conf
			echo 'push "dhcp-option DNS 1.1.1.1"' >> /etc/openvpn/server.conf
		;;
		4) # Quad9
			echo 'push "dhcp-option DNS 9.9.9.9"' >> /etc/openvpn/server.conf
			echo 'push "dhcp-option DNS 149.112.112.112"' >> /etc/openvpn/server.conf
		;;
		5) # Quad9 uncensored
			echo 'push "dhcp-option DNS 9.9.9.10"' >> /etc/openvpn/server.conf
			echo 'push "dhcp-option DNS 149.112.112.10"' >> /etc/openvpn/server.conf
		;;
		6) # FDN
			echo 'push "dhcp-option DNS 80.67.169.40"' >> /etc/openvpn/server.conf
			echo 'push "dhcp-option DNS 80.67.169.12"' >> /etc/openvpn/server.conf
		;;
		7) # DNS.WATCH
			echo 'push "dhcp-option DNS 84.200.69.80"' >> /etc/openvpn/server.conf
			echo 'push "dhcp-option DNS 84.200.70.40"' >> /etc/openvpn/server.conf
		;;
		8) # OpenDNS
			echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server.conf
			echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server.conf
		;;
		9) # Google
			echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server.conf
			echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server.conf
		;;
		10) # Yandex Basic
			echo 'push "dhcp-option DNS 77.88.8.8"' >> /etc/openvpn/server.conf
			echo 'push "dhcp-option DNS 77.88.8.1"' >> /etc/openvpn/server.conf
		;;
		11) # AdGuard DNS
			echo 'push "dhcp-option DNS 176.103.130.130"' >> /etc/openvpn/server.conf
			echo 'push "dhcp-option DNS 176.103.130.131"' >> /etc/openvpn/server.conf
		;;
	esac
	echo 'push "redirect-gateway def1 bypass-dhcp" '>> /etc/openvpn/server.conf

	# IPv6 network settings if needed
	if [[ "$IPV6_SUPPORT" = 'y' ]]; then
		echo 'server-ipv6 fd42:42:42:42::/112
tun-ipv6
push tun-ipv6
push "route-ipv6 2000::/3"
push "redirect-gateway ipv6"' >> /etc/openvpn/server.conf
	fi

	if [[ $COMPRESSION_ENABLED == "y"  ]]; then
		echo "compress $COMPRESSION_ALG" >> /etc/openvpn/server.conf
	fi

	if [[ $DH_TYPE == "1" ]]; then
		echo "dh none" >> /etc/openvpn/server.conf
		echo "ecdh-curve $DH_CURVE" >> /etc/openvpn/server.conf
	elif [[ $DH_TYPE == "2" ]]; then
		echo "dh dh.pem" >> /etc/openvpn/server.conf
	fi

	case $TLS_SIG in
		1)
			echo "tls-crypt tls-crypt.key 0" >> /etc/openvpn/server.conf
		;;
		2)
			echo "tls-auth tls-auth.key 0" >> /etc/openvpn/server.conf
		;;
	esac

	echo "crl-verify crl.pem
ca ca.crt
cert $SERVER_NAME.crt
key $SERVER_NAME.key 
auth $HMAC_ALG
cipher $CIPHER
ncp-ciphers $CIPHER
tls-server
tls-version-min 1.2
tls-cipher $CC_CIPHER
status /var/log/openvpn/status.log
verb 3" >> /etc/openvpn/server.conf

	# Create log dir
	mkdir -p /var/log/openvpn

	# Enable routing
	echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
	if [[ "$IPV6_SUPPORT" = 'y' ]]; then
		echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
	fi
	# Avoid an unneeded reboot
	sysctl --system

	# If SELinux is enabled and a custom port was selected, we need this
	if hash sestatus 2>/dev/null; then
		if sestatus | grep "Current mode" | grep -qs "enforcing"; then
			if [[ "$PORT" != '1194' ]]; then
				semanage port -a -t openvpn_port_t -p "$PROTOCOL" "$PORT"
			fi
		fi
	fi

	# Finally, restart and enable OpenVPN
	if [[ "$OS" = 'arch' || "$OS" = 'fedora' ]]; then
		# Don't modify package-provided service
		cp /usr/lib/systemd/system/openvpn-server@.service /etc/systemd/system/openvpn-server@.service
		
		# Workaround to fix OpenVPN service on OpenVZ
		sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn-server@.service
		# Another workaround to keep using /etc/openvpn/
		sed -i 's|/etc/openvpn/server|/etc/openvpn|' /etc/systemd/system/openvpn-server@.service
		# On fedora, the service hardcodes the ciphers. We want to manage the cipher ourselves, so we remove it from the service
		if [[ "$OS" == "fedora" ]];then
			sed -i 's|--cipher AES-256-GCM --ncp-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC:AES-128-CBC:BF-CBC||' /etc/systemd/system/openvpn-server@.service
		fi

		systemctl daemon-reload
		systemctl restart openvpn-server@server
		systemctl enable openvpn-server@server
	elif [[ "$OS" == "ubuntu" ]] && [[ "$VERSION_ID" == "16.04" ]]; then
		# On Ubuntu 16.04, we use the package from the OpenVPN repo
		# This package uses a sysvinit service
		systemctl enable openvpn
		systemctl start openvpn
	else
		# Don't modify package-provided service
		cp /lib/systemd/system/openvpn\@.service /etc/systemd/system/openvpn\@.service
		
		# Workaround to fix OpenVPN service on OpenVZ
		sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn\@.service
		# Another workaround to keep using /etc/openvpn/
		sed -i 's|/etc/openvpn/server|/etc/openvpn|' /etc/systemd/system/openvpn\@.service
		
		systemctl daemon-reload
		systemctl restart openvpn@server
		systemctl enable openvpn@server
	fi

	if [[ $DNS == 2 ]];then
		installUnbound
	fi

	# Add iptables rules in two scripts
	mkdir /etc/iptables

	# Script to add rules
	echo "#!/bin/sh
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $NIC -j MASQUERADE
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A FORWARD -i $NIC -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o $NIC -j ACCEPT
iptables -A INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" > /etc/iptables/add-openvpn-rules.sh

	if [[ "$IPV6_SUPPORT" = 'y' ]]; then
		echo "ip6tables -t nat -A POSTROUTING -s fd42:42:42:42::/112 -o $NIC -j MASQUERADE
ip6tables -A INPUT -i tun0 -j ACCEPT
ip6tables -A FORWARD -i $NIC -o tun0 -j ACCEPT
ip6tables -A FORWARD -i tun0 -o $NIC -j ACCEPT" >> /etc/iptables/add-openvpn-rules.sh
	fi

	# Script to remove rules
	echo "#!/bin/sh
iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $NIC -j MASQUERADE
iptables -D INPUT -i tun0 -j ACCEPT
iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT
iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT
iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" > /etc/iptables/rm-openvpn-rules.sh

	if [[ "$IPV6_SUPPORT" = 'y' ]]; then
		echo "ip6tables -t nat -D POSTROUTING -s fd42:42:42:42::/112 -o $NIC -j MASQUERADE
ip6tables -D INPUT -i tun0 -j ACCEPT
ip6tables -D FORWARD -i $NIC -o tun0 -j ACCEPT
ip6tables -D FORWARD -i tun0 -o $NIC -j ACCEPT" >> /etc/iptables/rm-openvpn-rules.sh
	fi

	chmod +x /etc/iptables/add-openvpn-rules.sh
	chmod +x /etc/iptables/rm-openvpn-rules.sh

	# Handle the rules via a systemd script
	echo "[Unit]
Description=iptables rules for OpenVPN
Before=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/add-openvpn-rules.sh
ExecStop=/etc/iptables/rm-openvpn-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/iptables-openvpn.service

	# Enable service and apply rules
	systemctl daemon-reload
	systemctl enable iptables-openvpn
	systemctl start iptables-openvpn

	# If the server is behind a NAT, use the correct IP address for the clients to connect to
	if [[ "$PUBLICIP" != "" ]]; then
		IP=$PUBLICIP
	fi

	# client-template.txt is created so we have a template to add further users later
	echo "client" > /etc/openvpn/client-template.txt
	if [[ "$PROTOCOL" = 'udp' ]]; then
		echo "proto udp" >> /etc/openvpn/client-template.txt
	elif [[ "$PROTOCOL" = 'tcp' ]]; then
		echo "proto tcp-client" >> /etc/openvpn/client-template.txt
	fi
	echo "remote $IP $PORT
dev tun
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verify-x509-name $SERVER_NAME name
auth $HMAC_ALG
auth-nocache
cipher $CIPHER
tls-client
tls-version-min 1.2
tls-cipher $CC_CIPHER
setenv opt block-outside-dns # Prevent Windows 10 DNS leak
verb 3" >> /etc/openvpn/client-template.txt

if [[ $COMPRESSION_ENABLED == "y"  ]]; then
	echo "compress $COMPRESSION_ALG" >> /etc/openvpn/client-template.txt
fi

	# Generate the custom client.ovpn
	newClient
	echo "如果要添加更多客户端，只需再次运行此脚本即可"
}

function newClient () {
	echo ""
	echo "输入用户的用户名."
	echo "请不要输入特殊字符."

	until [[ "$CLIENT" =~ ^[a-zA-Z0-9_]+$ ]]; do
		read -rp "用户名: " -e CLIENT
	done

	echo ""
	echo "是否要使用密码认证配置文件?"
	echo "(e.g. 使用密码加密私钥)"
	echo "   1) 添加一个不需要密码的用户"
	echo "   2) 添加一个需要密码的用户"

	until [[ "$PASS" =~ ^[1-2]$ ]]; do
		read -rp "Select an option [1-2]: " -e -i 1 PASS
	done

	cd /etc/openvpn/easy-rsa/ || return
	case $PASS in
		1)
			./easyrsa build-client-full "$CLIENT" nopass
		;;
		2)
		echo "⚠️ 您将被要求提供用户的密码 ⚠️"
			./easyrsa build-client-full "$CLIENT"
		;;
	esac

	# Home directory of the user, where the client configuration (.ovpn) will be written
	if [ -e "/home/$CLIENT" ]; then  # if $1 is a user name
		homeDir="/home/$CLIENT"
	elif [ "${SUDO_USER}" ]; then   # if not, use SUDO_USER
		homeDir="/home/${SUDO_USER}"
	else  # if not SUDO_USER, use /root
		homeDir="/root"
	fi

	# Determine if we use tls-auth or tls-crypt
	if grep -qs "^tls-crypt" /etc/openvpn/server.conf; then
		TLS_SIG="1"
	elif grep -qs "^tls-auth" /etc/openvpn/server.conf; then
		TLS_SIG="2"
	fi

	# Generates the custom client.ovpn
	cp /etc/openvpn/client-template.txt "$homeDir/$CLIENT.ovpn"
	{
		echo "<ca>"
		cat "/etc/openvpn/easy-rsa/pki/ca.crt"
		echo "</ca>"

		echo "<cert>"
		awk '/BEGIN/,/END/' "/etc/openvpn/easy-rsa/pki/issued/$CLIENT.crt"
		echo "</cert>"

		echo "<key>"
		cat "/etc/openvpn/easy-rsa/pki/private/$CLIENT.key"
		echo "</key>"

		case $TLS_SIG in
			1)
				echo "<tls-crypt>"
				cat /etc/openvpn/tls-crypt.key
				echo "</tls-crypt>"
			;;
			2)
				echo "key-direction 1"
				echo "<tls-auth>"
				cat /etc/openvpn/tls-auth.key
				echo "</tls-auth>"
			;;
		esac
	} >> "$homeDir/$CLIENT.ovpn"

	echo ""
	echo "Client $CLIENT added, the configuration file is available at $homeDir/$CLIENT.ovpn."
	echo "下载 .ovpn 配置文件并且导入到你的OpenVPN客户端."
}

function revokeClient () {
	NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
	if [[ "$NUMBEROFCLIENTS" = '0' ]]; then
		echo ""
		echo "当前没有用户!"
		exit 1
	fi

	echo ""
	echo "Select the existing client certificate you want to revoke"
	tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
	if [[ "$NUMBEROFCLIENTS" = '1' ]]; then
		read -rp "选择一个用户 [1]: " CLIENTNUMBER
	else
		read -rp "选择一个用户 [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
	fi

	CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$CLIENTNUMBER"p)
	cd /etc/openvpn/easy-rsa/
	./easyrsa --batch revoke "$CLIENT"
	EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
	# Cleanup
	rm -f "pki/reqs/$CLIENT.req"
	rm -f "pki/private/$CLIENT.key"
	rm -f "pki/issued/$CLIENT.crt"
	rm -f /etc/openvpn/crl.pem
	cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
	chmod 644 /etc/openvpn/crl.pem
	find /home/ -maxdepth 2 -name "$CLIENT.ovpn" -delete
	rm -f "/root/$CLIENT.ovpn"
	sed -i "s|^$CLIENT,.*||" /etc/openvpn/ipp.txt

	echo ""
	echo "客户端证书 $CLIENT 已经移除."
}

function removeUnbound () {
	# Remove OpenVPN-related config
	sed -i 's|include: \/etc\/unbound\/openvpn.conf||' /etc/unbound/unbound.conf
	rm /etc/unbound/openvpn.conf
	systemctl restart unbound

	until [[ $REMOVE_UNBOUND =~ (y|n) ]]; do
		echo ""
		echo "如果您在安装OpenVPN之前已经使用了Unbound，我删除了与OpenVPN相关的配置."
		read -rp "确定完全删除 Unbound? [y/n]: " -e REMOVE_UNBOUND
	done

	if [[ "$REMOVE_UNBOUND" = 'y' ]]; then
		# Stop Unbound
		systemctl stop unbound

		if [[ "$OS" =~ (debian|ubuntu) ]]; then
			apt-get autoremove --purge -y unbound
		elif [[ "$OS" = 'arch' ]]; then
			pacman --noconfirm -R unbound
		elif [[ "$OS" = 'centos' ]]; then
			yum remove -y unbound
		elif [[ "$OS" = 'fedora' ]]; then
			dnf remove -y unbound
		fi

		rm -rf /etc/unbound/

		echo ""
		echo "Unbound 删除成功!"
	else
		echo ""
		echo "Unbound 删除终止."
	fi
}

function removeOpenVPN () {
	echo ""
	read -rp "确定要卸载OpenVPN? [y/n]: " -e -i n REMOVE
	if [[ "$REMOVE" = 'y' ]]; then
		# Get OpenVPN port from the configuration
		PORT=$(grep '^port ' /etc/openvpn/server.conf | cut -d " " -f 2)

		# Stop OpenVPN
		if [[ "$OS" =~ (fedora|arch) ]]; then
			systemctl disable openvpn-server@server
			systemctl stop openvpn-server@server
			# Remove customised service
			rm /etc/systemd/system/openvpn-server@.service
		elif [[ "$OS" == "ubuntu" ]] && [[ "$VERSION_ID" == "16.04" ]]; then
			systemctl disable openvpn
			systemctl stop openvpn
		else
			systemctl disable openvpn@server
			systemctl stop openvpn@server
			# Remove customised service
			rm /etc/systemd/system/openvpn\@.service
		fi

		# Remove the iptables rules related to the script
		systemctl stop iptables-openvpn
		# Cleanup
		systemctl disable iptables-openvpn
		rm /etc/systemd/system/iptables-openvpn.service
		systemctl daemon-reload
		rm /etc/iptables/add-openvpn-rules.sh
		rm /etc/iptables/rm-openvpn-rules.sh

		# SELinux
		if hash sestatus 2>/dev/null; then
			if sestatus | grep "Current mode" | grep -qs "enforcing"; then
				if [[ "$PORT" != '1194' ]]; then
					semanage port -d -t openvpn_port_t -p udp "$PORT"
				fi
			fi
		fi

		if [[ "$OS" =~ (debian|ubuntu) ]]; then
			apt-get autoremove --purge -y openvpn
			if [[ -e /etc/apt/sources.list.d/openvpn.list ]];then
				rm /etc/apt/sources.list.d/openvpn.list
				apt-get update
			fi
		elif [[ "$OS" = 'arch' ]]; then
			pacman --noconfirm -R openvpn
		elif [[ "$OS" = 'centos' ]]; then
			yum remove -y openvpn
		elif [[ "$OS" = 'fedora' ]]; then
			dnf remove -y openvpn
		fi

		# Cleanup
		find /home/ -maxdepth 2 -name "*.ovpn" -delete
		find /root/ -maxdepth 1 -name "*.ovpn" -delete
		rm -rf /etc/openvpn
		rm -rf /usr/share/doc/openvpn*
		rm -f /etc/sysctl.d/20-openvpn.conf
		rm -rf /var/log/openvpn

		# Unbound
		if [[ -e /etc/unbound/openvpn.conf ]]; then
			removeUnbound
		fi
		echo ""
		echo "OpenVPN 卸载成功!"
	else
		echo ""
		echo "卸载终止!"
	fi
}

function manageMenu () {
	clear
	echo "欢迎使用OpenVPN一键脚本!"
	echo "脚本原作者: https://github.com/angristan/openvpn-install"
	echo "脚本汉化: 白菜 QQ:773609275"
	echo ""
	echo "OpenVPN 已经正常安装."
	echo ""
	echo "请选择你要进行的操作?"
	echo "   1) 添加一个用户"
	echo "   2) 删除一个存在的用户"
	echo "   3) 卸载OpenVPN"
	echo "   4) 退出"
	until [[ "$MENU_OPTION" =~ ^[1-4]$ ]]; do
		read -rp "选择选项 [1-4]: " MENU_OPTION
	done

	case $MENU_OPTION in
		1)
			newClient
		;;
		2)
			revokeClient
		;;
		3)
			removeOpenVPN
		;;
		4)
			exit 0
		;;
	esac
}

# Check for root, TUN, OS...
initialCheck

# Check if OpenVPN is already installed
if [[ -e /etc/openvpn/server.conf ]]; then
	manageMenu
else
	installOpenVPN
fi
