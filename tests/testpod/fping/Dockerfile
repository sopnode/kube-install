FROM fedora

RUN dnf -y install iputils iproute bind-utils hostname tcpdump netcat

ENTRYPOINT ["bash", "-c", "while true; do echo BEEP; sleep 1; done"]
