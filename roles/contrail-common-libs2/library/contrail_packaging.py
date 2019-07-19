import os
import re

from ansible.module_utils.basic import AnsibleModule
from datetime import datetime

ANSIBLE_METADATA = {
    'metadata_version': '1.1',
    'status': ['preview'],
    'supported_by': 'community'
}

result = dict(
    changed=False,
    original_message='',
    message='',
)

MASTER_RELEASE = '5.2.0'
version_branch_regex = re.compile(r'^(master)|(R\d+\.\d+(\.\d+)?(\.x)?)$')


class ReleaseType(object):
    CONTINUOUS_INTEGRATION = 'continuous-integration'
    NIGHTLY = 'nightly'


def main():
    module = AnsibleModule(
        argument_spec=dict(
            zuul=dict(type='dict', required=True),
            release_type=dict(type='str', required=False, default=ReleaseType.CONTINUOUS_INTEGRATION),
            build_number=dict(type='str', required=False, default=''),
            openstack_version=dict(type='str', required=False, default='')
        )
    )

    zuul = module.params['zuul']
    release_type = module.params['release_type']
    build_number = module.params['build_number']
    openstack_version = module.params['openstack_version']

    branch = zuul['branch']
    if not version_branch_regex.match(branch):
        branch = 'master'
    date = datetime.now().strftime("%Y%m%d%H%M%S")

    version = dict()
    if branch == 'master':
        version['upstream'] = MASTER_RELEASE
        version['public'] = 'master'
        version['branch'] = 'master'
        docker_version = 'master'
    else:
        version['upstream'] = branch[1:]
        version['public'] = branch[1:]
        version['branch'] = branch
        docker_version = version['upstream']

    if release_type == ReleaseType.CONTINUOUS_INTEGRATION:
        # Versioning in CI consists of change id, pachset and date
        change = zuul['change']
        patchset = zuul['patchset']
        version['distrib'] = "ci{change}.{patchset}".format(
            change=change, patchset=patchset, date=date
        )
        if zuul['pipeline'] not in ['gate', 'experimental-sanity']:
            docker_version = "{change}-{patchset}".format(change=change, patchset=patchset)
        else:
            docker_version = "{}-latest".format(version['public'])
    elif release_type == ReleaseType.NIGHTLY:
        version['distrib'] = "{}".format(build_number)
        docker_version = '{}-{}'.format(docker_version, build_number)
    else:
        module.fail_json(
            msg="Unknown release_type: %s" % (release_type,), **result
        )

    packaging = {
        'name': 'contrail',
        'version': version,
        'target_dir': "contrail-%s" % (version['upstream'],),
        'repo_name': docker_version,
        'docker_version': docker_version,
    }

    module.exit_json(ansible_facts={'packaging': packaging}, **result)


if __name__ == "__main__":
    main()
