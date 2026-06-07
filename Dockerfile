# # Dockerfile that builds a fully functional image of your app.
# #
# # This image installs all Python dependencies for your application. It's based
# # on Almalinux (https://github.com/inveniosoftware/docker-invenio)
# # and includes Pip, Pipenv, Node.js, NPM and some few standard libraries
# # Invenio usually needs.
# #
# # Note: It is important to keep the commands in this file in sync with your
# # bootstrap script located in ./scripts/bootstrap.
#
# FROM registry.cern.ch/inveniosoftware/almalinux:1
#
# COPY site ./site
# COPY pyproject.toml uv.lock ./
# RUN uv sync --locked --no-progress --compile-bytecode && \
#     uv clean
#
# COPY ./docker/uwsgi/ ${INVENIO_INSTANCE_PATH}
# COPY ./invenio.cfg ${INVENIO_INSTANCE_PATH}
# COPY ./templates/ ${INVENIO_INSTANCE_PATH}/templates/
# COPY ./app_data/ ${INVENIO_INSTANCE_PATH}/app_data/
# COPY ./translations/ ${INVENIO_INSTANCE_PATH}/translations/
# COPY ./ .
#
# RUN cp -r ./static/. ${INVENIO_INSTANCE_PATH}/static/ && \
#     cp -r ./assets/. ${INVENIO_INSTANCE_PATH}/assets/ && \
#     invenio collect --verbose  && \
#     invenio webpack buildall
#
# ENTRYPOINT [ "bash", "-c"]

# ^ original dockerfile | v TUW dockerfile

# Dockerfile that builds a fully functional image of your app.

FROM cgr.dev/chainguard/wolfi-base AS builder

# the server name is just there to satisfy the strict startup sanity check
# it's not really used during the build step, so it can be set to anything
ARG INVENIO_SERVER_NAME=localhost
ARG INVENIO_INSTANCE_PATH=/var/instance

# set language/locale
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV PATH="${INVENIO_INSTANCE_PATH}/.venv/bin:${PATH}"

# create the instance dir and set it as working directory
RUN mkdir -p "${INVENIO_INSTANCE_PATH}"
WORKDIR ${INVENIO_INSTANCE_PATH}

# install build dependencies
RUN apk update && \
    apk add cairo gcc git nodejs npm py3.14-setuptools python-3.14 python-3.14-dev uv && \
    npm install --global --ignore-scripts pnpm

# install the python dependencies system-wide
COPY ./site ${INVENIO_INSTANCE_PATH}/site
ENV CC=gcc
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-progress --compile-bytecode && \
    uv clean

# copy the relevant files from the local project directory
COPY ./docker/uwsgi/ ${INVENIO_INSTANCE_PATH}/uwsgi/
COPY ./invenio.cfg ${INVENIO_INSTANCE_PATH}/
COPY ./app_data/ ${INVENIO_INSTANCE_PATH}/app_data/
COPY ./assets/ /tmp/assets/
COPY ./static/ /tmp/static/
COPY ./templates/ /tmp/templates/
COPY ./translations/ /tmp/translations/

# collect & build the frontend, and clean up unnecessary source files
# local overrides are copied over before/after the build step so they don't get lost during the build
ENV INVENIO_WEBPACKEXT_NPM_PKG_CLS=pynpm:PNPMPackage
RUN invenio collect --verbose && \
    mkdir assets templates translations && \
    cp -r /tmp/assets/ ${INVENIO_INSTANCE_PATH}/ && \
    invenio webpack create && \
    invenio webpack install && \
    INVENIO_WEBPACKEXT_NPM_PKG_CLS=pynpm:NPMPackage invenio webpack build && \
    cp -r /tmp/static/ ${INVENIO_INSTANCE_PATH}/ && \
    cp -r /tmp/templates/ ${INVENIO_INSTANCE_PATH}/ && \
    cp -r /tmp/translations/ ${INVENIO_INSTANCE_PATH}/ && \
    rm -rf ${INVENIO_INSTANCE_PATH}/assets/node_modules && \
    pnpm cache delete


# the actual invenio app image
FROM cgr.dev/chainguard/wolfi-base

ARG INVENIO_INSTANCE_PATH=/var/instance
WORKDIR ${INVENIO_INSTANCE_PATH}

# set language/locale
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV INVENIO_INSTANCE_PATH=/var/instance
ENV PATH="${INVENIO_INSTANCE_PATH}/.venv/bin:${PATH}"

# install the runtime dependencies
RUN apk update && \
    apk add cairo ttf-dejavu imagemagick py3.14-setuptools python-3.14 && \
    apk cache clean

# copy over the built application
COPY --from=builder "${INVENIO_INSTANCE_PATH}" "${INVENIO_INSTANCE_PATH}"
RUN chmod g+w "${INVENIO_INSTANCE_PATH}"

ENTRYPOINT ["sh", "-c"]
