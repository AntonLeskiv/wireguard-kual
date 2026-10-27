#!/bin/sh

EXT_DIR="/mnt/us/extensions/wireguard"
CONF_FILE="$EXT_DIR/wg0.conf"
TMP_DIR="/var/tmp/wireguard-kual"
CLEAN_CONF="$TMP_DIR/wg0.clean.conf"
UNIX_CONF="$TMP_DIR/wg0.unix.conf"
ENDPOINT_ROUTE_FILE="$TMP_DIR/endpoint.route"
LOG_FILE="$EXT_DIR/wireguard.log"
IFACE="wg0"

eink_msg() {
    MSG="$1"
    eips 1 38 "                                                  " >/dev/null 2>&1
    eips 2 38 "$MSG" >/dev/null 2>&1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $MSG" >> "$LOG_FILE"
}

prepare_env() {
    mkdir -p "$TMP_DIR"

    if [ ! -f "$EXT_DIR/bin/wireguard-go" ] || [ ! -f "$EXT_DIR/bin/wg" ]; then
        eink_msg "WG Error: Faltan binarios en bin/"
        exit 1
    fi

    if [ ! -x "$TMP_DIR/wireguard-go" ] || [ ! -x "$TMP_DIR/wg" ]; then
        cp "$EXT_DIR/bin/wireguard-go" "$TMP_DIR/wireguard-go"
        cp "$EXT_DIR/bin/wg" "$TMP_DIR/wg"
        chmod +x "$TMP_DIR/wireguard-go" "$TMP_DIR/wg"
    fi

    if [ ! -c /dev/net/tun ]; then
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200
        chmod 600 /dev/net/tun
    fi
}

parse_config() {
    if [ ! -f "$CONF_FILE" ]; then
        eink_msg "WG Error: No existe wg0.conf"
        exit 1
    fi

    tr -d '\r' < "$CONF_FILE" > "$UNIX_CONF"

    WG_ADDR=$(grep -i '^[[:space:]]*Address[[:space:]]*=' "$UNIX_CONF" | head -n 1 | cut -d '=' -f 2 | tr -d ' ' | cut -d ',' -f 1)
    WG_MTU=$(grep -i '^[[:space:]]*MTU[[:space:]]*=' "$UNIX_CONF" | head -n 1 | cut -d '=' -f 2 | tr -d ' ')
    [ -z "$WG_MTU" ] && WG_MTU="1420"

    ALLOWED_IPS=$(grep -i '^[[:space:]]*AllowedIPs[[:space:]]*=' "$UNIX_CONF" | cut -d '=' -f 2 | tr ',' ' ')

    grep -v -i -E '^[[:space:]]*(Address|DNS|MTU|PreUp|PostUp|PreDown|PostDown|SaveConfig|Table)[[:space:]]*=' "$UNIX_CONF" > "$CLEAN_CONF"

    if [ -z "$WG_ADDR" ]; then
        eink_msg "WG Error: Falta 'Address' en wg0.conf"
        exit 1
    fi
}

