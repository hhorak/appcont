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

# we use this internal registry for testing
QUAY_REGISTRY_PREFIX=${QUAY_REGISTRY_PREFIX:-registry-proxy.engineering.redhat.com/rh-osbs/}

# adds internal registry for podman or docker
appcont_basic__add_internal_registris() {
  sed -i \
      -e "/\[registries.insecure\]/a registries = ['registry-proxy.engineering.redhat.com']" \
      -e "/\[registries.insecure\]/{n;d}" \
      /etc/containers/registries.conf
}

# install docker or podman, whatever is the default choice on that platform
# and configure it so we can use the internal registry
appcont_basic__get_docker() {
  case $(source /etc/os-release ; echo $VERSION_ID) in
    7*)
      # for docker package
      if ! grep rhel-7-server-extras-rpms /etc/yum.repos.d/*repo ; then
        cat >/etc/yum.repos.d/rhel-extras.repo <<'EOF'
[rhel-7-server-extras-rpms]
name = Red Hat Enterprise Linux 7 Extras
mirrorlist = http://git.app.eng.bos.redhat.com/git/RH_Software_Collections.git/plain/Containers/osbs-repos-signed-pkgs/pulp_multiarch/$basearch/extras
enabled = 0
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF
      fi
      # images work with this in the Dockerfile, so we should make sure the rhscl repo is available
      if ! grep rhel-server-rhscl-7-rpms /etc/yum.repos.d/*repo ; then
        cat >/etc/yum.repos.d/rhscl-pulp.repo <<'EOF'
[rhel-server-rhscl-7-rpms]
name = Red Hat Software Collections Pulp
mirrorlist = http://git.app.eng.bos.redhat.com/git/RH_Software_Collections.git/plain/Containers/osbs-repos-signed-pkgs/pulp_multiarch/$basearch/rhscl
enabled = 0
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF
      fi
      yum-config-manager --enable rhel-7-server-extras-rpms
      yum install -y docker http://download.eng.bos.redhat.com/brewroot/vol/rhel-7/packages/golang-github-cpuguy83-go-md2man/1.0.4/4.el7/x86_64/golang-github-cpuguy83-go-md2man-1.0.4-4.el7.x86_64.rpm

      appcont_basic__add_internal_registris
      systemctl restart docker
    ;;
    *)
      # rhel-8 and fedora
      yum install -y podman podman-docker
      appcont_basic__add_internal_registris
    ;;
  esac
}

# which branch to take the container sources from
get_branch_name() {
  local version_id=$(source /etc/os-release ; echo $VERSION_ID)
  case ${version_id} in
    7*) git branch -a | grep -o rhscl-3\.[0-9]-rhel-7 | sort | tail -n 1 ;;
    8*) echo "rhel-${version_id}.0" ;;
    *)  # fedora
        echo "f${version_id}" ;;
  esac
}

# tests need this variable defined
get_os_name() {
  case $(source /etc/os-release ; echo $VERSION_ID) in
    7*) OS=rhel7 ;;
    8*) OS=rhel8 ;;
    *) OS=fedora ;;
  esac
}

# clones the image sources
appcont_basic__get_image_sources() {
  local container_component=$1
  local image_sources_dir=$2
  git clone git://pkgs.devel.redhat.com/containers/${container_component} ${image_sources_dir}
}

# parses the parent image from a Dockerfile and pulls it
appcont_basic__get_parent_image() {
  parent_image=$(grep ^FROM Dockerfile | sed -e 's/FROM\s*//')
  parent_image_quay=${parent_image//\//-}
  parent_image_full=${QUAY_REGISTRY_PREFIX}${parent_image_quay}
  docker pull ${parent_image_full}
  docker tag ${parent_image_full} ${parent_image}
}

# prepares a Dockerfile into a new file Dockerfile.tempcopy in CWD
appcont_basic__prepare_dockerfile() {
  mkdir -p ./temp_repos
  cat Dockerfile > Dockerfile.tempcopy
  for repo_file in /etc/yum.repos.d/*repo ; do
    sed -i -e "/^FROM/ a\
ADD ./temp_repos/$(basename $repo_file) $repo_file" Dockerfile.tempcopy
    cat "$repo_file" >> ./temp_repos/"$(basename $repo_file)"
  done

  echo "Generating help.1 from README.md and storing into /help.1"
  go-md2man -in "README.md" -out "help.1"
  echo "ADD help.1 /help.1" >> Dockerfile.tempcopy
}

# main function that is supposed to be called to do all the stuff
# prepares the environment and process the testing itself
appcont_basic__test_image() {
  local container_component=$1
  local container_version=$2

  appcont_basic__get_docker

  image_sources_dir=$(mktemp -d ./image_sources_XXXXXX)
  appcont_basic__get_image_sources "${container_component}" "${image_sources_dir}"

  pushd "${image_sources_dir}"

  git checkout $(get_branch_name)

  appcont_basic__get_parent_image
  appcont_basic__prepare_dockerfile

  docker build -t testimage -f Dockerfile.tempcopy .

  IMAGE_NAME=testimage VERSION=${container_version} test/run

  popd # from image_sources
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
