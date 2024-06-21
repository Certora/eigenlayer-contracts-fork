FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y make curl git software-properties-common jq \
    && add-apt-repository -y ppa:longsleep/golang-backports \
    && add-apt-repository -y ppa:ethereum/ethereum \
    && apt-get update \
    && apt-get install -y golang "ethereum=1.14.5+build29958+$(lsb_release -c | awk '{ print $2 }')" \
    && curl -L https://foundry.paradigm.xyz | bash \
    && /root/.foundry/bin/foundryup

RUN cp -R /root/.foundry/bin/* /usr/local/bin/

