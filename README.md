# Kubernetes Resource Mapper

A comprehensive tool for visualizing and understanding the relationships between Kubernetes resources in your cluster.

## 🙏 Special Thanks

Special thanks to **Leandro "Big Dog" Silva** for enabling this project with guidance and expertise. Your contributions to making Kubernetes resource visualization more accessible are greatly appreciated! 🐕

## 📝 Description

This tool provides a clear, ASCII-based visualization of your Kubernetes cluster resources and their interconnections. It maps out deployments, services, pods, configmaps, and ingress resources, showing how they are connected and their current state.

## ✨ Features

- 🔍 Comprehensive resource mapping
- 🔄 Service-to-pod relationship visualization
- 📊 ConfigMap usage tracking
- 🌐 Ingress routing visualization
- 🎨 Color-coded output for better readability
- 📡 Real-time cluster state analysis
- 🔗 Resource relationship mapping

## 🚀 Prerequisites

- Kubernetes cluster access
- `kubectl` installed and configured
- `jq` command-line JSON processor

### Installing Prerequisites

```bash
# For Ubuntu/Debian
sudo apt-get install jq

# For CentOS/RHEL
sudo yum install jq

# For macOS
brew install jq
```

## 📦 Installation

1. Clone the repository or download the scripts:
```bash
# Clone repository or copy files manually
git clone <repository-url>
```

2. Make the scripts executable:
```bash
chmod +x setup.sh
chmod +x deploy.sh
chmod +x k8s-resource-mapper.sh
```

## 🛠️ Usage

### Setting up test applications
```bash
# Create test applications
./setup.sh

# Deploy applications
./deploy.sh
```

### Running the resource mapper
```bash
./k8s-resource-mapper.sh
```

## 🎯 Sample Output

```
External Traffic
│
▼
[Ingress Layer]
├── api-ingress
│   ----> Service: auth-service
│   ----> Service: product-service
├── public-ingress
│   ----> Service: web-frontend
│
▼
[Service Layer]
├── auth-service
│   ----> Pod: auth-service-xxx-yyy
├── product-service
│   ----> Pod: product-service-xxx-yyy
├── web-frontend
│   ----> Pod: web-frontend-xxx-yyy
```

## 🏗️ Architecture

The tool maps the following resources and their relationships:

- **Ingress Resources**
  - Routes to services
  - External access points

- **Services**
  - Pod connections
  - Selector mapping
  - Port configurations

- **Pods**
  - Running state
  - Node assignment
  - Service associations

- **ConfigMaps**
  - Usage by pods
  - Volume mounts
  - Environment variables

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🔍 Directory Structure

```
k8s-test-apps/
├── auth-service/
│   ├── 01-auth-deployment.yaml
│   ├── 02-auth-service.yaml
│   └── 03-auth-configmap.yaml
├── frontend/
│   ├── 01-web-frontend-deployment.yaml
│   ├── 02-web-frontend-service.yaml
│   └── 03-web-frontend-configmap.yaml
├── ingress/
│   ├── 01-public-ingress.yaml
│   └── 02-api-ingress.yaml
├── product-service/
│   ├── 01-product-deployment.yaml
│   ├── 02-product-service.yaml
│   └── 03-product-configmap.yaml
└── rbac/
    ├── 01-service-accounts.yaml
    ├── 02-roles.yaml
    └── 03-role-bindings.yaml
```

## 🚨 Troubleshooting

If you encounter any issues:

1. Ensure `kubectl` is properly configured:
```bash
kubectl cluster-info
```

2. Verify `jq` is installed:
```bash
jq --version
```

3. Check namespace permissions:
```bash
kubectl auth can-i get pods --all-namespaces
```

## 📞 Support

If you encounter any issues or have questions, please open an issue in the repository.

## 🌟 Acknowledgments

- Special thanks to Leandro "Big Dog" Silva for the inspiration and guidance
- Kubernetes community for their excellent documentation
- All contributors who help improve this tool

