#!/bin/bash

function test_curl() {
    # tests egress from curl (default ns) to nginx (foo ns)
    kubectl exec deploy/curl -- curl -s -o /dev/null --connect-timeout 1 http://nginx.foo.svc.cluster.local 2> /dev/null
}

function expect_success() {
    if ! test_curl; then
        echo "❌ Blocked (but should have connected)"
    else
        echo "✅ Connected"
    fi
}

function expect_failure() {
    if test_curl; then
        echo "❌ Connected (but should have blocked)"
    else
        echo "✅ Blocked"
    fi
}

if [[ "$SETUP" == "true" ]]; then
    # Install minikube + calico
    curl -sS -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    curl -sS -L https://github.com/projectcalico/calico/releases/download/v3.24.5/calicoctl-linux-amd64 -o calicoctl
    sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64 
    sudo install calicoctl /usr/local/bin/calicoctl && rm calicoctl

    # Start minikube + calico
    minikube delete
    minikube start --cni=calico --wait=all

    kubectl rollout status deploy -n kube-system calico-kube-controllers --timeout 60s
    kubectl rollout status daemonset -n kube-system calico-node --timeout 60s
fi

if [[ "$SETUP" == "true" || "$DEPLOY" == "true" ]]; then
    # Apply k8s resources
    kubectl apply -f kubernetes/foo-ns.yaml -f kubernetes/foo-nginx-deploy.yaml -f kubernetes/foo-nginx-service.yaml -f kubernetes/curl.yaml
    kubectl rollout status deploy -n foo nginx --timeout 60s
    kubectl rollout status deploy -n default curl --timeout=60s
fi

echo
echo "*** No policy ***"
calicoctl delete --skip-not-exists -f calico/
expect_success

echo
echo "*** Deny all egress ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/deny-all-egress.yaml
expect_failure

echo
echo "*** Allow egress to selector: app == 'nginx' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-unspecified-namespace-nginx-pods.yaml
expect_success

echo
echo "*** Allow egress to selector: app == 'other' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-unspecified-namespace-other-pods.yaml
expect_failure

echo
echo "*** Allow egress to selector: app != 'other' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-unspecified-namespace-not-other-pods.yaml
expect_success

echo
echo "*** Allow egress to namespaceSelector: all(), selector: all() ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-all-namespaces-all-pods.yaml
expect_success

echo
echo "*** Allow egress to namespaceSelector: all(), selector: app == 'nginx' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-all-namespaces-nginx-pods.yaml
expect_success

echo
echo "*** Allow egress to namespaceSelector: all(), selector: app != 'nginx' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-all-namespaces-not-nginx-pods.yaml
expect_failure

echo
echo "*** Allow egress to namespaceSelector: all(), selector: app == 'other' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-all-namespaces-other-pods.yaml
expect_failure

echo
echo "*** Allow egress to namespaceSelector: all(), selector: app != 'other' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-all-namespaces-not-other-pods.yaml
expect_success

echo
echo "*** Allow egress to namespaceSelector: projectcalico.org/name == 'foo', selector: all() ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-foo-namespace-all-pods.yaml
expect_success

echo
echo "*** Allow egress to namespaceSelector: projectcalico.org/name == 'foo', selector: app == 'nginx' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-foo-namespace-nginx-pods.yaml
expect_success

echo
echo "*** Allow egress to namespaceSelector: projectcalico.org/name == 'foo', selector: app != 'nginx' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-foo-namespace-not-nginx-pods.yaml
expect_failure

echo
echo "*** Allow egress to namespaceSelector: projectcalico.org/name != 'bar', selector: all() ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-not-bar-namespace-all-pods.yaml
expect_success

echo
echo "*** Allow egress to namespaceSelector: projectcalico.org/name != 'bar', selector: app == 'nginx' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-not-bar-namespace-nginx-pods.yaml
expect_success

echo
echo "*** Allow egress to namespaceSelector: projectcalico.org/name != 'bar', selector: app != 'haproxy' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-not-bar-namespace-not-other-pods.yaml
expect_success

echo
echo "*** Allow egress to namespaceSelector: projectcalico.org/name != 'foo', selector: all() ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-not-foo-namespace-all-pods.yaml
expect_failure

echo
echo "*** Allow egress to namespaceSelector: projectcalico.org/name != 'foo', selector: app != 'nginx' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/allow-egress-to-not-foo-namespace-not-nginx-pods.yaml
expect_failure

echo
echo "*** GLOBAL:  Allow egress to namespaceSelector: all(), selector: app == 'nginx' ***"
calicoctl delete --skip-not-exists -f calico/
calicoctl apply -f calico/global-allow-egress-to-all-namespaces-nginx-pods.yaml
expect_success
