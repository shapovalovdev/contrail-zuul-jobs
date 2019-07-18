#!/bin/bash
set -ex

# stop ufw service
sudo service ufw stop
sudo systemctl disable ufw
sudo iptables -F
sudo sysctl -w vm.max_map_count=1048575

cd ${OSH_PATH}
./tools/deployment/developer/common/001-install-packages-opencontrail.sh

set -x
cd ${OSH_INFRA_PATH}
make dev-deploy setup-host multinode
make dev-deploy k8s multinode

nslookup kubernetes.default.svc.cluster.local || /bin/true
kubectl get nodes -o wide
kubectl get nodes -o custom-columns=C1:.status.addresses[0].address,C2:.status.addresses[1].address
kubectl get nodes -o yaml

for ip in `kubectl get nodes -o custom-columns=C1:.status.addresses[0].address | grep -v "C1"` ; do
  name=`kubectl get nodes -o custom-columns=C1:.status.addresses[0].address,C2:.status.addresses[1].address | grep $ip | awk '{print $2}'`
  if echo $CONTROLLER_NODES | grep -q $ip ; then
    echo "INFO: label node $name / $ip as controller node"
    kubectl label node $name --overwrite openstack-compute-node=disable
    kubectl label node $name opencontrail.org/controller=enabled
  else
    echo "INFO: label node $name / $ip as compute node"
    kubectl label node $name --overwrite openstack-control-plane=disable
    if [[ "$AGENT_MODE" == "dpdk" ]]; then
      kubectl label node $name opencontrail.org/vrouter-dpdk=enabled
    else
      kubectl label node $name opencontrail.org/vrouter-kernel=enabled
    fi
  fi
done

cd ${OSH_PATH}

export OSH_EXTRA_HELM_ARGS_MARIADB="--set pod.replicas.server=1"
export OSH_EXTRA_HELM_ARGS_KEYSTONE="--set pod.replicas.api=1"
export OSH_EXTRA_HELM_ARGS_GLANCE="--set pod.replicas.api=1 --set pod.replicas.registry=1"
export OSH_EXTRA_HELM_ARGS_CINDER="--set pod.replicas.api=1"

export OSH_EXTRA_HELM_ARGS_NEUTRON="--values ./tools/overrides/backends/opencontrail/neutron-rbac.yaml --set images.tags.opencontrail_neutron_init=${CONTRAIL_REGISTRY}/contrail-openstack-neutron-init:${CONTAINER_TAG}"
echo "INFO: extra neutron args: $OSH_EXTRA_HELM_ARGS_NEUTRON"
extra_nova_args='--set pod.replicas.placement=1 --set pod.replicas.osapi=1 --set pod.replicas.conductor=1 --set pod.replicas.consoleauth=1'
if [[ "$OPENSTACK_VERSION" == 'ocata' ]]; then
  extra_nova_args+=" --set compute_patch=true"
fi
export OSH_EXTRA_HELM_ARGS_NOVA="$extra_nova_args --set images.tags.opencontrail_compute_init=${CONTRAIL_REGISTRY}/contrail-openstack-compute-init:${CONTAINER_TAG}"
echo "INFO: extra nova args: $OSH_EXTRA_HELM_ARGS_NOVA"
extra_heat_args="--set pod.replicas.api=1 --set pod.replicas.cfn=1 --set pod.replicas.cloudwatch=1 --set pod.replicas.engine=1"
export OSH_EXTRA_HELM_ARGS_HEAT="$extra_heat_args --set images.tags.opencontrail_heat_init=${CONTRAIL_REGISTRY}/contrail-openstack-heat-init:${CONTAINER_TAG}"
echo "INFO: extra heat args: $OSH_EXTRA_HELM_ARGS_HEAT"

./tools/deployment/multinode/010-setup-client.sh
./tools/deployment/multinode/021-ingress-opencontrail.sh
./tools/deployment/multinode/030-ceph.sh
./tools/deployment/multinode/040-ceph-ns-activate.sh
./tools/deployment/multinode/050-mariadb.sh
./tools/deployment/multinode/060-rabbitmq.sh
./tools/deployment/multinode/070-memcached.sh
./tools/deployment/multinode/080-keystone.sh
./tools/deployment/multinode/090-ceph-radosgateway.sh
./tools/deployment/multinode/100-glance.sh
./tools/deployment/multinode/110-cinder.sh
./tools/deployment/multinode/131-libvirt-opencontrail.sh

cd $CHD_PATH
make

