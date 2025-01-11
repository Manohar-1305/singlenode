package main

import (
    "context"
    "flag"
    "fmt"
    "time"
    
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/apimachinery/pkg/runtime"
    "k8s.io/apimachinery/pkg/runtime/schema"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
    "k8s.io/client-go/util/retry"
    "k8s.io/klog/v2"
)

func main() {
    klog.InitFlags(nil)
    flag.Parse()

    // Load kubernetes config
    config, err := clientcmd.BuildConfigFromFlags("", clientcmd.RecommendedHomeFile)
    if err != nil {
        klog.Fatalf("Error building kubeconfig: %s", err.Error())
    }

    // Create kubernetes clientset
    kubeClient, err := kubernetes.NewForConfig(config)
    if err != nil {
        klog.Fatalf("Error building kubernetes clientset: %s", err.Error())
    }

    // Create controller
    controller := &Controller{
        kubeClient: kubeClient,
    }

    // Run the controller
    stopCh := make(chan struct{})
    defer close(stopCh)
    
    if err = controller.Run(stopCh); err != nil {
        klog.Fatalf("Error running controller: %s", err.Error())
    }
}