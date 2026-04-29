#!/bin/bash
set -e

echo "[wrapper] Starting Site A Syslog Tier"

mkdir -p /var/log/network /var/spool/rsyslog
chown -R splunk:splunk /var/log/network /var/spool/rsyslog
chmod 755 /var/log/network /var/spool/rsyslog

rm -f /var/run/rsyslogd.pid

echo "[wrapper] Starting rsyslog daemon..."
rsyslogd
sleep 2

if pgrep rsyslogd > /dev/null; then
    echo "[wrapper] rsyslog running (UDP/514, TCP/514)"
else
    echo "[wrapper] WARNING: rsyslog did not start"
fi

echo "[wrapper] SPLUNK_START_ARGS=$SPLUNK_START_ARGS"
echo "[wrapper] SPLUNK_PASSWORD set: $([ -n "$SPLUNK_PASSWORD" ] && echo yes || echo no)"
echo "[wrapper] Handing off to Splunk's official entrypoint with start-service..."

exec /sbin/entrypoint.sh start-service 2>&1