start_wg() {
    if ip link show "$IFACE" >/dev/null 2>&1; then
        eink_msg "WG: Ya esta conectado"
        exit 0
    fi

    prepare_env
    parse_config
    eink_msg "WG: Iniciando tunel..."

    export WG_I_WANT_A_DEPRECATED_KERNEL_SYNTAX=1
    "$TMP_DIR/wireguard-go" "$IFACE" >> "$LOG_FILE" 2>&1
    sleep 1

    if ! ip link show "$IFACE" >/dev/null 2>&1; then
        eink_msg "WG Error: Fallo al crear wg0"
        exit 1
    fi

    if ! "$TMP_DIR/wg" setconf "$IFACE" "$CLEAN_CONF" >> "$LOG_FILE" 2>&1; then
        eink_msg "WG Error: Configuracion invalida"
        ip link del "$IFACE" 2>/dev/null
        exit 1
    fi

    ip addr add "$WG_ADDR" dev "$IFACE" >> "$LOG_FILE" 2>&1
    ip link set mtu "$WG_MTU" up dev "$IFACE" >> "$LOG_FILE" 2>&1

    # Desactivar rp_filter para permitir tráfico asimétrico en wg0
    echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter 2>/dev/null
    echo 0 > /proc/sys/net/ipv4/conf/"$IFACE"/rp_filter 2>/dev/null

    for cidr in $ALLOWED_IPS; do
        case "$cidr" in
            *:*) continue ;;
            0.0.0.0/0)
                ENDPOINT_IP=$("$TMP_DIR/wg" show "$IFACE" endpoints | awk '{print $2}' | cut -d ':' -f 1 | head -n 1)
                DEFAULT_GW=$(ip route show default 2>/dev/null | awk '/default/ {print $3}' | head -n 1)
                [ -z "$DEFAULT_GW" ] && DEFAULT_GW=$(route -n 2>/dev/null | awk '/^0.0.0.0/ {print $2}' | head -n 1)
                DEFAULT_DEV=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n 1)
                [ -z "$DEFAULT_DEV" ] && DEFAULT_DEV=$(route -n 2>/dev/null | awk '/^0.0.0.0/ {print $8}' | head -n 1)
                if [ -n "$ENDPOINT_IP" ] && [ -n "$DEFAULT_GW" ] && [ -n "$DEFAULT_DEV" ]; then
                    (ip route add "$ENDPOINT_IP/32" via "$DEFAULT_GW" dev "$DEFAULT_DEV" 2>/dev/null || route add -host "$ENDPOINT_IP" gw "$DEFAULT_GW" dev "$DEFAULT_DEV" 2>/dev/null)
                    echo "$ENDPOINT_IP/32" > "$ENDPOINT_ROUTE_FILE"
                    (ip route add 0.0.0.0/1 dev "$IFACE" 2>/dev/null || route add -net 0.0.0.0/1 dev "$IFACE" 2>/dev/null)
                    (ip route add 128.0.0.0/1 dev "$IFACE" 2>/dev/null || route add -net 128.0.0.0/1 dev "$IFACE" 2>/dev/null)
                fi
                ;;
            *)
                echo "Configurando ruta para $cidr..." >> "$LOG_FILE"
                if ! ip route add "$cidr" dev "$IFACE" >> "$LOG_FILE" 2>&1; then
                    route add -net "$cidr" dev "$IFACE" >> "$LOG_FILE" 2>&1
                fi
                ;;
        esac
    done

    iptables -C INPUT -i "$IFACE" -j ACCEPT 2>/dev/null || iptables -I INPUT -i "$IFACE" -j ACCEPT
    iptables -C OUTPUT -o "$IFACE" -j ACCEPT 2>/dev/null || iptables -I OUTPUT -o "$IFACE" -j ACCEPT

    eink_msg "WG: CONECTADO ($WG_ADDR)"
}

stop_wg() {
    if ! ip link show "$IFACE" >/dev/null 2>&1; then
        eink_msg "WG: No estaba activo"
        exit 0
    fi

    if [ -f "$ENDPOINT_ROUTE_FILE" ]; then
        SAVED_ROUTE=$(cat "$ENDPOINT_ROUTE_FILE")
        [ -n "$SAVED_ROUTE" ] && ip route del "$SAVED_ROUTE" 2>/dev/null
        rm -f "$ENDPOINT_ROUTE_FILE"
    fi

    iptables -D INPUT -i "$IFACE" -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -o "$IFACE" -j ACCEPT 2>/dev/null
    ip link del "$IFACE" 2>/dev/null
    killall wireguard-go 2>/dev/null

    eink_msg "WG: DESCONECTADO"
}

status_wg() {
    if ip link show "$IFACE" >/dev/null 2>&1; then
        prepare_env
        HS=$("$TMP_DIR/wg" show "$IFACE" latest-handshakes | awk '{print $2}' | head -n 1)
        RX=$("$TMP_DIR/wg" show "$IFACE" transfer | awk '{print $2}' | head -n 1)
        if [ -n "$HS" ] && [ "$HS" != "0" ]; then
            NOW=$(date +%s)
            DIFF=$((NOW - HS))
            eink_msg "WG ON | HS hace ${DIFF}s | RX: ${RX}B"
        else
            eink_msg "WG ON | Sin Handshake (Revisar red)"
        fi
    else
        eink_msg "WG Estado: APAGADO"
    fi
}

show_log() {
    if [ -f "$LOG_FILE" ]; then
        L1=$(tail -n 2 "$LOG_FILE" | head -n 1 | cut -c 1-48)
        L2=$(tail -n 1 "$LOG_FILE" | cut -c 1-48)
        eips 1 37 "                                                  " >/dev/null 2>&1
        eips 2 37 "$L1" >/dev/null 2>&1
        eips 1 38 "                                                  " >/dev/null 2>&1
        eips 2 38 "$L2" >/dev/null 2>&1
    else
        eink_msg "WG Log: Archivo vacio"
    fi
}

case "$1" in
    up) start_wg ;;
    down) stop_wg ;;
    status) status_wg ;;
    log) show_log ;;
    *) echo "Uso: $0 {up|down|status|log}" ; exit 1 ;;
esac
