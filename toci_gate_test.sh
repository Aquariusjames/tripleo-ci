#!/usr/bin/env bash

set -eu

# cd to toci directory so relative paths work (below and in toci_devtest.sh)
cd $(dirname $0)

# Once rh1 migrates to the 172.16.0.0/22 network we can remove the
# 192.168.1.0/24 entries
export http_proxy=http://192.168.1.100:3128/
export GEARDSERVER=192.168.1.1
export PYPIMIRROR=192.168.1.101
# TODO : make this the default once rh1 has switched over
if [[ $NODE_NAME =~ .*tripleo-test-cloud-hp1* ]] ; then
    export http_proxy=http://172.16.3.253:3128/
    export GEARDSERVER=172.16.3.254
    export PYPIMIRROR=172.16.3.252
fi

# tripleo ci default control variables
export DIB_COMMON_ELEMENTS="common-venv stackuser"
export TRIPLEO_TEST=${TRIPLEO_TEST:-"overcloud"}
export USE_CIRROS=${USE_CIRROS:-"1"}
export USE_MERGEPY=${USE_MERGEPY:-1}
export OVERCLOUD_CONTROLSCALE=${OVERCLOUD_CONTROLSCALE:-"1"}
export TRIPLEO_DEBUG=${TRIPLEO_DEBUG:-""}
export OVERCLOUD_STACK_TIMEOUT="35"

# Switch defaults based on the job name
for JOB_TYPE_PART in $(sed 's/-/ /g' <<< "${TOCI_JOBTYPE:-}") ; do
    case $JOB_TYPE_PART in
        undercloud)
            export TRIPLEO_TEST=undercloud
            ;;
        ha)
            export OVERCLOUD_CONTROLSCALE=3
            export TRIPLEO_DEBUG=1
            ;;
        vlan)
            export TRIPLEO_TEST=vlan
            ;;
        f20)
            export DIB_RELEASE=20
            export USE_MERGEPY=0
            ;;
        f20puppet)
            export DIB_RELEASE=20
            export TRIPLEO_ROOT=/opt/stack/new/ #FIXME: also defined in toci_devtest
            # FIXME: remove this once nodepool/scripts/prepare_tripleo.sh is
            # updated
            if [ ! -d $TRIPLEO_ROOT/tripleo-puppet-elements ]; then
              git clone git://git.openstack.org/openstack/tripleo-puppet-elements $TRIPLEO_ROOT/tripleo-puppet-elements
            fi
            export ELEMENTS_PATH=$TRIPLEO_ROOT/tripleo-puppet-elements/elements:$TRIPLEO_ROOT/heat-templates/hot/software-config/elements:$TRIPLEO_ROOT/tripleo-image-elements/elements
            export USE_MERGEPY=0
            export DELOREAN_REPO_URL="http://104.130.230.24/f21/0d/97/0d979b220da3c5c809a20d6d9e7afa6b2c246712_772aab0d"
            export RDO_RELEASE=juno
            export DIB_COMMON_ELEMENTS='stackuser os-net-config delorean-repo rdo-release'
            export USE_MARIADB=0
            export SEED_DIB_EXTRA_ARGS='rabbitmq-server mariadb-rpm'
            export DIB_DEFAULT_INSTALLTYPE=package
            BASE_PUPPET_ELEMENTS='hosts baremetal dhcp-all-interfaces os-collect-config heat-config-puppet puppet-modules hiera'
            export OVERCLOUD_CONTROL_DIB_ELEMENTS=$BASE_PUPPET_ELEMENTS
            export OVERCLOUD_CONTROL_DIB_EXTRA_ARGS='overcloud-controller'
            export OVERCLOUD_COMPUTE_DIB_ELEMENTS=$BASE_PUPPET_ELEMENTS
            export OVERCLOUD_COMPUTE_DIB_EXTRA_ARGS='overcloud-compute'
            export RESOURCE_REGISTRY_PATH="$TRIPLEO_ROOT/tripleo-heat-templates/overcloud-resource-registry-puppet.yaml"
            export DIB_INSTALLTYPE_puppet_modules=source
            ;;
    esac
done

# print the final values of control variables to console
env | grep -E "(DIB_COMMON_ELEMENTS|OVERCLOUD_CONTROLSCALE|TRIPLEO_TEST|USE_CIRROS|TRIPLEO_DEBUG)="

# This allows communication between tripleo jumphost and the CI host running
# the devtest_seed configuration
sudo iptables -I INPUT -p tcp --dport 27410 -i eth1 -j ACCEPT

# Download a custom Fedora image here. We want to use an explit URL
# so that Squid caches this. I'm doing it here to test things for now...
# Once it works this code actually belongs in prepare_node_tripleo.sh
# in openstack-infra/config so the Slave node will essentially pre-cache
# it for us.
DISTRIB_CODENAME=$(lsb_release -si)
if [ $DISTRIB_CODENAME == 'Fedora' ]; then
    # TODO : This should read the ARCH of the test being targeted
    FEDORA_IMAGE=$(wget -q http://dl.fedoraproject.org/pub/fedora/linux/updates/$DIB_RELEASE/Images/x86_64/ -O - | grep -o -E 'href="([^"#]+qcow2)"' | cut -d'"' -f2)
    if [ -n "$FEDORA_IMAGE" ]; then
        wget --progress=dot:mega http://dl.fedoraproject.org/pub/fedora/linux/updates/$DIB_RELEASE/Images/x86_64/$FEDORA_IMAGE
    else
        # No Fedora update images are available. Use the release...
        FEDORA_IMAGE=fedora-$DIB_RELEASE.x86_64.qcow2
        wget --progress=dot:mega http://cloud.fedoraproject.org/$FEDORA_IMAGE
    fi
    export DIB_LOCAL_IMAGE=$PWD/$FEDORA_IMAGE
fi

# XXX: 127.0.0.1 naturally won't work for real CI but for manual
# testing running a server on the same machine is convenient.
GEARDSERVER=${GEARDSERVER:-127.0.0.1}

TIMEOUT_SECS=$((DEVSTACK_GATE_TIMEOUT*60))
set -m
./testenv-client -b $GEARDSERVER:4730 -t $TIMEOUT_SECS -- ./toci_devtest.sh
