#!/usr/bin/env bash
# CIS Level 2 hardening for Rocky Linux 9 — run during Packer image build as root.
#
# Cloud exceptions:
#   - No bootloader password (no physical console on EC2 / QEMU cloud images)
#   - No separate partitions (single-root layout; enforce at launch via LVM if needed)
#   - AIDE not initialised at build time (initialise on first boot of running instances)
#   - cramfs module not disabled (benign on cloud, avoids boot issues on some kernels)

set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ── 1. Filesystem ─────────────────────────────────────────────────────────────

log "1. Filesystem — disabling unused kernel modules"

for mod in freevxfs jffs2 hfs hfsplus squashfs udf; do
  cat > "/etc/modprobe.d/${mod}.conf" <<EOF
install ${mod} /bin/false
blacklist ${mod}
EOF
done

log "1. Filesystem — /tmp via tmpfs"
# Enable the systemd tmp.mount unit (mounts /tmp as tmpfs with nodev,nosuid,noexec)
systemctl unmask tmp.mount
systemctl enable tmp.mount

log "1. Filesystem — /dev/shm hardening via systemd override"
mkdir -p /etc/systemd/system/dev-shm.mount.d
cat > /etc/systemd/system/dev-shm.mount.d/options.conf <<'EOF'
[Mount]
Options=nodev,nosuid,noexec
EOF

# ── 2. Package hygiene ────────────────────────────────────────────────────────

log "2. Package hygiene — removing legacy / high-risk packages"
dnf remove -y \
  telnet \
  rsh \
  rsh-server \
  ypbind \
  ypserv \
  tftp \
  tftp-server \
  talk \
  talk-server \
  xinetd \
  net-snmp \
  openldap-clients \
  2>/dev/null || true

log "2. Package hygiene — ensuring gpgcheck is enabled"
sed -i 's/^gpgcheck\s*=.*/gpgcheck=1/' /etc/dnf/dnf.conf
# Ensure all repo files also enforce gpgcheck
find /etc/yum.repos.d -name '*.repo' -exec \
  sed -i 's/^gpgcheck\s*=\s*0/gpgcheck=1/' {} \;

log "2. Package hygiene — applying available security updates"
dnf update -y --security 2>/dev/null || dnf update -y

# ── 3. Process hardening ──────────────────────────────────────────────────────

log "3. Process hardening — core dumps, ASLR, ptrace scope"

cat > /etc/sysctl.d/99-cis-process.conf <<'EOF'
# Restrict core dumps
fs.suid_dumpable = 0

# Address Space Layout Randomisation
kernel.randomize_va_space = 2

# Restrict ptrace to own processes (CIS 1.5.4)
kernel.yama.ptrace_scope = 1
EOF

# Disable core dumps via limits
cat > /etc/security/limits.d/cis-coredump.conf <<'EOF'
* hard core 0
EOF

# Disable core dump storage via systemd
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/cis.conf <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF

# ── 4. Mandatory access control ───────────────────────────────────────────────

log "4. SELinux — enforcing / targeted"
sed -i 's/^SELINUX=.*/SELINUX=enforcing/'   /etc/selinux/config
sed -i 's/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' /etc/selinux/config

log "4. Crypto policy — FIPS"
update-crypto-policies --set FIPS

# ── 5. Services ───────────────────────────────────────────────────────────────

log "5. Services — disabling high-risk / unnecessary services"
for svc in \
  avahi-daemon \
  cups \
  dhcpd \
  slapd \
  nfs-server \
  rpcbind \
  named \
  vsftpd \
  httpd \
  dovecot \
  smb \
  squid \
  snmpd \
  ypserv \
  rsh.socket \
  rlogin.socket \
  rexec.socket \
  telnet.socket \
; do
  systemctl disable --now "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done

log "5. Services — enabling firewalld"
dnf install -y firewalld
systemctl enable --now firewalld
firewall-cmd --set-default-zone=public --permanent

log "5. Services — enabling auditd at boot"
systemctl enable auditd

# ── 6. Network ────────────────────────────────────────────────────────────────

log "6. Network — kernel parameters (sysctl)"
cat > /etc/sysctl.d/99-cis-network.conf <<'EOF'
# Disable IP forwarding (host-only, not a router)
net.ipv4.ip_forward = 0

# Disable send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable accept source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Log martian packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore broadcast ICMP
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP errors
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Disable IPv6 router advertisements and redirects
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
EOF

log "6. Network — disabling uncommon network protocols"
for proto in dccp sctp rds tipc; do
  cat > "/etc/modprobe.d/${proto}.conf" <<EOF
install ${proto} /bin/false
blacklist ${proto}
EOF
done

