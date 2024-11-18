#!/bin/bash

# Set color codes for better visualization
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl is not installed. Please install kubectl first.${NC}"
        exit 1
    fi
}

# Function to check if namespace exists
check_namespace() {
    if ! kubectl get namespace test-apps &> /dev/null; then
        echo -e "${GREEN}Creating namespace: test-apps${NC}"
        kubectl create namespace test-apps
    else
        echo -e "${GREEN}Namespace test-apps already exists${NC}"
    fi
}

# Function to apply Kubernetes configurations
apply_configurations() {
    local base_dir="k8s-test-apps"
    
    echo -e "${BLUE}Applying RBAC configurations...${NC}"
    kubectl apply -f "$base_dir/rbac/" -n test-apps
    
    echo -e "${BLUE}Applying Auth Service configurations...${NC}"
    kubectl apply -f "$base_dir/auth-service/" -n test-apps
    
    echo -e "${BLUE}Applying Product Service configurations...${NC}"
    kubectl apply -f "$base_dir/product-service/" -n test-apps
    
    echo -e "${BLUE}Applying Frontend configurations...${NC}"
    kubectl apply -f "$base_dir/frontend/" -n test-apps
    
    echo -e "${BLUE}Applying Ingress configurations...${NC}"
    kubectl apply -f "$base_dir/ingress/" -n test-apps
}

# Function to wait for deployments to be ready
wait_for_deployments() {
    echo -e "${GREEN}Waiting for deployments to be ready...${NC}"
    kubectl wait --for=condition=available --timeout=300s deployment/web-frontend -n test-apps
    kubectl wait --for=condition=available --timeout=300s deployment/auth-service -n test-apps
    kubectl wait --for=condition=available --timeout=300s deployment/product-service -n test-apps
}

# Function to display status
show_status() {
    echo -e "${GREEN}Deployment Status:${NC}"
    kubectl get all -n test-apps
    
    echo -e "\n${GREEN}Ingress Status:${NC}"
    kubectl get ingress -n test-apps
    
    echo -e "\n${GREEN}ConfigMaps:${NC}"
    kubectl get configmaps -n test-apps
    
    echo -e "\n${GREEN}Service Accounts and RBAC:${NC}"
    kubectl get serviceaccounts,roles,rolebindings -n test-apps
}

# Main execution
echo "Deploying test applications..."

# Check prerequisites
check_kubectl
check_namespace

# Apply configurations
apply_configurations

# Wait for deployments
wait_for_deployments

# Show status
show_status

echo -e "\n${GREEN}Deployment complete!${NC}"
echo "You can access the applications at:"
echo "  - Frontend: http://shop.example.com"
echo "  - Auth API: http://api.example.com/auth"
echo "  - Product API: http://api.example.com/products"
echo -e "\n${BLUE}Note: Make sure to add these domains to your /etc/hosts file:${NC}"
echo "127.0.0.1 shop.example.com api.example.com"