###############################################################################
# Step 1 : Builder image
FROM kubevious/node-builder:24@sha256:e64dd91a6d1b48f3b1386d6b09b441aee40658220f28f1d4790ba134ab32235a
RUN node --version
RUN npm --version
RUN yarn --version
WORKDIR /app
# COPY ASSESTS FROM MOCK-DATA
RUN mkdir -p ./assets/k8s-api-json-schema
RUN git clone https://github.com/kubevious/mock-data.git mock-data.git
RUN cp mock-data.git/k8s-api-json-schema/*.json ./assets/k8s-api-json-schema/
RUN rm -rf mock-data.git
# COPY CRD ASSETS
COPY ./crds ./assets/crds
RUN find ./assets
# COPY SOURCES
COPY ./package*.json ./
COPY ./yarn.lock ./
RUN yarn install --frozen-lockfile
COPY ./bin ./bin
COPY ./src ./src
COPY ./tsconfig.json ./
# BUILD
RUN npm run build
RUN npm pack
RUN mv kubevious-$(node -p -e "require('./package.json').version").tgz kubevious.tgz

###############################################################################
# Step 2 : Runner image
FROM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5
RUN apk update && apk upgrade && \
    apk --no-cache add ca-certificates bash openssl git curl wget jq
# DATA
RUN mkdir -p /data
# HELM 
ENV HELM_CACHE_HOME=/data/helm/cache
ENV HELM_CONFIG_HOME=/data/helm/config
ENV HELM_DATA_HOME=/data/helm/data
RUN mkdir -p ${HELM_CACHE_HOME}
RUN mkdir -p ${HELM_CONFIG_HOME}
RUN mkdir -p ${HELM_DATA_HOME}
ENV HELM_VERSION=3.22.1
WORKDIR /tmp
RUN curl -L https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz -o helm.tar.gz && \
    curl -L https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz.sha256sum -o helm.tar.gz.sha256sum && \
    sha256sum -c helm.tar.gz.sha256sum || echo "WARNING: Helm checksum mismatch" && \
    tar -xvf helm.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf helm.tar.gz helm.tar.gz.sha256sum linux-amd64
# KUSTOMIZE
ENV KUSTOMIZE_VER=5.2.1
WORKDIR /tmp
RUN curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VER}/kustomize_v${KUSTOMIZE_VER}_linux_amd64.tar.gz -o kustomize.tar.gz && \
    curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VER}/checksums.txt -o kustomize.checksums.txt && \
    grep "kustomize_v${KUSTOMIZE_VER}_linux_amd64.tar.gz" kustomize.checksums.txt | sha256sum -c - || echo "WARNING: Kustomize checksum mismatch" && \
    tar -xvf kustomize.tar.gz && \
    chmod +x kustomize && \
    rm kustomize.tar.gz kustomize.checksums.txt
RUN mv kustomize /usr/local/bin/
RUN ls -la /usr/local/bin/kustomize
# Kubevious CLI
WORKDIR /app
COPY --from=0 /app/kubevious.tgz ./
RUN npm install -g ./kubevious.tgz
RUN rm -rf /app
WORKDIR /src
COPY ./docker/docker-entrypoint.sh /
RUN addgroup -S kubevious && adduser -S kubevious -G kubevious -h /src
RUN chown -R kubevious:kubevious /data
USER kubevious
ENTRYPOINT ["/docker-entrypoint.sh"]