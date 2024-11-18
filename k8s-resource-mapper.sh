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

# Function to get all namespaces
get_namespaces() {
    echo -e "${BLUE}Fetching namespaces...${NC}"
    kubectl get namespaces -o custom-columns=NAME:.metadata.name --no-headers
}

# Function to get ConfigMap details
get_configmap_details() {
    local namespace=$1
    local configmap=$2

    echo -e "\n${CYAN}ConfigMap: $configmap${NC}"

    # Get ConfigMap data
    local data=$(kubectl get configmap "$configmap" -n "$namespace" -o json)

    # Extract and display data fields
    echo "├── Data Keys:"
    echo "$data" | jq -r '.data | keys[]' 2>/dev/null | while read -r key; do
        echo "│   ├── $key"
        # Get value but limit to first 100 characters
        local value=$(echo "$data" | jq -r ".data[\"$key\"]" | head -c 100)
        echo "│   │   └── Value: ${value}..."
    done

    # Find pods using this ConfigMap
    echo "└── Used by Pods:"
    kubectl get pods -n "$namespace" -o json | jq -r ".items[] | select(.spec.volumes[]?.configMap.name == \"$configmap\" or .spec.containers[].envFrom[]?.configMapRef.name == \"$configmap\") | .metadata.name" | while read -r pod; do
        if [ ! -z "$pod" ]; then
            echo "    $(create_arrow 4) $pod"
        fi
    done
}

# Function to get application interconnections
get_app_connections() {
    local namespace=$1
    echo -e "\n${BLUE}Mapping application interconnections in namespace: $namespace${NC}"

    # Get all pods
    local pods=$(kubectl get pods -n "$namespace" -o json)

    # Create temporary files for the graph
    local tmp_dir=$(mktemp -d)
    local graph_file="$tmp_dir/graph.txt"
    local nodes_file="$tmp_dir/nodes.txt"

    echo "digraph G {" > "$graph_file"
    echo '    rankdir=LR;' >> "$graph_file"
    echo '    node [shape=box];' >> "$graph_file"

    # Process each pod
    echo "$pods" | jq -r '.items[] | select(.status.phase=="Running")' | while read -r pod; do
        local pod_name=$(echo "$pod" | jq -r '.metadata.name')
        local app_label=$(echo "$pod" | jq -r '.metadata.labels.app // .metadata.labels["app.kubernetes.io/name"] // .metadata.name')

        # Add node
        echo "    \"$app_label\" [label=\"$app_label\"];" >> "$graph_file"
        echo "$app_label" >> "$nodes_file"

        # Get container environment variables that reference services
        echo "$pod" | jq -r '.spec.containers[].env[]? | select(.valueFrom.configMapKeyRef != null) | .valueFrom.configMapKeyRef.name' | while read -r configmap; do
            if [ ! -z "$configmap" ]; then
                echo "    \"$app_label\" -> \"ConfigMap: $configmap\" [color=blue];" >> "$graph_file"
            fi
        done

        # Get service connections from environment variables
        echo "$pod" | jq -r '.spec.containers[].env[]? | select(.value != null) | .value' | grep -o '[a-zA-Z0-9-]\+\.[a-zA-Z0-9-]\+\.svc\.cluster\.local' | while read -r svc; do
            local service_name=$(echo "$svc" | cut -d. -f1)
            if [ ! -z "$service_name" ]; then
                echo "    \"$app_label\" -> \"Service: $service_name\" [color=green];" >> "$graph_file"
            fi
        done
    done

    # Add services and their connections
    kubectl get services -n "$namespace" -o json | jq -r '.items[]' | while read -r service; do
        local service_name=$(echo "$service" | jq -r '.metadata.name')
        local selector=$(echo "$service" | jq -r '.spec.selector | to_entries | map(.key + "=" + .value) | join(",")')

        if [ ! -z "$selector" ]; then
            kubectl get pods -n "$namespace" -l "$selector" -o json | jq -r '.items[].metadata.labels.app // .items[].metadata.labels["app.kubernetes.io/name"] // .items[].metadata.name' | while read -r app; do
                if [ ! -z "$app" ]; then
                    echo "    \"Service: $service_name\" -> \"$app\" [color=red];" >> "$graph_file"
                fi
            done
        fi
    done

    echo "}" >> "$graph_file"

    # Display ASCII representation of the graph
    echo -e "\n${YELLOW}Application Interconnections:${NC}"
    echo -e "Legend:"
    echo -e "→ Service dependency"
    echo -e "⇢ ConfigMap usage"
    echo -e "⇾ Service exposure"
    echo ""

    # Create simple ASCII representation
    while read -r node; do
        echo "[$node]"
        grep "\"$node\" ->" "$graph_file" | while read -r connection; do
            target=$(echo "$connection" | grep -o '"[^"]*"' | tail -n 1 | tr -d '"')
            echo "  $(create_arrow 4) $target"
        done
    done < "$nodes_file"

    # Cleanup
    rm -rf "$tmp_dir"
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

    # Get and show detailed ConfigMap information
    echo -e "\n${YELLOW}ConfigMaps:${NC}"
    local configmaps=$(kubectl get configmaps -n "$namespace" -o custom-columns=NAME:.metadata.name --no-headers)
    while IFS= read -r configmap; do
        if [ ! -z "$configmap" ]; then
            get_configmap_details "$namespace" "$configmap"
        fi
    done <<< "$configmaps"

    # Get ingresses
    echo -e "\n${YELLOW}Ingresses:${NC}"
    kubectl get ingress -n "$namespace" -o custom-columns=NAME:.metadata.name,HOSTS:.spec.rules[*].host --no-headers 2>/dev/null
}

# Main execution
echo -e "${GREEN}Kubernetes Resource Mapper${NC}"
print_line

# Check for required tools
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed. Please install jq first.${NC}"
    exit 1
fi

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

        # Get application interconnections
        get_app_connections "$namespace"

        print_line
    fi
done <<< "$namespaces"

echo -e "${GREEN}Resource mapping complete!${NC}"
