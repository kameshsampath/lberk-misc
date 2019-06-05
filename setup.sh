#!/usr/bin/env bash

set -e

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

serving_version="v0.6.0"
eventing_version="v0.6.0"
eventing_sources_version="v0.6.0"
istio_version="1.0.7"
#kube_version="v1.12.1"
kube_version="v1.13.4"

MEMORY="$(minikube config view | awk '/memory/ { print $3 }')"
CPUS="$(minikube config view | awk '/cpus/ { print $3 }')"
DISKSIZE="$(minikube config view | awk '/disk-size/ { print $3 }')"
DRIVER="$(minikube config view | awk '/vm-driver/ { print $3 }')"

function header_text {
  echo "$header$*$reset"
}

header_text             "Starting Knative on minikube!"
header_text "Using Kubernetes Version:               ${kube_version}"
header_text "Using Knative Serving Version:          ${serving_version}"
header_text "Using Knative Eventing Version:         ${eventing_version}"
header_text "Using Knative Eventing Sources Version: ${eventing_sources_version}"
header_text "Using Istio Version:                    ${istio_version}"

minikube start --memory="${MEMORY:-12288}" --cpus="${CPUS:-4}" --kubernetes-version="${kube_version}" --vm-driver="${DRIVER:-kvm2}" --disk-size="${DISKSIZE:-30g}" --extra-config=apiserver.enable-admission-plugins="LimitRanger,NamespaceExists,NamespaceLifecycle,ResourceQuota,ServiceAccount,DefaultStorageClass,MutatingAdmissionWebhook"
header_text "Waiting for core k8s services to initialize"
sleep 5; while echo && kubectl get pods -n kube-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Setting up istio"
kubectl apply --filename "https://raw.githubusercontent.com/knative/serving/${serving_version}/third_party/istio-${istio_version}/istio-crds.yaml" &&
    curl -L "https://raw.githubusercontent.com/knative/serving/${serving_version}/third_party/istio-${istio_version}/istio.yaml" \
        | sed 's/LoadBalancer/NodePort/' \
        | kubectl apply --filename -

# Label the default namespace with istio-injection=enabled.
header_text "Labeling default namespace w/ istio-injection=enabled"
kubectl label namespace default istio-injection=enabled
header_text "Waiting for istio to become ready"
sleep 5; while echo && kubectl get pods -n istio-system | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done

header_text "Setting up Knative Serving"
curl -L "https://github.com/knative/serving/releases/download/${serving_version}/serving.yaml" \
  | sed 's/LoadBalancer/NodePort/' \
  | kubectl apply --filename -

header_text "Waiting for Knative Serving to become ready"
sleep 5; while echo && kubectl get pods -n knative-serving | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done


header_text "Setting up Knative Eventing"
#kubectl apply --filename https://github.com/knative/eventing/releases/download/${eventing_version}/release.yaml
kubectl apply --filename https://storage.googleapis.com/knative-nightly/eventing/latest/release.yaml

header_text "Waiting for Knative Eventing to become ready"
sleep 5; while echo && kubectl get pods -n knative-eventing | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done
