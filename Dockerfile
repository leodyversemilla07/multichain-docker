# Multichain Dockerfile (latest stable as of Aug 2025)
FROM ubuntu:22.04

ENV MULTICHAIN_VERSION=2.3.3

WORKDIR /tmp

RUN apt-get update && \
    apt-get install -y wget tar && \
    wget https://www.multichain.com/download/multichain-${MULTICHAIN_VERSION}.tar.gz && \
    tar -xvzf multichain-${MULTICHAIN_VERSION}.tar.gz && \
    cd multichain-${MULTICHAIN_VERSION} && \
    mv multichaind multichain-cli multichain-util /usr/local/bin/ && \
    cd /tmp && \
    rm -rf multichain-${MULTICHAIN_VERSION} multichain-${MULTICHAIN_VERSION}.tar.gz

WORKDIR /

VOLUME ["/root/.multichain"]

EXPOSE 8000 8001

CMD ["multichaind", "-daemon"]
