#!/bin/bash

# Set color codes for better visualization
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

# Function to get all namespaces
get_namespaces() {
    echo -e "${BLUE}Fetching namespaces...${NC}"
    kubectl get namespaces -o custom-columns=NAME:.metadata.name --no-headers
}

# Function to get all resources in a namespace
get_resources() {
    local namespace=$1
    echo -e "${GREEN}Resources in namespace: $namespace${NC}"

    # Get deployments
    echo -e "\n${YELLOW}Deployments:${NC}"
    kubectl get deployments -n "$namespace" -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,AVAILABLE:.status.availableReplicas --no-headers

    # Get services
    echo -e "\n${YELLOW}Services:${NC}"
    kubectl get services -n "$namespace" -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.spec.externalIPs --no-headers

    # Get pods
    echo -e "\n${YELLOW}Pods:${NC}"
    kubectl get pods -n "$namespace" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName --no-headers

    # Get configmaps
    echo -e "\n${YELLOW}ConfigMaps:${NC}"
    kubectl get configmaps -n "$namespace" -o custom-columns=NAME:.metadata.name --no-headers

    # Get secrets
    echo -e "\n${YELLOW}Secrets:${NC}"
    kubectl get secrets -n "$namespace" -o custom-columns=NAME:.metadata.name,TYPE:.type --no-headers

    # Get ingresses
    echo -e "\n${YELLOW}Ingresses:${NC}"
    kubectl get ingress -n "$namespace" -o custom-columns=NAME:.metadata.name,HOSTS:.spec.rules[*].host --no-headers 2>/dev/null
}

# Function to map service connections
map_service_connections() {
    local namespace=$1
    echo -e "\n${BLUE}Mapping service connections in namespace: $namespace${NC}"

    # Get all services
    local services=$(kubectl get services -n "$namespace" -o custom-columns=NAME:.metadata.name --no-headers)

    for service in $services; do
        echo -e "\n${YELLOW}Service: $service${NC}"

        # Get selector labels
        local selector=$(kubectl get service "$service" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)
        if [ ! -z "$selector" ]; then
            echo "├── Selectors: $selector"

            # Find pods matching selector
            local pods=$(kubectl get pods -n "$namespace" -l "$(echo $selector | tr -d '{}"' | sed 's/:/=/g')" -o custom-columns=NAME:.metadata.name --no-headers)
            if [ ! -z "$pods" ]; then
                echo "└── Connected Pods:"
                while IFS= read -r pod; do
                    if [ ! -z "$pod" ]; then
                        echo "    $(create_arrow 4) $pod"
                    fi
                done <<< "$pods"
            fi
        fi
    done
}

# Function to create ASCII visualization
create_visualization() {
    local namespace=$1
    echo -e "\n${BLUE}Creating ASCII visualization for namespace: $namespace${NC}\n"

    # Get ingresses
    local ingresses=$(kubectl get ingress -n "$namespace" -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

    # Get services
    local services=$(kubectl get services -n "$namespace" -o custom-columns=NAME:.metadata.name --no-headers)

    # Print visualization
    echo "External Traffic"
    echo "      │"

    if [ ! -z "$ingresses" ]; then
        echo "      ▼"
        echo "  [Ingress]"
        while IFS= read -r ingress; do
            if [ ! -z "$ingress" ]; then
                echo "   │"
                echo "   └──> $ingress"
            fi
        done <<< "$ingresses"
        echo "      │"
    fi

    echo "      ▼"
    echo "  [Services]"
    while IFS= read -r service; do
        if [ ! -z "$service" ]; then
            echo "   │"
            echo "   └──> $service"

            # Get pods connected to service
            local selector=$(kubectl get service "$service" -n "$namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)
            if [ ! -z "$selector" ]; then
                local pods=$(kubectl get pods -n "$namespace" -l "$(echo $selector | tr -d '{}"' | sed 's/:/=/g')" -o custom-columns=NAME:.metadata.name --no-headers)
                while IFS= read -r pod; do
                    if [ ! -z "$pod" ]; then
                        echo "        │"
                        echo "        └──> [Pod] $pod"
                    fi
                done <<< "$pods"
            fi
        fi
    done <<< "$services"
}

# Function to show volume relationships
show_volume_relationships() {
    local namespace=$1
    echo -e "\n${BLUE}Volume relationships in namespace: $namespace${NC}\n"

    # Get PVCs
    local pvcs=$(kubectl get pvc -n "$namespace" -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null)

    if [ ! -z "$pvcs" ]; then
        while IFS= read -r pvc; do
            if [ ! -z "$pvc" ]; then
                echo "PVC: $pvc"

                # Get pods using this PVC
                local pods=$(kubectl get pods -n "$namespace" -o jsonpath="{range .items[?(@.spec.volumes[*].persistentVolumeClaim.claimName=='$pvc')]}{.metadata.name}{'\n'}{end}")

                if [ ! -z "$pods" ]; then
                    echo "└── Used by pods:"
                    while IFS= read -r pod; do
                        if [ ! -z "$pod" ]; then
                            echo "    $(create_arrow 4) $pod"
                        fi
                    done <<< "$pods"
                fi
            fi
        done <<< "$pvcs"
    fi
}

# Main execution
echo -e "${GREEN}Kubernetes Resource Mapper${NC}"
print_line

# Get all namespaces
namespaces=$(get_namespaces)

# Process each namespace
while IFS= read -r namespace; do
    if [ ! -z "$namespace" ]; then
        print_line
        echo -e "${RED}Analyzing namespace: $namespace${NC}"
        print_line

        # Get all resources
        get_resources "$namespace"

        # Map service connections
        map_service_connections "$namespace"

        # Create visualization
        create_visualization "$namespace"

        # Show volume relationships
        show_volume_relationships "$namespace"

        print_line
    fi
done <<< "$namespaces"

echo -e "${GREEN}Resource mapping complete!${NC}"
