#!/usr/bin/env bash

set -eu
set -o pipefail

# Turn colors in this script off by setting the NO_COLOR variable in your
# environment to any value:
#
# $ NO_COLOR=1 test.sh
NO_COLOR=${NO_COLOR:-""}
if [ -z "$NO_COLOR" ]; then
  header=$'\e[1;33m'
  reset=$'\e[0m'
else
  header=''
  reset=''
fi

strimzi_version=`curl https://github.com/strimzi/strimzi-kafka-operator/releases/latest |  awk -F 'tag/' '{print $2}' | awk -F '"' '{print $1}' 2>/dev/null`
serving_version="v0.11.0"
eventing_version="v0.11.0"
eventing_contrib_version="v0.11.1"
camel_version="v0.11.2"
istio_version="1.3.5"
kube_version="v1.14.7"

MEMORY="${MEMORY:-$(minikube config view | awk '/memory/ { print $3 }')}"
CPUS="${CPUS:-$(minikube config view | awk '/cpus/ { print $3 }')}"
DISKSIZE="${DISKSIZE:-$(minikube config view | awk '/disk-size/ { print $3 }')}"
DRIVER="${DRIVER:-$(minikube config view | awk '/vm-driver/ { print $3 }')}"

EXTRA_CONFIG="apiserver.enable-admission-plugins=\
LimitRanger,\
NamespaceExists,\
NamespaceLifecycle,\
ResourceQuota,\
ServiceAccount,\
DefaultStorageClass,\
MutatingAdmissionWebhook"

function header_text {
  echo "$header$*$reset"
}

header_text             "Starting Knative on minikube!"
header_text "Using Kubernetes Version:               ${kube_version}"
header_text "Using Strimzi Version:                  ${strimzi_version}"
header_text "Using Knative Serving Version:          ${serving_version}"
header_text "Using Knative Eventing Version:         ${eventing_version}"
header_text "Using Knative Eventing Contrib Version: ${eventing_contrib_version}"
header_text "Using CamelSource Verison:              ${camel_version}"
header_text "Using Istio Version:                    ${istio_version}"

minikube profile "${MINIKUBE_PROFILE:-knative}"
minikube start -p "${MINIKUBE_PROFILE:-knative}" \
  --container-runtime="${CONTAINER_RUNTIME:-docker}" \
  --memory="${MEMORY:-8192}" \
  --cpus="${CPUS:-6}" \
  --kubernetes-version="${kube_version}" \
  --vm-driver="${DRIVER:-virtualbox}" \
  --disk-size="${DISKSIZE:-50g}" \
  --extra-config="$EXTRA_CONFIG" \
  --insecure-registry='10.0.0.0/24'

minikube addons enable registry

header_text "Waiting for core k8s services to initialize"
sleep 5; while echo && kubectl get pods -n kube-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Strimzi install"
cat <<-EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: kafka
spec: {}
EOF
curl -L "https://github.com/strimzi/strimzi-kafka-operator/releases/download/${strimzi_version}/strimzi-cluster-operator-${strimzi_version}.yaml" \
  | sed 's/namespace: .*/namespace: kafka/' \
  | kubectl -n kafka apply -f -

header_text "Applying Strimzi Cluster file"
kubectl -n kafka apply -f "https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/${strimzi_version}/examples/kafka/kafka-persistent-single.yaml"
header_text "Waiting for Strimzi to become ready"
sleep 5; while echo && kubectl get pods -n kafka | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Setting up Istio"

pushd /tmp > /dev/null

export ISTIO_VERSION="${istio_version}"

curl -L https://git.io/getLatestIstio | sh -

pushd istio-${ISTIO_VERSION} > /dev/null

header_text "Creating Istio Custom Resource Definitions(CRD)"

for i in install/kubernetes/helm/istio-init/files/crd*yaml;
do
  kubectl apply -f $i;
done

header_text "Creating istio-system namespace"

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
  labels:
    istio-injection: disabled
spec: {}
EOF

header_text "Deploying Istio components"

