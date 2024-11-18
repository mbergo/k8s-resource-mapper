#!/bin/bash

# Set color codes for better visualization
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Creating directory structure...${NC}"

# Create the directory structure
mkdir -p k8s-test-apps/frontend
mkdir -p k8s-test-apps/auth-service
mkdir -p k8s-test-apps/product-service
mkdir -p k8s-test-apps/ingress
mkdir -p k8s-test-apps/rbac

echo -e "${GREEN}Created directories:${NC}"
tree k8s-test-apps

echo -e "${BLUE}Creating YAML files...${NC}"

# 1. Frontend Application
echo -e "${GREEN}Creating frontend configurations...${NC}"
cat > k8s-test-apps/frontend/01-web-frontend-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
  labels:
    app: web-frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-frontend
  template:
    metadata:
      labels:
        app: web-frontend
    spec:
      containers:
      - name: web-frontend
        image: nginx:alpine
        ports:
        - containerPort: 80
        env:
        - name: AUTH_SERVICE_URL
          value: "http://auth-service:8080"
        - name: PRODUCT_SERVICE_URL
          value: "http://product-service:8081"
        volumeMounts:
        - name: frontend-config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: frontend-config
        configMap:
          name: frontend-config
EOF

cat > k8s-test-apps/frontend/02-web-frontend-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web-frontend
spec:
  selector:
    app: web-frontend
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

cat > k8s-test-apps/frontend/03-web-frontend-configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-config
data:
  default.conf: |
    server {
        listen 80;
        location /auth/ {
            proxy_pass http://auth-service:8080/;
        }
        location /products/ {
            proxy_pass http://product-service:8081/;
        }
    }
EOF

# 2. Auth Service
echo -e "${GREEN}Creating auth service configurations...${NC}"
cat > k8s-test-apps/auth-service/01-auth-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  labels:
    app: auth-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
    spec:
      containers:
      - name: auth-service
        image: nginx:alpine
        ports:
        - containerPort: 8080
        env:
        - name: DB_CONFIG
          valueFrom:
            configMapKeyRef:
              name: auth-service-config
              key: database-url
      serviceAccountName: auth-service-account
EOF

cat > k8s-test-apps/auth-service/02-auth-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: auth-service
spec:
  selector:
    app: auth-service
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
EOF

cat > k8s-test-apps/auth-service/03-auth-configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: auth-service-config
data:
  database-url: "postgres://auth-db:5432/authdb"
EOF

# 3. Product Service
echo -e "${GREEN}Creating product service configurations...${NC}"
cat > k8s-test-apps/product-service/01-product-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service
  labels:
    app: product-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: product-service
  template:
    metadata:
      labels:
        app: product-service
    spec:
      containers:
      - name: product-service
        image: nginx:alpine
        ports:
        - containerPort: 8081
        env:
        - name: AUTH_SERVICE_URL
          value: "http://auth-service:8080"
        - name: DB_CONFIG
          valueFrom:
            configMapKeyRef:
              name: product-service-config
              key: database-url
      serviceAccountName: product-service-account
EOF

cat > k8s-test-apps/product-service/02-product-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: product-service
spec:
  selector:
    app: product-service
  ports:
  - port: 8081
    targetPort: 8081
  type: ClusterIP
EOF

cat > k8s-test-apps/product-service/03-product-configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: product-service-config
data:
  database-url: "postgres://product-db:5432/productdb"
EOF

# 4. Ingress Configurations
echo -e "${GREEN}Creating ingress configurations...${NC}"
cat > k8s-test-apps/ingress/01-public-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: public-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: shop.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-frontend
            port:
              number: 80
EOF

cat > k8s-test-apps/ingress/02-api-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /auth
        pathType: Prefix
        backend:
          service:
            name: auth-service
            port:
              number: 8080
      - path: /products
        pathType: Prefix
        backend:
          service:
            name: product-service
            port:
              number: 8081
EOF

# 5. RBAC Configurations
echo -e "${GREEN}Creating RBAC configurations...${NC}"
cat > k8s-test-apps/rbac/01-service-accounts.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: auth-service-account
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: product-service-account
EOF

cat > k8s-test-apps/rbac/02-roles.yaml << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: service-reader
rules:
- apiGroups: [""]
  resources: ["services", "endpoints"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get"]
EOF

cat > k8s-test-apps/rbac/03-role-bindings.yaml << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: auth-service-role-binding
subjects:
- kind: ServiceAccount
  name: auth-service-account
roleRef:
  kind: Role
  name: service-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: product-service-role-binding
subjects:
- kind: ServiceAccount
  name: product-service-account
roleRef:
  kind: Role
  name: service-reader
  apiGroup: rbac.authorization.k8s.io
EOF

echo -e "${GREEN}All configuration files have been created!${NC}"
echo -e "${BLUE}Directory structure:${NC}"
tree k8s-test-apps

echo -e "${GREEN}Setup complete! You can now run the deployment script.${NC}"
