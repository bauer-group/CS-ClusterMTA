# ClusterMTA

A production-ready, self-hosted mail server based on [Poste.io](https://poste.io/) with BAUER GROUP branding, automated setup, and backup/restore functionality.

## Features

- **Full mail server stack** - SMTP, IMAP, POP3, Webmail in one container
- **ClamAV antivirus** - Real-time virus scanning (optional, saves ~1GB RAM when disabled)
- **Rspamd spam filtering** - Advanced spam detection with DKIM signing
- **Roundcube webmail** - Modern webmail interface (optional)
- **Let's Encrypt SSL/TLS** - Automatic certificate management
- **One-command setup** - Automated configuration with `setup.sh`
- **Online backup/restore** - Consistent backups without downtime
- **Custom branding** - BAUER GROUP favicon and styling

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CS-ClusterMTA                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Postfix   │  │   Dovecot   │  │   Rspamd    │  │   ClamAV    │        │
│  │   (SMTP)    │  │(IMAP/POP3)  │  │   (Spam)    │  │ (Antivirus) │        │
│  │  25,465,587 │  │ 110,143,993 │  │             │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘        │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐         │
│  │  Roundcube  │  │   Nginx     │  │      Let's Encrypt          │         │
│  │  (Webmail)  │  │  (Web UI)   │  │   (SSL Certificates)        │         │
│  │             │  │   80,443    │  │                             │         │
│  └─────────────┘  └─────────────┘  └─────────────────────────────┘         │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        /data (Persistent Volume)                     │   │
│  │   Mail Data │ Accounts │ Certificates │ Configuration │ Logs        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### One-Line Install (Recommended)

`setup.sh` installs into `/opt/clustermta` as a **git checkout**, so
`./clustermta.sh update` keeps working afterwards:

```bash
curl -fsSL https://raw.githubusercontent.com/bauer-group/CS-ClusterMTA/main/setup.sh | sudo bash
```

With auto-start:

```bash
curl -fsSL https://raw.githubusercontent.com/bauer-group/CS-ClusterMTA/main/setup.sh | sudo bash -s -- --start
```

> The old `install.sh` URL still works — it simply forwards to `setup.sh`.
> Re-running the installer over an existing install is safe: it updates the
> checkout and **repairs a legacy non-git install in place** (your `.env` and
> `backups/` are preserved).

### Manual Installation

```bash
# 1. Clone the repository straight into the install location
sudo git clone https://github.com/bauer-group/CS-ClusterMTA.git /opt/clustermta
cd /opt/clustermta

# 2. Run setup (creates folders, .env with auto-detected values)
sudo ./setup.sh

# 3. Edit configuration (set your hostname!)
sudo nano /opt/clustermta/.env

# 4. Start mail server
sudo ./clustermta.sh start

# 5. Access admin panel
#    https://<your-hostname>/admin/
```

> Running `sudo ./setup.sh` from a clone in a different directory is also fine —
> it bootstraps the install into `/opt/clustermta` and continues from there.

## Requirements

- **OS**: Linux server (Ubuntu 22.04+ recommended)
- **Docker**: Docker Engine with Docker Compose v2
- **Access**: Root/sudo privileges
- **RAM**: Minimum 2GB (4GB+ recommended with ClamAV enabled)
- **Ports**: 25, 80, 110, 143, 443, 465, 587, 993, 995, 4190
- **DNS**: Properly configured DNS records (see DNS Configuration)

## File Structure

```
/opt/clustermta/                # Installation directory
├── docker-compose.yml          # Container stack definition
├── .env                        # Environment configuration (generated)
├── .env.example                # Configuration template
├── clustermta.sh               # Management CLI
├── setup.sh                    # Initial setup script
├── update.sh                   # Git-based update script
├── install.sh                  # One-line installer
├── README.md                   # This file
├── src/                        # Custom Docker image
│   ├── Dockerfile              # Image build definition
│   └── assets/                 # Custom files
│       ├── etc/cont-init.d/    # s6 init scripts
│       └── opt/                # Branding (favicon, etc.)
├── config/
│   └── traefik/                # Traefik reverse proxy config
│       └── mail-server.yml
└── backups/                    # Backup storage
```

## Management Commands

```bash
sudo ./clustermta.sh <command>
```

| Command | Description |
|---------|-------------|
| `start` | Start the mail server |
| `stop` | Stop the mail server |
| `restart` | Restart the mail server |
| `status` | Show container status and access URLs |
| `logs` | Stream container logs (Ctrl+C to exit) |
| `update` | Pull latest from git and rebuild image |
| `backup` | Create online backup (stack must be running) |
| `restore <file>` | Restore from backup (stack must be stopped) |
| `destroy` | Remove all containers and volumes (DESTRUCTIVE!) |
| `help` | Show help message |

### Examples

```bash
# View logs
sudo ./clustermta.sh logs

# Create backup
sudo ./clustermta.sh backup

# Restore from backup
sudo ./clustermta.sh stop
sudo ./clustermta.sh restore backups/mx1_backup_20250125_120000.tar.gz
sudo ./clustermta.sh start

# Update to latest version
sudo ./clustermta.sh update
```

## Configuration

Edit `/opt/clustermta/.env` to customize your installation.

### Stack Identification

| Variable | Default | Description |
|----------|---------|-------------|
| `STACK_NAME` | `mx1_simply_send_com` | Unique identifier for containers and volumes |

### Poste.io Image

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTEIO_REPOSITORY` | `analogic/poste.io` | Docker image repository |
| `POSTEIO_VERSION` | `2.5.14` | Image version tag |

### General Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `TIME_ZONE` | `Etc/UTC` | Container timezone |
| `SERVICE_HOSTNAME` | `mx1.simply-send.com` | Mail server FQDN (must match DNS!) |
| `HTTPS_MODE` | `ON` | `ON` = Let's Encrypt, `OFF` = self-signed |

### Service Modules

| Variable | Default | Description |
|----------|---------|-------------|
| `DISABLE_CLAMAV` | `FALSE` | `TRUE` disables antivirus (saves ~1GB RAM) |
| `DISABLE_RSPAMD` | `FALSE` | `TRUE` disables spam filter (also disables DKIM!) |
| `DISABLE_ROUNDCUBE` | `FALSE` | `TRUE` disables webmail interface |

### Memory Requirements

| Component | RAM Usage |
|-----------|-----------|
| Base system | ~500 MB |
| ClamAV | ~1.0 GB |
| Rspamd | ~200 MB |
| Roundcube | ~100 MB |
| **Total (all enabled)** | **~1.8 GB** |

### Custom Ports (Optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `HTTP_PORT` | `80` | HTTP port for web interface |
| `HTTPS_PORT` | `443` | HTTPS port for secure web interface |

### Multi-IP Support (Optional)

Control which IP addresses the mail server listens on and sends from. Useful for multi-homed servers or running multiple instances.

| Variable | Default | Description |
|----------|---------|-------------|
| `LISTEN_ON` | `*` | IPs for incoming connections |
| `SEND_ON` | *(same as LISTEN_ON)* | IP for outgoing mail |

**LISTEN_ON Values:**

| Value | Description |
|-------|-------------|
| `*` | Listen on all interfaces (default, standard Poste.io behavior) |
| `host` | Listen only on hostname's resolved IPs |
| `1.2.3.4` | Listen on specific IP address |
| `1.2.3.4 5.6.7.8` | Listen on multiple IPs (space-separated) |

**Examples:**

```bash
# All interfaces (default)
LISTEN_ON=*

# Single IPv4
LISTEN_ON=116.202.101.48

# IPv4 + IPv6
LISTEN_ON="116.202.101.48 2a01:4f8:c012:754d::1"

# Different send IP
LISTEN_ON="116.202.101.48 116.202.101.49"
SEND_ON=116.202.101.49
```

**Affected Services:**
- Dovecot (IMAP/POP3)
- Haraka SMTP (Port 25)
- Haraka Submission (Ports 587, 465)
- Postfix (outbound SMTP via SEND_ON)

### Roundcube Plugins

ClusterMTA enables the following built-in Roundcube plugins by default:

| Plugin | Description |
|--------|-------------|
| `persistent_login` | "Keep me logged in" checkbox for persistent sessions |
| `swipe` | Swipe gestures for mobile/touch devices |

These plugins are pre-installed in Poste.io but not enabled by default. ClusterMTA activates them via the init script `92-roundcube-plugins.sh`.

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 25 | SMTP | Incoming mail (MTA-to-MTA) |
| 80 | HTTP | Web interface, ACME challenges |
| 110 | POP3 | Mail retrieval (legacy) |
| 143 | IMAP | Mail synchronization |
| 443 | HTTPS | Secure web interface |
| 465 | SMTPS | Secure SMTP submission (implicit TLS) |
| 587 | Submission | SMTP submission (STARTTLS) |
| 993 | IMAPS | Secure IMAP |
| 995 | POP3S | Secure POP3 (legacy) |
| 4190 | Sieve | Mail filtering rules |

## DNS Configuration

Complete DNS zone for the default configuration (`simply-send.com`):

### A/AAAA Records (Host IP Addresses)

```dns
@    3600  IN  A       116.202.101.48
@    3600  IN  AAAA    2a01:4f8:c012:754d::1
mx1  3600  IN  A       116.202.101.48
mx1  3600  IN  AAAA    2a01:4f8:c012:754d::1
```

### MX Record (Mail Routing)

```dns
@  3600  IN  MX  10 mx1
```

### CNAME Records (Aliases)

```dns
mx   3600  IN  CNAME  mx1
www  3600  IN  CNAME  @
```

### SPF Record (Sender Policy Framework)

```dns
# Main SPF - redirects to dedicated SPF record
@     3600  IN  TXT  "v=spf1 redirect=_spf.simply-send.com"

# Dedicated SPF record with all allowed senders
_spf  3600  IN  TXT  "v=spf1 mx ip4:116.202.101.48 ip6:2a01:4f8:c012:754d::/64 -all"
```

### DKIM Record (DomainKeys Identified Mail)

```dns
# DKIM selector record (generated by Poste.io - copy from admin panel)
s20260125000._domainkey  3600  IN  TXT  "k=rsa; p=MIIBIjAN..."

# ADSP (Author Domain Signing Practices)
_adsp._domainkey         3600  IN  TXT  "dkim=all"
```

> **Note**: The DKIM public key is generated by Poste.io. After first start, copy it from the admin panel under "Virtual Domains" → your domain → "DKIM key".

### DMARC Record (Domain-based Message Authentication)

```dns
_dmarc  3600  IN  TXT  "v=DMARC1; p=reject; pct=100; sp=none; adkim=r; aspf=r"
```

| Tag | Value | Description |
|-----|-------|-------------|
| `p=reject` | Policy | Reject mail failing authentication |
| `pct=100` | Percentage | Apply to 100% of mail |
| `sp=none` | Subdomain policy | No policy for subdomains |
| `adkim=r` | DKIM alignment | Relaxed mode |
| `aspf=r` | SPF alignment | Relaxed mode |

> **Tip**: Start with `p=none` for monitoring, then `p=quarantine`, finally `p=reject` once verified.

### CAA Records (Certificate Authority Authorization)

```dns
@  3600  IN  CAA  0 issue     "letsencrypt.org"
@  3600  IN  CAA  0 issuewild "letsencrypt.org"
@  3600  IN  CAA  0 iodef     "mailto:abuse@bauer-group.com"
```

### PTR Record (Reverse DNS)

Configure at your hosting provider:

```text
116.202.101.48        → mx1.simply-send.com
2a01:4f8:c012:754d::1 → mx1.simply-send.com
```

### DNS Checklist

- [ ] A/AAAA records for mail server hostname
- [ ] MX record pointing to mail server
- [ ] SPF record (use `redirect` for cleaner setup)
- [ ] DKIM record (copy from Poste.io admin panel after first start)
- [ ] DMARC record (start with `p=none`, then `quarantine`, finally `reject`)
- [ ] CAA records (allow Let's Encrypt)
- [ ] Reverse DNS (PTR) for server IP → mail hostname

## Backup & Restore

### What's Included in Backups

| Content | Description |
|---------|-------------|
| Mail data | All emails and mailboxes |
| Accounts | User accounts and passwords |
| Certificates | SSL/TLS certificates |
| Configuration | Server and domain settings |
| DKIM keys | Domain signing keys |

### Create Backup

```bash
# Stack must be running for consistent backup
sudo ./clustermta.sh backup
```

Creates a backup archive in `./backups/` with timestamp.

### Restore Backup

```bash
# 1. Stop the stack first
sudo ./clustermta.sh stop

# 2. Restore from backup
sudo ./clustermta.sh restore backups/mx1_backup_20250125_120000.tar.gz

# 3. Start the stack
sudo ./clustermta.sh start
```

## Traefik Integration

For environments using Traefik as reverse proxy:

### 1. Configure Custom Ports

Edit `.env`:

```bash
HTTP_PORT=8080
HTTPS_PORT=8443
```

### 2. Copy Traefik Configuration

```bash
cp config/traefik/mail-server.yml /path/to/traefik/config/
```

### 3. Adjust Hostname

Edit `mail-server.yml` and set your hostname.

### Traffic Flow

```text
Internet → Traefik (443) → mail-server (8443)
                         → mail-server (25, 465, 587, 993, 995) [direct]
```

> **Note**: Only HTTP/HTTPS traffic goes through Traefik. Mail protocols (SMTP, IMAP, POP3) must be exposed directly.

## Advanced Customization

Poste.io 2.5.x provides official mechanisms for customization that persist across container updates. These methods are recommended for advanced users who need additional customization beyond what ClusterMTA provides.

### Configuration Overrides (`/data/_override/`)

Override any configuration file without modifying the container:

```bash
# Structure mirrors the root filesystem
/data/_override/
├── etc/
│   ├── dovecot/
│   │   └── conf.d/
│   │       └── 99-custom.conf      # Custom Dovecot settings
│   ├── postfix/
│   │   └── main.cf.d/
│   │       └── 99-custom.cf        # Custom Postfix settings
│   └── rspamd/
│       └── local.d/
│           └── custom.conf         # Custom Rspamd settings
└── opt/
    └── admin/
        └── templates/
            └── custom.twig         # Custom admin templates
```

Files in `/data/_override/` are copied to their corresponding locations at container startup, overwriting the original files.

### External Roundcube Plugins (`/data/roundcube-plugins/`)

Install additional Roundcube plugins that aren't bundled with Poste.io:

```bash
# Example: Install a custom plugin
cd /data/roundcube-plugins/
git clone https://github.com/example/custom-plugin.git

# Plugin is automatically loaded on next container restart
```

> **Note**: Built-in plugins (like `persistent_login`, `swipe`) should be enabled via config, not installed here. ClusterMTA already enables common built-in plugins.

### Custom Haraka Plugins (`/data/haraka/`)

Add custom Haraka SMTP plugins:

```bash
/data/haraka/
├── smtp/           # For port 25 (incoming mail)
│   └── plugins/
│       └── custom_plugin.js
└── submission/     # For ports 587/465 (submission)
    └── plugins/
        └── custom_plugin.js
```

### Roundcube Encryption Key (`DES_KEY`)

For persistent Roundcube sessions across container restarts, set a stable encryption key:

```bash
# In .env or docker-compose.yml
DES_KEY=your-random-32-character-string
```

Without this, Roundcube generates a new key on each restart, invalidating existing sessions.

### ClusterMTA Custom Scripts

ClusterMTA uses s6-overlay init scripts for its customizations:

| Script | Purpose |
|--------|---------|
| `91-bind-hostname.sh` | Multi-IP binding (LISTEN_ON/SEND_ON) |
| `92-roundcube-plugins.sh` | Enable built-in Roundcube plugins |
| `93-custom-branding.sh` | BAUER GROUP branding |

These scripts run after Poste.io's own initialization (numbered 90+).

## Troubleshooting

### Stack won't start

```bash
# Check Docker is running
sudo systemctl status docker

# Check for port conflicts
sudo netstat -tlnp | grep -E '25|80|443|465|587'

# View detailed logs
sudo ./clustermta.sh logs
```

### Certificate issues

```bash
# Check certificate status in Poste.io admin panel
# Virtual Domains → your domain → SSL Certificate

# Force certificate renewal
# Admin Panel → System Settings → TLS Certificate → Renew
```

#### Automatic certificate self-heal

Poste.io renews Let's Encrypt certificates daily, but its renewal is not
atomic: the fresh certificate is written to
`/data/ssl/letsencrypt/<domain>/` and only *afterwards* copied into the live
store `/etc/ssl/` and reloaded. If anything in between fails (most commonly the
renewal-notification e-mail), the fresh certificate is never activated and the
served certificate stays frozen until it expires — while a perfectly valid
certificate already sits in the container.

ClusterMTA ships a **self-heal reconcile** (`/opt/clustermta/le-cert-sync.sh`)
that closes this gap. It runs at container start and every 15 minutes via cron,
compares the served certificate against the freshest valid Let's Encrypt
certificate, and re-activates + reloads the daemons only when they drift. It is
idempotent and a no-op on healthy systems and on self-signed / proxy setups.

```bash
# Watch what the self-heal did
docker exec <container_name> tail -n 50 /data/log/clustermta/cert-sync.log

# Trigger a reconcile immediately (instead of waiting for the 15-min cron)
docker exec <container_name> /opt/clustermta/le-cert-sync.sh --cron
```

Manual last-resort fix (should no longer be necessary): re-point the served
certificate at the current Let's Encrypt files and restart the container.

```bash
ln -sf /data/ssl/letsencrypt/<domain>/fullchain.pem /data/ssl/server.crt
ln -sf /data/ssl/letsencrypt/<domain>/chain.pem     /data/ssl/ca.crt
ln -sf /data/ssl/letsencrypt/<domain>/private.pem   /data/ssl/server.key
```

### Mail delivery issues

```bash
# Check mail queue
docker exec -it <container_name> postqueue -p

# View mail logs
sudo ./clustermta.sh logs | grep -E 'postfix|dovecot'

# Test SMTP connection
telnet mx1.simply-send.com 25
```

### Reset everything

```bash
# Stop and remove containers/volumes (DESTRUCTIVE!)
sudo ./clustermta.sh destroy

# Remove all data
sudo rm -rf /opt/clustermta/.env

# Start fresh
sudo ./setup.sh
sudo ./clustermta.sh start
```

## Security Considerations

- **Network mode**: Host mode required for proper mail server operation
- **Firewall**: Ensure only required ports are open
- **Updates**: Regularly update with `./clustermta.sh update`
- **Backups**: Schedule regular backups
- **Monitoring**: Check logs for suspicious activity
- **DMARC**: Use `p=reject` policy after verification

## License

MIT License - BAUER GROUP

## Links

- [Poste.io Documentation](https://poste.io/doc/)
- [Poste.io FAQ](https://poste.io/doc/faq)
- [Docker Hub - Poste.io](https://hub.docker.com/r/analogic/poste.io)
- [Mail-Tester](https://www.mail-tester.com/) - Test your mail server configuration
- [MXToolbox](https://mxtoolbox.com/) - DNS and mail server diagnostics
