package main

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strings"

	v1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

// ANSI color codes
const (
	colorRed    = "\033[0;31m"
	colorGreen  = "\033[0;32m"
	colorBlue   = "\033[0;34m"
	colorYellow = "\033[1;33m"
	colorCyan   = "\033[0;36m"
	colorReset  = "\033[0m"
)

type ResourceMapper struct {
	clientset *kubernetes.Clientset
	ctx       context.Context
}

func NewResourceMapper() (*ResourceMapper, error) {
	// Get kubeconfig from default location
	kubeconfig := os.Getenv("KUBECONFIG")
	if kubeconfig == "" {
		kubeconfig = os.Getenv("HOME") + "/.kube/config"
	}

	// Build config from kubeconfig file
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return nil, fmt.Errorf("error building kubeconfig: %v", err)
	}

	// Create the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("error creating kubernetes client: %v", err)
	}

	return &ResourceMapper{
		clientset: clientset,
		ctx:       context.Background(),
	}, nil
}

func (rm *ResourceMapper) printLine() {
	fmt.Println(strings.Repeat("-", 80))
}

func (rm *ResourceMapper) createArrow(length int) string {
	return strings.Repeat("-", length) + ">"
}

func (rm *ResourceMapper) getNamespaces() ([]string, error) {
	namespaces, err := rm.clientset.CoreV1().Namespaces().List(rm.ctx, metav1.ListOptions{})
	if err != nil {
		return nil, err
	}

	var namespaceNames []string
	for _, ns := range namespaces.Items {
		namespaceNames = append(namespaceNames, ns.Name)
	}
	return namespaceNames, nil
}

func (rm *ResourceMapper) getResources(namespace string) error {
	fmt.Printf("%sResources in namespace: %s%s\n", colorGreen, namespace, colorReset)

	// Get deployments
	fmt.Printf("\n%sDeployments:%s\n", colorYellow, colorReset)
	deployments, err := rm.clientset.AppsV1().Deployments(namespace).List(rm.ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}
	for _, d := range deployments.Items {
		fmt.Printf("%s %d %d\n", d.Name, *d.Spec.Replicas, d.Status.AvailableReplicas)
	}

	// Get services
	fmt.Printf("\n%sServices:%s\n", colorYellow, colorReset)
	services, err := rm.clientset.CoreV1().Services(namespace).List(rm.ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}
	for _, s := range services.Items {
		fmt.Printf("%s %s %s %v\n", s.Name, s.Spec.Type, s.Spec.ClusterIP, s.Spec.ExternalIPs)
	}

	// Get pods
	fmt.Printf("\n%sPods:%s\n", colorYellow, colorReset)
	pods, err := rm.clientset.CoreV1().Pods(namespace).List(rm.ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}
	for _, p := range pods.Items {
		fmt.Printf("%s %s %s\n", p.Name, p.Status.Phase, p.Spec.NodeName)
	}

	// Get configmaps
	fmt.Printf("\n%sConfigMaps:%s\n", colorYellow, colorReset)
	configmaps, err := rm.clientset.CoreV1().ConfigMaps(namespace).List(rm.ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}
	for _, cm := range configmaps.Items {
		fmt.Printf("%s\n", cm.Name)
	}

	return nil
}

func (rm *ResourceMapper) mapServiceConnections(namespace string) error {
	fmt.Printf("\n%sService connections in namespace: %s%s\n", colorBlue, namespace, colorReset)

	services, err := rm.clientset.CoreV1().Services(namespace).List(rm.ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}

	for _, service := range services.Items {
		fmt.Printf("\n%sService: %s%s\n", colorYellow, service.Name, colorReset)

		if len(service.Spec.Selector) > 0 {
			fmt.Printf("├── Selectors: %v\n", service.Spec.Selector)

			labelSelector := metav1.FormatLabelSelector(&metav1.LabelSelector{
				MatchLabels: service.Spec.Selector,
			})
			pods, err := rm.clientset.CoreV1().Pods(namespace).List(rm.ctx, metav1.ListOptions{
				LabelSelector: labelSelector,
			})
			if err != nil {
				return err
			}

			if len(pods.Items) > 0 {
				fmt.Printf("└── Connected Pods:\n")
				for _, pod := range pods.Items {
					fmt.Printf("    %s %s\n", rm.createArrow(4), pod.Name)
				}
			}
		}
	}

	return nil
}

