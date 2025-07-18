#!/bin/bash
cd /home/tomakabe/workspace/github.com/torumakabe/aks-scale-to-zero/src/api

echo "Running handler tests..."
go test ./handlers -v -cover

echo -e "\nRunning k8s client tests..."
go test ./k8s -v -cover

echo -e "\nRunning middleware tests..."
go test ./middleware -v -cover

echo -e "\nGenerating coverage report..."
go test ./... -coverprofile=coverage.out
go tool cover -func=coverage.out | tail -n 1