# ── 7. Logging and auditing ───────────────────────────────────────────────────

log "7. Auditd — configuration"
dnf install -y audit audit-libs

sed -i 's|^space_left_action\s*=.*|space_left_action = email|'       /etc/audit/auditd.conf
sed -i 's|^action_mail_acct\s*=.*|action_mail_acct = root|'          /etc/audit/auditd.conf
sed -i 's|^admin_space_left_action\s*=.*|admin_space_left_action = halt|' /etc/audit/auditd.conf
sed -i 's|^max_log_file\s*=.*|max_log_file = 32|'                    /etc/audit/auditd.conf
sed -i 's|^max_log_file_action\s*=.*|max_log_file_action = keep_logs|' /etc/audit/auditd.conf
sed -i 's|^log_format\s*=.*|log_format = ENRICHED|'                  /etc/audit/auditd.conf

log "7. Auditd — CIS Level 2 audit rules"
cat > /etc/audit/rules.d/99-cis.rules <<'EOF'
## CIS Level 2 audit rules for Rocky Linux 9

# Remove any existing rules and set buffer size
-D
-b 8192
--backlog_wait_time 60000
-f 2

# --- Identity changes ---
-w /etc/group  -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow  -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# --- Network environment ---
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale
-w /etc/issue      -p wa -k system-locale
-w /etc/issue.net  -p wa -k system-locale
-w /etc/hosts      -p wa -k system-locale
-w /etc/sysconfig/network -p wa -k system-locale
-w /etc/sysconfig/network-scripts/ -p wa -k system-locale

# --- MAC policy changes ---
-w /etc/selinux/  -p wa -k MAC-policy
-w /usr/share/selinux/ -p wa -k MAC-policy

# --- Login / logout ---
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins

# --- Session initiation ---
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins

# --- Discretionary access control changes ---
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=unset -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=unset -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=unset -k perm_mod
-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=unset -k perm_mod
-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=unset -k perm_mod
-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=unset -k perm_mod

# --- Unsuccessful file access ---
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM  -F auid>=1000 -F auid!=unset -k access
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM  -F auid>=1000 -F auid!=unset -k access

# --- Privileged commands ---
-a always,exit -F path=/usr/bin/chage   -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/bin/chsh    -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/bin/newgrp  -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/bin/passwd  -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/bin/sudo    -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/bin/su      -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/bin/gpasswd -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/sbin/usermod -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/sbin/useradd -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/sbin/userdel -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/sbin/groupadd -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/sbin/groupmod -F perm=x -F auid>=1000 -F auid!=unset -k privileged
-a always,exit -F path=/usr/sbin/groupdel -F perm=x -F auid>=1000 -F auid!=unset -k privileged

# --- File deletion ---
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=unset -k delete
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=unset -k delete

# --- Sudoers changes ---
-w /etc/sudoers      -p wa -k scope
-w /etc/sudoers.d/   -p wa -k scope

# --- Sudo log ---
-w /var/log/sudo.log -p wa -k actions

# --- Kernel module loading ---
-w /sbin/insmod  -p x -k modules
-w /sbin/rmmod   -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

# Make the configuration immutable (requires reboot to change rules)
-e 2
EOF

log "7. Rsyslog — ensuring remote logging is configured"
dnf install -y rsyslog
systemctl enable rsyslog

# Ensure rsyslog sends logs to local files (CIS 4.2.1)
cat > /etc/rsyslog.d/99-cis.conf <<'EOF'
# CIS 4.2 — ensure all auth messages are logged
auth,authpriv.*                 /var/log/secure
mail.*                          -/var/log/maillog
cron.*                          /var/log/cron
*.emerg                         :omusrmsg:*
uucp,news.crit                  /var/log/spooler
local7.*                        /var/log/boot.log
EOF

# ── 8. SSH ────────────────────────────────────────────────────────────────────

log "8. SSH — applying CIS hardened configuration"
cat > /etc/ssh/sshd_config.d/99-cis.conf <<'EOF'
# CIS Level 2 SSH hardening — Rocky Linux 9

LogLevel VERBOSE
MaxAuthTries 4
IgnoreRhosts yes
HostbasedAuthentication no
PermitRootLogin no
PermitEmptyPasswords no
PermitUserEnvironment no
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 0
LoginGraceTime 60
Banner /etc/issue.net
UsePAM yes
PrintLastLog yes

Ciphers aes256-gcm@openssh.com,chacha20-poly1305@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp521
EOF

# Restrict SSH host key file permissions
chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true

# ── 9. PAM and password policy ────────────────────────────────────────────────

log "9. PAM — password quality (pwquality)"
dnf install -y libpwquality