func (rm *ResourceMapper) showResourceRelationships(namespace string) error {
	fmt.Printf("\n%sResource relationships in namespace: %s%s\n\n", colorBlue, namespace, colorReset)

	fmt.Println("External Traffic")
	fmt.Println("│")

	// Get ingresses
	ingresses, err := rm.clientset.NetworkingV1().Ingresses(namespace).List(rm.ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}

	if len(ingresses.Items) > 0 {
		fmt.Println("▼")
		fmt.Println("[Ingress Layer]")
		for _, ingress := range ingresses.Items {
			fmt.Printf("├── %s\n", ingress.Name)
			for _, rule := range ingress.Spec.Rules {
				if rule.HTTP != nil {
					for _, path := range rule.HTTP.Paths {
						fmt.Printf("│   %s Service: %s\n", rm.createArrow(4), path.Backend.Service.Name)
					}
				}
			}
		}
		fmt.Println("│")
	}

	fmt.Println("▼")
	fmt.Println("[Service Layer]")
	services, err := rm.clientset.CoreV1().Services(namespace).List(rm.ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}

	for _, service := range services.Items {
		fmt.Printf("├── %s\n", service.Name)

		if len(service.Spec.Selector) > 0 {
			labelSelector := metav1.FormatLabelSelector(&metav1.LabelSelector{
				MatchLabels: service.Spec.Selector,
			})
			pods, err := rm.clientset.CoreV1().Pods(namespace).List(rm.ctx, metav1.ListOptions{
				LabelSelector: labelSelector,
			})
			if err != nil {
				return err
			}

			for _, pod := range pods.Items {
				fmt.Printf("│   %s Pod: %s\n", rm.createArrow(4), pod.Name)
			}
		}
	}

	return nil
}

func (rm *ResourceMapper) showConfigMapUsage(namespace string) error {
	fmt.Printf("\n%sConfigMap usage in namespace: %s%s\n", colorCyan, namespace, colorReset)

	configmaps, err := rm.clientset.CoreV1().ConfigMaps(namespace).List(rm.ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}

	pods, err := rm.clientset.CoreV1().Pods(namespace).List(rm.ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}

	for _, cm := range configmaps.Items {
		fmt.Printf("\nConfigMap: %s\n", cm.Name)

		usagePods := make(map[string][]string)
		for _, pod := range pods.Items {
			usageTypes := rm.findConfigMapUsage(&pod, cm.Name)
			if len(usageTypes) > 0 {
				usagePods[pod.Name] = usageTypes
			}
		}

		if len(usagePods) > 0 {
			fmt.Println("└── Used by pods:")
			podNames := make([]string, 0, len(usagePods))
			for podName := range usagePods {
				podNames = append(podNames, podName)
			}
			sort.Strings(podNames)

			for _, podName := range podNames {
				fmt.Printf("    %s %s\n", rm.createArrow(4), podName)
				for _, usageType := range usagePods[podName] {
					fmt.Printf("        - %s\n", usageType)
				}
			}
		}
	}

	return nil
}

func (rm *ResourceMapper) findConfigMapUsage(pod *v1.Pod, configMapName string) []string {
	var usageTypes []string

	// Check volumes
	for _, volume := range pod.Spec.Volumes {
		if volume.ConfigMap != nil && volume.ConfigMap.Name == configMapName {
			usageTypes = append(usageTypes, "Mounted as volume")
		}
	}

	// Check containers
	for _, container := range pod.Spec.Containers {
		// Check envFrom
		for _, envFrom := range container.EnvFrom {
			if envFrom.ConfigMapRef != nil && envFrom.ConfigMapRef.Name == configMapName {
				usageTypes = append(usageTypes, "Used in envFrom")
			}
		}

		// Check env
		for _, env := range container.Env {
			if env.ValueFrom != nil && env.ValueFrom.ConfigMapKeyRef != nil && env.ValueFrom.ConfigMapKeyRef.Name == configMapName {
				usageTypes = append(usageTypes, "Used in environment variables")
			}
		}
	}

	return usageTypes
}

func main() {
	rm, err := NewResourceMapper()
	if err != nil {
		fmt.Printf("Error initializing resource mapper: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("%sKubernetes Resource Mapper%s\n", colorGreen, colorReset)
	rm.printLine()

	namespaces, err := rm.getNamespaces()
	if err != nil {
		fmt.Printf("Error getting namespaces: %v\n", err)
		os.Exit(1)
	}

	for _, namespace := range namespaces {
		rm.printLine()
		fmt.Printf("%sAnalyzing namespace: %s%s\n", colorRed, namespace, colorReset)
		rm.printLine()

		if err := rm.getResources(namespace); err != nil {
			fmt.Printf("Error getting resources: %v\n", err)
			continue
		}

		if err := rm.mapServiceConnections(namespace); err != nil {
			fmt.Printf("Error mapping service connections: %v\n", err)
			continue
		}

		if err := rm.showResourceRelationships(namespace); err != nil {
			fmt.Printf("Error showing resource relationships: %v\n", err)
			continue
		}

		if err := rm.showConfigMapUsage(namespace); err != nil {
			fmt.Printf("Error showing ConfigMap usage: %v\n", err)
			continue
		}

		rm.printLine()
	}

	fmt.Printf("%sResource mapping complete!%s\n", colorGreen, colorReset)
}