tee /tmp/contrail.yaml << EOF
global:
  images:
    tags:
      cassandra: "${CONTRAIL_REGISTRY}/contrail-external-cassandra:${CONTAINER_TAG}"
      kafka: "${CONTRAIL_REGISTRY}/contrail-external-kafka:${CONTAINER_TAG}"
      zookeeper: "${CONTRAIL_REGISTRY}/contrail-external-zookeeper:${CONTAINER_TAG}"
      rabbitmq: "${CONTRAIL_REGISTRY}/contrail-external-rabbitmq:${CONTAINER_TAG}"
      redis: "${CONTRAIL_REGISTRY}/contrail-external-redis:${CONTAINER_TAG}"
      config_api: "${CONTRAIL_REGISTRY}/contrail-controller-config-api:${CONTAINER_TAG}"
      config_devicemgr: "${CONTRAIL_REGISTRY}/contrail-controller-config-devicemgr:${CONTAINER_TAG}"
      config_schema_transformer: "${CONTRAIL_REGISTRY}/contrail-controller-config-schema:${CONTAINER_TAG}"
      config_svcmonitor: "${CONTRAIL_REGISTRY}/contrail-controller-config-svcmonitor:${CONTAINER_TAG}"
      contrail_control: "${CONTRAIL_REGISTRY}/contrail-controller-control-control:${CONTAINER_TAG}"
      control_dns: "${CONTRAIL_REGISTRY}/contrail-controller-control-dns:${CONTAINER_TAG}"
      control_named: "${CONTRAIL_REGISTRY}/contrail-controller-control-named:${CONTAINER_TAG}"
      nodemgr: "${CONTRAIL_REGISTRY}/contrail-nodemgr:${CONTAINER_TAG}"
      contrail_status: "${CONTRAIL_REGISTRY}/contrail-status:${CONTAINER_TAG}"
      node_init: "${CONTRAIL_REGISTRY}/contrail-node-init:${CONTAINER_TAG}"
      webui_middleware: "${CONTRAIL_REGISTRY}/contrail-controller-webui-job:${CONTAINER_TAG}"
      webui: "${CONTRAIL_REGISTRY}/contrail-controller-webui-web:${CONTAINER_TAG}"
      analytics_alarm_gen: "${CONTRAIL_REGISTRY}/contrail-analytics-alarm-gen:${CONTAINER_TAG}"
      analytics_api: "${CONTRAIL_REGISTRY}/contrail-analytics-api:${CONTAINER_TAG}"
      analytics_query_engine: "${CONTRAIL_REGISTRY}/contrail-analytics-query-engine:${CONTAINER_TAG}"
      analytics_snmp_collector: "${CONTRAIL_REGISTRY}/contrail-analytics-snmp-collector:${CONTAINER_TAG}"
      contrail_collector: "${CONTRAIL_REGISTRY}/contrail-analytics-collector:${CONTAINER_TAG}"
      contrail_topology: "${CONTRAIL_REGISTRY}/contrail-analytics-snmp-topology:${CONTAINER_TAG}"
      build_driver_init: "${CONTRAIL_REGISTRY}/contrail-vrouter-kernel-build-init:${CONTAINER_TAG}"
      vrouter_agent: "${CONTRAIL_REGISTRY}/contrail-vrouter-agent:${CONTAINER_TAG}"
      vrouter_init_kernel: "${CONTRAIL_REGISTRY}/contrail-vrouter-kernel-init:${CONTAINER_TAG}"
      vrouter_dpdk: "${CONTRAIL_REGISTRY}/contrail-vrouter-agent-dpdk:${CONTAINER_TAG}"
      vrouter_init_dpdk: "${CONTRAIL_REGISTRY}/contrail-vrouter-kernel-init-dpdk:${CONTAINER_TAG}"
      vrouter_plugin_mellanox_init: "${CONTRAIL_REGISTRY}/contrail-vrouter-plugin-mellanox-init-ubuntu:${CONTAINER_TAG}"
  contrail_env:
    CONTROLLER_NODES: $CONTROLLER_NODES
    CONTROL_NODES: $CONTROL_NODES
    LOG_LEVEL: SYS_DEBUG
    CLOUD_ORCHESTRATOR: openstack
    AAA_MODE: rbac
    CONFIG_DATABASE_NODEMGR__DEFAULTS__minimum_diskGB: "10"
    DATABASE_NODEMGR__DEFAULTS__minimum_diskGB: "10"
    JVM_EXTRA_OPTS: "-Xms1g -Xmx2g"
    BGP_PORT: "1179"
    VROUTER_ENCRYPTION: FALSE
    ANALYTICS_ALARM_ENABLE: TRUE
    ANALYTICS_SNMP_ENABLE: TRUE
    ANALYTICSDB_ENABLE: TRUE
  contrail_env_vrouter_kernel:
    AGENT_MODE: kernel
EOF

helm install --name contrail-thirdparty ${CHD_PATH}/contrail-thirdparty --namespace=contrail --values=/tmp/contrail.yaml
helm install --name contrail-analytics ${CHD_PATH}/contrail-analytics --namespace=contrail --values=/tmp/contrail.yaml
helm install --name contrail-controller ${CHD_PATH}/contrail-controller --namespace=contrail --values=/tmp/contrail.yaml
helm install --name contrail-vrouter ${CHD_PATH}/contrail-vrouter --namespace=contrail --values=/tmp/contrail.yaml
${OSH_PATH}/tools/deployment/common/wait-for-pods.sh contrail 1200

# let's wait for services
sleep 60
sudo contrail-status

cd ${OSH_PATH}
./tools/deployment/multinode/141-compute-kit-opencontrail.sh || /bin/true
# workaround steps. remove later.
make build-helm-toolkit
make build-heat
./tools/deployment/developer/nfs/091-heat-opencontrail.sh

# Verify creation of VM
./tools/deployment/developer/nfs/901-use-it-opencontrail.sh
