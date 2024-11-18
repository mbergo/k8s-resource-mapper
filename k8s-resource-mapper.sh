#!/bin/bash

# Set color codes for better visualization
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print horizontal line
print_line() {
    printf "%80s\n" | tr " " "-"
}

# Function to create ASCII arrow
create_arrow() {
    local length=$1
    local arrow=""
    for ((i=0; i<length; i++)); do
        arrow="${arrow}-"
    done
    echo "${arrow}>"
}

# Function to show ConfigMap usage
show_configmap_usage() {
    local namespace=$1
    echo -e "\n${CYAN}ConfigMap usage in namespace: $namespace${NC}"

    local configmaps=$(kubectl get configmaps -n "$namespace" -o name)
    for cm in $configmaps; do
        cm_name=${cm#configmap/}
        echo -e "\nConfigMap: $cm_name"

        # Find pods using this ConfigMap as volumes
        local volume_pods=$(kubectl get pods -n "$namespace" -o json | jq -r --arg name "$cm_name" '.items[] | select(.spec.volumes[]?.configMap.name == $name) | .metadata.name')

        # Find pods using this ConfigMap in envFrom
        local env_from_pods=$(kubectl get pods -n "$namespace" -o json | jq -r --arg name "$cm_name" '.items[] | select(.spec.containers[].envFrom[]?.configMapRef.name == $name) | .metadata.name')

        # Find pods using this ConfigMap in env valueFrom
        local env_value_pods=$(kubectl get pods -n "$namespace" -o json | jq -r --arg name "$cm_name" '.items[] | select(.spec.containers[].env[]?.valueFrom.configMapKeyRef.name == $name) | .metadata.name')

        # Combine and deduplicate results
        local all_pods=$(echo -e "${volume_pods}\n${env_from_pods}\n${env_value_pods}" | sort -u | grep -v '^$')

        if [ ! -z "$all_pods" ]; then
            echo "└── Used by pods:"
            echo "$all_pods" | while read pod; do
                if [ ! -z "$pod" ]; then
                    echo "    $(create_arrow 4) $pod"

                    # Show how the ConfigMap is used
                    if echo "$volume_pods" | grep -q "^${pod}$"; then
                        echo "        - Mounted as volume"
                    fi
                    if echo "$env_from_pods" | grep -q "^${pod}$"; then
                        echo "        - Used in envFrom"
                    fi
                    if echo "$env_value_pods" | grep -q "^${pod}$"; then
                        echo "        - Used in environment variables"
                    fi
                fi
            done
        fi
    done
}

# Function to get all resources in a namespace
get_resources() {
    local namespace=$1
    echo -e "${GREEN}Resources in namespace: $namespace${NC}"

    # Get deployments
    echo -e "\n${YELLOW}Deployments:${NC}"
    kubectl get deployments -n "$namespace" -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,AVAILABLE:.status.availableReplicas --no-headers

    # Get hpa
    echo -e "\n${YELLOW}Hpa:${NC}"
    kubectl get hpa -n "$namespace" -o custom-columns=NAME:.metadata.name,TARGETS:.spec.metrics[].resource.name,TARGETS:.spec.metrics[].resource.target.averageUtilization --no-headers
    
    # Get services
    echo -e "\n${YELLOW}Services:${NC}"
    kubectl get services -n "$namespace" -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.externalIPs --no-headers

    # Get Ingress
    echo -e "\n${YELLOW}Ingress:${NC}"
    kubectl get ingress -n "$namespace" -o custom-columns=NAME:.metadata.name,HOSTS:.spec.rules[*].host --no-headers
    
    # Get pods
    echo -e "\n${YELLOW}Pods:${NC}"
    kubectl get pods -n "$namespace" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName --no-headers

    # Get configmaps
    echo -e "\n${YELLOW}ConfigMaps:${NC}"
    kubectl get configmaps -n "$namespace" -o custom-columns=NAME:.metadata.name --no-headers
}

# Function to map service connections
map_service_connections() {
    local namespace=$1
    echo -e "\n${BLUE}Service connections in namespace: $namespace${NC}"

    # Get all services
    local services=$(kubectl get services -n "$namespace" -o name)
    for service in $services; do
        service_name=${service#service/}
        echo -e "\n${YELLOW}Service: $service_name${NC}"

        # Get service selectors
        local selectors=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)
        if [ ! -z "$selectors" ]; then
            echo "├── Selectors: $selectors"

            # Get pods matching selectors
            local selector_query=$(echo $selectors | jq -r 'to_entries | map(.key + "=" + .value) | join(",")')
            local pods=$(kubectl get pods -n "$namespace" -l "$selector_query" -o name 2>/dev/null)
            if [ ! -z "$pods" ]; then
                echo "└── Connected Pods:"
                for pod in $pods; do
                    pod_name=${pod#pod/}
                    echo "    $(create_arrow 4) $pod_name"
                done
            fi
        fi
    done
}

# Function to show resource relationships
show_resource_relationships() {
    local namespace=$1
    echo -e "\n${BLUE}Resource relationships in namespace: $namespace${NC}\n"

    echo "External Traffic"
    echo "│"

    # Get ingresses
    local ingresses=$(kubectl get ingress -n "$namespace" -o name 2>/dev/null)
    if [ ! -z "$ingresses" ]; then
        echo "▼"
        echo "[Ingress Layer]"
        for ingress in $ingresses; do
            ingress_name=${ingress#ingress.networking.k8s.io/}
            echo "├── $ingress_name"

            # Get backend services for this ingress
            local backends=$(kubectl get ingress "$ingress_name" -n "$namespace" -o json | \
                           jq -r '.spec.rules[].http.paths[].backend.service.name' 2>/dev/null)
            for backend in $backends; do
                if [ ! -z "$backend" ]; then
                    echo "│   $(create_arrow 4) Service: $backend"
                fi
            done
        done
        echo "│"
    fi

    echo "▼"
    echo "[Service Layer]"
    local services=$(kubectl get services -n "$namespace" -o name)
    for service in $services; do
        service_name=${service#service/}
        echo "├── $service_name"

        # Get pods for this service
        local selector=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)
        if [ ! -z "$selector" ]; then
            local selector_query=$(echo $selector | jq -r 'to_entries | map(.key + "=" + .value) | join(",")')
            local pods=$(kubectl get pods -n "$namespace" -l "$selector_query" -o name 2>/dev/null)
            for pod in $pods; do
                pod_name=${pod#pod/}
                echo "│   $(create_arrow 4) Pod: $pod_name"
            done
        fi
    done
}

# Main execution
echo -e "${GREEN}Kubernetes Resource Mapper${NC}"
print_line

# Check for required tools
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed. Please install jq first.${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is required but not installed.${NC}"
    exit 1
fi

# Get all namespaces
namespaces=$(kubectl get namespaces -o name)

# Process each namespace
for ns in $namespaces; do
    namespace=${ns#namespace/}
    print_line
    echo -e "${RED}Analyzing namespace: $namespace${NC}"
    print_line

    # Get all resources
    get_resources "$namespace"

    # Map service connections
    map_service_connections "$namespace"

    # Show resource relationships
    show_resource_relationships "$namespace"

    # Show ConfigMap usage
    show_configmap_usage "$namespace"

    print_line
done

echo -e "${GREEN}Resource mapping complete!${NC}"
