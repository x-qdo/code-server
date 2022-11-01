FROM node:16.15.1 as dev

WORKDIR /app

RUN apt update && apt install -y  \
    quilt \
    jq \
    curl \
    wget \
    dumb-init \
    zsh \
    htop \
    locales \
    man \
    nano \
    git \
    git-lfs \
    procps \
    openssh-client \
    rsync \
    vim.tiny \
    lsb-release \
    libx11-dev \
    libxkbfile-dev \
    libsecret-1-dev

RUN curl -sSfL https://github.com/goreleaser/nfpm/releases/download/v2.3.1/nfpm_2.3.1_`uname -s`_`uname -m`.tar.gz | tar -C /usr/local/bin -zxv nfpm \
    && curl -sSfL https://github.com/a8m/envsubst/releases/download/v1.1.0/envsubst-`uname -s`-`uname -m` -o envsubst \
    && chmod +x envsubst \
    && mv envsubst /usr/local/bin

#COPY ./ci ./ci
#COPY ./lib/vscode/build/npm ./lib/vscode/build/npm
#COPY package.json yarn.lock ./
#COPY test/package.json test/yarn.lock test/
#COPY test/e2e/extensions/test-extension/package.json test/e2e/extensions/test-extension/yarn.lock test/e2e/extensions/test-extension/
#COPY lib/vscode/package.json lib/vscode/yarn.lock lib/vscode/

ADD . .

RUN --mount=type=cache,id=vscode-yarn-cache,target=/root/.yarn \
        YARN_CACHE_FOLDER=/root/.yarn yarn --frozen-lockfile

ENV PATH=$PATH:/app/node_modules/.bin/

ENTRYPOINT ["yarn", "run", "watch"]

FROM dev as builder

RUN tsc --outDir ./out_temp && tsc --outDir ./out
RUN yarn build
RUN yarn build:vscode
RUN yarn release
RUN yarn release:standalone
RUN yarn package

FROM code-server:0.3 as ready

RUN apt update && apt install -y wget curl zsh
RUN sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
RUN mkdir /home/task

COPY ./configs/code-server /root/.config/code-server
COPY ./configs/vsode /root/.local/share/code-server

ENTRYPOINT ["yarn", "run", "watch"]


FROM builder as package

FROM debian:11 as coddy

RUN apt-get update \
 && apt-get install -y \
    curl \
    dumb-init \
    zsh \
    htop \
    locales \
    man \
    nano \
    git \
    git-lfs \
    procps \
    openssh-client \
    vim.tiny \
    lsb-release \
  && git lfs install \
  && rm -rf /var/lib/apt/lists/*

COPY --from=package /app/release-packages/code-server_4.4.0_amd64.deb /tmp/
RUN dpkg -i /tmp/code-server*amd64.deb

WORKDIR /home/task

COPY ./configs/code-server /root/.config/code-server
COPY ./configs/vsode /root/.local/share/code-server

RUN code-server --install-extension redhat.vscode-yaml

ENTRYPOINT ["/usr/bin/code-server", "--bind-addr", "0.0.0.0:8080", "."]


FROM coddy

# renovate: datasource=github-tags depName=helm/helm
ENV HELM_VERSION=v3.8.2
ENV HELM_HOME="/root/.helm"

COPY ./configs/vsode /root/.local/share/code-server

RUN apt-get update && apt-get install -y wget openssh-client jq pv zsh \
    && wget -q https://storage.googleapis.com/kubernetes-release/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl -O /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && sh -c "$(wget https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)" \
    && wget -q https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -O - | tar -xzO linux-amd64/helm > /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm

RUN mkdir -p $HELM_HOME/plugins \
    && helm plugin install --debug https://github.com/databus23/helm-diff
