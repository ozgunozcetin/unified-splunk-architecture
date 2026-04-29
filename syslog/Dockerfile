FROM splunk/universalforwarder:9.4

USER root

# UBI-based image — install rsyslog via microdnf
# Pre-install our UF apps so Splunk Ansible picks them up at first boot
# (single RUN to minimise layers — DL3059)
RUN microdnf install -y rsyslog && \
    microdnf clean all && \
    mkdir -p /opt/splunkforwarder/etc/apps/syslog_inputs/local && \
    mkdir -p /opt/splunkforwarder/etc/apps/syslog_outputs/local && \
    mkdir -p /seed

COPY config/inputs.conf /opt/splunkforwarder/etc/apps/syslog_inputs/local/inputs.conf
COPY config/outputs.conf /opt/splunkforwarder/etc/apps/syslog_outputs/local/outputs.conf
COPY config/rsyslog.conf /etc/rsyslog.conf
COPY scripts/wrapper.sh /wrapper.sh

# Single RUN for permission fixes (DL3059)
RUN chmod +x /wrapper.sh && \
    chown -R splunk:splunk \
      /opt/splunkforwarder/etc/apps/syslog_inputs \
      /opt/splunkforwarder/etc/apps/syslog_outputs

EXPOSE 514/udp
EXPOSE 514/tcp

ENTRYPOINT ["/wrapper.sh"]