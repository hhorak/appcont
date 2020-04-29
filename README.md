# appcont: Beakerlib library for application containers testing during RPM verification

Few thoughts this library is designed with:

* The library should work for RHSCL, RHEL and Fedora images
* For RHSCL and RHEL images, some environment variables need to be re-defined by the test case itself
* The packages we work with are coming from the host repositories (these repos are coppied to the container)
* We cover the following two use cases:
  1. Build an image from source and run the tests from the git repo
  1. Take the last released image, update the package we test and then run the tests from the git repo


## Example of the usage

The following is an example how a concrete test case can look like:

```
rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm --all
        rlAssertBinaryOrigin $NODEJS

        rlRun "rlImport appcont/basic"

        rlRun "appcont_basic__get_docker" 0 "Installing and configuring docker or podman"
        rlRun "appcont_basic__get_os_name"

        rlRun "node_major=$(node --version | sed -e 's/\..*$//' -e 's/^v//')"

        CONTAINER_SOURCES=https://src.fedoraproject.org/container/nodejs.git
        CONTAINER_NAME="f$(source /etc/os-release ; echo $VERSION_ID)/nodejs"
        [ -f container-env.sh ] && source container-env.sh

        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "git clone $CONTAINER_SOURCES '${TmpDir}'" 0 "Getting container image sources"
        rlRun "pushd $TmpDir"

        rlRun "git checkout $(get_branch_name)" 0 "Switch branch"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "appcont_basic__get_parent_image" 0 "Pull parent image"
        rlRun "appcont_basic__prepare_dockerfile_rebuild" 0 "Prepare the Dockerfile"
        rlRun "docker build -t testimage -f Dockerfile.tempcopy ." 0 "Build an image from scratch from the prepared Dockerfile"

        rlRun "IMAGE_NAME=testimage VERSION=${node_major} test/run" 0 "Run the container tests"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "appcont_basic__prepare_dockerfile_updated ${CONTAINER_NAME} 'nodejs npm'" 0 "Prepare the Dockerfile"
        rlRun "docker build -t testimage -f Dockerfile.tempcopy ." 0 "Build an image from the prepared Dockerfile with updating package"

        rlRun "IMAGE_NAME=testimage VERSION=${node_major} test/run" 0 "Run the container tests"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
```
