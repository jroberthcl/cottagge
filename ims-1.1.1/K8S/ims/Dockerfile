# ------------------------------------------------------------------------------
# BASE IMAGE
# Puedes descomentar la siguiente línea si deseas parametrizar la imagen base
# ARG IUM_PROJECT
# ARG IUM_IMAGE_NAME
# ARG IUM_TYPE_VERSION
# ARG IUM_BASE_VERSION
# ARG IUM_BASE_TAG

FROM hub.valentine.sfr.com/${IUM_PROJECT}/${IUM_IMAGE_NAME}:${IUM_IMAGE_TAG}

USER root


# Application packaging

RUN mkdir -p /tmp/package.d/App
COPY src/ims/App /tmp/package.d/App
COPY src/ims/App.yaml /tmp/package.d/App.yaml
RUN cd /tmp/package.d/ && jar cvf /tmp/App.jar .
RUN mkdir -p /eium/mnt/package.d /var/opt/scripts
RUN cp /tmp/App.jar /eium/mnt/package.d/App.jar
RUN cp /tmp/package.d/App/scripts/dynamic_environment.sh /var/opt/scripts/dynamic_environment.sh
RUN chmod a+rx /var/opt/scripts/dynamic_environment.sh


# Certificates

RUN mkdir -p /etc/pki/ca-trust/source/anchors
COPY src/ims/certificates/cert03.pem /etc/pki/ca-trust/source/anchors
RUN update-ca-trust


# Environment

COPY src/ims/env/.bashrc /home/eium/.bashrc
RUN chown 10001:10001 /home/eium/.bashrc

USER 10001
WORKDIR /var/opt/SIU/
