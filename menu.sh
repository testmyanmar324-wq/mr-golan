#!/bin/bash
‎clear
‎
‎# الألوان
‎RED='\033[1;31m'
‎GREEN='\033[1;32m'
‎YELLOW='\033[1;33m'
‎BLUE='\033[1;34m'
‎MAGENTA='\033[1;35m'
‎CYAN='\033[1;36m'
‎NC='\033[0m'
‎
‎if [[ "$(whoami)" != "root" ]]; then
‎    echo -e "${RED}Error: You must run this script as root.${NC}"
‎    exit 1
‎fi
‎
‎# اكتشاف IP السيرفر تلقائياً
‎echo -e "${YELLOW}[*] Detecting server IP...${NC}"
‎SERVER_IP=$(hostname -I | awk '{print $1}')
‎
‎if [ -z "$SERVER_IP" ]; then
‎    echo -e "${RED}❌ Could not detect IP. Please enter it manually:${NC}"
‎    read -p "Enter your server IP: " SERVER_IP
‎fi
‎
‎echo -e "${CYAN}=============================================${NC}"
‎echo -e "${GREEN}   Installing Secure SSL & WebSocket Proxy   ${NC}"
‎echo -e "${CYAN}=============================================${NC}"
‎echo -e "${YELLOW}[*] Server IP: ${SERVER_IP}${NC}"
‎echo -e "${YELLOW}[*] Updating system and installing dependencies...${NC}"
‎apt update -y && apt install python3 openssl dropbear -y > /dev/null 2>&1
‎
‎# توليد شهادة الأمان (CN فقط بدون أي بيانات إضافية)
‎echo -e "${YELLOW}[*] Generating SSL Certificate...${NC}"
‎mkdir -p /etc/ssl/certs /etc/ssl/private
‎openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
‎  -keyout /etc/ssl/private/proxy.key \
‎  -out /etc/ssl/certs/proxy.crt \
‎  -subj "/CN=${SERVER_IP}" > /dev/null 2>&1
‎
‎# إنشاء البانر
‎echo -e "${YELLOW}[*] Setting up Banner...${NC}"
‎BANNER_TEXT="★════════════════════════════════════════════════════════★
‎★                                                        ★
‎★              ♦♦♦  GOLAN 400  ♦♦♦                     ★
‎★                                                        ★
‎★           ★ PREMIUM SECURE CONNECTION ★              ★
‎★                                                        ★
‎★              ♦♦♦  GOLAN 400  ♦♦♦                     ★
‎★                                                        ★
‎★════════════════════════════════════════════════════════★"
‎
‎echo "$BANNER_TEXT" > /etc/ssh/banner
‎echo "$BANNER_TEXT" > /etc/dropbear/banner 2>/dev/null || true
‎chmod 644 /etc/ssh/banner /etc/dropbear/banner 2>/dev/null
‎
‎# تفعيل البانر في OpenSSH
‎sed -i '/^Banner /d' /etc/ssh/sshd_config 2>/dev/null
‎echo "Banner /etc/ssh/banner" >> /etc/ssh/sshd_config
‎systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
‎
‎# تفعيل البانر في Dropbear
‎if [ -f /etc/default/dropbear ]; then
‎    sed -i 's|^DROPBEAR_EXTRA_ARGS=.*|DROPBEAR_EXTRA_ARGS="-p 2222 -b /etc/dropbear/banner"|' /etc/default/dropbear
‎    sed -i 's|^NO_START=.*|NO_START=0|' /etc/default/dropbear
‎    systemctl restart dropbear 2>/dev/null
‎fi
‎
‎echo -e "${YELLOW}[*] Creating secure multi-port proxy script (63 Ports)...${NC}"
‎cat << 'PYEOF' > /usr/local/bin/cf_multi_proxy.py
‎import socket
‎import threading
‎import ssl
‎import time
‎
‎# 35 بورت للبايلود
‎UNSECURE_PORTS = [80, 8080, 8081, 8082, 8880, 8888, 2052, 2082, 2086, 2095, 3128, 1080, 1081, 1082, 1083, 1084, 1085, 9050, 9051, 88118, 8008, 5000, 5001, 3000, 3001, 4000, 4001, 8000, 8001, 8002, 8003, 8004, 8005, 8006, 8007]
‎# 28 بورت للـ SSL
‎SECURE_PORTS = [443, 4443, 8443, 8883, 9443, 2053, 2083, 2087, 2096, 1443, 3443, 5443, 6443, 7443, 8083, 8084, 8085, 8086, 8087, 8088, 8089, 8090, 9090, 9091, 9092, 9093, 9094, 9095]
‎
‎SSH_PORT = 22
‎HTTP_RESPONSE = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
‎CERT_FILE = "/etc/ssl/certs/proxy.crt"
‎KEY_FILE = "/etc/ssl/private/proxy.key"
‎
‎def set_keepalive(sock):
‎    """تفعيل Keep-Alive على مستوى نظام التشغيل"""
‎    sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
‎    try:
‎        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 60)
‎        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 10)
‎        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 6)
‎    except (AttributeError, OSError):
‎        pass
‎
‎def forward_traffic(source, destination):
‎    """نقل البيانات بشكل مستقر بدون إغلاق مفاجئ"""
‎    try:
‎        set_keepalive(source)
‎        set_keepalive(destination)
‎        source.settimeout(None)
‎        destination.settimeout(None)
‎        
‎        while True:
‎            try:
‎                data = source.recv(8192)
‎                if not data:
‎                    time.sleep(0.5)
‎                    try:
‎                        data2 = source.recv(8192)
‎                        if not data2:
‎                            break
‎                        else:
‎                            destination.sendall(data2)
‎                            continue
‎                    except:
‎                        break
‎                destination.sendall(data)
‎            except (ssl.SSLWantReadError, ssl.SSLWantWriteError):
‎                time.sleep(0.1)
‎                continue
‎            except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError, OSError):
‎                break
‎            except ssl.SSLError:
‎                break
‎            except Exception:
‎                break
‎    except Exception:
‎        pass
‎    finally:
‎        for s in (source, destination):
‎            try: s.shutdown(socket.SHUT_RDWR)
‎            except: pass
‎            try: s.close()
‎            except: pass
‎
‎def create_ssl_context():
‎    try:
‎        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
‎        context.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
‎        context.check_hostname = False
‎        context.verify_mode = ssl.CERT_NONE
‎        context.options |= ssl.OP_NO_COMPRESSION
‎        context.set_ciphers('DEFAULT:@SECLEVEL=0')
‎        return context
‎    except Exception:
‎        return None
‎
‎def handle_client(client_socket, is_secure):
‎    try:
‎        client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
‎        client_socket.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
‎        
‎        if is_secure:
‎            ssl_context = create_ssl_context()
‎            if ssl_context:
‎                try:
‎                    client_socket = ssl_context.wrap_socket(client_socket, server_side=True)
‎                except Exception:
‎                    client_socket.close()
‎                    return
‎            
‎            ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
‎            ssh_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
‎            ssh_socket.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
‎            ssh_socket.connect(("127.0.0.1", SSH_PORT))
‎        else:
‎            try:
‎                client_socket.settimeout(5)
‎                client_socket.recv(2048)
‎                client_socket.settimeout(None)
‎            except:
‎                client_socket.settimeout(None)
‎            
‎            client_socket.sendall(HTTP_RESPONSE)
‎            
‎            ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
‎            ssh_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
‎            ssh_socket.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
‎            ssh_socket.connect(("127.0.0.1", SSH_PORT))
‎        
‎        t1 = threading.Thread(target=forward_traffic, args=(client_socket, ssh_socket))
‎        t2 = threading.Thread(target=forward_traffic, args=(ssh_socket, client_socket))
‎        t1.daemon = True
‎        t2.daemon = True
‎        t1.start()
‎        t2.start()
‎        
‎        t1.join()
‎        t2.join()
‎        
‎    except Exception:
‎        pass
‎    finally:
‎        try:
‎            client_socket.close()
‎        except:
‎            pass
‎
‎def start_listener(port, is_secure):
‎    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
‎    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
‎    try:
‎        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
‎    except:
‎        pass
‎    
‎    try:
‎        server.bind(("0.0.0.0", port))
‎        server.listen(500)
‎        while True:
‎            client_sock, addr = server.accept()
‎            client_thread = threading.Thread(target=handle_client, args=(client_sock, is_secure))
‎            client_thread.daemon = True
‎            client_thread.start()
‎    except Exception:
‎        pass
‎
‎def main():
‎    for port in UNSECURE_PORTS:
‎        t = threading.Thread(target=start_listener, args=(port, False))
‎        t.daemon = True
‎        t.start()
‎        
‎    for port in SECURE_PORTS:
‎        t = threading.Thread(target=start_listener, args=(port, True))
‎        t.daemon = True
‎        t.start()
‎        
‎    while True:
‎        threading.Event().wait(10)
‎
‎if __name__ == "__main__":
‎    main()
‎PYEOF
‎
‎echo -e "${YELLOW}[*] Creating Systemd service...${NC}"
‎cat << 'SEREOF' > /etc/systemd/system/cf-proxy.service
‎[Unit]
‎Description=Secure SSL & Multi-Port SSH WebSocket Proxy
‎After=network.target
‎
‎[Service]
‎Type=simple
‎User=root
‎ExecStart=/usr/bin/python3 /usr/local/bin/cf_multi_proxy.py
‎Restart=always
‎RestartSec=3
‎LimitNOFILE=65536
‎
‎[Install]
‎WantedBy=multi-user.target
‎SEREOF
‎
‎echo -e "${YELLOW}[*] Starting and enabling proxy service...${NC}"
‎systemctl daemon-reload
‎systemctl enable cf-proxy >/dev/null 2>&1
‎systemctl restart cf-proxy >/dev/null 2>&1
‎
‎echo -e "${YELLOW}[*] Configuring Firewall (63 Ports)...${NC}"
‎for port in 80 8080 8081 8082 8880 8888 2052 2082 2086 2095 3128 1080 1081 1082 1083 1084 1085 9050 9051 88118 8008 5000 5001 3000 3001 4000 4001 8000 8001 8002 8003 8004 8005 8006 8007 443 4443 8443 8883 9443 2053 2083 2087 2096 1443 3443 5443 6443 7443 8083 8084 8085 8086 8087 8088 8089 8090 9090 9091 9092 9093 9094 9095; do
‎    ufw allow $port/tcp >/dev/null 2>&1
‎done
‎
‎echo -e "${YELLOW}[*] Creating Colorized Management Panel...${NC}"
‎cat << MENUEOF > /usr/local/bin/menu
‎#!/bin/bash
‎clear
‎
‎RED='\033[1;31m'
‎GREEN='\033[1;32m'
‎YELLOW='\033[1;33m'
‎BLUE='\033[1;34m'
‎MAGENTA='\033[1;35m'
‎CYAN='\033[1;36m'
‎NC='\033[0m'
‎
‎SERVER_IP="${SERVER_IP}"
‎
‎# اسم GOLAN400 صغير فوق القائمة
‎echo -e "${YELLOW}          ╔══════════════════════════════╗${NC}"
‎echo -e "${YELLOW}          ║        GOLAN400              ║${NC}"
‎echo -e "${YELLOW}          ╚══════════════════════════════╝${NC}"
‎echo ""
‎echo -e "\${CYAN}=============================================\${NC}"
‎echo -e "\${MAGENTA}       👥 SSH Account Management Panel 👥    \${NC}"
‎echo -e "\${CYAN}=============================================\${NC}"
‎echo -e "\${YELLOW}Server IP: \${GREEN}\$SERVER_IP\${NC}"
‎echo -e "\${YELLOW}1)\${NC} Create New User (User/Pass)"
‎echo -e "\${YELLOW}2)\${NC} Delete Existing User"
‎echo -e "\${YELLOW}3)\${NC} List Active Users"
‎echo -e "\${YELLOW}4)\${NC} Show Payload & Port Status"
‎echo -e "\${YELLOW}5)\${NC} Exit"
‎echo -e "\${CYAN}=============================================\${NC}"
‎echo -n -e "\${BLUE}👉 Choose an option: \${NC}"
‎read choice
‎
‎case \$choice in
‎    1)
‎        echo -e "\\n\${CYAN}--- [Create New User] ---\${NC}"
‎        echo -n -e "\${GREEN}👤 Enter Username and Password (e.g., user pass): \${NC}"
‎        read username password
‎        echo ""
‎        if [ -z "\$username" ] || [ -z "\$password" ]; then
‎            echo -e "\${RED}❌ Fields cannot be empty!\${NC}"
‎        elif id "\$username" &>/dev/null; then
‎            echo -e "\${RED}❌ User already exists!\${NC}"
‎        else
‎            useradd -m -s /bin/false "\$username"
‎            echo "\$username:\$password" | chpasswd
‎            echo -e "\${GREEN}✅ User [\$username] created successfully.\${NC}"
‎        fi
‎        echo ""
‎        read -n 1 -s -r -p "Press any key to return..."
‎        /usr/local/bin/menu
‎        ;;
‎    2)
‎        echo -e "\\n\${CYAN}--- [Delete User] ---\${NC}"
‎        echo -n -e "\${RED}👤 Username to delete: \${NC}"
‎        read username
‎        if id "\$username" &>/dev/null; then
‎            userdel -r "\$username"
‎            echo -e "\${GREEN}✅ User deleted successfully.\${NC}"
‎        else
‎            echo -e "\${RED}❌ User does not exist!\${NC}"
‎        fi
‎        echo ""
‎        read -n 1 -s -r -p "Press any key to return..."
‎        /usr/local/bin/menu
‎        ;;
‎    3)
‎        echo -e "\\n\${CYAN}--- [Active Users List] ---\${NC}"
‎        awk -F: '\$3 >= 1000 && \$1 != "nobody" {print "  • \\033[1;32m" \$1 "\\033[0m"}' /etc/passwd
‎        echo -e "\${CYAN}=============================================\${NC}"
‎        read -n 1 -s -r -p "Press any key to return..."
‎        /usr/local/bin/menu
‎        ;;
‎    4)
‎        echo -e "\\n\${CYAN}--- [Proxy & Payload Status] ---\${NC}"
‎        if systemctl is-active --quiet cf-proxy; then
‎            echo -e "\${GREEN}✅ Secure SSL Proxy is running successfully.\${NC}"
‎            echo -e "\\n\${YELLOW}📝 Your Payload for Non-SSL Ports:\${NC}"
‎            echo -e "\${MAGENTA}GET / HTTP/1.1[crlf]Host: \$SERVER_IP[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]\${NC}"
‎            echo -e "\\n\${CYAN}📌 SSL/TLS Ports (28 Ports - Direct Connection):\${NC}"
‎            echo -e "\${GREEN}443, 4443, 8443, 8883, 9443, 2053, 2083, 2087, 2096, 1443, 3443, 5443, 6443, 7443, 8083-8090, 9090-9095\${NC}"
‎            echo -e "\\n\${CYAN} Regular Ports (35 Ports - Requires Payload):\${NC}"
‎            echo -e "\${GREEN}80, 8080-8082, 8880, 8888, 2052, 2082, 2086, 2095, 3128, 1080-1085, 9050, 9051, 88118, 8008, 5000, 5001, 3000, 3001, 4000, 4001, 8000-8007\${NC}"
‎        else
‎            echo -e "\${RED}❌ Proxy is stopped! Try restarting the service.\${NC}"
‎        fi
‎        echo ""
‎        read -n 1 -s -r -p "Press any key to return..."
‎        /usr/local/bin/menu
‎        ;;
‎    5)
‎        echo -e "\${GREEN}👋 Goodbye!\${NC}"
‎        exit 0
‎        ;;
‎    *)
‎        echo -e "\${RED}❌ Invalid option!\${NC}"
‎        sleep 1
‎        /usr/local/bin/menu
‎        ;;
‎esac
‎MENUEOF
‎
‎chmod +x /usr/local/bin/menu
‎
‎clear
‎echo -e "${CYAN}=============================================${NC}"
‎echo -e "${GREEN}   ✅ SECURE INSTALLATION COMPLETED SUCCESSFULLY${NC}"
‎echo -e "${CYAN}=============================================${NC}"
‎echo -e "Server IP: ${GREEN}${SERVER_IP}${NC}"
‎echo -e "Type '${GREEN}menu${NC}' to open the control panel."
‎echo -e "${CYAN}=============================================${NC}"
‎EOF
‎
‎chmod +x /root/install_working_proxy.sh
‎bash /root/install_working_proxy.sh
‎