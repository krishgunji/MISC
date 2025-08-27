#!/bin/bash

set -e

# VARIABLES
LOCAL_REGISTRY="192.168.1.9:5000"
NODE_APP_DIR="/root/sample-node-backend"
FLUTTER_WEB_DIR="/root/sample_flutter_web"
NODE_IMAGE_NAME="$LOCAL_REGISTRY/my-node-backend:latest"
FLUTTER_IMAGE_NAME="$LOCAL_REGISTRY/my-flutter-web:latest"
NAMESPACE="helix"

command_exists() { command -v "$1" >/dev/null 2>&1; }

echo "========== ENVIRONMENT SETUP AND DEPLOYMENT =========="

# Node.js
if ! command_exists node; then
  echo "Installing Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt-get install -y nodejs
else
  echo "Node.js already installed."
fi

# Flutter
if ! command_exists flutter; then
  echo "Installing Flutter SDK..."
  cd /root
  if [ ! -d flutter ]; then
    git clone https://github.com/flutter/flutter.git -b stable
  fi
  export PATH="/root/flutter/bin:$PATH"
  /root/flutter/bin/flutter doctor
else
  echo "Flutter already installed."
fi

# Istio CLI
if ! command_exists istioctl; then
  echo "Installing Istio CLI..."
  curl -L https://istio.io/downloadIstio | sh -
  cd istio-*
  export PATH="$PWD/bin:$PATH"
  cd /root
else
  echo "Istio CLI already installed."
fi

# Node backend files
if [ ! -f "$NODE_APP_DIR/index.js" ]; then
  echo "Creating sample Node.js backend app..."
  mkdir -p $NODE_APP_DIR
  cat >$NODE_APP_DIR/index.js <<EOF
