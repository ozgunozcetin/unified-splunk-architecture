FROM splunk/universalforwarder:9.4

USER root

# UBI-based image — install rsyslog via microdnf
RUN microdnf install -y rsyslog && \
    microdnf clean all

# Pre-install our UF apps so Splunk Ansible picks them up at first boot
RUN mkdir -p /opt/splunkforwarder/etc/apps/syslog_inputs/local
RUN mkdir -p /opt/splunkforwarder/etc/apps/syslog_outputs/local
COPY config/inputs.conf /opt/splunkforwarder/etc/apps/syslog_inputs/local/inputs.conf
COPY config/outputs.conf /opt/splunkforwarder/etc/apps/syslog_outputs/local/outputs.conf

# rsyslog config
COPY config/rsyslog.conf /etc/rsyslog.conf

# Wrapper entrypoint: run rsyslog in background, then hand off to Splunk's official entrypoint
COPY scripts/wrapper.sh /wrapper.sh
RUN chmod +x /wrapper.sh

# Reset ownership so splunk user can read its apps
RUN chown -R splunk:splunk /opt/splunkforwarder/etc/apps/syslog_inputs /opt/splunkforwarder/etc/apps/syslog_outputs

EXPOSE 514/udp
EXPOSE 514/tcp

ENTRYPOINT ["/wrapper.sh"]