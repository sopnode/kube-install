FROM ubuntu

RUN apt-get update
RUN apt-get install -y iputils-ping iproute2 dnsutils tcpdump netcat lksctp-tools curl

ENTRYPOINT ["bash", "-c", "while true; do echo BEEP; sleep 1; done"]