const express = require('express');
const app = express();
const port = 3000;
app.get('/api/hello', (req, res) => { res.json({ message: 'Hello from Node.js backend!' }); });
app.listen(port, () => { console.log(\`Backend listening at http://localhost:\${port}\`); });
EOF
  cat >$NODE_APP_DIR/package.json <<EOF
{ "name": "sample-node-backend", "version": "1.0.0", "main": "index.js",
  "dependencies": { "express": "^4.18.2" } }
EOF
else
  echo "Node.js backend files present."
fi

# Flutter app files
if [ ! -d "$FLUTTER_WEB_DIR" ]; then
  echo "Creating sample Flutter web app..."
  cd /root
  flutter create sample_flutter_web
  cat > $FLUTTER_WEB_DIR/lib/main.dart <<EOF
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
void main() { runApp(const MyApp()); }
class MyApp extends StatelessWidget { const MyApp({super.key});
  @override Widget build(BuildContext context) {return MaterialApp(
    title: 'Flutter Web with Backend',
    home: Scaffold(appBar: AppBar(title: const Text('Flutter Web + Node.js Backend')),
    body: const Center(child: BackendResponseWidget()),),);}}
class BackendResponseWidget extends StatefulWidget { const BackendResponseWidget({super.key});
  @override _BackendResponseWidgetState createState() => _BackendResponseWidgetState(); }
class _BackendResponseWidgetState extends State<BackendResponseWidget> {
  String _response = 'Loading...';
  @override void initState() { super.initState(); fetchBackendResponse(); }
  Future<void> fetchBackendResponse() async {
    try { final url = Uri.parse('/api/hello'); final res = await http.get(url);
      if (res.statusCode == 200) { final data = json.decode(res.body); setState(() { _response = data['message']; }); }
      else { setState(() { _response = 'Failed to load data'; }); }
    } catch (e) { setState(() { _response = 'Error: \$e'; }); }
  }
  @override Widget build(BuildContext context) { return Text(_response); }
}
EOF
else
  echo "Flutter web app already exists."
fi

# Add http package to flutter (if missing)
if ! grep -q 'http:' "$FLUTTER_WEB_DIR/pubspec.yaml"; then
  echo "Adding http dependency to Flutter pubspec.yaml..."
  sed -i '/dependencies:/a\  http: ^0.13.6' $FLUTTER_WEB_DIR/pubspec.yaml
fi
cd $FLUTTER_WEB_DIR
flutter pub get
flutter config --enable-web
flutter build web

# Dockerfiles
if [ ! -f "$NODE_APP_DIR/Dockerfile" ]; then
  echo "Creating Dockerfile for Node.js..."
  cat > $NODE_APP_DIR/Dockerfile <<EOF
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "index.js"]
EOF
fi
if [ ! -f "$FLUTTER_WEB_DIR/Dockerfile" ]; then
  echo "Creating Dockerfile for Flutter Web..."
  cat > $FLUTTER_WEB_DIR/Dockerfile <<EOF
FROM nginx:alpine
COPY build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF
fi

# Build Docker images
echo "Building Docker images..."
docker build -t $NODE_IMAGE_NAME $NODE_APP_DIR
docker build -t $FLUTTER_IMAGE_NAME $FLUTTER_WEB_DIR

# Start local Docker registry if needed
if ! docker ps -q -f name=registry | grep .; then
  echo "Starting local Docker registry..."
  docker run -d -p 5000:5000 --restart=always --name registry registry:2
else
  echo "Local Docker registry already running."
fi

# Push Docker images
echo "Pushing Docker images to local registry..."
docker push $NODE_IMAGE_NAME
docker push $FLUTTER_IMAGE_NAME

# Istio install
echo "Installing Istio control plane if needed (idempotent)..."
istioctl install --set profile=demo -y

# Change ingressgateway service to NodePort
echo "Changing istio-ingressgateway Service type to NodePort..."
kubectl -n istio-system patch svc istio-ingressgateway -p '{"spec": {"type": "NodePort"}}'

# Enable Istio auto-injection
kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite

# Deploy app and Istio networking
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: node-backend, namespace: $NAMESPACE }
spec:
  replicas: 2
  selector: { matchLabels: { app: node-backend } }
  template:
    metadata: { labels: { app: node-backend } }
    spec:
      containers:
      - name: node-backend
        image: $NODE_IMAGE_NAME
        ports: [ { containerPort: 3000 } ]
---
apiVersion: v1
kind: Service
metadata: { name: node-backend, namespace: $NAMESPACE }
spec:
  selector: { app: node-backend }
  ports: [ { protocol: TCP, port: 80, targetPort: 3000 } ]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: flutter-web, namespace: $NAMESPACE }
spec:
  replicas: 2
  selector: { matchLabels: { app: flutter-web } }
  template:
    metadata: { labels: { app: flutter-web } }
    spec:
      containers:
      - name: flutter-web
        image: $FLUTTER_IMAGE_NAME
        ports: [ { containerPort: 80 } ]
---
apiVersion: v1
kind: Service
metadata: { name: flutter-web, namespace: $NAMESPACE }
spec:
  selector: { app: flutter-web }
  ports: [ { protocol: TCP, port: 80, targetPort: 80 } ]
---
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata: { name: sample-app-gateway, namespace: $NAMESPACE }
spec:
  selector: { istio: ingressgateway }
  servers:
  - port: { number: 80, name: http, protocol: HTTP }
    hosts: [ "*" ]
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata: { name: sample-app, namespace: $NAMESPACE }
spec:
  hosts: [ "*" ]
  gateways: [ sample-app-gateway ]
  http:
  - match: [ { uri: { prefix: "/api" } } ]
    route:
    - destination:
        host: node-backend.$NAMESPACE.svc.cluster.local
        port: { number: 80 }
  - route:
    - destination:
        host: flutter-web.$NAMESPACE.svc.cluster.local
        port: { number: 80 }
EOF

echo "Fetching Node IP and Istio ingressgateway NodePort..."
# Uses first worker node's InternalIP and 80 NodePort
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

echo "======================================================"
echo "App frontend:  http://$NODE_IP:$NODE_PORT/"
echo "API endpoint:  http://$NODE_IP:$NODE_PORT/api/hello"
echo "Deployment complete. Access your application above!"
controlplane:~$ ^C
controlplane:~$ 
