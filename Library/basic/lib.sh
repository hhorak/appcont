#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /CoreOS/appcont/Library/basic
#   Description: A library for running application containers tests
#   Author: Honza Horak <hhorak@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   library-prefix = appcont
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 NAME

appcont/basic - A library for running application containers tests

=head1 DESCRIPTION

This library provides functions for manipulation with application containers,
that are part of the RHSCL, RHEL or Fedora products.

=cut

# For some environments, different registry can be used
CONTAINER_REGISTRY_FLAT_NAMESPACE=0
CONTAINER_REGISTRY_INSECURE=0
CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-registry.access.redhat.com/}

# adds internal registry for podman or docker
appcont_basic__add_insecure_registry() {
  if [ "${CONTAINER_REGISTRY_INSECURE:-0}" -eq 1 ] ; then
    sed -i \
        -e "/\[registries.insecure\]/a registries = ['${CONTAINER_REGISTRY%%/*}']" \
        -e "/\[registries.insecure\]/{n;d}" \
        /etc/containers/registries.conf
  fi
}

# install docker or podman, whatever is the default choice on that platform
# and configure it so we can use the internal registry
appcont_basic__get_docker() {
  case $(source /etc/os-release ; echo $VERSION_ID) in
    7*)
      # extras needed for docker package
      yum-config-manager --enable rhel-7-server-extras-rpms
      yum install -y docker

      appcont_basic__add_insecure_registry
      systemctl restart docker
    ;;
    *)
      # rhel-8 and fedora
      yum install -y podman podman-docker
      appcont_basic__add_insecure_registry
    ;;
  esac
}


# which branch to take the container sources from
appcont_basic__get_branch_name() {
  local version_id=$(source /etc/os-release ; echo $VERSION_ID)
  case ${version_id} in
    7*) git branch -a | grep -o rhscl-3\.[0-9]-rhel-7 | sort | tail -n 1 ;;
    8*) echo "rhel-${version_id}.0" ;;
    *)  # fedora
        echo "f${version_id}" ;;
  esac
}

# tests need this variable defined
appcont_basic__get_os_name() {
  case $(source /etc/os-release ; echo $VERSION_ID) in
    7*) OS=rhel7 ;;
    8*) OS=rhel8 ;;
    *) OS=fedora ;;
  esac
}

# parses the parent image from a Dockerfile and pulls it
appcont_basic__get_parent_image() {
  local registry=''
  parent_image=$(grep ^FROM Dockerfile | sed -e 's/FROM\s*//')
  if ! echo "$parent_image" | grep -q -e '.*/.*/.*' ; then
    # it looks like the registry is not part of the parent name
    registry="${CONTAINER_REGISTRY}"
  fi
  if [ "${CONTAINER_REGISTRY_FLAT_NAMESPACE:-0}" -eq 1 ] ; then
    parent_image_full=${registry}${parent_image//\//-}
  else
    parent_image_full=${registry}${parent_image}
  fi
  docker pull ${parent_image_full}
  docker tag ${parent_image_full} ${parent_image}
}

appcont_basic__prepare_repo_dir_for_dockerfile() {
  local output_dir=$1
  local output_dockerfile=$2

  mkdir -p "${output_dir}"

  sed -i -e "/^FROM/ a\
ENV SKIP_REPOS_DISABLE=true SKIP_REPOS_ENABLE=true" "${output_dockerfile}"

  for repo_file in /etc/yum.repos.d/*repo ; do
    sed -i -e "/^FROM/ a\
ADD ${output_dir}/$(basename $repo_file) $repo_file" "${output_dockerfile}"
    cat "$repo_file" >> "${output_dir}"/"$(basename $repo_file)"
  done
}

# prepares a Dockerfile into a new file Dockerfile.tempcopy in CWD
appcont_basic__prepare_dockerfile_rebuild() {
  cat Dockerfile > Dockerfile.tempcopy
  appcont_basic__prepare_repo_dir_for_dockerfile ./temp_repos Dockerfile.tempcopy

  echo "Generating help.1 from README.md and storing into /help.1"
  cat README.md | docker run -i --rm quay.io/hhorak/md2man >help.1
  echo "ADD help.1 /help.1" >> Dockerfile.tempcopy
}

# prepares a Dockerfile for the updated use case
appcont_basic__prepare_dockerfile_updated() {
  local container_name=$1
  local packages_update=$2
  local original_user

  original_user=$(docker run -ti --rm $container_name bash -c 'id -u')

  echo "FROM $container_name" > Dockerfile.tempcopy
  echo "USER 0" >> Dockerfile.tempcopy
  appcont_basic__prepare_repo_dir_for_dockerfile ./temp_repos Dockerfile.tempcopy

  echo "RUN yum -y update ${packages_update} && yum -y clean all" >> Dockerfile.tempcopy
  echo "USER ${original_user}" >> Dockerfile.tempcopy
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Authors
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 AUTHORS

=over

=item *

Honza Horak <hhorak@redhat.com>

=back

=cut