helm template --namespace=istio-system \
  --set prometheus.enabled=false \
  --set mixer.enabled=false \
  --set mixer.policy.enabled=false \
  --set mixer.telemetry.enabled=false \
  `# Pilot doesn't need a sidecar.` \
  --set pilot.sidecar=false \
  --set pilot.resources.requests.memory=128Mi \
  `# Disable galley (and things requiring galley).` \
  --set galley.enabled=false \
  --set global.useMCP=false \
  `# Disable security / policy.` \
  --set security.enabled=false \
  --set global.disablePolicyChecks=true \
  `# Disable sidecar injection.` \
  --set sidecarInjectorWebhook.enabled=false \
  --set global.proxy.autoInject=disabled \
  --set global.omitSidecarInjectorConfigMap=true \
  --set gateways.istio-ingressgateway.autoscaleMin=1 \
  --set gateways.istio-ingressgateway.autoscaleMax=2 \
  `# Set pilot trace sampling to 100%` \
  --set pilot.traceSampling=100 \
  install/kubernetes/helm/istio \
  > ./istio-lean.yaml

helm template --namespace=istio-system \
  --set gateways.custom-gateway.autoscaleMin=1 \
  --set gateways.custom-gateway.autoscaleMax=2 \
  --set gateways.custom-gateway.cpu.targetAverageUtilization=60 \
  --set gateways.custom-gateway.labels.app='cluster-local-gateway' \
  --set gateways.custom-gateway.labels.istio='cluster-local-gateway' \
  --set gateways.custom-gateway.type='ClusterIP' \
  --set gateways.istio-ingressgateway.enabled=false \
  --set gateways.istio-egressgateway.enabled=false \
  --set gateways.istio-ilbgateway.enabled=false \
  install/kubernetes/helm/istio \
  -f install/kubernetes/helm/istio/example-values/values-istio-gateways.yaml \
  | sed -e "s/custom-gateway/cluster-local-gateway/g" -e "s/customgateway/clusterlocalgateway/g" \
  > ./istio-local-gateway.yaml

kubectl apply -f istio-lean.yaml &&\
kubectl apply -f istio-local-gateway.yaml

header_text "Waiting for Istio to become ready"
sleep 5; while echo && kubectl get pods -n istio-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Istio successfully installed"

popd > /dev/null && popd > /dev/null

header_text "Setting up Knative Serving"

 n=0
  until [ $n -ge 2 ]
  do
    kubectl apply --filename https://github.com/knative/serving/releases/download/${serving_version}/serving.yaml && break
    n=$[$n+1]
    sleep 5
  done

header_text "Waiting for Knative Serving to become ready"
sleep 5; while echo && kubectl get pods -n knative-serving | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done


header_text "Setting up Knative Eventing"
kubectl apply --filename https://github.com/knative/eventing/releases/download/${eventing_version}/release.yaml

header_text "Waiting for Knative Eventing to become ready"
sleep 5; while echo && kubectl get pods -n knative-eventing | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Setting up Knative Eventing Sources"
kubectl apply \
  --filename https://github.com/knative/eventing-contrib/releases/download/${eventing_contrib_version}/kafka-source.yaml \
  --filename https://github.com/knative/eventing-contrib/releases/download/${camel_version}/camel.yaml

header_text "Waiting for Knative Eventing Sources to become ready"
sleep 5; while echo && kubectl get pods -n knative-sources | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Setting up Knative Kafka Channel"
curl -L "https://github.com/knative/eventing-contrib/releases/download/${eventing_contrib_version}/kafka-channel.yaml" \
 | sed 's/REPLACE_WITH_CLUSTER_URL/my-cluster-kafka-bootstrap.kafka:9092/' \
 | kubectl apply --filename -

header_text "Waiting for Knative Eventing Kafka Channel to become ready"
sleep 5; while echo && kubectl get pods -n knative-eventing | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Creating project knativetutorial namespace"
cat <<-EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    istio-injection: enabled
    knative-eventing-injection: enabled
  name: knativetutorial
spec: {}
EOF