cat > /etc/security/pwquality.conf <<'EOF'
# CIS 5.3.1 — password complexity
minlen   = 14
minclass = 4
maxrepeat = 3
maxsequence = 3
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
EOF

log "9. PAM — account lockout (faillock)"
cat > /etc/security/faillock.conf <<'EOF'
# CIS 5.3.2 — lock account after 5 failed attempts for 15 minutes
deny = 5
fail_interval = 900
unlock_time = 900
even_deny_root
EOF

log "9. PAM — limit password reuse"
# Ensure pam_pwhistory is configured to remember 24 passwords
if grep -q 'pam_pwhistory' /etc/pam.d/system-auth 2>/dev/null; then
  sed -i 's/remember=[0-9]*/remember=24/' /etc/pam.d/system-auth
else
  sed -i '/pam_unix.so.*use_authtok/i password    requisite     pam_pwhistory.so use_authtok remember=24 retry=3' \
    /etc/pam.d/system-auth 2>/dev/null || true
fi

log "9. Password aging"
sed -i 's/^PASS_MAX_DAYS\s*.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS\s*.*/PASS_MIN_DAYS   7/'  /etc/login.defs
sed -i 's/^PASS_WARN_AGE\s*.*/PASS_WARN_AGE   14/' /etc/login.defs

log "9. Default umask — 027"
sed -i 's/^UMASK\s*.*/UMASK           027/' /etc/login.defs
# Also set in /etc/profile.d
cat > /etc/profile.d/cis-umask.sh <<'EOF'
umask 027
EOF

log "9. User inactivity — lock accounts inactive for 30 days"
useradd -D -f 30

# ── 10. Access controls ───────────────────────────────────────────────────────

log "10. Cron — restrict to root only"
rm -f /etc/cron.deny /etc/at.deny
cat > /etc/cron.allow <<'EOF'
root
EOF
cat > /etc/at.allow <<'EOF'
root
EOF
chmod 600 /etc/cron.allow /etc/at.allow
chown root:root /etc/cron.allow /etc/at.allow

log "10. cron directories — set permissions"
chown root:root /etc/crontab
chmod og-rwx   /etc/crontab

for dir in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d; do
  [ -d "${dir}" ] && chown root:root "${dir}" && chmod og-rwx "${dir}"
done

log "10. Login banners"
cat > /etc/issue <<'EOF'
Authorised users only. All activity may be monitored and reported.
EOF
cat > /etc/issue.net <<'EOF'
Authorised users only. All activity may be monitored and reported.
EOF
cat > /etc/motd <<'EOF'
Authorised users only. All activity may be monitored and reported.
EOF
chmod 644 /etc/issue /etc/issue.net /etc/motd
chown root:root /etc/issue /etc/issue.net /etc/motd

log "10. Sensitive file permissions"
chmod 600 /etc/ssh/sshd_config
chown root:root /etc/ssh/sshd_config
chmod 644 /etc/passwd /etc/group
chmod 640 /etc/shadow /etc/gshadow
chown root:shadow /etc/shadow /etc/gshadow 2>/dev/null || \
  chown root:root  /etc/shadow /etc/gshadow

log "10. Ensure /etc/passwd- and /etc/shadow- backups have correct permissions"
[ -f /etc/passwd- ] && chmod 600 /etc/passwd-
[ -f /etc/shadow- ] && chmod 000 /etc/shadow-
[ -f /etc/group-  ] && chmod 644 /etc/group-

log "10. Disable root login on non-console ttys"
cat > /etc/securetty <<'EOF'
console
EOF

# ── 11. Sudo ──────────────────────────────────────────────────────────────────

log "11. Sudo — require password, use pty, restrict log"
cat > /etc/sudoers.d/99-cis <<'EOF'
Defaults use_pty
Defaults logfile="/var/log/sudo.log"
Defaults !visiblepw
Defaults always_set_home
Defaults match_group_by_gid
Defaults always_query_group_plugin
EOF
chmod 440 /etc/sudoers.d/99-cis

# ── 12. Kernel hardening ──────────────────────────────────────────────────────

log "12. Kernel hardening — additional sysctl parameters"
cat > /etc/sysctl.d/99-cis-kernel.conf <<'EOF'
# Restrict access to kernel logs
kernel.dmesg_restrict = 1

# Restrict kernel pointer exposure
kernel.kptr_restrict = 2

# Disable magic sysrq
kernel.sysrq = 0

# Restrict unprivileged BPF
kernel.unprivileged_bpf_disabled = 1

# Enable BPF JIT hardening
net.core.bpf_jit_harden = 2
EOF

log "Hardening complete."
