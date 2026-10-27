# kindle-wireguard-kual

**WireGuard VPN client for jailbroken Amazon Kindle devices via KUAL**

> Run a full WireGuard VPN tunnel on your Kindle — no kernel modules required.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/AntonLeskiv/kindle-wireguard-kual/release.yml?label=build)](https://github.com/AntonLeskiv/kindle-wireguard-kual/actions)
[![Release](https://img.shields.io/github/v/release/AntonLeskiv/kindle-wireguard-kual)](https://github.com/AntonLeskiv/kindle-wireguard-kual/releases/latest)

---

**[English](#english)** · **[Español](#español)**

---

## English

### What is this?

`kindle-wireguard-kual` is a [KUAL (Kindle Unified Application Launcher)](https://www.mobileread.com/forums/showthread.php?t=203326) extension that runs a **userspace WireGuard VPN client** on jailbroken Amazon Kindle e-readers.

It uses [`wireguard-go`](https://git.zx2c4.com/wireguard-go) (the official Go userspace implementation) and [`wg`](https://git.zx2c4.com/wireguard-tools) (the standard configuration tool), both statically cross-compiled for **ARMv7 (`armhf`)** — no kernel module compilation or kernel headers are needed.

### Features

- 🔒 **Userspace WireGuard** — Uses `wireguard-go` + `/dev/net/tun`. No kernel modules required.
- 💾 **FAT32 workaround** — Binaries are automatically copied from the FAT32 partition (`/mnt/us/extensions/`) to `tmpfs` (`/var/tmp/`) at runtime, where they receive execute permissions.
- 📄 **Standard config file** — Drop in a regular `wg0.conf` (exported from any WireGuard server). The script handles CRLF line endings and strips `wg-quick`-only directives (`Address`, `DNS`, `MTU`, `PostUp`, etc.) before passing the cleaned config to `wg setconf`.
- 🌐 **Split-Tunnel & Full-Tunnel** — Supports both modes. Full-tunnel (`0.0.0.0/0`) automatically creates a host route for the endpoint and installs `0.0.0.0/1` + `128.0.0.0/1` routes.
- 🔥 **Automatic firewall rules** — Injects `iptables` rules to allow traffic on `wg0` (Amazon's default firewall blocks unknown interfaces).
- 📟 **E-Ink display feedback** — Status messages shown directly on the Kindle screen via `eips`.
- 📋 **Logging** — Detailed timestamped log written to `/mnt/us/extensions/wireguard/wireguard.log`.

### Use Cases

- Connect **KOReader** securely to your home server from anywhere (Calibre-Web, OPDS catalogs, Syncthing, WebDAV).
- Access your **NAS**, **SSH**, or any service on your home LAN through a secure tunnel.
- Route all Kindle traffic through your VPN for privacy on public networks.

### Compatibility

Tested on **Kindle Paperwhite 11th Gen (PW5)** — Bellatrix MT8113 platform.

Compatible with any **jailbroken Kindle with KUAL** running **ARMv7 (`armhf`)** userspace:

| Model | Platform | Status |
|-------|----------|--------|
| Kindle Basic (7th–11th Gen) | Various | ✅ Compatible |
| Kindle Paperwhite 3 (7th Gen) | Wario | ✅ Compatible |
| Kindle Paperwhite 4 (10th Gen) | Zelda | ✅ Compatible |
| Kindle Paperwhite 5 (11th Gen) | Bellatrix | ✅ Tested |
| Kindle Paperwhite 6 (12th Gen) | — | ✅ Compatible |
| Kindle Voyage | — | ✅ Compatible |
| Kindle Oasis (8th–10th Gen) | — | ✅ Compatible |
| Kindle Scribe | — | ✅ Compatible |

> **Note:** Your Kindle must have a working jailbreak and KUAL installed. The device must have `/dev/net/tun` support (the script creates the node automatically if missing).

### Quick Install (End User)

1. **Download** `kindle-wireguard-kual.zip` from the [Releases](https://github.com/AntonLeskiv/kindle-wireguard-kual/releases/latest) page.
2. **Connect** your Kindle via USB.
3. **Extract** the zip into the Kindle's root — the `wireguard/` folder should end up at:
   ```
   /mnt/us/extensions/wireguard/
   ```
4. **Copy** `wg0.conf.example` to `wg0.conf` and fill in your WireGuard keys and server details:
   ```
   /mnt/us/extensions/wireguard/wg0.conf
   ```
5. **Eject** the Kindle and open **KUAL**.
6. Tap **WireGuard VPN → ▶ Conectar VPN**.

### Configuration

Edit `wireguard/wg0.conf` with your WireGuard credentials. You can use a standard config file exported from any WireGuard server (including files edited on Windows with CRLF line endings).

#### Split-Tunnel (Recommended)

Route only traffic to your VPN subnet and home LAN:

```ini
[Interface]
Address = 10.0.0.2/24
PrivateKey = YOUR_PRIVATE_KEY
MTU = 1420

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = vpn.example.com:51820
AllowedIPs = 10.0.0.0/24, 192.168.1.0/24
PersistentKeepalive = 25
```

#### Full-Tunnel

Route **all** internet traffic through the VPN:

```ini
[Peer]
...
AllowedIPs = 0.0.0.0/0
```

### KUAL Menu

| Menu Item | Action |
|-----------|--------|
| ▶ Conectar VPN | Start the WireGuard tunnel |
| ■ Desconectar VPN | Stop the tunnel and clean up routes/firewall |
| ℹ Estado del Tunel | Show connection status, last handshake, and RX bytes |
| 📄 Ver Ultimo Log | Display the last log line on screen |

### Building from Source

#### Prerequisites

- **Go** ≥ 1.22
- **ARM cross-compiler**: `gcc-arm-linux-gnueabihf`
- **Tools**: `make`, `zip`, `git`

#### On Debian/Ubuntu

```bash
sudo apt-get install -y gcc-arm-linux-gnueabihf golang-go make zip git
make all
```

This will:
1. Clone and cross-compile `wireguard-go` (static, `GOOS=linux GOARCH=arm GOARM=7`).
2. Clone and cross-compile `wg` (static, via `arm-linux-gnueabihf-gcc`).
3. Package everything into `kindle-wireguard-kual.zip`.

#### Verify binaries

```bash
file wireguard/bin/wireguard-go
# wireguard/bin/wireguard-go: ELF 32-bit LSB executable, ARM, EABI5, statically linked, ...

file wireguard/bin/wg
# wireguard/bin/wg: ELF 32-bit LSB executable, ARM, EABI5, statically linked, ...
```

### How It Works (Technical Details)

1. **FAT32 bypass**: The Kindle's `/mnt/us` partition is FAT32, which doesn't support Unix execute permissions. At runtime, binaries are copied to `/var/tmp/wireguard-kual/` (a `tmpfs` mount) and `chmod +x`'d there.

2. **Config parsing**: Standard `wg0.conf` files contain directives like `Address`, `DNS`, `PostUp`, etc. that `wg setconf` doesn't understand (those are `wg-quick` features). The script:
   - Strips `\r` carriage returns (Windows compatibility).
   - Extracts `Address`, `MTU`, and `AllowedIPs` for routing.
   - Generates a cleaned config with only `[Interface]`/`[Peer]` WireGuard-native fields.

3. **TUN device**: Creates `/dev/net/tun` if it doesn't exist (`mknod c 10 200`).

4. **Routing**:
   - Split-tunnel: Adds explicit routes for each `AllowedIPs` CIDR.
   - Full-tunnel (`0.0.0.0/0`): Creates a host route for the endpoint IP via the original default gateway, then installs `0.0.0.0/1` + `128.0.0.0/1` (more specific than the default route, avoiding conflicts).

5. **Firewall**: Amazon's Kindle OS drops traffic on unknown interfaces. The script injects `iptables -I INPUT -i wg0 -j ACCEPT` and `iptables -I OUTPUT -o wg0 -j ACCEPT`, and removes them on disconnect.

6. **E-Ink display**: Uses the Kindle's built-in `eips` command to show status messages at the bottom of the screen (row 38).

### Troubleshooting

| Problem | Solution |
|---------|----------|
| `WG Error: Faltan binarios en bin/` | The compiled `wireguard-go` and `wg` binaries are missing from `wireguard/bin/`. Download the release zip or build from source. |
| `WG Error: No existe wg0.conf` | Copy `wg0.conf.example` to `wg0.conf` and fill in your keys. |
| `WG Error: Fallo al crear wg0` | The TUN device may not be available. Check `ls -la /dev/net/tun` via SSH. |
| `WG Error: Configuracion invalida` | Your `wg0.conf` may have syntax errors. Check the log file. |
| `WG ON \| Sin Handshake` | The tunnel is up but can't reach the server. Check the endpoint IP/port, your internet connection, and firewall rules on the server. |

### License

[MIT](LICENSE)

---

## Español

### ¿Qué es esto?

`kindle-wireguard-kual` es una extensión para [KUAL (Kindle Unified Application Launcher)](https://www.mobileread.com/forums/showthread.php?t=203326) que ejecuta un **cliente VPN WireGuard en espacio de usuario** en dispositivos Amazon Kindle con jailbreak.

Utiliza [`wireguard-go`](https://git.zx2c4.com/wireguard-go) (la implementación oficial en Go para espacio de usuario) y [`wg`](https://git.zx2c4.com/wireguard-tools) (la herramienta de configuración estándar), ambos compilados estáticamente para **ARMv7 (`armhf`)** — no se necesita compilar módulos del kernel ni tener cabeceras del kernel.

### Características

- 🔒 **WireGuard en espacio de usuario** — Usa `wireguard-go` + `/dev/net/tun`. No requiere módulos del kernel.
- 💾 **Bypass de FAT32** — Los binarios se copian automáticamente desde la partición FAT32 (`/mnt/us/extensions/`) a `tmpfs` (`/var/tmp/`) en tiempo de ejecución, donde reciben permisos de ejecución.
- 📄 **Archivo de configuración estándar** — Coloca un `wg0.conf` normal (exportado de cualquier servidor WireGuard). El script maneja saltos de línea CRLF y elimina las directivas exclusivas de `wg-quick` (`Address`, `DNS`, `MTU`, `PostUp`, etc.) antes de pasar la configuración limpia a `wg setconf`.
- 🌐 **Split-Tunnel y Full-Tunnel** — Soporta ambos modos. El full-tunnel (`0.0.0.0/0`) crea automáticamente una ruta host para el endpoint e instala rutas `0.0.0.0/1` + `128.0.0.0/1`.
- 🔥 **Reglas de firewall automáticas** — Inyecta reglas `iptables` para permitir tráfico en `wg0` (el firewall de Amazon bloquea interfaces desconocidas por defecto).
- 📟 **Feedback visual en pantalla E-Ink** — Mensajes de estado mostrados directamente en la pantalla del Kindle vía `eips`.
- 📋 **Logging** — Log detallado con timestamp escrito en `/mnt/us/extensions/wireguard/wireguard.log`.

### Casos de Uso

- Conectar **KOReader** de forma segura a tu servidor doméstico desde cualquier lugar (Calibre-Web, catálogos OPDS, Syncthing, WebDAV).
- Acceder a tu **NAS**, **SSH** o cualquier servicio en tu red local a través de un túnel seguro.
- Enrutar todo el tráfico del Kindle a través de tu VPN para mayor privacidad en redes públicas.

### Compatibilidad

Probado en **Kindle Paperwhite 11ª Gen (PW5)** — plataforma Bellatrix MT8113.

Compatible con cualquier **Kindle con jailbreak y KUAL** que ejecute espacio de usuario **ARMv7 (`armhf`)**:

| Modelo | Plataforma | Estado |
|--------|-----------|--------|
| Kindle Basic (7ª–11ª Gen) | Varios | ✅ Compatible |
| Kindle Paperwhite 3 (7ª Gen) | Wario | ✅ Compatible |
| Kindle Paperwhite 4 (10ª Gen) | Zelda | ✅ Compatible |
| Kindle Paperwhite 5 (11ª Gen) | Bellatrix | ✅ Probado |
| Kindle Paperwhite 6 (12ª Gen) | — | ✅ Compatible |
| Kindle Voyage | — | ✅ Compatible |
| Kindle Oasis (8ª–10ª Gen) | — | ✅ Compatible |
| Kindle Scribe | — | ✅ Compatible |

> **Nota:** Tu Kindle debe tener un jailbreak funcional y KUAL instalado. El dispositivo debe soportar `/dev/net/tun` (el script crea el nodo automáticamente si no existe).

### Instalación Rápida (Usuario Final)

1. **Descarga** `kindle-wireguard-kual.zip` desde la página de [Releases](https://github.com/AntonLeskiv/kindle-wireguard-kual/releases/latest).
2. **Conecta** tu Kindle por USB.
3. **Extrae** el zip en la raíz del Kindle — la carpeta `wireguard/` debe quedar en:
   ```
   /mnt/us/extensions/wireguard/
   ```
4. **Copia** `wg0.conf.example` a `wg0.conf` y rellena tus claves WireGuard y datos del servidor:
   ```
   /mnt/us/extensions/wireguard/wg0.conf
   ```
5. **Expulsa** el Kindle de forma segura y abre **KUAL**.
6. Toca **WireGuard VPN → ▶ Conectar VPN**.

### Configuración

Edita `wireguard/wg0.conf` con tus credenciales WireGuard. Puedes usar un archivo de configuración estándar exportado de cualquier servidor WireGuard (incluyendo archivos editados en Windows con saltos de línea CRLF).

#### Split-Tunnel (Recomendado)

Enruta solo el tráfico hacia tu subred VPN y tu LAN doméstica:

```ini
[Interface]
Address = 10.0.0.2/24
PrivateKey = TU_CLAVE_PRIVADA
MTU = 1420

[Peer]
PublicKey = CLAVE_PUBLICA_DEL_SERVIDOR
Endpoint = vpn.tudominio.com:51820
AllowedIPs = 10.0.0.0/24, 192.168.1.0/24
PersistentKeepalive = 25
```

#### Full-Tunnel

Enruta **todo** el tráfico de internet por la VPN:

```ini
[Peer]
...
AllowedIPs = 0.0.0.0/0
```

### Menú KUAL

| Elemento del Menú | Acción |
|--------------------|--------|
| ▶ Conectar VPN | Iniciar el túnel WireGuard |
| ■ Desconectar VPN | Detener el túnel y limpiar rutas/firewall |
| ℹ Estado del Tunel | Mostrar estado de conexión, último handshake y bytes RX |
| 📄 Ver Ultimo Log | Mostrar la última línea del log en pantalla |

### Compilación desde Código Fuente

#### Requisitos

- **Go** ≥ 1.22
- **Compilador cruzado ARM**: `gcc-arm-linux-gnueabihf`
- **Herramientas**: `make`, `zip`, `git`

#### En Debian/Ubuntu

```bash
sudo apt-get install -y gcc-arm-linux-gnueabihf golang-go make zip git
make all
```

Esto hará:
1. Clonar y compilar `wireguard-go` (estático, `GOOS=linux GOARCH=arm GOARM=7`).
2. Clonar y compilar `wg` (estático, vía `arm-linux-gnueabihf-gcc`).
3. Empaquetar todo en `kindle-wireguard-kual.zip`.

#### Verificar binarios

```bash
file wireguard/bin/wireguard-go
# wireguard/bin/wireguard-go: ELF 32-bit LSB executable, ARM, EABI5, statically linked, ...

file wireguard/bin/wg
# wireguard/bin/wg: ELF 32-bit LSB executable, ARM, EABI5, statically linked, ...
```

### Cómo Funciona (Detalles Técnicos)

1. **Bypass de FAT32**: La partición `/mnt/us` del Kindle es FAT32, que no soporta permisos de ejecución Unix. En tiempo de ejecución, los binarios se copian a `/var/tmp/wireguard-kual/` (un montaje `tmpfs`) y reciben `chmod +x` allí.

2. **Parser de configuración**: Los archivos `wg0.conf` estándar contienen directivas como `Address`, `DNS`, `PostUp`, etc. que `wg setconf` no entiende (son características de `wg-quick`). El script:
   - Elimina retornos de carro `\r` (compatibilidad con Windows).
   - Extrae `Address`, `MTU` y `AllowedIPs` para el enrutamiento.
   - Genera una configuración limpia con solo campos nativos de WireGuard (`[Interface]`/`[Peer]`).

3. **Dispositivo TUN**: Crea `/dev/net/tun` si no existe (`mknod c 10 200`).

4. **Enrutamiento**:
   - Split-tunnel: Añade rutas explícitas para cada CIDR en `AllowedIPs`.
   - Full-tunnel (`0.0.0.0/0`): Crea una ruta host para la IP del endpoint vía la puerta de enlace por defecto original, luego instala `0.0.0.0/1` + `128.0.0.0/1` (más específicas que la ruta por defecto, evitando conflictos).

5. **Firewall**: El sistema operativo del Kindle de Amazon descarta tráfico en interfaces desconocidas. El script inyecta `iptables -I INPUT -i wg0 -j ACCEPT` e `iptables -I OUTPUT -o wg0 -j ACCEPT`, y las elimina al desconectar.

6. **Pantalla E-Ink**: Usa el comando `eips` integrado del Kindle para mostrar mensajes de estado en la parte inferior de la pantalla (fila 38).

### Solución de Problemas

| Problema | Solución |
|----------|----------|
| `WG Error: Faltan binarios en bin/` | Los binarios compilados `wireguard-go` y `wg` no están en `wireguard/bin/`. Descarga el zip de releases o compila desde el código fuente. |
| `WG Error: No existe wg0.conf` | Copia `wg0.conf.example` a `wg0.conf` y rellena tus claves. |
| `WG Error: Fallo al crear wg0` | El dispositivo TUN puede no estar disponible. Verifica `ls -la /dev/net/tun` vía SSH. |
| `WG Error: Configuracion invalida` | Tu `wg0.conf` puede tener errores de sintaxis. Revisa el archivo de log. |
| `WG ON \| Sin Handshake` | El túnel está levantado pero no puede alcanzar el servidor. Verifica la IP/puerto del endpoint, tu conexión a internet y las reglas de firewall en el servidor. |

### Licencia

[MIT](LICENSE)

---

## Architecture

```
Kindle Device
┌─────────────────────────────────────────────────────────┐
│  /mnt/us/extensions/wireguard/  (FAT32)                 │
│  ├── config.xml          ← KUAL extension descriptor    │
│  ├── menu.json           ← KUAL menu entries            │
│  ├── wg0.conf            ← User's WireGuard config      │
│  └── bin/                                               │
│      ├── wg-control.sh   ← Main control script          │
│      ├── wireguard-go    ← Go userspace WG (ARM static) │
│      └── wg              ← WG config tool (ARM static)  │
│                                                         │
│  /var/tmp/wireguard-kual/  (tmpfs — RAM)                │
│  ├── wireguard-go        ← Executable copy              │
│  ├── wg                  ← Executable copy              │
│  ├── wg0.unix.conf       ← CRLF-cleaned config          │
│  ├── wg0.clean.conf      ← Stripped for wg setconf      │
│  └── endpoint.route      ← Saved endpoint route         │
└─────────────────────────────────────────────────────────┘
```
